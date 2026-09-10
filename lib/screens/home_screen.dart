import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/status_model.dart';
import '../models/user_model.dart';
import '../services/call_manager.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../models/message_model.dart';
import '../widgets/avatar_image_helper.dart';
import '../widgets/media_viewer.dart';
import '../widgets/whatsapp_camera_screen.dart';
import '../widgets/whatsapp_forward_dialog.dart';
import 'ai_chat_screen.dart';
import 'call_info_screen.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import 'create_group_screen.dart';
import 'group_chat_screen.dart';
import 'login_screen.dart';
import 'payments_screen.dart';
import 'profile_setup_screen.dart';
import 'users_list_screen.dart';

class HomeScreen extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const HomeScreen({
    super.key,
    required this.navigatorKey,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final UserService _userService = UserService();
  final ChatService _chatService = ChatService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  UserModel? _currentUser;
  bool _isLoading = true;
  int _currentBottomNavIndex = 0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  int _selectedFilter = 0; // 0: All, 1: Unread, 2: Groups

  // Long-press selection mode
  final Set<String> _selectedChatIds = {};
  bool get _isSelectionMode => _selectedChatIds.isNotEmpty;
  final Set<String> _archivedChatIds = {}; // locally archived chats

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _initUserAndCallListener();
    _controller.forward();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _userService.setOnlineStatus(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _userService.setOnlineStatus(false);
    }
  }

  Future<void> _initUserAndCallListener() async {
    try {
      final user = await _userService.ensureUserLoggedIn();
      final profile = await _userService.getCurrentUserProfile();

      // Mark user online immediately
      await _userService.setOnlineStatus(true);

      if (mounted) {
        setState(() {
          _currentUser = profile;
          _isLoading = false;
        });

        // Start global incoming call listener
        CallManager().startListening(user.uid, widget.navigatorKey);

        // Start real-time message notification listener
        NotificationService().startMessageNotificationListener(user.uid);

        if (profile == null || profile.name.isEmpty || profile.phoneNumber.isEmpty) {
          _showProfileSetupPrompt();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showProfileSetupPrompt() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(navigatorKey: widget.navigatorKey),
        ),
        (_) => false,
      );
    });
  }

  Future<void> _switchAccount() async {
    // Show confirmation
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Switch Account?',
          style: TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will sign you out and allow a new user to set up their profile on this device.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B50E6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Switch', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // Sign out
    await _userService.signOut();

    if (!mounted) return;
    // Navigate to LoginScreen for new user onboarding
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => LoginScreen(navigatorKey: widget.navigatorKey),
      ),
      (_) => false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _userService.setOnlineStatus(false);
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openScreen(Widget screen) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, animation, secondaryAnimation) => screen,
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _openCameraScreen() async {
    File? capturedMediaFile;
    String capturedMediaCaption = '';
    String capturedMediaType = 'image';

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WhatsAppCameraScreen(
          onMediaCaptured: (file, caption, type) {
            capturedMediaFile = file;
            capturedMediaCaption = caption;
            capturedMediaType = type;
          },
        ),
      ),
    );

    if (capturedMediaFile != null && mounted) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) {
        _handleCapturedMediaFromCamera(capturedMediaFile!, capturedMediaCaption, capturedMediaType);
      }
    }
  }

  void _handleCapturedMediaFromCamera(File file, String caption, String type) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1F2C34),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header info
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B50E6).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Icon(
                          type == 'video' ? Icons.videocam_rounded : Icons.photo_camera_rounded,
                          color: const Color(0xFF8E85F3),
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type == 'video' ? 'Video Captured' : 'Photo Captured',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            caption.isNotEmpty ? caption : 'Where do you want to share?',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 8),

                // Option 1: My Status
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00A884).withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF00A884), width: 2),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.motion_photos_on_rounded,
                          color: Color(0xFF00A884),
                          size: 26,
                        ),
                      ),
                    ),
                    title: const Text(
                      'My Status',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15.5,
                      ),
                    ),
                    subtitle: const Text(
                      'Post as status update (disappears in 24 hours)',
                      style: TextStyle(color: Colors.white60, fontSize: 12.5),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 15),
                    onTap: () {
                      Navigator.pop(ctx);
                      _uploadCapturedToStatus(file, caption, type);
                    },
                  ),
                ),

                const SizedBox(height: 4),

                // Option 2: Share to Contacts
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B50E6).withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF5B50E6), width: 2),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.chat_bubble_rounded,
                          color: Color(0xFF8E85F3),
                          size: 22,
                        ),
                      ),
                    ),
                    title: const Text(
                      'Share to Contacts',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15.5,
                      ),
                    ),
                    subtitle: const Text(
                      'Select one or more chats or groups to send',
                      style: TextStyle(color: Colors.white60, fontSize: 12.5),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 15),
                    onTap: () {
                      Navigator.pop(ctx);
                      _shareCapturedToContacts(file, caption, type);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _uploadCapturedToStatus(File file, String caption, String type) async {
    _currentUser ??= await _userService.getCurrentUserProfile();
    if (_currentUser == null) {
      _showSnackBar('User not logged in');
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2C34),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 16)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(color: Color(0xFF00A884), strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Text(
                'Uploading ${type == 'video' ? 'video' : 'photo'} status...',
                style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final ext = type == 'video' ? 'mp4' : 'jpg';
      final fileName = 'status_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final storagePath = 'statuses/${_currentUser!.id}/$fileName';

      String downloadUrl = '';
      try {
        downloadUrl = await _chatService.uploadFile(file, storagePath);
      } catch (uploadErr) {
        debugPrint('Status upload failed, using fallback: $uploadErr');
        if (type == 'image') {
          final bytes = await file.readAsBytes();
          downloadUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        } else {
          downloadUrl = file.path;
        }
      }

      await _chatService.uploadStatus(
        userId: _currentUser!.id,
        userName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
        userPhone: _currentUser!.phoneNumber,
        mediaUrl: downloadUrl,
        textContent: caption.isNotEmpty ? caption : null,
        type: type,
      );

      if (mounted) Navigator.pop(context);
      _showSnackBar('${type == 'video' ? 'Video' : 'Photo'} status updated successfully! Valid for 24 hours.');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('Failed to update status: $e');
    }
  }

  Future<void> _shareCapturedToContacts(File file, String caption, String type) async {
    _currentUser ??= await _userService.getCurrentUserProfile();
    if (_currentUser == null) {
      _showSnackBar('User not logged in');
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2C34),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 16)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(color: Color(0xFF5B50E6), strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Text(
                'Preparing ${type == 'video' ? 'video' : 'photo'} to share...',
                style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final ext = type == 'video' ? 'mp4' : 'jpg';
      final fileName = 'media_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final storagePath = 'chat_media/${_currentUser!.id}/$fileName';

      String downloadUrl = '';
      try {
        downloadUrl = await _chatService.uploadFile(file, storagePath);
      } catch (uploadErr) {
        debugPrint('Media upload failed, using fallback: $uploadErr');
        if (type == 'image') {
          final bytes = await file.readAsBytes();
          downloadUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        } else {
          downloadUrl = file.path;
        }
      }

      // Dismiss loading dialog
      if (mounted) Navigator.pop(context);

      final message = MessageModel(
        id: '',
        senderId: _currentUser!.id,
        receiverId: '',
        message: caption,
        mediaUrl: downloadUrl,
        type: type,
        timestamp: DateTime.now(),
      );

      if (!mounted) return;

      WhatsAppForwardDialog.show(
        context,
        message: message,
        currentUserId: _currentUser!.id,
        currentUserName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('Failed to share media: $e');
    }
  }

  Future<void> _markAllChatsAsRead() async {
    if (_currentUser == null) return;
    try {
      final snap = await _firestore
          .collection('chats')
          .where('participants', arrayContains: _currentUser!.id)
          .get();

      final batch = _firestore.batch();
      for (var doc in snap.docs) {
        batch.set(doc.reference, {'unread_${_currentUser!.id}': 0}, SetOptions(merge: true));
      }
      await batch.commit();
      _showSnackBar('All chats marked as read');
    } catch (e) {
      _showSnackBar('Marked all as read');
    }
  }

  void _showBroadcastDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.campaign_rounded, color: Color(0xFF3B82F6), size: 24),
                ),
                const SizedBox(width: 14),
                const Text('Broadcast lists', style: TextStyle(color: Color(0xFF171B2D), fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Only contacts with your phone number saved in their address book will receive your broadcast messages.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B50E6),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openScreen(const UsersListScreen());
                },
                child: const Text('New list', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLinkedDevicesDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.devices_rounded, color: Color(0xFF6366F1), size: 36),
            ),
            const SizedBox(height: 14),
            const Text('Use on other devices', style: TextStyle(color: Color(0xFF171B2D), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Link up to 4 devices to your account simultaneously to chat anytime, anywhere.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B50E6),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Link a device', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStarredDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 36),
            ),
            const SizedBox(height: 14),
            const Text('Starred messages', style: TextStyle(color: Color(0xFF171B2D), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Tap and hold on any message in any chat to star it, so you can easily find it later.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B50E6),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Got it', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildWhatsAppMenuItem(
    String value,
    String text, [
    IconData? icon,
    Color? iconColor,
  ]) {
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: (iconColor ?? const Color(0xFF5B50E6)).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: iconColor ?? const Color(0xFF5B50E6),
                  size: 17,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF171B2D),
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FC),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF5B50E6)),
              )
            : IndexedStack(
                index: _currentBottomNavIndex,
                children: [
                  _buildChatsTab(),
                  _buildUpdatesTab(),
                  _buildCommunitiesTab(),
                  _buildCallsTab(),
                ],
              ),
      ),

      // WhatsApp Floating Action Button
      floatingActionButton: _currentBottomNavIndex == 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'fab_group',
                  backgroundColor: Colors.white,
                  onPressed: () => _openScreen(const CreateGroupScreen()),
                  child: const Icon(Icons.group_add_rounded, color: Color(0xFF5B50E6)),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'fab_chat',
                  backgroundColor: const Color(0xFF5B50E6),
                  onPressed: () => _openScreen(const UsersListScreen()),
                  child: const Icon(Icons.chat_bubble_rounded, color: Colors.white),
                ),
              ],
            )
          : (_currentBottomNavIndex == 3
              ? FloatingActionButton(
                  heroTag: 'fab_call',
                  backgroundColor: const Color(0xFF5B50E6),
                  onPressed: () => _openScreen(const UsersListScreen()),
                  child: const Icon(Icons.add_call, color: Colors.white),
                )
              : null),

      // WhatsApp Bottom Navigation Bar
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentBottomNavIndex,
          onTap: (index) {
            setState(() {
              _currentBottomNavIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF5B50E6),
          unselectedItemColor: const Color(0xFF64748B),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              activeIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.change_circle_outlined),
              activeIcon: Icon(Icons.change_circle_rounded),
              label: 'Updates',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.groups_outlined),
              activeIcon: Icon(Icons.groups_rounded),
              label: 'Communities',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.call_outlined),
              activeIcon: Icon(Icons.call_rounded),
              label: 'Calls',
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TAB 0: WHATSAPP CHAT LIST / CONVERSATION HISTORY
  // ============================================================

  // ---- Selection Mode Helpers ----
  void _toggleSelect(String id) {
    setState(() {
      if (_selectedChatIds.contains(id)) {
        _selectedChatIds.remove(id);
      } else {
        _selectedChatIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedChatIds.clear());
  }

  void _archiveSelected() {
    setState(() {
      _archivedChatIds.addAll(_selectedChatIds);
      _selectedChatIds.clear();
    });
    _showSnackBar('${_archivedChatIds.length} chat(s) archived');
  }

  void _muteSelected() {
    final count = _selectedChatIds.length;
    _clearSelection();
    _showSnackBar('$count chat(s) muted');
  }

  void _pinSelected() {
    final count = _selectedChatIds.length;
    _clearSelection();
    _showSnackBar('$count chat(s) pinned');
  }

  void _deleteSelected() {
    final count = _selectedChatIds.length;
    final idsToDelete = List<String>.from(_selectedChatIds);
    bool alsoDeletePerson = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF233138),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Delete $count item(s)?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will permanently delete the conversation and messages from Firestore.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Theme(
                data: ThemeData(unselectedWidgetColor: Colors.white60),
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF10B981),
                  checkColor: Colors.white,
                  value: alsoDeletePerson,
                  title: const Text(
                    'Also delete contact/person from database',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  onChanged: (val) {
                    setDialogState(() {
                      alsoDeletePerson = val ?? true;
                    });
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);

                _showSnackBar('Deleting $count item(s)...');

                int deleted = 0;
                for (final id in idsToDelete) {
                  try {
                    // Check if group
                    final groupDoc = await _firestore.collection('groups').doc(id).get();
                    if (groupDoc.exists) {
                      await _chatService.deleteGroup(id);
                      deleted++;
                      continue;
                    }

                    // 1-on-1 contact
                    if (_currentUser != null) {
                      final chatId = _chatService.getChatId(_currentUser!.id, id);
                      await _chatService.deleteChatByChatId(chatId);

                      if (alsoDeletePerson) {
                        await _userService.deleteUser(id);
                      }
                      deleted++;
                    }
                  } catch (e) {
                    debugPrint('Error deleting $id: $e');
                  }
                }

                // Clear selection and force UI rebuild AFTER deletion completes
                if (mounted) {
                  setState(() {
                    _selectedChatIds.clear();
                  });
                  _showSnackBar('$deleted item(s) deleted');
                }
              },
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _markSelectedAsRead() async {
    final toMark = List<String>.from(_selectedChatIds);
    _clearSelection();
    if (_currentUser != null) {
      for (final otherId in toMark) {
        await _chatService.markChatAsRead(
          userId: _currentUser!.id,
          otherUserId: otherId,
        );
      }
    }
    _showSnackBar('${toMark.length} chat(s) marked as read');
  }

  Widget _buildChatsTab() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          children: [
            // ===== SELECTION MODE APP BAR =====
            if (_isSelectionMode)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                color: const Color(0xFF1A2530),
                padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                child: Row(
                  children: [
                    // Back / close selection
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: _clearSelection,
                    ),
                    // Selected count
                    Expanded(
                      child: Text(
                        '${_selectedChatIds.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Archive
                    IconButton(
                      tooltip: 'Archive',
                      icon: const Icon(Icons.archive_outlined, color: Colors.white),
                      onPressed: _archiveSelected,
                    ),
                    // Delete
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                      onPressed: _deleteSelected,
                    ),
                    // More options (mute, pin, mark as read)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                      color: Colors.white,
                      elevation: 10,
                      shadowColor: Colors.black.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      onSelected: (val) {
                        if (val == 'mute') _muteSelected();
                        if (val == 'pin') _pinSelected();
                        if (val == 'read') _markSelectedAsRead();
                      },
                      itemBuilder: (_) => [
                        _buildWhatsAppMenuItem('mute', 'Mute notifications', Icons.notifications_off_outlined, const Color(0xFFF59E0B)),
                        _buildWhatsAppMenuItem('pin', 'Pin chat', Icons.push_pin_outlined, const Color(0xFF5B50E6)),
                        _buildWhatsAppMenuItem('read', 'Mark as read', Icons.done_all_rounded, const Color(0xFF10B981)),
                      ],
                    ),
                  ],
                ),
              )
            else
            // ===== NORMAL APP BAR =====
            // Top Header: App Title, Camera, Search, More Menu
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'ChatApp',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF171B2D),
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // WhatsApp Pay (Circled Rupee) Shortcut
                  IconButton(
                    tooltip: 'Payments',
                    onPressed: () => _openScreen(const PaymentsScreen()),
                    icon: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF171B2D),
                          width: 1.8,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.currency_rupee_rounded,
                          size: 14,
                          color: Color(0xFF171B2D),
                        ),
                      ),
                    ),
                  ),

                  // In-App Camera Viewfinder Shortcut
                  IconButton(
                    icon: const Icon(Icons.camera_alt_outlined, color: Color(0xFF171B2D)),
                    tooltip: 'In-app Camera',
                    onPressed: _openCameraScreen,
                  ),

                  // 3-Dots Menu (Modern App UI Style)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF171B2D)),
                    color: Colors.white,
                    elevation: 12,
                    shadowColor: Colors.black.withValues(alpha: 0.18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    offset: const Offset(0, 48),
                    onSelected: (val) {
                      if (val == 'new_group') {
                        _openScreen(const CreateGroupScreen());
                      } else if (val == 'new_community') {
                        setState(() => _currentBottomNavIndex = 2);
                      } else if (val == 'broadcast_lists') {
                        _showBroadcastDialog();
                      } else if (val == 'linked_devices') {
                        _showLinkedDevicesDialog();
                      } else if (val == 'starred') {
                        _showStarredDialog();
                      } else if (val == 'meta_ai') {
                        _openScreen(const AiChatScreen());
                      } else if (val == 'payments') {
                        _openScreen(const PaymentsScreen());
                      } else if (val == 'read_all') {
                        _markAllChatsAsRead();
                      } else if (val == 'settings') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfileSetupScreen(
                              isEditing: true,
                              onSaved: _initUserAndCallListener,
                            ),
                          ),
                        );
                      } else if (val == 'switch_account') {
                        _switchAccount();
                      }
                    },
                    itemBuilder: (_) => [
                      _buildWhatsAppMenuItem('new_group', 'New group', Icons.group_add_outlined, const Color(0xFF5B50E6)),
                      _buildWhatsAppMenuItem('new_community', 'New community', Icons.groups_outlined, const Color(0xFF7C3AED)),
                      _buildWhatsAppMenuItem('broadcast_lists', 'Broadcast lists', Icons.campaign_outlined, const Color(0xFF2563EB)),
                      _buildWhatsAppMenuItem('linked_devices', 'Linked devices', Icons.devices_outlined, const Color(0xFF0D9488)),
                      _buildWhatsAppMenuItem('starred', 'Starred messages', Icons.star_border_rounded, const Color(0xFFF59E0B)),
                      _buildWhatsAppMenuItem('meta_ai', 'Meta AI', Icons.auto_awesome_rounded, const Color(0xFF8B5CF6)),
                      _buildWhatsAppMenuItem('payments', 'Payments', Icons.currency_rupee_rounded, const Color(0xFF10B981)),
                      _buildWhatsAppMenuItem('read_all', 'Mark all read', Icons.done_all_rounded, const Color(0xFF3B82F6)),
                      _buildWhatsAppMenuItem('settings', 'Settings', Icons.settings_outlined, const Color(0xFF6366F1)),
                      const PopupMenuDivider(height: 12),
                      _buildWhatsAppMenuItem('switch_account', 'Switch account', Icons.switch_account_outlined, const Color(0xFFEC4899)),
                    ],
                  ),
                ],
              ),
            ),

            // Search Bar ("Ask Meta AI or Search")
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.toLowerCase().trim()),
                  decoration: InputDecoration(
                    hintText: 'Ask Meta AI or Search',
                    hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Colors.grey,
                      size: 22,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                ),
              ),
            ),

            // WhatsApp Style Filter Chips: All, Unread, Groups
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Row(
                children: [
                  _buildFilterChip('All', 0),
                  const SizedBox(width: 8),
                  _buildFilterChip('Unread', 1),
                  const SizedBox(width: 8),
                  _buildFilterChip('Groups', 2),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // Real-time Chat & Group List Stream
            Expanded(
              child: StreamBuilder<List<UserModel>>(
                stream: _userService.getAllUsersStream(),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting && _currentUser == null) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF5B50E6)));
                  }

                  final allContacts = userSnapshot.data ?? [];

                  if (_currentUser == null) {
                    return const Center(child: Text('Loading conversations...'));
                  }

                  // Stream groups that the current user belongs to
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _chatService.getUserGroupsStream(_currentUser!.id),
                    builder: (context, groupSnapshot) {
                      final groupDocs = groupSnapshot.data?.docs ?? [];

                      // Stream recent individual chats
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _chatService.getRecentChatsStream(_currentUser!.id),
                        builder: (context, chatSnapshot) {
                          final chatDocs = chatSnapshot.data?.docs ?? [];
                          final Map<String, Map<String, dynamic>> recentChatMap = {};

                          for (final doc in chatDocs) {
                            final data = doc.data();
                            final List participants = List.from(data['participants'] ?? []);
                            final otherId = participants.firstWhere(
                              (id) => id != _currentUser!.id,
                              orElse: () => '',
                            );
                            if (otherId.isNotEmpty) {
                              recentChatMap[otherId] = data;
                            }
                          }

                          // Filter groups
                          final filteredGroups = groupDocs.where((doc) {
                            final name = doc.data()['name']?.toString().toLowerCase() ?? '';
                            if (_searchQuery.isEmpty) return true;
                            return name.contains(_searchQuery);
                          }).toList();

                          // Filter contacts
                          final filteredContacts = allContacts.where((u) {
                            if (_searchQuery.isEmpty) return true;
                            return u.name.toLowerCase().contains(_searchQuery) ||
                                u.phoneNumber.contains(_searchQuery);
                          }).toList();

                          // Sort contacts: unread chats first, then by most recent message time, then name
                          filteredContacts.sort((a, b) {
                            final aChat = recentChatMap[a.id];
                            final bChat = recentChatMap[b.id];
                            final aUnread = (aChat?['unread_${_currentUser?.id}'] as num?)?.toInt() ?? 0;
                            final bUnread = (bChat?['unread_${_currentUser?.id}'] as num?)?.toInt() ?? 0;

                            // 1. Unread conversations come first
                            if (aUnread > 0 && bUnread == 0) return -1;
                            if (aUnread == 0 && bUnread > 0) return 1;
                            if (aUnread > 0 && bUnread > 0 && aUnread != bUnread) {
                              return bUnread.compareTo(aUnread);
                            }

                            // 2. Most recent active conversation
                            final dynamic aTimeRaw = aChat?['lastMessageTime'];
                            final dynamic bTimeRaw = bChat?['lastMessageTime'];
                            final DateTime? aTime = aTimeRaw is Timestamp ? aTimeRaw.toDate() : null;
                            final DateTime? bTime = bTimeRaw is Timestamp ? bTimeRaw.toDate() : null;

                            if (aTime != null && bTime != null) {
                              return bTime.compareTo(aTime);
                            }
                            if (aTime != null && bTime == null) return -1;
                            if (aTime == null && bTime != null) return 1;

                            // 3. Fallback: alphabetical
                            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                          });

                          // If "Groups" filter is selected: show only groups
                          if (_selectedFilter == 2) {
                            if (filteredGroups.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.groups_outlined, size: 64, color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'No groups created yet',
                                      style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 10),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF5B50E6),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                      ),
                                      icon: const Icon(Icons.group_add_rounded, color: Colors.white),
                                      label: const Text('Create Group', style: TextStyle(color: Colors.white)),
                                      onPressed: () => _openScreen(const CreateGroupScreen()),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              itemCount: filteredGroups.length,
                              itemBuilder: (context, index) {
                                return _buildGroupChatItem(filteredGroups[index]);
                              },
                            );
                          }

                          // If "Unread" filter: show groups and contacts with unread messages
                          if (_selectedFilter == 1) {
                            final unreadGroups = filteredGroups.where((g) {
                              final unread = (g.data()['unread_${_currentUser?.id}'] as num?)?.toInt() ?? 0;
                              return unread > 0;
                            }).toList();

                            final unreadContacts = filteredContacts.where((c) {
                              final chatInfo = recentChatMap[c.id];
                              if (chatInfo == null) return false;
                              final unread = (chatInfo['unread_${_currentUser?.id}'] as num?)?.toInt() ?? 0;
                              return unread > 0;
                            }).toList();

                            final totalUnread = unreadGroups.length + unreadContacts.length;

                            if (totalUnread == 0) {
                              return const Center(
                                child: Text('No unread conversations', style: TextStyle(color: Colors.grey, fontSize: 15)),
                              );
                            }
                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              itemCount: totalUnread,
                              itemBuilder: (context, index) {
                                if (index < unreadGroups.length) {
                                  return _buildGroupChatItem(unreadGroups[index]);
                                } else {
                                  final contact = unreadContacts[index - unreadGroups.length];
                                  final chatInfo = recentChatMap[contact.id];
                                  return _buildWhatsAppChatItem(contact, chatInfo);
                                }
                              },
                            );
                          }

                          // Default "All" filter: Show Groups first, then contacts
                          final totalItems = filteredGroups.length + filteredContacts.length;
                          if (totalItems == 0) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.chat_bubble_outline_rounded, size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No conversations yet',
                                    style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF5B50E6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    ),
                                    icon: const Icon(Icons.add, color: Colors.white),
                                    label: const Text('Start Chat', style: TextStyle(color: Colors.white)),
                                    onPressed: () => _openScreen(const UsersListScreen()),
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            itemCount: totalItems,
                            itemBuilder: (context, index) {
                              if (index < filteredGroups.length) {
                                return _buildGroupChatItem(filteredGroups[index]);
                              } else {
                                final contactIndex = index - filteredGroups.length;
                                final contact = filteredContacts[contactIndex];
                                final chatInfo = recentChatMap[contact.id];
                                return _buildWhatsAppChatItem(contact, chatInfo);
                              }
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedFilter == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF5B50E6) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF171B2D),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildGroupChatItem(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final name = data['name']?.toString() ?? 'Group';
    final lastMsg = data['lastMessage']?.toString() ?? 'No messages yet';
    final lastSenderName = data['lastSenderName']?.toString();
    final lastMsgTime = data['lastMessageTime'];
    DateTime? dt;
    if (lastMsgTime is Timestamp) {
      dt = lastMsgTime.toDate();
    }
    final timeText = dt != null ? _formatChatTime(dt) : '';
    final members = List<String>.from(data['members'] ?? []);

    final int unreadCount = _currentUser != null
        ? ((data['unread_${_currentUser!.id}'] as num?)?.toInt() ?? 0)
        : 0;
    final bool hasUnread = unreadCount > 0;

    final subtitle = (lastSenderName != null && lastSenderName.isNotEmpty)
        ? '$lastSenderName: $lastMsg'
        : lastMsg;

    final bool isGroupSelected = _selectedChatIds.contains(doc.id);

    return GestureDetector(
      onLongPress: () => _toggleSelect(doc.id),
      onTap: _isSelectionMode
          ? () => _toggleSelect(doc.id)
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupChatScreen(
                    groupId: doc.id,
                    groupName: name,
                    memberIds: members,
                  ),
                ),
              );
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: isGroupSelected
              ? Border.all(color: const Color(0xFF5B50E6).withValues(alpha: 0.4), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Material(
          color: isGroupSelected ? const Color(0xFF5B50E6).withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFF5B50E6).withValues(alpha: 0.15),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '\u{1F465}',
                    style: const TextStyle(
                      color: Color(0xFF5B50E6),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                if (isGroupSelected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B50E6).withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
                    ),
                  )
                else
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFF7C3AED),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.groups_rounded, size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: hasUnread ? FontWeight.w900 : FontWeight.bold,
                      fontSize: 15.5,
                      color: const Color(0xFF171B2D),
                    ),
                  ),
                ),
                if (timeText.isNotEmpty)
                  Text(
                    timeText,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: hasUnread ? const Color(0xFF10B981) : Colors.grey,
                      fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  const Icon(Icons.done_all_rounded, size: 15, color: Color(0xFF5B50E6)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasUnread ? const Color(0xFF171B2D) : Colors.grey.shade600,
                        fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (hasUnread) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      alignment: Alignment.center,
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Individual WhatsApp-style chat list tile with real presence and message snippet
  Widget _buildWhatsAppChatItem(UserModel contact, Map<String, dynamic>? chatInfo) {
    return StreamBuilder<UserModel?>(
      stream: _userService.streamUser(contact.id),
      initialData: contact,
      builder: (context, presenceSnap) {
        final liveUser = presenceSnap.data ?? contact;
        final bool isOnline = liveUser.isOnline;

        String subtitleText = 'Tap to chat';
        String timeText = '';
        int unreadCount = 0;
        String lastMsgStatus = 'sent';
        bool iLastMsgByMe = false;

        if (chatInfo != null) {
          subtitleText = chatInfo['lastMessage']?.toString() ?? 'Media';
          final dynamic time = chatInfo['lastMessageTime'];
          if (time is Timestamp) {
            timeText = _formatChatTime(time.toDate());
          }
          unreadCount = (chatInfo['unread_${_currentUser?.id}'] as num?)?.toInt() ?? 0;
          lastMsgStatus = chatInfo['lastMessageStatus']?.toString() ?? 'sent';
          iLastMsgByMe = chatInfo['lastSenderId']?.toString() == _currentUser?.id;
        } else {
          // Outside chat list: do not clutter with last seen, simply show 'Tap to chat'
          subtitleText = 'Tap to chat';
        }

        final bool hasUnread = unreadCount > 0;
        final bool isContactSelected = _selectedChatIds.contains(contact.id);

        return GestureDetector(
          onLongPress: () => _toggleSelect(contact.id),
          onTap: _isSelectionMode
              ? () => _toggleSelect(contact.id)
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(targetUser: liveUser),
                    ),
                  ).then((_) {
                    if (_currentUser != null) {
                      _chatService.markChatAsRead(
                        userId: _currentUser!.id,
                        otherUserId: liveUser.id,
                      );
                    }
                  });
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: isContactSelected
                  ? Border.all(color: const Color(0xFF5B50E6).withValues(alpha: 0.4), width: 1.5)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Material(
              color: isContactSelected ? const Color(0xFF5B50E6).withValues(alpha: 0.12) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundImage: getAvatarImageProvider(liveUser.avatarUrl),
                  backgroundColor: const Color(0xFF5B50E6).withValues(alpha: 0.12),
                  child: getAvatarImageProvider(liveUser.avatarUrl) == null
                      ? Text(
                          liveUser.name.isNotEmpty ? liveUser.name[0].toUpperCase() : '\u{1F464}',
                          style: const TextStyle(
                            color: Color(0xFF5B50E6),
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        )
                      : null,
                ),
                // Show checkmark overlay when selected
                if (isContactSelected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B50E6).withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
                    ),
                  )
                // Show green dot ONLY if online and NOT selected
                else if (isOnline)
                  Positioned(
                    bottom: 1,
                    right: 1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    liveUser.name.isNotEmpty ? liveUser.name : liveUser.phoneNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: hasUnread ? FontWeight.w900 : FontWeight.bold,
                      fontSize: 15.5,
                      color: const Color(0xFF171B2D),
                    ),
                  ),
                ),
                if (timeText.isNotEmpty)
                  Text(
                    timeText,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: hasUnread ? const Color(0xFF10B981) : Colors.grey,
                      fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  if (chatInfo != null && iLastMsgByMe) ...[
                    _buildHomeTickIcon(lastMsgStatus),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      subtitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasUnread
                            ? const Color(0xFF171B2D)
                            : (isOnline && chatInfo == null)
                                ? const Color(0xFF10B981)
                                : Colors.grey.shade600,
                        fontSize: 13,
                        fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (hasUnread) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  },
);
}

  Widget _buildHomeTickIcon(String status) {
    if (status == 'read') {
      return const Icon(Icons.done_all_rounded, size: 15, color: Color(0xFF38BDF8));
    } else if (status == 'delivered') {
      return Icon(Icons.done_all_rounded, size: 15, color: Colors.grey.shade500);
    } else {
      return Icon(Icons.check_rounded, size: 15, color: Colors.grey.shade500);
    }
  }

  String _formatChatTime(DateTime dt) {
    final now = DateTime.now();
    if (now.year == dt.year && now.month == dt.month && now.day == dt.day) {
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    } else if (now.difference(dt).inDays <= 1) {
      return 'Yesterday';
    } else {
      return '${dt.day}/${dt.month}';
    }
  }

  String _formatStatusTime(DateTime dt) {
    final now = DateTime.now();
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:$minute $period';

    if (now.year == dt.year && now.month == dt.month && now.day == dt.day) {
      return 'Today, $timeStr';
    }
    final yesterday = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
      return 'Yesterday, $timeStr';
    }

    final List<String> months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthName = months[dt.month - 1];
    final dayStr = dt.day.toString().padLeft(2, '0');
    return '$dayStr $monthName, $timeStr';
  }

  Widget _buildStatusThumbnail(StatusModel status, {double size = 48}) {
    if (status.type == 'image' && status.mediaUrl != null && status.mediaUrl!.isNotEmpty) {
      final url = status.mediaUrl!;
      Widget img;
      if (url.startsWith('data:image')) {
        img = Image.memory(
          base64Decode(url.contains(',') ? url.split(',').last : url),
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey),
        );
      } else {
        img = Image.network(
          url,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(width: size, height: size, child: img),
      );
    } else if (status.type == 'video') {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 24),
      );
    } else {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Color(status.bgColor ?? const Color(0xFF5B50E6).toARGB32()),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(4),
        alignment: Alignment.center,
        child: Text(
          status.textContent ?? 'T',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );
    }
  }

  void _showMyStatusOptions(List<StatusModel> myStatuses) {
    if (myStatuses.isEmpty) {
      _openAddStatusDialog();
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'My Status Updates',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF171B2D)),
                      ),
                      Text(
                        '${myStatuses.length} active ${myStatuses.length == 1 ? 'status' : 'statuses'} (24h validity)',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFF5B50E6)),
                    tooltip: 'Add new status',
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openAddStatusDialog();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFFECEFF5)),
              const SizedBox(height: 8),

              // List of all user's posted status photos / videos / texts
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: myStatuses.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F3F9)),
                  itemBuilder: (context, idx) {
                    final status = myStatuses[idx];
                    final String typeLabel = status.type == 'image'
                        ? 'Photo status'
                        : (status.type == 'video' ? 'Video status' : 'Text status');

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      leading: _buildStatusThumbnail(status, size: 48),
                      title: Text(
                        typeLabel,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                      ),
                      subtitle: Text(
                        _formatStatusTime(status.timestamp),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showStatusStory(status);
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.visibility_outlined, color: Color(0xFF5B50E6), size: 22),
                            tooltip: 'View',
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showStatusStory(status);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                            tooltip: 'Delete this status photo',
                            onPressed: () {
                              Navigator.pop(ctx);
                              _confirmDeleteStatus(status);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Bottom Actions: Add New Status & Delete All
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF5B50E6),
                        side: const BorderSide(color: Color(0xFF5B50E6)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Status', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openAddStatusDialog();
                      },
                    ),
                  ),
                  if (myStatuses.length > 1) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.delete_forever_rounded, size: 18),
                        label: const Text('Delete All', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmDeleteAllStatuses(myStatuses);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteStatus(StatusModel status) async {
    final String typeName = status.type == 'image' ? 'photo' : (status.type == 'video' ? 'video' : 'text');

    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text('Delete $typeName status?', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          'This status update will be permanently deleted and removed for all your contacts.',
          style: TextStyle(fontSize: 14, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        await _chatService.deleteStatus(status.id);
        _showSnackBar('Status $typeName deleted successfully');
      } catch (e) {
        _showSnackBar('Failed to delete status: $e');
      }
    }
  }

  Future<void> _confirmDeleteAllStatuses(List<StatusModel> statuses) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete all status updates?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          'All ${statuses.length} status updates will be permanently deleted.',
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        for (final s in statuses) {
          await _chatService.deleteStatus(s.id);
        }
        _showSnackBar('All ${statuses.length} statuses deleted successfully');
      } catch (e) {
        _showSnackBar('Failed to delete statuses: $e');
      }
    }
  }

  // ============================================================
  // TAB 1: UPDATES / STATUS TAB (REAL FIRESTORE & 24H VALIDITY)
  // ============================================================

  Widget _buildUpdatesTab() {
    if (_currentUser == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF5B50E6)));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _chatService.getStatusesStream(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final now = DateTime.now();
        final cutoff = now.subtract(const Duration(hours: 24));

        final List<StatusModel> allValidStatuses = [];
        for (var doc in docs) {
          try {
            final s = StatusModel.fromFirestore(doc);
            if (s.timestamp.isAfter(cutoff)) {
              allValidStatuses.add(s);
            }
          } catch (_) {}
        }

        // Separate current user statuses and others
        final myStatuses = allValidStatuses.where((s) => s.userId == _currentUser!.id).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        final otherStatuses = allValidStatuses.where((s) => s.userId != _currentUser!.id).toList();

        // Deduplicate other users' statuses so each user appears only once with their latest update
        final Map<String, StatusModel> uniqueUserStatusMap = {};
        for (var s in otherStatuses) {
          if (!uniqueUserStatusMap.containsKey(s.userId) || s.timestamp.isAfter(uniqueUserStatusMap[s.userId]!.timestamp)) {
            uniqueUserStatusMap[s.userId] = s;
          }
        }
        final List<StatusModel> recentContactUpdates = uniqueUserStatusMap.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Updates',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF171B2D)),
                ),
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate_rounded, color: Color(0xFF5B50E6)),
                  tooltip: 'Add Status',
                  onPressed: _openAddStatusDialog,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // My Status Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: myStatuses.isNotEmpty
                        ? () => _showStatusStory(myStatuses.first)
                        : _openAddStatusDialog,
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: myStatuses.isNotEmpty ? const Color(0xFF10B981) : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 24,
                            backgroundColor: const Color(0xFF5B50E6).withValues(alpha: 0.15),
                            child: Text(
                              _currentUser!.name.isNotEmpty ? _currentUser!.name[0].toUpperCase() : 'U',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B50E6), fontSize: 18),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _openAddStatusDialog,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.add, color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: GestureDetector(
                      onTap: myStatuses.isNotEmpty
                          ? () => _showStatusStory(myStatuses.first)
                          : _openAddStatusDialog,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('My status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(
                            myStatuses.isNotEmpty
                                ? _formatStatusTime(myStatuses.first.timestamp)
                                : 'Tap to add status update (24h valid)',
                            style: TextStyle(
                              color: myStatuses.isNotEmpty ? Colors.black54 : Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
                    tooltip: 'Status Options',
                    onPressed: () => _showMyStatusOptions(myStatuses),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text('Recent updates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF171B2D))),
            const SizedBox(height: 12),

            if (recentContactUpdates.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.amp_stories_rounded, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      const Text(
                        'No recent updates from contacts',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...recentContactUpdates.map((status) {
                return _buildRecentStatusTile(status);
              }),
          ],
        );
      },
    );
  }

  Widget _buildRecentStatusTile(StatusModel status) {
    return GestureDetector(
      onTap: () => _showStatusStory(status),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF10B981), width: 2.5),
              ),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                child: Text(
                  status.userName.isNotEmpty ? status.userName[0].toUpperCase() : 'U',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7C3AED)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status.userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Row(
                    children: [
                      if (status.type == 'video')
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.videocam_rounded, size: 14, color: Colors.grey),
                        ),
                      Text(_formatStatusTime(status.timestamp), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _openAddStatusDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Add status update', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF5B50E6),
                  child: Icon(Icons.camera_alt_rounded, color: Colors.white),
                ),
                title: const Text('Photo status', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Share a photo from camera or gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadPhotoStatus();
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEF4444),
                  child: Icon(Icons.videocam_rounded, color: Colors.white),
                ),
                title: const Text('Video status', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Share a video clip (up to 60s)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadVideoStatus();
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF7C3AED),
                  child: Icon(Icons.edit_rounded, color: Colors.white),
                ),
                title: const Text('Text status', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Type a message with colored background'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCreateTextStatusDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadPhotoStatus() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1280,
      maxHeight: 1280,
    );

    if (image == null || _currentUser == null) return;

    _showSnackBar('Uploading status photo...');
    try {
      final file = File(image.path);
      final fileName = 'status_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = 'statuses/${_currentUser!.id}/$fileName';

      String downloadUrl = '';
      try {
        downloadUrl = await _chatService.uploadFile(file, path);
      } catch (_) {
        final bytes = await file.readAsBytes();
        downloadUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }

      await _chatService.uploadStatus(
        userId: _currentUser!.id,
        userName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
        userPhone: _currentUser!.phoneNumber,
        mediaUrl: downloadUrl,
        type: 'image',
      );

      _showSnackBar('Status updated successfully! Valid for 24 hours.');
    } catch (e) {
      _showSnackBar('Failed to update status: $e');
    }
  }

  Future<void> _pickAndUploadVideoStatus() async {
    final ImagePicker picker = ImagePicker();
    final XFile? video = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );

    if (video == null || _currentUser == null) return;

    _showSnackBar('Uploading status video...');
    try {
      final file = File(video.path);
      final fileName = 'status_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final path = 'statuses/${_currentUser!.id}/$fileName';

      String downloadUrl = '';
      try {
        downloadUrl = await _chatService.uploadFile(file, path);
      } catch (_) {
        downloadUrl = video.path;
      }

      await _chatService.uploadStatus(
        userId: _currentUser!.id,
        userName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
        userPhone: _currentUser!.phoneNumber,
        mediaUrl: downloadUrl,
        type: 'video',
      );

      _showSnackBar('Video status updated successfully! Valid for 24 hours.');
    } catch (e) {
      _showSnackBar('Failed to update video status: $e');
    }
  }

  void _openCreateTextStatusDialog() {
    final textController = TextEditingController();
    int selectedColor = const Color(0xFF5B50E6).toARGB32();
    final List<Color> colors = [
      const Color(0xFF5B50E6),
      const Color(0xFF7C3AED),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF06B6D4),
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: Color(selectedColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('New Text Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: const InputDecoration(
                  hintText: 'Type a status...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: colors.map((c) {
                  final isSelected = c.toARGB32() == selectedColor;
                  return GestureDetector(
                    onTap: () => setModalState(() => selectedColor = c.toARGB32()),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: isSelected ? 3 : 1),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              onPressed: () async {
                final text = textController.text.trim();
                if (text.isNotEmpty && _currentUser != null) {
                  Navigator.pop(ctx);
                  await _chatService.uploadStatus(
                    userId: _currentUser!.id,
                    userName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
                    userPhone: _currentUser!.phoneNumber,
                    textContent: text,
                    type: 'text',
                    bgColor: selectedColor,
                  );
                  _showSnackBar('Status updated successfully! Valid for 24 hours.');
                }
              },
              child: const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }

  void _showStatusStory(StatusModel status) {
    final bool isMyStatus = _currentUser != null && status.userId == _currentUser!.id;

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Status Content
            if (status.type == 'video' && status.mediaUrl != null)
              Center(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context); // close dialog first
                    InAppVideoPlayerScreen.open(
                      context,
                      mediaUrl: status.mediaUrl!,
                      title: 'Video Status',
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: Color(0xFF5B50E6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 48),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Tap to play video status',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (status.type == 'image' && status.mediaUrl != null)
              InteractiveViewer(
                child: Center(
                  child: status.mediaUrl!.startsWith('data:image')
                      ? Image.memory(
                          base64Decode(status.mediaUrl!.contains(',') ? status.mediaUrl!.split(',').last : status.mediaUrl!),
                          fit: BoxFit.contain,
                        )
                      : Image.network(
                          status.mediaUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Center(
                            child: Icon(Icons.broken_image, color: Colors.white, size: 64),
                          ),
                        ),
                ),
              )
            else
              Container(
                color: Color(status.bgColor ?? const Color(0xFF5B50E6).toARGB32()),
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                child: Text(
                  status.textContent ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),

            // Top Header Bar
            Positioned(
              top: 40,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white24,
                    child: Text(
                      status.userName.isNotEmpty ? status.userName[0].toUpperCase() : 'U',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMyStatus ? 'You' : status.userName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          _formatStatusTime(status.timestamp),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),

                  // Delete status icon if it's the current user's status
                  if (isMyStatus)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
                      tooltip: 'Delete Status',
                      onPressed: () {
                        Navigator.pop(ctx);
                        _confirmDeleteStatus(status);
                      },
                    ),

                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TAB 2: COMMUNITIES & GROUPS TAB
  // ============================================================

  Widget _buildCommunitiesTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Communities & Groups',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF171B2D)),
            ),
            IconButton(
              icon: const Icon(Icons.group_add_rounded, color: Color(0xFF5B50E6)),
              tooltip: 'New Group',
              onPressed: () => _openScreen(const CreateGroupScreen()),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // New Community / Group Banner
        GestureDetector(
          onTap: () => _openScreen(const CreateGroupScreen()),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B50E6).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.groups_rounded, color: Color(0xFF5B50E6), size: 28),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xFF25D366),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New Community or Group',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF171B2D)),
                    ),
                    SizedBox(height: 2),
                    Text('Create group chat with contacts', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Real Groups Stream from Firestore
        if (_currentUser != null)
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _chatService.getUserGroupsStream(_currentUser!.id),
            builder: (context, snapshot) {
              final groups = snapshot.data?.docs ?? [];
              if (groups.isEmpty) {
                return Column(
                  children: [
                    _buildCommunityCard(
                      title: 'Biz Boss',
                      subtitle: 'Business & Entrepreneurship community',
                      iconText: 'BB',
                      iconBg: const Color(0xFF25D366),
                    ),
                    const SizedBox(height: 12),
                    _buildCommunityCard(
                      title: 'Sanfoundry Tech',
                      subtitle: 'Engineering & Technology hub',
                      iconText: 'SF',
                      iconBg: const Color(0xFF5B50E6),
                    ),
                  ],
                );
              }

              return Column(
                children: groups.map((doc) {
                  final data = doc.data();
                  final name = data['name']?.toString() ?? 'Group';
                  final lastMsg = data['lastMessage']?.toString() ?? 'No messages yet';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8),
                      ],
                    ),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                        onTap: () {
                          final members = List<String>.from(data['members'] ?? []);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupChatScreen(
                                groupId: doc.id,
                                groupName: name,
                                memberIds: members,
                              ),
                            ),
                          );
                        },
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFF5B50E6).withValues(alpha: 0.15),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '👥',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B50E6), fontSize: 18),
                          ),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        trailing: const Icon(Icons.chat_bubble_outline_rounded, size: 20, color: Color(0xFF5B50E6)),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _buildCommunityCard({
    required String title,
    required String subtitle,
    required String iconText,
    required Color iconBg,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                iconText,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
        ),
      ),
    );
  }

  // ============================================================
  // TAB 3: REAL CALL HISTORY TAB FROM FIRESTORE
  // ============================================================

  void _showClearCallHistoryDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Clear call log?'),
        content: const Text('Do you want to clear your entire call history? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _clearAllCallHistory();
            },
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllCallHistory() async {
    if (_currentUser == null) return;
    final uid = _currentUser!.id;

    try {
      final callsQuery = await _firestore.collection('calls').get();
      final batch = _firestore.batch();
      int count = 0;

      for (final doc in callsQuery.docs) {
        final data = doc.data();
        if (data['callerId'] == uid || data['receiverId'] == uid) {
          batch.delete(doc.reference);
          count++;
          if (count >= 400) break;
        }
      }

      final groupCallsQuery = await _firestore.collection('group_calls').get();
      for (final doc in groupCallsQuery.docs) {
        final data = doc.data();
        final List invited = List.from(data['invitedUserIds'] ?? []);
        final callerId = data['callerId']?.toString();
        if (callerId == uid || invited.contains(uid)) {
          batch.delete(doc.reference);
          count++;
          if (count >= 480) break;
        }
      }

      await batch.commit();
      _showSnackBar('Call history cleared ✓');
    } catch (e) {
      _showSnackBar('Failed to clear call history: $e');
    }
  }

  Widget _buildCallsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Calls',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF171B2D)),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_call, color: Color(0xFF5B50E6)),
                    tooltip: 'New Call',
                    onPressed: () => _openScreen(const UsersListScreen()),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF171B2D)),
                    color: Colors.white,
                    elevation: 8,
                    shadowColor: Colors.black.withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    offset: const Offset(0, 48),
                    onSelected: (val) {
                      if (val == 'clear_all') {
                        _showClearCallHistoryDialog();
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'clear_all',
                        child: Row(
                          children: [
                            Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20),
                            SizedBox(width: 10),
                            Text('Clear call log', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: _currentUser == null
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF5B50E6)))
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _firestore.collection('calls').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFF5B50E6)));
                    }

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _firestore.collection('group_calls').snapshots(),
                      builder: (context, groupCallSnapshot) {
                        final allCalls = snapshot.data?.docs ?? [];
                        final allGroupCalls = groupCallSnapshot.data?.docs ?? [];

                        final List<Map<String, dynamic>> combinedCalls = [];

                        // 1. One-on-one calls involving current user
                        for (final doc in allCalls) {
                          final data = doc.data();
                          final callerId = data['callerId']?.toString() ?? '';
                          final receiverId = data['receiverId']?.toString() ?? '';
                          if (callerId == _currentUser!.id || receiverId == _currentUser!.id) {
                            final dynamic timeVal = data['createdAt'] ?? data['timestamp'];
                            DateTime dt = DateTime.fromMillisecondsSinceEpoch(0);
                            if (timeVal is Timestamp) dt = timeVal.toDate();

                            combinedCalls.add({
                              'isGroup': false,
                              'docId': doc.id,
                              'callerId': callerId,
                              'receiverId': receiverId,
                              'type': data['type']?.toString() ?? 'voice',
                              'status': data['status']?.toString() ?? 'ended',
                              'timestamp': dt,
                              'data': data,
                            });
                          }
                        }

                        // 2. Group calls involving current user
                        for (final doc in allGroupCalls) {
                          final data = doc.data();
                          final callerId = data['callerId']?.toString() ?? '';
                          final List invited = List.from(data['invitedUserIds'] ?? []);
                          if (callerId == _currentUser!.id || invited.contains(_currentUser!.id)) {
                            final dynamic timeVal = data['createdAt'];
                            DateTime dt = DateTime.fromMillisecondsSinceEpoch(0);
                            if (timeVal is Timestamp) dt = timeVal.toDate();

                            combinedCalls.add({
                              'isGroup': true,
                              'docId': doc.id,
                              'groupId': data['groupId']?.toString() ?? '',
                              'groupName': data['groupName']?.toString() ?? 'Group Call',
                              'callerId': callerId,
                              'callerName': data['callerName']?.toString() ?? 'Member',
                              'type': data['callType']?.toString() ?? 'voice',
                              'status': data['status']?.toString() ?? 'ended',
                              'timestamp': dt,
                              'data': data,
                            });
                          }
                        }

                        // Sort newest first
                        combinedCalls.sort((a, b) {
                          final DateTime aDt = a['timestamp'] as DateTime;
                          final DateTime bDt = b['timestamp'] as DateTime;
                          return bDt.compareTo(aDt);
                        });

                        if (combinedCalls.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.phone_disabled_rounded, size: 56, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                const Text(
                                  'No recent calls',
                                  style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF5B50E6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                  icon: const Icon(Icons.phone, color: Colors.white),
                                  label: const Text('Start a call', style: TextStyle(color: Colors.white)),
                                  onPressed: () => _openScreen(const UsersListScreen()),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          itemCount: combinedCalls.length,
                          itemBuilder: (context, index) {
                            final item = combinedCalls[index];
                            final bool isGroup = item['isGroup'] == true;
                            final String callType = item['type']?.toString() ?? 'voice';
                            final String status = item['status']?.toString() ?? 'ended';
                            final DateTime dt = item['timestamp'] as DateTime;
                            final String timeString = _formatChatTime(dt);

                            if (isGroup) {
                              final String groupName = item['groupName'] ?? 'Group Call';
                              final String callerName = item['callerName'] ?? 'Member';
                              final bool isOutgoing = item['callerId'] == _currentUser!.id;
                              final bool isMissed = status == 'missed' || (status == 'rejected' && !isOutgoing);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                                    onTap: () {
                                      final groupId = item['groupId']?.toString() ?? '';
                                      if (groupId.isNotEmpty) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => GroupChatScreen(
                                              groupId: groupId,
                                              groupName: groupName,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    leading: CircleAvatar(
                                      radius: 22,
                                      backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                                      child: const Icon(Icons.groups_rounded, color: Color(0xFF7C3AED), size: 22),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            groupName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: isMissed ? Colors.redAccent : const Color(0xFF171B2D),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text('Group', style: TextStyle(fontSize: 10.5, color: Color(0xFF7C3AED), fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                    subtitle: Row(
                                      children: [
                                        Icon(
                                          isOutgoing
                                              ? Icons.call_made_rounded
                                              : (isMissed ? Icons.call_missed_rounded : Icons.call_received_rounded),
                                          size: 16,
                                          color: isMissed ? Colors.redAccent : const Color(0xFF10B981),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '${isOutgoing ? 'You' : callerName} • $timeString',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: Icon(
                                      callType == 'video' ? Icons.videocam_rounded : Icons.phone_rounded,
                                      color: const Color(0xFF5B50E6),
                                    ),
                                  ),
                                ),
                              );
                            }

                            // 1-on-1 Call Item
                            final callData = item['data'] as Map<String, dynamic>;
                            final String callerId = item['callerId']?.toString() ?? '';
                            final String receiverId = item['receiverId']?.toString() ?? '';
                            final bool isOutgoing = callerId == _currentUser!.id;
                            final String otherUserId = isOutgoing ? receiverId : callerId;
                            final bool isMissed = status == 'missed' || (status == 'rejected' && !isOutgoing);

                            return FutureBuilder<UserModel?>(
                              future: _userService.getUserById(otherUserId),
                              builder: (context, userSnap) {
                                final otherUser = userSnap.data;
                                final displayName = otherUser != null && otherUser.name.isNotEmpty
                                    ? otherUser.name
                                    : (otherUser?.phoneNumber.isNotEmpty == true ? otherUser!.phoneNumber : 'User');

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    clipBehavior: Clip.antiAlias,
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => CallInfoScreen(
                                              otherUser: otherUser,
                                              otherUserId: otherUserId,
                                              displayName: displayName,
                                              displayPhone: otherUser?.phoneNumber ??
                                                  (callData['receiverPhone']?.toString() ??
                                                      callData['callerPhone']?.toString() ??
                                                      ''),
                                              initialCallData: callData,
                                            ),
                                          ),
                                        );
                                      },
                                      leading: CircleAvatar(
                                        radius: 22,
                                        backgroundColor: const Color(0xFF5B50E6).withValues(alpha: 0.12),
                                        backgroundImage: getAvatarImageProvider(otherUser?.avatarUrl),
                                        child: getAvatarImageProvider(otherUser?.avatarUrl) == null
                                            ? Text(
                                                displayName.isNotEmpty ? displayName[0].toUpperCase() : '👤',
                                                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B50E6)),
                                              )
                                            : null,
                                      ),
                                      title: Text(
                                        displayName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: isMissed ? Colors.redAccent : const Color(0xFF171B2D),
                                        ),
                                      ),
                                      subtitle: Row(
                                        children: [
                                          Icon(
                                            isOutgoing
                                                ? Icons.call_made_rounded
                                                : (isMissed ? Icons.call_missed_rounded : Icons.call_received_rounded),
                                            size: 16,
                                            color: isMissed ? Colors.redAccent : const Color(0xFF10B981),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(timeString, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                        ],
                                      ),
                                      trailing: IconButton(
                                        icon: Icon(
                                          callType == 'video' ? Icons.videocam_rounded : Icons.phone_rounded,
                                          color: const Color(0xFF5B50E6),
                                        ),
                                        onPressed: otherUser == null
                                            ? null
                                            : () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => CallScreen(
                                                      callerId: _currentUser!.id,
                                                      callerName: _currentUser!.name,
                                                      callerPhone: _currentUser!.phoneNumber,
                                                      callerAvatarUrl: _currentUser!.avatarUrl,
                                                      receiverId: otherUser.id,
                                                      receiverName: otherUser.name,
                                                      receiverPhone: otherUser.phoneNumber,
                                                      receiverAvatarUrl: otherUser.avatarUrl,
                                                      isIncoming: false,
                                                      callType: callType,
                                                    ),
                                                  ),
                                                );
                                              },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}