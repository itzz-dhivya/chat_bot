import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../services/user_service.dart';
import 'call_screen.dart';
import 'chat_screen.dart';

class CallInfoScreen extends StatefulWidget {
  final UserModel? otherUser;
  final String otherUserId;
  final String displayName;
  final String displayPhone;
  final Map<String, dynamic>? initialCallData;

  const CallInfoScreen({
    super.key,
    this.otherUser,
    required this.otherUserId,
    required this.displayName,
    required this.displayPhone,
    this.initialCallData,
  });

  @override
  State<CallInfoScreen> createState() => _CallInfoScreenState();
}

class _CallInfoScreenState extends State<CallInfoScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserService _userService = UserService();
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  UserModel? _currentUser;
  UserModel? _targetUser;

  @override
  void initState() {
    super.initState();
    _targetUser = widget.otherUser;
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    _currentUser = await _userService.getCurrentUserProfile();
    if (_targetUser == null && widget.otherUserId.isNotEmpty) {
      _targetUser = await _userService.getUserById(widget.otherUserId);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _startCall({required bool isVideo}) {
    final currentUid = _currentUserId;
    if (currentUid == null) return;

    final callerName = _currentUser?.name.isNotEmpty == true
        ? _currentUser!.name
        : (_currentUser?.phoneNumber ?? 'Caller');
    final callerPhone = _currentUser?.phoneNumber ?? '';

    final receiverName = _targetUser?.name.isNotEmpty == true
        ? _targetUser!.name
        : widget.displayName;
    final receiverPhone = _targetUser?.phoneNumber.isNotEmpty == true
        ? _targetUser!.phoneNumber
        : widget.displayPhone;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callerId: currentUid,
          callerName: callerName,
          callerPhone: callerPhone,
          receiverId: widget.otherUserId,
          receiverName: receiverName,
          receiverPhone: receiverPhone,
          isIncoming: false,
          callType: isVideo ? 'video' : 'voice',
        ),
      ),
    );
  }

  void _openChat() {
    final user = _targetUser ??
        UserModel(
          id: widget.otherUserId,
          name: widget.displayName,
          phoneNumber: widget.displayPhone,
          fcmToken: '',
          isOnline: false,
        );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(targetUser: user),
      ),
    );
  }

  void _showContactInfo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101A20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Contact Info',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline_rounded, color: Color(0xFF00A884)),
              title: const Text('Name', style: TextStyle(color: Colors.white70, fontSize: 13)),
              subtitle: Text(
                _targetUser?.name ?? widget.displayName,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phone_outlined, color: Color(0xFF00A884)),
              title: const Text('Phone number', style: TextStyle(color: Colors.white70, fontSize: 13)),
              subtitle: Text(
                _targetUser?.phoneNumber ?? widget.displayPhone,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            if (_targetUser?.about.isNotEmpty == true)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline_rounded, color: Color(0xFF00A884)),
                title: const Text('About', style: TextStyle(color: Colors.white70, fontSize: 13)),
                subtitle: Text(
                  _targetUser!.about,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCallLogs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2C34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove from call log?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Do you want to delete this call history with this contact?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      for (final doc in docs) {
        await doc.reference.delete();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Call log removed')),
        );
        Navigator.pop(context);
      }
    }
  }

  String _formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final checkDate = DateTime(dt.year, dt.month, dt.day);

    if (checkDate == today) return 'Today';
    if (checkDate == yesterday) return 'Yesterday';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'pm' : 'am';
    return '$hour:$minute $period';
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    if (mins == 0) return '$secs sec';
    return '$mins min $secs sec';
  }

  @override
  Widget build(BuildContext context) {
    final name = _targetUser?.name.isNotEmpty == true ? _targetUser!.name : widget.displayName;
    final phone = _targetUser?.phoneNumber.isNotEmpty == true ? _targetUser!.phoneNumber : widget.displayPhone;

    return Scaffold(
      backgroundColor: const Color(0xFF0B141B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B141B),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Call info',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            color: const Color(0xFF1F2C34),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'block') {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$name blocked')),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'block',
                child: Text('Block', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore.collection('calls').snapshots(),
        builder: (context, snapshot) {
          final allDocs = snapshot.data?.docs ?? [];
          // Filter calls between current user and other user
          final relevantCalls = allDocs.where((d) {
            final data = d.data();
            final cId = data['callerId']?.toString() ?? '';
            final rId = data['receiverId']?.toString() ?? '';
            return (_currentUserId != null) &&
                ((cId == _currentUserId && rId == widget.otherUserId) ||
                    (cId == widget.otherUserId && rId == _currentUserId));
          }).toList();

          // Sort descending by timestamp
          relevantCalls.sort((a, b) {
            final aData = a.data();
            final bData = b.data();
            final dynamic aTime = aData['createdAt'] ?? aData['timestamp'];
            final dynamic bTime = bData['createdAt'] ?? bData['timestamp'];
            DateTime aDt = DateTime.fromMillisecondsSinceEpoch(0);
            DateTime bDt = DateTime.fromMillisecondsSinceEpoch(0);
            if (aTime is Timestamp) aDt = aTime.toDate();
            if (bTime is Timestamp) bDt = bTime.toDate();
            return bDt.compareTo(aDt);
          });

          // Group calls by date string
          final Map<String, List<Map<String, dynamic>>> grouped = {};
          if (relevantCalls.isEmpty && widget.initialCallData != null) {
            final dt = (widget.initialCallData!['createdAt'] is Timestamp)
                ? (widget.initialCallData!['createdAt'] as Timestamp).toDate()
                : DateTime.now();
            final header = _formatDateHeader(dt);
            grouped[header] = [widget.initialCallData!];
          } else {
            for (final doc in relevantCalls) {
              final data = doc.data();
              final dynamic timeVal = data['createdAt'] ?? data['timestamp'];
              DateTime dt = DateTime.now();
              if (timeVal is Timestamp) dt = timeVal.toDate();
              final header = _formatDateHeader(dt);
              grouped.putIfAbsent(header, () => []).add(data);
            }
          }

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),

                // BIG PROFILE AVATAR
                Center(
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2B33),
                      shape: BoxShape.circle,
                      image: _targetUser?.avatarUrl != null && _targetUser!.avatarUrl!.isNotEmpty
                          ? (_targetUser!.avatarUrl!.startsWith('data:image')
                              ? DecorationImage(
                                  image: MemoryImage(base64Decode(_targetUser!.avatarUrl!.split(',').last)),
                                  fit: BoxFit.cover,
                                )
                              : DecorationImage(
                                  image: NetworkImage(_targetUser!.avatarUrl!),
                                  fit: BoxFit.cover,
                                ))
                          : null,
                    ),
                    child: _targetUser?.avatarUrl == null || _targetUser!.avatarUrl!.isEmpty
                        ? const Center(
                            child: Icon(
                              Icons.person,
                              size: 64,
                              color: Color(0xFF8696A0),
                            ),
                          )
                        : null,
                  ),
                ),

                const SizedBox(height: 16),

                // NAME
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                // PHONE NUMBER
                Center(
                  child: Text(
                    phone.isNotEmpty ? phone : '+91 90878 06717',
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: Color(0xFF8696A0),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 4 CIRCULAR ACTION BUTTONS (Message, Voice, Video, Info)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Message',
                        onTap: _openChat,
                      ),
                      _buildActionButton(
                        icon: Icons.phone_outlined,
                        label: 'Voice',
                        onTap: () => _startCall(isVideo: false),
                      ),
                      _buildActionButton(
                        icon: Icons.videocam_outlined,
                        label: 'Video',
                        onTap: () => _startCall(isVideo: true),
                      ),
                      _buildActionButton(
                        icon: Icons.info_outline_rounded,
                        label: 'Info',
                        onTap: _showContactInfo,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),
                const Divider(color: Color(0xFF1E2B33), height: 1),
                const SizedBox(height: 16),

                // CALL LOG ENTRIES GROUPED BY DATE
                if (grouped.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No call history with this contact',
                        style: TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                    ),
                  )
                else
                  ...grouped.entries.map((entry) {
                    final dateHeader = entry.key;
                    final calls = entry.value;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                          child: Text(
                            dateHeader,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF8696A0),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        ...calls.map((call) => _buildCallHistoryTile(call)),
                        const SizedBox(height: 12),
                      ],
                    );
                  }),

                const SizedBox(height: 30),

                // DELETE CALL LOG BUTTON
                if (relevantCalls.isNotEmpty)
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _deleteCallLogs(relevantCalls),
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                      label: const Text(
                        'Clear call log for this contact',
                        style: TextStyle(color: Colors.redAccent, fontSize: 14),
                      ),
                    ),
                  ),

                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFF182229),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF22313A), width: 1.2),
            ),
            child: Icon(icon, color: const Color(0xFFE9EDEF), size: 22),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF8696A0),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildCallHistoryTile(Map<String, dynamic> call) {
    final callerId = call['callerId']?.toString() ?? '';
    final bool isOutgoing = _currentUserId != null && callerId == _currentUserId;
    final String type = call['type']?.toString() ?? 'voice';
    final bool isVideo = type == 'video';
    final String status = call['status']?.toString() ?? 'ended';
    final bool isMissed = status == 'missed' || (status == 'rejected' && !isOutgoing);

    final dynamic timeVal = call['createdAt'] ?? call['timestamp'];
    DateTime dt = DateTime.now();
    if (timeVal is Timestamp) dt = timeVal.toDate();
    final timeStr = _formatTime(dt);

    final int duration = (call['duration'] is int) ? call['duration'] as int : 0;
    final durationStr = _formatDuration(duration);

    // Title formulation
    String titleText;
    if (isMissed) {
      titleText = isVideo ? 'Missed video call' : 'Missed voice call';
    } else if (isOutgoing) {
      titleText = isVideo ? 'Outgoing video call' : 'Outgoing voice call';
    } else {
      titleText = isVideo ? 'Incoming video call' : 'Incoming voice call';
    }

    // Icon on the left
    IconData leadingIcon;
    Color iconColor;
    if (isVideo) {
      leadingIcon = Icons.videocam_rounded;
      iconColor = isMissed ? Colors.redAccent : const Color(0xFF8696A0);
    } else {
      if (isMissed) {
        leadingIcon = Icons.call_missed_rounded;
        iconColor = Colors.redAccent;
      } else if (isOutgoing) {
        leadingIcon = Icons.call_made_rounded;
        iconColor = const Color(0xFF10B981);
      } else {
        leadingIcon = Icons.call_received_rounded;
        iconColor = const Color(0xFF10B981);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(leadingIcon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isMissed ? Colors.redAccent : Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      timeStr,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8696A0),
                      ),
                    ),
                    if (durationStr.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const Text('·', style: TextStyle(color: Color(0xFF8696A0), fontSize: 13)),
                      const SizedBox(width: 8),
                      Text(
                        durationStr,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF8696A0),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
