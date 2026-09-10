import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';

class WhatsAppForwardDialog extends StatefulWidget {
  final MessageModel message;
  final String currentUserId;
  final String? currentUserName;

  const WhatsAppForwardDialog({
    super.key,
    required this.message,
    required this.currentUserId,
    this.currentUserName,
  });

  static Future<void> show(
    BuildContext context, {
    required MessageModel message,
    required String currentUserId,
    String? currentUserName,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WhatsAppForwardDialog(
        message: message,
        currentUserId: currentUserId,
        currentUserName: currentUserName,
      ),
    );
  }

  @override
  State<WhatsAppForwardDialog> createState() => _WhatsAppForwardDialogState();
}

class _WhatsAppForwardDialogState extends State<WhatsAppForwardDialog> {
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();

  final Set<String> _selectedUserIds = <String>{};
  final Set<String> _selectedGroupIds = <String>{};
  final Map<String, _ForwardTarget> _selectedTargets = <String, _ForwardTarget>{};

  String _searchQuery = '';
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleUserSelection(UserModel user) {
    setState(() {
      if (_selectedUserIds.contains(user.id)) {
        _selectedUserIds.remove(user.id);
        _selectedTargets.remove(user.id);
      } else {
        _selectedUserIds.add(user.id);
        _selectedTargets[user.id] = _ForwardTarget(
          id: user.id,
          name: user.name.isNotEmpty ? user.name : user.phoneNumber,
          avatarUrl: user.avatarUrl,
          isGroup: false,
        );
      }
    });
  }

  void _toggleGroupSelection(String groupId, String groupName) {
    setState(() {
      if (_selectedGroupIds.contains(groupId)) {
        _selectedGroupIds.remove(groupId);
        _selectedTargets.remove(groupId);
      } else {
        _selectedGroupIds.add(groupId);
        _selectedTargets[groupId] = _ForwardTarget(
          id: groupId,
          name: groupName,
          avatarUrl: null,
          isGroup: true,
        );
      }
    });
  }

  Future<void> _handleSendForward() async {
    if (_selectedTargets.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      await _chatService.forwardMessage(
        senderId: widget.currentUserId,
        senderName: widget.currentUserName,
        targetUserIds: _selectedUserIds.toList(),
        targetGroupIds: _selectedGroupIds.toList(),
        originalMessage: widget.message,
      );

      if (mounted) {
        final count = _selectedTargets.length;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.forward_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Forwarded to $count ${count == 1 ? 'chat' : 'chats'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF5B50E6),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to forward message: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedTargets.isNotEmpty;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              // Sheet Drag Handle & Header
              _buildHeader(hasSelection),

              // Horizontal Selected Chips
              if (hasSelection) _buildSelectedChips(),

              // Search Bar
              _buildSearchBar(),

              const Divider(height: 1, color: Color(0xFFECEFF5)),

              // Scrollable Targets List (Recent, Groups, Contacts)
              Expanded(
                child: _buildTargetsList(),
              ),
            ],
          ),

          // Floating Forward Action Button
          if (hasSelection)
            Positioned(
              bottom: 24,
              right: 20,
              child: FloatingActionButton.extended(
                backgroundColor: const Color(0xFF5B50E6),
                foregroundColor: Colors.white,
                elevation: 4,
                onPressed: _isSending ? null : _handleSendForward,
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(
                  _isSending ? 'Sending...' : 'Forward (${_selectedTargets.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool hasSelection) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F3F9))),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Forward to...',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF171B2D),
                    ),
                  ),
                  if (hasSelection)
                    Text(
                      '${_selectedTargets.length} selected',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5B50E6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.grey),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedChips() {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFD),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: _selectedTargets.values.map((target) {
          return Container(
            margin: const EdgeInsets.only(right: 12),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: target.isGroup
                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                          : const Color(0xFF5B50E6).withValues(alpha: 0.15),
                      child: target.isGroup
                          ? const Icon(Icons.group_rounded, color: Color(0xFF10B981), size: 20)
                          : Text(
                              target.name.isNotEmpty ? target.name[0].toUpperCase() : '👤',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B50E6)),
                            ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      width: 54,
                      child: Text(
                        target.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: -2,
                  right: -2,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (target.isGroup) {
                          _selectedGroupIds.remove(target.id);
                        } else {
                          _selectedUserIds.remove(target.id);
                        }
                        _selectedTargets.remove(target.id);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.grey,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6FC),
          borderRadius: BorderRadius.circular(20),
        ),
        child: TextField(
          controller: _searchController,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search contacts or groups...',
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 13.5),
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, color: Colors.grey, size: 18),
                    onPressed: () => _searchController.clear(),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    );
  }

  Widget _buildTargetsList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('user').snapshots(),
      builder: (context, userSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('groups')
              .where('members', arrayContains: widget.currentUserId)
              .snapshots(),
          builder: (context, groupSnap) {
            final allUserDocs = userSnap.data?.docs ?? [];
            final allGroupDocs = groupSnap.data?.docs ?? [];

            // Filter out current user
            final contacts = allUserDocs
                .where((d) => d.id != widget.currentUserId)
                .map((d) => UserModel.fromMap(d.data(), d.id))
                .where((u) {
                  if (_searchQuery.isEmpty) return true;
                  return u.name.toLowerCase().contains(_searchQuery) ||
                      u.phoneNumber.contains(_searchQuery);
                })
                .toList();

            final groups = allGroupDocs.where((d) {
              if (_searchQuery.isEmpty) return true;
              final name = d.data()['name']?.toString().toLowerCase() ?? '';
              return name.contains(_searchQuery);
            }).toList();

            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                // Groups Section
                if (groups.isNotEmpty) ...[
                  _buildSectionHeader('Groups', groups.length),
                  ...groups.map((doc) {
                    final gid = doc.id;
                    final gdata = doc.data();
                    final gname = gdata['name']?.toString() ?? 'Group';
                    final isSelected = _selectedGroupIds.contains(gid);

                    return ListTile(
                      onTap: () => _toggleGroupSelection(gid, gname),
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                            child: const Icon(Icons.group_rounded, color: Color(0xFF10B981)),
                          ),
                          if (isSelected)
                            Positioned(
                              bottom: -2,
                              right: -2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF5B50E6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check, size: 14, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        gname,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                      ),
                      subtitle: Text(
                        '${(gdata['members'] as List?)?.length ?? 0} members',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: Checkbox(
                        value: isSelected,
                        activeColor: const Color(0xFF5B50E6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        onChanged: (_) => _toggleGroupSelection(gid, gname),
                      ),
                    );
                  }),
                ],

                // Contacts Section
                if (contacts.isNotEmpty) ...[
                  _buildSectionHeader('Contacts', contacts.length),
                  ...contacts.map((user) {
                    final isSelected = _selectedUserIds.contains(user.id);

                    return ListTile(
                      onTap: () => _toggleUserSelection(user),
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: const Color(0xFF5B50E6).withValues(alpha: 0.15),
                            child: Text(
                              user.name.isNotEmpty ? user.name[0].toUpperCase() : '👤',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5B50E6),
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Positioned(
                              bottom: -2,
                              right: -2,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF5B50E6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check, size: 14, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        user.name.isNotEmpty ? user.name : user.phoneNumber,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                      ),
                      subtitle: Text(
                        user.phoneNumber,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: Checkbox(
                        value: isSelected,
                        activeColor: const Color(0xFF5B50E6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        onChanged: (_) => _toggleUserSelection(user),
                      ),
                    );
                  }),
                ],

                if (groups.isEmpty && contacts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('No matching contacts or groups found', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForwardTarget {
  final String id;
  final String name;
  final String? avatarUrl;
  final bool isGroup;

  _ForwardTarget({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.isGroup,
  });
}
