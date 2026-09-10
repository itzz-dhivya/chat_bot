import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../widgets/avatar_image_helper.dart';
import 'chat_screen.dart';
import 'call_screen.dart';

class UsersListScreen extends StatefulWidget {
  const UsersListScreen({super.key});

  @override
  State<UsersListScreen> createState() => _UsersListScreenState();
}

class _UsersListScreenState extends State<UsersListScreen> {
  final UserService _userService = UserService();
  final TextEditingController _searchController =
  TextEditingController();

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      setState(() {
        _searchQuery =
            _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // VOICE CALL
  // ============================================================

  void _startCallWithUser(
      UserModel otherUser,
      ) async {
    final currentUser =
    await _userService.getCurrentUserProfile();

    if (!mounted) return;

    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please set up your profile first',
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callerId: currentUser.id,
          callerName: currentUser.name,
          callerPhone: currentUser.phoneNumber,
          callerAvatarUrl: currentUser.avatarUrl,

          receiverId: otherUser.id,
          receiverName: otherUser.name,
          receiverPhone: otherUser.phoneNumber,
          receiverAvatarUrl: otherUser.avatarUrl,

          isIncoming: false,

          // IMPORTANT
          callType: 'voice',
        ),
      ),
    );
  }

  // ============================================================
  // VIDEO CALL
  // ============================================================

  void _startVideoCallWithUser(
      UserModel otherUser,
      ) async {
    final currentUser =
    await _userService.getCurrentUserProfile();

    if (!mounted) return;

    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please set up your profile first',
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callerId: currentUser.id,
          callerName: currentUser.name,
          callerPhone: currentUser.phoneNumber,
          callerAvatarUrl: currentUser.avatarUrl,

          receiverId: otherUser.id,
          receiverName: otherUser.name,
          receiverPhone: otherUser.phoneNumber,
          receiverAvatarUrl: otherUser.avatarUrl,

          isIncoming: false,

          // IMPORTANT
          callType: 'video',
        ),
      ),
    );
  }

  // ============================================================
  // CHAT
  // ============================================================

  void _startChatWithUser(
      UserModel otherUser,
      ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          targetUser: otherUser,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FC),

      appBar: AppBar(
        backgroundColor:
        const Color(0xFF5B50E6),
        foregroundColor: Colors.white,

        title: const Text(
          'Select Contact',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),

        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
          ),
          onPressed: () =>
              Navigator.pop(context),
        ),
      ),

      body: Column(
        children: [
          // ======================================================
          // SEARCH BAR
          // ======================================================

          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,

            child: TextField(
              controller: _searchController,

              decoration: InputDecoration(
                hintText:
                'Search by name or phone...',

                hintStyle:
                const TextStyle(
                  color: Colors.black38,
                  fontSize: 14,
                ),

                prefixIcon:
                const Icon(
                  Icons.search,
                  color:
                  Color(0xFF5B50E6),
                ),

                filled: true,

                fillColor:
                const Color(0xFFF4F6FC),

                contentPadding:
                const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),

                border:
                OutlineInputBorder(
                  borderRadius:
                  BorderRadius.circular(
                    24,
                  ),
                  borderSide:
                  BorderSide.none,
                ),
              ),
            ),
          ),

          // ======================================================
          // USERS LIST
          // ======================================================

          Expanded(
            child:
            StreamBuilder<List<UserModel>>(
              stream:
              _userService
                  .getAllUsersStream(),

              builder:
                  (context, snapshot) {
                if (snapshot
                    .connectionState ==
                    ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child:
                    CircularProgressIndicator(
                      color:
                      Color(0xFF5B50E6),
                    ),
                  );
                }

                final users =
                    snapshot.data ?? [];

                // =================================================
                // SEARCH FILTER
                // =================================================

                final filteredUsers =
                users.where((u) {
                  if (_searchQuery
                      .isEmpty) {
                    return true;
                  }

                  final nameMatch =
                  u.name
                      .toLowerCase()
                      .contains(
                    _searchQuery,
                  );

                  final phoneMatch =
                  u.phoneNumber
                      .contains(
                    _searchQuery,
                  );

                  return nameMatch ||
                      phoneMatch;
                }).toList();

                // =================================================
                // EMPTY
                // =================================================

                if (filteredUsers
                    .isEmpty) {
                  return Center(
                    child: Padding(
                      padding:
                      const EdgeInsets.all(
                        32.0,
                      ),

                      child: Column(
                        mainAxisAlignment:
                        MainAxisAlignment
                            .center,

                        children: [
                          Icon(
                            Icons
                                .people_outline_rounded,
                            size: 70,
                            color: Colors
                                .grey
                                .shade400,
                          ),

                          const SizedBox(
                            height: 16,
                          ),

                          Text(
                            _searchQuery
                                .isEmpty
                                ? 'No other registered users yet'
                                : 'No contacts match "$_searchQuery"',

                            textAlign:
                            TextAlign
                                .center,

                            style:
                            TextStyle(
                              fontSize: 16,
                              fontWeight:
                              FontWeight
                                  .w600,
                              color: Colors
                                  .grey
                                  .shade700,
                            ),
                          ),

                          const SizedBox(
                            height: 8,
                          ),

                          Text(
                            'When someone installs this app and enters their name, they will appear here automatically!',

                            textAlign:
                            TextAlign
                                .center,

                            style:
                            TextStyle(
                              fontSize: 13,
                              color: Colors
                                  .grey
                                  .shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // =================================================
                // LIST
                // =================================================

                return ListView.separated(
                  padding:
                  const EdgeInsets
                      .symmetric(
                    vertical: 8,
                  ),

                  itemCount:
                  filteredUsers.length,

                  separatorBuilder:
                      (_, __) =>
                  const Divider(
                    height: 1,
                    indent: 72,
                  ),

                  itemBuilder:
                      (context, index) {
                    final user =
                    filteredUsers[
                    index];

                    return ListTile(
                      contentPadding:
                      const EdgeInsets
                          .symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),

                      // Tap user -> Chat
                      onTap: () =>
                          _startChatWithUser(
                            user,
                          ),

                      // =================================================
                      // PROFILE ICON
                      // =================================================

                      leading: Stack(
                        children: [
                          CircleAvatar(
                            radius: 25,
                            backgroundColor: const Color(0xFF5B50E6).withValues(alpha: 0.15),
                            backgroundImage: getAvatarImageProvider(user.avatarUrl),
                            child: getAvatarImageProvider(user.avatarUrl) == null
                                ? Text(
                                    user.name.isNotEmpty
                                        ? user.name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Color(0xFF5B50E6),
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),

                          // Online indicator
                          if (user.isOnline)
                            Positioned(
                              right: 0,
                              bottom: 0,

                              child:
                              Container(
                                width: 14,
                                height: 14,

                                decoration:
                                BoxDecoration(
                                  color:
                                  const Color(
                                    0xFF10B981,
                                  ),

                                  shape: BoxShape
                                      .circle,

                                  border:
                                  Border.all(
                                    color: Colors
                                        .white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),

                      // =================================================
                      // NAME
                      // =================================================

                      title: Text(
                        user.name.isNotEmpty
                            ? user.name
                            : 'Unknown User',

                        style:
                        const TextStyle(
                          fontWeight:
                          FontWeight.bold,
                          fontSize: 16,
                          color: Color(
                              0xFF111B21),
                        ),
                      ),

                      // =================================================
                      // PHONE
                      // =================================================

                      subtitle: Text(
                        user.phoneNumber
                            .isNotEmpty
                            ? user.phoneNumber
                            : 'No phone number',

                        style:
                        TextStyle(
                          color: Colors
                              .grey
                              .shade600,
                          fontSize: 13,
                        ),
                      ),

                      // =================================================
                      // CHAT + VOICE + VIDEO
                      // =================================================

                      trailing: Row(
                        mainAxisSize:
                        MainAxisSize.min,

                        children: [
                          // -----------------------------
                          // CHAT
                          // -----------------------------

                          IconButton(
                            icon:
                            const Icon(
                              Icons
                                  .chat_bubble_outline_rounded,
                              color: Color(
                                  0xFF5B50E6),
                            ),

                            tooltip:
                            'Chat',

                            onPressed: () =>
                                _startChatWithUser(
                                  user,
                                ),
                          ),

                          // -----------------------------
                          // VOICE CALL
                          // -----------------------------

                          IconButton(
                            icon:
                            const Icon(
                              Icons
                                  .phone_rounded,
                              color: Color(
                                  0xFF7C3AED),
                            ),

                            tooltip:
                            'Voice Call',

                            onPressed: () =>
                                _startCallWithUser(
                                  user,
                                ),
                          ),

                          // -----------------------------
                          // VIDEO CALL
                          // -----------------------------

                          IconButton(
                            icon:
                            const Icon(
                              Icons
                                  .videocam_rounded,
                              color: Color(
                                  0xFF10B981),
                            ),

                            tooltip:
                            'Video Call',

                            onPressed: () =>
                                _startVideoCallWithUser(
                                  user,
                                ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}