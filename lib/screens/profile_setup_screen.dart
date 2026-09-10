import 'dart:convert';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/user_service.dart';
import '../widgets/avatar_image_helper.dart';
import 'payments_screen.dart';
import 'whatsapp_qr_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  final bool isEditing;
  final VoidCallback? onSaved;

  const ProfileSetupScreen({
    super.key,
    this.isEditing = false,
    this.onSaved,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final UserService _userService = UserService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _aboutController = TextEditingController(
    text: 'Memories With The Right People Are Always Priceless.🪄',
  );
  final TextEditingController _upiController = TextEditingController(
    text: 'dhivya032005-1@okhdfcbank',
  );
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  bool _isSavingAvatar = false;
  String? _newAvatarUrl;
  bool _isSearching = false;
  String _searchQuery = '';

  // Settings state toggles
  bool _readReceipts = true;
  bool _notificationsEnabled = true;
  String _selectedLanguage = 'English (device\'s language)';
  String _selectedTheme = 'System default';

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  Future<void> _loadExistingProfile() async {
    final profile = await _userService.getCurrentUserProfile();
    if (profile != null && mounted) {
      setState(() {
        if (profile.name.isNotEmpty) {
          _nameController.text = profile.name;
        }
        _phoneController.text = profile.phoneNumber;
        if (profile.about.isNotEmpty) {
          _aboutController.text = profile.about;
        }
        if (profile.upiId != null && profile.upiId!.isNotEmpty) {
          _upiController.text = profile.upiId!;
        } else if (profile.name.toLowerCase().contains('dhivya')) {
          _upiController.text = 'dhivya032005-1@okhdfcbank';
        }
        _newAvatarUrl = profile.avatarUrl;
      });
    }
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? img = await picker.pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 360,
        maxHeight: 360,
      );
      if (img == null) return;

      setState(() => _isSavingAvatar = true);

      final uid = _userService.currentUserId ?? 'unknown';
      String? uploadedUrl;

      // 1. First try Firebase Storage
      try {
        final ext = img.path.split('.').last;
        final ref = FirebaseStorage.instance
            .ref()
            .child('avatars/$uid/profile.$ext');
        await ref.putFile(File(img.path));
        uploadedUrl = await ref.getDownloadURL();
      } catch (storageError) {
        debugPrint('FirebaseStorage upload failed, falling back to base64: $storageError');
        final bytes = await File(img.path).readAsBytes();
        final base64Str = base64Encode(bytes);
        uploadedUrl = 'data:image/jpeg;base64,$base64Str';
      }

      // Save directly to user profile in Firestore
      await _userService.saveUserProfile(
        name: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        avatarUrl: uploadedUrl,
        about: _aboutController.text.trim(),
        upiId: _upiController.text.trim().isNotEmpty ? _upiController.text.trim() : null,
      );

      setState(() {
        _newAvatarUrl = uploadedUrl;
        _isSavingAvatar = false;
      });

      _showSnack('Profile photo updated ✓');
      widget.onSaved?.call();
    } catch (e) {
      setState(() => _isSavingAvatar = false);
      _showSnack('Failed to update photo: $e');
    }
  }

  Future<void> _saveProfile({bool popOnSuccess = false}) async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final about = _aboutController.text.trim();
    final upi = _upiController.text.trim();

    if (name.isEmpty) {
      _showSnack('Please enter your name');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _userService.saveUserProfile(
        name: name,
        phoneNumber: phone.replaceAll(RegExp(r'\D'), ''),
        avatarUrl: _newAvatarUrl,
        about: about,
        upiId: upi.isNotEmpty ? upi : null,
      );

      if (!mounted) return;
      _showSnack('Profile saved ✓');
      widget.onSaved?.call();

      if (popOnSuccess && (widget.isEditing || Navigator.canPop(context))) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showSnack('Error saving profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w500)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF5B50E6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showAvatarPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Profile photo',
                  style: TextStyle(color: Color(0xFF171B2D), fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.camera_alt_rounded, color: Color(0xFF10B981), size: 22),
                  ),
                ),
                title: const Text('Camera', style: TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadAvatar(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B50E6).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.photo_library_rounded, color: Color(0xFF5B50E6), size: 22),
                  ),
                ),
                title: const Text('Gallery', style: TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadAvatar(ImageSource.gallery);
                },
              ),
              if (_newAvatarUrl != null && _newAvatarUrl!.isNotEmpty)
                ListTile(
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.delete_rounded, color: Colors.redAccent, size: 22),
                    ),
                  ),
                  title: const Text('Remove photo',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    Navigator.pop(context);
                    setState(() => _newAvatarUrl = null);
                    await _saveProfile();
                    _showSnack('Profile photo removed');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditProfileSheet() {
    final nameCtrl = TextEditingController(text: _nameController.text);
    final phoneCtrl = TextEditingController(text: _phoneController.text);
    final aboutCtrl = TextEditingController(text: _aboutController.text);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Edit Profile',
              style: TextStyle(color: Color(0xFF171B2D), fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Name
            const Text('Your Name', style: TextStyle(color: Color(0xFF5B50E6), fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Color(0xFF171B2D)),
              decoration: InputDecoration(
                hintText: 'Enter your name',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                filled: true,
                fillColor: const Color(0xFFF4F6FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF5B50E6), width: 1.8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            // About / Status
            const Text('About / Status Quote', style: TextStyle(color: Color(0xFF5B50E6), fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: aboutCtrl,
              style: const TextStyle(color: Color(0xFF171B2D)),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Enter your status quote',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                filled: true,
                fillColor: const Color(0xFFF4F6FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF5B50E6), width: 1.8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),

            // Phone
            const Text('Phone Number', style: TextStyle(color: Color(0xFF5B50E6), fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Color(0xFF171B2D)),
              decoration: InputDecoration(
                hintText: 'Enter 10-digit phone number',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                filled: true,
                fillColor: const Color(0xFFF4F6FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF5B50E6), width: 1.8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B50E6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                onPressed: () {
                  setState(() {
                    _nameController.text = nameCtrl.text;
                    _aboutController.text = aboutCtrl.text;
                    _phoneController.text = phoneCtrl.text;
                  });
                  Navigator.pop(ctx);
                  _saveProfile();
                },
                child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInlineAboutEditor() {
    final ctrl = TextEditingController(text: _aboutController.text);
    final quickQuotes = [
      'Memories With The Right People Are Always Priceless.🪄',
      'Available',
      'Busy',
      'At work',
      'Battery about to die',
      'Can\'t talk, WhatsApp only',
      'In a meeting',
      'Sleeping',
      'Urgent calls only',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('About / Status', style: TextStyle(color: Color(0xFF171B2D), fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                style: const TextStyle(color: Color(0xFF171B2D)),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF4F6FC),
                  hintText: 'Add a status...',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check_rounded, color: Color(0xFF5B50E6)),
                    onPressed: () {
                      setState(() => _aboutController.text = ctrl.text.trim());
                      Navigator.pop(ctx);
                      _saveProfile();
                    },
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF5B50E6), width: 1.8)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Select About:', style: TextStyle(color: Color(0xFF5B50E6), fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: quickQuotes.length,
                  separatorBuilder: (context, index) => Divider(color: Colors.grey.shade100, height: 1),
                  itemBuilder: (_, i) {
                    final q = quickQuotes[i];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      title: Text(q, style: const TextStyle(color: Color(0xFF171B2D), fontSize: 14, fontWeight: FontWeight.w500)),
                      onTap: () {
                        setModalState(() => ctrl.text = q);
                        setState(() => _aboutController.text = q);
                        Navigator.pop(ctx);
                        _saveProfile();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInlineNameEditor() {
    final ctrl = TextEditingController(text: _nameController.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Enter your name', style: TextStyle(color: Color(0xFF171B2D), fontSize: 19, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Color(0xFF171B2D)),
          decoration: InputDecoration(
            hintText: 'Your Name',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true,
            fillColor: const Color(0xFFF4F6FC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF5B50E6), width: 1.8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B50E6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                setState(() => _nameController.text = ctrl.text.trim());
                Navigator.pop(ctx);
                _saveProfile();
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _aboutController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FC),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          if (_isLoading)
            const LinearProgressIndicator(
              color: Color(0xFF5B50E6),
              backgroundColor: Colors.transparent,
              minHeight: 2,
            ),
          Expanded(
            child: _isSearching ? _buildSearchResults() : _buildMainSettingsContent(),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_isSearching) {
      return AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF171B2D),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF171B2D)),
          onPressed: () {
            setState(() {
              _isSearching = false;
              _searchController.clear();
            });
          },
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Color(0xFF171B2D), fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search settings...',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Color(0xFF171B2D)),
              onPressed: () => _searchController.clear(),
            ),
        ],
      );
    }

    final displayName = _nameController.text.isNotEmpty ? '~${_nameController.text}' : 'Settings';

    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF171B2D),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF171B2D)),
        onPressed: () {
          if (widget.isEditing || Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        },
      ),
      title: Text(
        displayName,
        style: const TextStyle(
          color: Color(0xFF171B2D),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search_rounded, color: Color(0xFF171B2D)),
          tooltip: 'Search',
          onPressed: () => setState(() => _isSearching = true),
        ),
        IconButton(
          icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF171B2D)),
          tooltip: 'QR code',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WhatsAppQrCodeScreen(
                  userName: _nameController.text.isNotEmpty ? _nameController.text : 'User',
                  avatarUrl: _newAvatarUrl,
                  phoneNumber: _phoneController.text.isNotEmpty ? _phoneController.text : '+91 98765 43210',
                ),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: Color(0xFF5B50E6)),
          tooltip: 'Edit Profile',
          onPressed: _showEditProfileSheet,
        ),
      ],
    );
  }

  Widget _buildMainSettingsContent() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        // ============================================================
        // TOP HEADER: THOUGHT BUBBLE, AVATAR, USERNAME
        // ============================================================
        _buildProfileHeaderSection(),

        const SizedBox(height: 12),

        // ============================================================
        // 1. PAYMENTS
        // ============================================================
        _buildSettingItem(
          icon: Icons.currency_rupee_rounded,
          iconColor: const Color(0xFF10B981),
          title: 'Payments',
          subtitle: 'UPI and payment history',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentsScreen())),
        ),

        // ============================================================
        // 2. SUBSCRIPTIONS
        // ============================================================
        _buildSettingItem(
          icon: Icons.diamond_outlined,
          iconColor: const Color(0xFF8B5CF6),
          title: 'Subscriptions',
          subtitle: 'Explore premium benefits',
          onTap: () => _showSubscriptionsDialog(),
        ),

        // ============================================================
        // 3. LINKED DEVICES
        // ============================================================
        _buildSettingItem(
          icon: Icons.devices_outlined,
          iconColor: const Color(0xFF0D9488),
          title: 'Linked devices',
          subtitle: 'Use on other devices',
          onTap: () => _showLinkedDevicesSheet(),
        ),

        // ============================================================
        // 4. ACCOUNT
        // ============================================================
        _buildSettingItem(
          icon: Icons.key_outlined,
          iconColor: const Color(0xFF3B82F6),
          title: 'Account',
          subtitle: 'Security notifications, change number',
          onTap: () => _showAccountSheet(),
        ),

        // ============================================================
        // 5. PRIVACY
        // ============================================================
        _buildSettingItem(
          icon: Icons.lock_outline_rounded,
          iconColor: const Color(0xFF10B981),
          title: 'Privacy',
          subtitle: 'Blocked accounts, disappearing messages',
          onTap: () => _showPrivacySheet(),
        ),

        // ============================================================
        // 6. LISTS
        // ============================================================
        _buildSettingItem(
          icon: Icons.photo_library_outlined,
          iconColor: const Color(0xFFEC4899),
          title: 'Lists',
          subtitle: 'Manage people and groups',
          onTap: () => _showGenericInfoSheet('Lists', 'Manage custom lists of people and groups to quickly message or share status updates with.'),
        ),

        // ============================================================
        // 7. CHATS
        // ============================================================
        _buildSettingItem(
          icon: Icons.chat_bubble_outline_rounded,
          iconColor: const Color(0xFF5B50E6),
          title: 'Chats',
          subtitle: 'Chat history, backup',
          onTap: () => _showChatsSheet(),
        ),

        // ============================================================
        // 8. APPEARANCE
        // ============================================================
        _buildSettingItem(
          icon: Icons.palette_outlined,
          iconColor: const Color(0xFFF59E0B),
          title: 'Appearance',
          subtitle: 'Chat theme, app icon, app theme',
          onTap: () => _showAppearanceSheet(),
        ),

        // ============================================================
        // 9. BROADCASTS
        // ============================================================
        _buildSettingItem(
          icon: Icons.campaign_outlined,
          iconColor: const Color(0xFF6366F1),
          title: 'Broadcasts',
          subtitle: 'Manage lists and send broadcasts',
          onTap: () => _showGenericInfoSheet('Broadcasts', 'Broadcast lists let you send one message to many contacts at once without creating a group.'),
        ),

        // ============================================================
        // 10. NOTIFICATIONS
        // ============================================================
        _buildSettingItem(
          icon: Icons.notifications_none_rounded,
          iconColor: const Color(0xFFEF4444),
          title: 'Notifications',
          subtitle: 'Message, group & call tones',
          onTap: () => _showNotificationsSheet(),
        ),

        // ============================================================
        // 11. STORAGE AND DATA
        // ============================================================
        _buildSettingItem(
          icon: Icons.pie_chart_outline_rounded,
          iconColor: const Color(0xFF0284C7),
          title: 'Storage and data',
          subtitle: 'Network usage, auto-download',
          onTap: () => _showGenericInfoSheet('Storage and data', 'Manage media storage, auto-download settings, and network data usage.'),
        ),

        // ============================================================
        // 12. PARENTAL CONTROLS
        // ============================================================
        _buildSettingItem(
          icon: Icons.shield_outlined,
          iconColor: const Color(0xFF84CC16),
          title: 'Parental controls',
          subtitle: 'Settings for your family',
          onTap: () => _showGenericInfoSheet('Parental controls', 'Configure safety settings, content filters, and supervision for family members.'),
        ),

        // ============================================================
        // 13. ACCESSIBILITY
        // ============================================================
        _buildSettingItem(
          icon: Icons.accessibility_new_rounded,
          iconColor: const Color(0xFF64748B),
          title: 'Accessibility',
          subtitle: 'Increase contrast, animation',
          onTap: () => _showGenericInfoSheet('Accessibility', 'Options to increase text contrast, manage animation speed, and improve visibility.'),
        ),

        // ============================================================
        // 14. APP LANGUAGE
        // ============================================================
        _buildSettingItem(
          icon: Icons.language_rounded,
          iconColor: const Color(0xFF14B8A6),
          title: 'App language',
          subtitle: _selectedLanguage,
          onTap: () => _showLanguagePicker(),
        ),

        // ============================================================
        // 15. HELP AND FEEDBACK
        // ============================================================
        _buildSettingItem(
          icon: Icons.help_outline_rounded,
          iconColor: const Color(0xFF6366F1),
          title: 'Help and feedback',
          subtitle: 'Help centre, contact us, privacy policy',
          onTap: () => _showGenericInfoSheet('Help and feedback', 'Access FAQ guides, contact WhatsApp support team, or view Terms and Privacy Policy.'),
        ),

        // ============================================================
        // 16. INVITE A FRIEND
        // ============================================================
        _buildSettingItem(
          icon: Icons.group_add_outlined,
          iconColor: const Color(0xFFF43F5E),
          title: 'Invite a friend',
          onTap: () => _showGenericInfoSheet('Invite a friend', 'Share a link via SMS, email or social apps inviting friends to download WhatsApp.'),
        ),

        // ============================================================
        // 17. APP UPDATES
        // ============================================================
        _buildSettingItem(
          icon: Icons.system_update_rounded,
          iconColor: const Color(0xFF3B82F6),
          title: 'App updates',
          onTap: () => _showSnack('App is up to date (Version 2.26.8)'),
        ),

        const Divider(color: Color(0xFFE5E7EB), height: 32, indent: 20, endIndent: 20),

        // ============================================================
        // 18. ACCOUNTS CENTRE (META)
        // ============================================================
        _buildSettingItem(
          icon: Icons.all_inclusive_rounded,
          iconColor: const Color(0xFF2563EB),
          title: 'Accounts Centre',
          subtitle: 'Control your experience across WhatsApp, Facebook, Instagram and more.',
          onTap: () => _showGenericInfoSheet('Accounts Centre', 'Manage connected experiences, account security, and personal details across Meta technologies.'),
        ),

        const SizedBox(height: 16),

        // ============================================================
        // 19. ALSO FROM META
        // ============================================================
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            'Also from Meta',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetaAppBadge(
                icon: Icons.camera_alt_outlined,
                name: 'Instagram',
              ),
              _buildMetaAppBadge(
                icon: Icons.facebook_rounded,
                name: 'Facebook',
              ),
              _buildMetaAppBadge(
                icon: Icons.alternate_email_rounded,
                name: 'Threads',
              ),
              _buildMetaAppBadge(
                icon: Icons.auto_awesome_rounded,
                name: 'Meta AI\nApp',
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PROFILE HEADER (MATCHING APP MODERN UI)
  // ============================================================
  Widget _buildProfileHeaderSection() {
    final displayName = _nameController.text.isNotEmpty ? _nameController.text : 'User';
    final aboutText = _aboutController.text.isNotEmpty
        ? _aboutController.text
        : 'Memories With The Right People Are Always Priceless.🪄';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: Column(
        children: [
          // Status / Thought Bubble at Top
          GestureDetector(
            onTap: _showInlineAboutEditor,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6FC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      aboutText,
                      style: const TextStyle(
                        color: Color(0xFF171B2D),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit_rounded, color: Color(0xFF5B50E6), size: 15),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Profile Picture
          GestureDetector(
            onTap: _showAvatarPicker,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5B50E6), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF5B50E6).withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 46,
                    backgroundColor: const Color(0xFFEDE9FE),
                    backgroundImage: getAvatarImageProvider(_newAvatarUrl),
                    child: _isSavingAvatar
                        ? const CircularProgressIndicator(color: Color(0xFF5B50E6))
                        : (getAvatarImageProvider(_newAvatarUrl) == null)
                            ? const Icon(
                                Icons.person_rounded,
                                color: Color(0xFF5B50E6),
                                size: 50,
                              )
                            : null,
                  ),
                ),

                // Small camera / edit badge on bottom-right
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFF5B50E6),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Name with badge
          GestureDetector(
            onTap: _showInlineNameEditor,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Color(0xFF171B2D),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.edit_note_rounded,
                  color: Color(0xFF5B50E6),
                  size: 22,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SINGLE SETTINGS LIST TILE (APP MODERN STYLE)
  // ============================================================
  Widget _buildSettingItem({
    IconData? icon,
    Widget? iconWidget,
    Color? iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final effectiveColor = iconColor ?? const Color(0xFF5B50E6);
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        splashColor: effectiveColor.withValues(alpha: 0.08),
        highlightColor: effectiveColor.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: effectiveColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: iconWidget ??
                      Icon(
                        icon,
                        color: effectiveColor,
                        size: 20,
                      ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF171B2D),
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // META APP BADGE
  // ============================================================
  Widget _buildMetaAppBadge({
    required IconData icon,
    required String name,
  }) {
    return InkWell(
      onTap: () => _showSnack('Opening $name...'),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: const Color(0xFF5B50E6), size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF171B2D),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SEARCH RESULTS
  // ============================================================
  Widget _buildSearchResults() {
    final allItems = [
      {'title': 'Payments', 'subtitle': 'Send and receive money using UPI', 'action': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentsScreen()))},
      {'title': 'Subscriptions', 'subtitle': 'Explore premium benefits', 'action': _showSubscriptionsDialog},
      {'title': 'Linked devices', 'subtitle': 'Use on other devices', 'action': _showLinkedDevicesSheet},
      {'title': 'Account', 'subtitle': 'Security notifications, change number', 'action': _showAccountSheet},
      {'title': 'Privacy', 'subtitle': 'Blocked accounts, disappearing messages', 'action': _showPrivacySheet},
      {'title': 'Lists', 'subtitle': 'Manage people and groups', 'action': () => _showGenericInfoSheet('Lists', 'Manage lists of contacts')},
      {'title': 'Chats', 'subtitle': 'Chat history, backup', 'action': _showChatsSheet},
      {'title': 'Appearance', 'subtitle': 'Chat theme, app icon, app theme', 'action': _showAppearanceSheet},
      {'title': 'Broadcasts', 'subtitle': 'Manage lists and send broadcasts', 'action': () => _showGenericInfoSheet('Broadcasts', 'Send messages to many contacts')},
      {'title': 'Notifications', 'subtitle': 'Message, group & call tones', 'action': _showNotificationsSheet},
      {'title': 'Storage and data', 'subtitle': 'Network usage, auto-download', 'action': () => _showGenericInfoSheet('Storage and data', 'Manage media storage')},
      {'title': 'Parental controls', 'subtitle': 'Settings for your family', 'action': () => _showGenericInfoSheet('Parental controls', 'Family safety settings')},
      {'title': 'Accessibility', 'subtitle': 'Increase contrast, animation', 'action': () => _showGenericInfoSheet('Accessibility', 'Contrast and text size')},
      {'title': 'App language', 'subtitle': 'English (device\'s language)', 'action': _showLanguagePicker},
      {'title': 'Help and feedback', 'subtitle': 'Help centre, contact us, privacy policy', 'action': () => _showGenericInfoSheet('Help', 'Support and FAQ')},
      {'title': 'Invite a friend', 'subtitle': 'Share WhatsApp invitation', 'action': () => _showGenericInfoSheet('Invite', 'Invite your friends')},
      {'title': 'App updates', 'subtitle': 'Check for latest versions', 'action': () => _showSnack('App is up to date')},
      {'title': 'Accounts Centre', 'subtitle': 'Meta connected accounts', 'action': () => _showGenericInfoSheet('Accounts Centre', 'Meta settings')},
    ];

    final filtered = allItems.where((item) {
      final t = (item['title'] as String).toLowerCase();
      final s = (item['subtitle'] as String).toLowerCase();
      return t.contains(_searchQuery) || s.contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, color: Colors.grey.shade400, size: 48),
            const SizedBox(height: 12),
            Text('No settings found for "$_searchQuery"', style: TextStyle(color: Colors.grey.shade600, fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: filtered.length,
      separatorBuilder: (context, index) => Divider(color: Colors.grey.shade100, height: 1),
      itemBuilder: (_, i) {
        final item = filtered[i];
        return ListTile(
          title: Text(item['title'] as String, style: const TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w600)),
          subtitle: Text(item['subtitle'] as String, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
          onTap: () {
            setState(() => _isSearching = false);
            (item['action'] as VoidCallback)();
          },
        );
      },
    );
  }

  // ============================================================
  // INTERACTIVE SHEETS / DIALOGS FOR SETTINGS (APP MODERN UI)
  // ============================================================

  void _showSubscriptionsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.diamond_outlined, color: Color(0xFF8B5CF6), size: 32),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Subscriptions', style: TextStyle(color: Color(0xFF171B2D), fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Explore premium features, extended cloud backup, and custom stickers for your chat experience.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.35),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B50E6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Explore Benefits', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLinkedDevicesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.devices_rounded, color: Color(0xFF0D9488), size: 32),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Linked devices', style: TextStyle(color: Color(0xFF171B2D), fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Use the app on Web, Desktop, tablets and other devices without keeping your phone online.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.35),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B50E6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WhatsAppQrCodeScreen(
                        userName: _nameController.text.isNotEmpty ? _nameController.text : 'User',
                        avatarUrl: _newAvatarUrl,
                        phoneNumber: _phoneController.text,
                      ),
                    ),
                  );
                },
                child: const Text('Link a device', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAccountSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Account', style: TextStyle(color: Color(0xFF171B2D), fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.security_rounded, color: Color(0xFF3B82F6), size: 20),
                ),
              ),
              title: const Text('Security notifications', style: TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w600)),
              subtitle: Text('Show security notifications on this phone', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
              onTap: () {
                Navigator.pop(ctx);
                _showSnack('Security notifications enabled');
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF5B50E6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.phone_iphone_rounded, color: Color(0xFF5B50E6), size: 20),
                ),
              ),
              title: const Text('Change number', style: TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w600)),
              subtitle: Text('Current: ${_phoneController.text.isNotEmpty ? _phoneController.text : "Not set"}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
              onTap: () {
                Navigator.pop(ctx);
                _showEditProfileSheet();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                ),
              ),
              title: const Text('Delete account', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _showSnack('Account deletion cancelled');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPrivacySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('Privacy', style: TextStyle(color: Color(0xFF171B2D), fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: const Color(0xFF5B50E6),
                title: const Text('Read receipts', style: TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w600)),
                subtitle: Text('If turned off, you won\'t send or receive read receipts (blue ticks).', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                value: _readReceipts,
                onChanged: (val) {
                  setSheetState(() => _readReceipts = val);
                  setState(() => _readReceipts = val);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(Icons.timer_outlined, color: Color(0xFF8B5CF6), size: 20),
                  ),
                ),
                title: const Text('Disappearing messages', style: TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w600)),
                subtitle: Text('Default message timer: Off', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSnack('Disappearing messages setting opened');
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(Icons.block_flipped, color: Color(0xFFEF4444), size: 20),
                  ),
                ),
                title: const Text('Blocked contacts', style: TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w600)),
                subtitle: Text('0 contacts blocked', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSnack('No contacts blocked');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChatsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Chats', style: TextStyle(color: Color(0xFF171B2D), fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF5B50E6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.cloud_upload_outlined, color: Color(0xFF5B50E6), size: 20),
                ),
              ),
              title: const Text('Chat backup', style: TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w600)),
              subtitle: Text('Back up messages and media to cloud', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
              onTap: () {
                Navigator.pop(ctx);
                _showSnack('Backup created successfully ✓');
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.wallpaper_rounded, color: Color(0xFFF59E0B), size: 20),
                ),
              ),
              title: const Text('Wallpaper', style: TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w600)),
              subtitle: Text('Change chat wallpaper and aesthetic theme', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
              onTap: () {
                Navigator.pop(ctx);
                _showSnack('Wallpaper settings updated');
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(Icons.history_rounded, color: Color(0xFF3B82F6), size: 20),
                ),
              ),
              title: const Text('Chat history', style: TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w600)),
              subtitle: Text('Export, archive, or clear all chats', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
              onTap: () {
                Navigator.pop(ctx);
                _showSnack('Chat history options');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAppearanceSheet() {
    final themes = ['Light', 'Dark', 'System default'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('Appearance', style: TextStyle(color: Color(0xFF171B2D), fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...themes.map(
                (t) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t, style: const TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w600)),
                  trailing: _selectedTheme == t
                      ? const Icon(Icons.check_circle_rounded, color: Color(0xFF5B50E6))
                      : Icon(Icons.circle_outlined, color: Colors.grey.shade400),
                  onTap: () {
                    setModalState(() => _selectedTheme = t);
                    setState(() => _selectedTheme = t);
                    Navigator.pop(ctx);
                    _showSnack('Theme changed to $t');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('Notifications', style: TextStyle(color: Color(0xFF171B2D), fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeTrackColor: const Color(0xFF5B50E6),
                title: const Text('Conversation tones', style: TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w600)),
                subtitle: Text('Play sounds for incoming and outgoing messages', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                value: _notificationsEnabled,
                onChanged: (val) {
                  setSheetState(() => _notificationsEnabled = val);
                  setState(() => _notificationsEnabled = val);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(Icons.music_note_rounded, color: Color(0xFFEF4444), size: 20),
                  ),
                ),
                title: const Text('Notification tone', style: TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w600)),
                subtitle: Text('Default tone', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSnack('Notification tone selected');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguagePicker() {
    final langs = [
      'English (device\'s language)',
      'தமிழ் (Tamil)',
      'हिन्दी (Hindi)',
      'తెలుగు (Telugu)',
      'മലയാളം (Malayalam)',
      'ಕನ್ನಡ (Kannada)',
      'বাংলা (Bengali)',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('App language', style: TextStyle(color: Color(0xFF171B2D), fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: langs.length,
                separatorBuilder: (context, index) => Divider(color: Colors.grey.shade100, height: 1),
                itemBuilder: (_, i) {
                  final lang = langs[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    title: Text(lang, style: const TextStyle(color: Color(0xFF171B2D), fontWeight: FontWeight.w500)),
                    trailing: _selectedLanguage == lang
                        ? const Icon(Icons.check_circle_rounded, color: Color(0xFF5B50E6))
                        : Icon(Icons.circle_outlined, color: Colors.grey.shade400),
                    onTap: () {
                      setState(() => _selectedLanguage = lang);
                      Navigator.pop(ctx);
                      _showSnack('Language set to $lang');
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

  void _showGenericInfoSheet(String title, String description) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(title, style: const TextStyle(color: Color(0xFF171B2D), fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(description, style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.4)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B50E6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
