import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';
import '../services/user_service.dart';
import 'group_chat_screen.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final UserService _userService = UserService();
  final ChatService _chatService = ChatService();

  final Set<String> _selectedUserIds = {};
  final List<UserModel> _selectedUsers = [];
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  bool _isStepTwo = false;
  bool _isCreating = false;
  String _searchQuery = '';

  @override
  void dispose() {
    _groupNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleUser(UserModel user) {
    setState(() {
      if (_selectedUserIds.contains(user.id)) {
        _selectedUserIds.remove(user.id);
        _selectedUsers.removeWhere((u) => u.id == user.id);
      } else {
        _selectedUserIds.add(user.id);
        _selectedUsers.add(user);
      }
    });
  }

  Future<void> _createGroup() async {
    final name = _groupNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name')),
      );
      return;
    }

    final currentUserId = _userService.currentUserId;
    if (currentUserId == null) return;

    setState(() => _isCreating = true);

    try {
      final groupId = await _chatService.createGroup(
        name: name,
        adminId: currentUserId,
        memberIds: _selectedUserIds.toList(),
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => GroupChatScreen(
              groupId: groupId,
              groupName: name,
              memberIds: [currentUserId, ..._selectedUserIds],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FC),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5B50E6), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () {
            if (_isStepTwo) {
              setState(() => _isStepTwo = false);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isStepTwo ? 'New group' : 'Add participants',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              _isStepTwo
                  ? '${_selectedUsers.length} members'
                  : (_selectedUsers.isEmpty ? 'Select contacts' : '${_selectedUsers.length} selected'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
      body: _isStepTwo ? _buildStepTwo() : _buildStepOne(),
      floatingActionButton: _isStepTwo
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF5B50E6),
              onPressed: _isCreating ? null : _createGroup,
              child: _isCreating
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.check_rounded, color: Colors.white),
            )
          : (_selectedUsers.isNotEmpty
              ? FloatingActionButton(
                  backgroundColor: const Color(0xFF5B50E6),
                  onPressed: () => setState(() => _isStepTwo = true),
                  child: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                )
              : null),
    );
  }

  Widget _buildStepOne() {
    return Column(
      children: [
        if (_selectedUsers.isNotEmpty)
          Container(
            height: 86,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedUsers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final user = _selectedUsers[index];
                return Stack(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFF5B50E6),
                          child: Text(
                            user.name.isNotEmpty ? user.name[0].toUpperCase() : '👤',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          width: 54,
                          child: Text(
                            user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 10, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => _toggleUser(user),
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
                );
              },
            ),
          ),

        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val.toLowerCase().trim()),
            decoration: InputDecoration(
              hintText: 'Search contacts...',
              prefixIcon: const Icon(Icons.search, color: Color(0xFF5B50E6)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        Expanded(
          child: StreamBuilder<List<UserModel>>(
            stream: _userService.getAllUsersStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF5B50E6)));
              }

              final allUsers = snapshot.data ?? [];
              final filtered = allUsers.where((u) {
                if (_searchQuery.isEmpty) return true;
                return u.name.toLowerCase().contains(_searchQuery) ||
                    u.phoneNumber.contains(_searchQuery);
              }).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text('No registered contacts found', style: TextStyle(color: Colors.grey)),
                );
              }

              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final user = filtered[index];
                  final isSelected = _selectedUserIds.contains(user.id);

                  return ListTile(
                    onTap: () => _toggleUser(user),
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: const Color(0xFF5B50E6).withValues(alpha: 0.1),
                          child: Text(
                            user.name.isNotEmpty ? user.name[0].toUpperCase() : '👤',
                            style: const TextStyle(
                              color: Color(0xFF5B50E6),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check, size: 12, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                    title: Text(
                      user.name.isNotEmpty ? user.name : 'Unknown Contact',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: Text(
                      user.phoneNumber.isNotEmpty ? user.phoneNumber : 'No phone number',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                    trailing: Checkbox(
                      value: isSelected,
                      activeColor: const Color(0xFF5B50E6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (_) => _toggleUser(user),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStepTwo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  height: 56,
                  width: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B50E6).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF5B50E6), size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _groupNameController,
                    autofocus: true,
                    maxLength: 35,
                    decoration: const InputDecoration(
                      hintText: 'Group name',
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF5B50E6), width: 2),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF5B50E6), width: 2),
                      ),
                      counterText: '',
                    ),
                  ),
                ),
                const Icon(Icons.emoji_emotions_outlined, color: Colors.grey),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'Participants',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedUsers.map((user) {
              return Chip(
                avatar: CircleAvatar(
                  backgroundColor: const Color(0xFF5B50E6),
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : '👤',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
                label: Text(user.name, style: const TextStyle(fontSize: 12)),
                backgroundColor: Colors.white,
                elevation: 1,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
