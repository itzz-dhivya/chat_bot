import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import '../models/message_model.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // =====================================================
  // ENSURE USER LOGIN
  // =====================================================

  Future<User> ensureUserLoggedIn() async {
    User? user = _auth.currentUser;

    if (user != null) {
      return user;
    }

    final UserCredential credential = await _auth.signInAnonymously();
    return credential.user!;
  }

  // =====================================================
  // SAVE USER
  // =====================================================

  Future<void> saveUser({
    required String name,
    required String phoneNumber,
  }) async {
    final User user = await ensureUserLoggedIn();

    final String cleanedPhone = phoneNumber.replaceAll(
      RegExp(r'\D'),
      '',
    );

    await _firestore.collection('user').doc(user.uid).set({
      'name': name.trim(),
      'phoneNumber': cleanedPhone,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // =====================================================
  // GET CURRENT USER
  // =====================================================

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final User? user = _auth.currentUser;

    if (user == null) {
      return null;
    }

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _firestore.collection('user').doc(user.uid).get();

    return snapshot.data();
  }

  // =====================================================
  // FIND USER BY PHONE NUMBER
  // =====================================================

  Future<DocumentSnapshot<Map<String, dynamic>>?> findUserByPhoneNumber(
    String phoneNumber,
  ) async {
    final String cleanedPhone = phoneNumber.replaceAll(
      RegExp(r'\D'),
      '',
    );

    final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collection('user')
        .where('phoneNumber', isEqualTo: cleanedPhone)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    return snapshot.docs.first;
  }

  // =====================================================
  // GET CHAT ID
  // =====================================================

  String getChatId(
    String userId,
    String otherUserId,
  ) {
    final List<String> ids = [
      userId,
      otherUserId,
    ];

    ids.sort();

    return '${ids[0]}_${ids[1]}';
  }

  // =====================================================
  // SEND NORMAL TEXT MESSAGE WITH OPTIONAL REPLY / LINK PREVIEW
  // =====================================================

  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String message,
    String? replyToId,
    String? replyToText,
    String? replyToSender,
    bool isForwarded = false,
    Map<String, dynamic>? linkPreview,
  }) async {
    final String chatId = getChatId(senderId, receiverId);
    final String cleanedMessage = message.trim();

    if (cleanedMessage.isEmpty) {
      return;
    }

    final MessageModel messageModel = MessageModel(
      senderId: senderId,
      receiverId: receiverId,
      message: cleanedMessage,
      timestamp: DateTime.now(),
      type: 'text',
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSender: replyToSender,
      isForwarded: isForwarded,
      linkPreview: linkPreview,
    );

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(messageModel.toMap());

    await _updateChatMetadata(
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      lastMessage: cleanedMessage,
      type: 'text',
    );
  }

  // =====================================================
  // UPLOAD MEDIA FILE TO FIREBASE STORAGE
  // =====================================================

  Future<String> uploadFile(File file, String path) async {
    final Reference ref = _storage.ref().child(path);
    final UploadTask uploadTask = ref.putFile(file);
    final TaskSnapshot snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  // =====================================================
  // SEND MEDIA MESSAGE (IMAGE / VIDEO / AUDIO)
  // =====================================================

  Future<void> sendMediaMessage({
    required String senderId,
    required String receiverId,
    required String mediaUrl,
    required String type, // 'image', 'video', 'audio'
    String message = '',
    String? replyToId,
    String? replyToText,
    String? replyToSender,
    bool isForwarded = false,
  }) async {
    final String chatId = getChatId(senderId, receiverId);

    final MessageModel messageModel = MessageModel(
      senderId: senderId,
      receiverId: receiverId,
      message: message.trim(),
      timestamp: DateTime.now(),
      type: type,
      mediaUrl: mediaUrl,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSender: replyToSender,
      isForwarded: isForwarded,
    );

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(messageModel.toMap());

    await _updateChatMetadata(
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      lastMessage: type == 'image' ? '📷 Photo' : (type == 'video' ? '📹 Video' : '🎤 Voice message'),
      type: type,
    );
  }

  // =====================================================
  // SEND DOCUMENT / APK MESSAGE
  // =====================================================

  Future<void> sendDocumentMessage({
    required String senderId,
    required String receiverId,
    required String mediaUrl,
    required String fileName,
    required String fileSize,
    String message = '',
    String? replyToId,
    String? replyToText,
    String? replyToSender,
    bool isForwarded = false,
  }) async {
    final String chatId = getChatId(senderId, receiverId);

    final MessageModel messageModel = MessageModel(
      senderId: senderId,
      receiverId: receiverId,
      message: message.trim(),
      timestamp: DateTime.now(),
      type: 'document',
      mediaUrl: mediaUrl,
      fileName: fileName,
      fileSize: fileSize,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSender: replyToSender,
      isForwarded: isForwarded,
    );

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(messageModel.toMap());

    await _updateChatMetadata(
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      lastMessage: '📄 $fileName',
      type: 'document',
    );
  }

  // =====================================================
  // SEND LOCATION MESSAGE
  // =====================================================

  Future<void> sendLocationMessage({
    required String senderId,
    required String receiverId,
    required double latitude,
    required double longitude,
    String? address,
    String? replyToId,
    String? replyToText,
    String? replyToSender,
    bool isForwarded = false,
  }) async {
    final String chatId = getChatId(senderId, receiverId);

    final MessageModel messageModel = MessageModel(
      senderId: senderId,
      receiverId: receiverId,
      message: address ?? 'Live location shared',
      timestamp: DateTime.now(),
      type: 'location',
      latitude: latitude,
      longitude: longitude,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSender: replyToSender,
      isForwarded: isForwarded,
    );

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(messageModel.toMap());

    await _updateChatMetadata(
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      lastMessage: address != null ? '📍 $address' : '📍 Location',
      type: 'location',
    );
  }

  // =====================================================
  // SEND POLL MESSAGE
  // =====================================================

  Future<void> sendPollMessage({
    required String senderId,
    required String receiverId,
    required String question,
    required List<String> options,
    bool allowMultipleAnswers = false,
  }) async {
    final String chatId = getChatId(senderId, receiverId);

    final List<Map<String, dynamic>> optionsList = options.map((opt) {
      return {
        'title': opt,
        'text': opt,
        'votes': <String>[], // list of userIds
      };
    }).toList();

    final MessageModel messageModel = MessageModel(
      senderId: senderId,
      receiverId: receiverId,
      message: question,
      timestamp: DateTime.now(),
      type: 'poll',
      pollData: {
        'question': question,
        'options': optionsList,
        'allowMultiple': allowMultipleAnswers,
      },
    );

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(messageModel.toMap());

    await _updateChatMetadata(
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      lastMessage: '📊 $question',
      type: 'poll',
    );
  }

  // =====================================================
  // SEND EVENT MESSAGE (P2P)
  // =====================================================

  Future<void> sendEventMessage({
    required String senderId,
    required String receiverId,
    required String title,
    required DateTime date,
    required TimeOfDay time,
    String? location,
    String? description,
  }) async {
    final String chatId = getChatId(senderId, receiverId);
    final String timeFormatted =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    final Map<String, dynamic> eventData = {
      'title': title.trim(),
      'date': date.toIso8601String(),
      'time': timeFormatted,
      if (location != null && location.trim().isNotEmpty) 'location': location.trim(),
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
    };

    final MessageModel messageModel = MessageModel(
      senderId: senderId,
      receiverId: receiverId,
      message: title.trim(),
      timestamp: DateTime.now(),
      type: 'event',
      eventData: eventData,
    );

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(messageModel.toMap());

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dateLabel = '${date.day} ${months[date.month - 1]}';

    await _updateChatMetadata(
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      lastMessage: 'Event ($dateLabel): ${title.trim()}',
      type: 'event',
    );
  }


  // =====================================================
  // VOTE ON POLL (P2P & GROUP)
  // =====================================================

  Future<void> _applyPollVote({
    required DocumentReference<Map<String, dynamic>> docRef,
    required int optionIndex,
    required String userId,
  }) async {
    try {
      final snapshot = await docRef.get();
      if (!snapshot.exists) {
        debugPrint('votePoll: Message ${docRef.path} does not exist');
        return;
      }

      final data = snapshot.data() ?? {};
      final pollData = Map<String, dynamic>.from(data['pollData'] ?? {});
      final rawOptions = pollData['options'] as List? ?? [];
      final List<Map<String, dynamic>> options = rawOptions
          .map((e) => Map<String, dynamic>.from(e is Map ? e : {}))
          .toList();
      final bool allowMultiple = pollData['allowMultiple'] == true;

      if (optionIndex < 0 || optionIndex >= options.length) return;

      for (int i = 0; i < options.length; i++) {
        final opt = options[i];
        final List<String> votes = List<String>.from(opt['votes'] ?? []);

        if (i == optionIndex) {
          if (votes.contains(userId)) {
            votes.remove(userId);
          } else {
            votes.add(userId);
          }
        } else if (!allowMultiple) {
          votes.remove(userId);
        }

        opt['votes'] = votes;
        final String optText = opt['title']?.toString() ?? opt['text']?.toString() ?? '';
        opt['title'] = optText;
        opt['text'] = optText;
      }

      pollData['options'] = options;
      await docRef.update({'pollData': pollData});
      debugPrint('votePoll: Updated votes successfully on ${docRef.path}');
    } catch (e) {
      debugPrint('votePoll error: $e');
    }
  }

  Future<void> votePoll({
    required String senderId,
    required String receiverId,
    required String messageId,
    required int optionIndex,
    required String userId,
  }) async {
    final String chatId = getChatId(senderId, receiverId);
    final docRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);
    await _applyPollVote(
      docRef: docRef,
      optionIndex: optionIndex,
      userId: userId,
    );
  }

  Future<void> voteGroupPoll({
    required String groupId,
    required String messageId,
    required int optionIndex,
    required String userId,
  }) async {
    final docRef = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId);
    await _applyPollVote(
      docRef: docRef,
      optionIndex: optionIndex,
      userId: userId,
    );
  }

  // =====================================================
  // SEND CONTACT MESSAGE
  // =====================================================

  Future<void> sendContactMessage({
    required String senderId,
    required String receiverId,
    required String contactName,
    required String phoneNumber,
    bool isForwarded = false,
  }) async {
    final String chatId = getChatId(senderId, receiverId);

    final MessageModel messageModel = MessageModel(
      senderId: senderId,
      receiverId: receiverId,
      message: contactName,
      timestamp: DateTime.now(),
      type: 'contact',
      isForwarded: isForwarded,
      contactData: {
        'name': contactName,
        'phone': phoneNumber,
      },
    );

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(messageModel.toMap());

    await _updateChatMetadata(
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      lastMessage: '👤 $contactName',
      type: 'contact',
    );
  }

  // =====================================================
  // TOGGLE REACTION (👍, ❤️, 😂, 😮, 😢, 🙏, etc.)
  // =====================================================

  Future<void> toggleReaction({
    required String senderId,
    required String receiverId,
    required String messageId,
    required String userId,
    required String emoji,
  }) async {
    final String chatId = getChatId(senderId, receiverId);
    final docRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);

    final snapshot = await docRef.get();
    if (!snapshot.exists) return;

    final data = snapshot.data() ?? {};
    Map<String, dynamic> reactions =
        Map<String, dynamic>.from(data['reactions'] ?? {});

    if (reactions[userId] == emoji) {
      reactions.remove(userId);
    } else {
      reactions[userId] = emoji;
    }

    await docRef.update({'reactions': reactions});
  }

  // =====================================================
  // SEND CALL HISTORY MESSAGE
  // =====================================================

  Future<void> sendCallMessage({
    required String senderId,
    required String receiverId,
    required String callType,
    required String callStatus,
    required int duration,
  }) async {
    if (callType != 'voice' && callType != 'video') {
      throw Exception('Invalid call type: $callType');
    }

    final String chatId = getChatId(senderId, receiverId);

    final MessageModel callMessage = MessageModel(
      senderId: senderId,
      receiverId: receiverId,
      message: callType == 'video' ? 'Video call' : 'Voice call',
      timestamp: DateTime.now(),
      type: 'call',
      callType: callType,
      callStatus: callStatus,
      callDuration: duration,
      status: 'read',
      isSeen: true,
    );

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(callMessage.toMap());

    await _updateChatMetadata(
      chatId: chatId,
      senderId: senderId,
      receiverId: receiverId,
      lastMessage: callType == 'video' ? '📹 Video call' : '📞 Voice call',
      type: 'call',
    );
  }

  // =====================================================
  // GET REALTIME MESSAGES (WITH DOC IDs)
  // =====================================================

  Stream<List<MessageModel>> getMessages({
    required String userId,
    required String otherUserId,
  }) {
    final String chatId = getChatId(userId, otherUserId);

    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy(
          'timestamp',
          descending: false,
        )
        .snapshots()
        .map(
          (snapshot) {
            return snapshot.docs.map(
              (doc) {
                return MessageModel.fromMap(
                  doc.data(),
                  doc.id,
                );
              },
            ).toList();
          },
        );
  }

  // =====================================================
  // DELETE MESSAGE
  // =====================================================

  /// Delete message for everyone (removes document completely)
  Future<void> deleteMessageForEveryone({
    required String senderId,
    required String receiverId,
    required String messageId,
  }) async {
    final String chatId = getChatId(senderId, receiverId);

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  /// Delete message for current user only ("Delete for me")
  Future<void> deleteMessageForMe({
    required String senderId,
    required String receiverId,
    required String messageId,
    required String userId,
  }) async {
    final String chatId = getChatId(senderId, receiverId);

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({
          'deletedFor': FieldValue.arrayUnion([userId]),
        });
  }

  /// Backwards-compatible alias
  Future<void> deleteMessage({
    required String senderId,
    required String receiverId,
    required String messageId,
  }) => deleteMessageForEveryone(
        senderId: senderId,
        receiverId: receiverId,
        messageId: messageId,
      );

  // =====================================================
  // DELETE ENTIRE CHAT
  // =====================================================

  Future<void> deleteChat({
    required String userId,
    required String otherUserId,
  }) async {
    final String chatId = getChatId(userId, otherUserId);

    final QuerySnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .get();

    final WriteBatch batch = _firestore.batch();

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();

    await _firestore.collection('chats').doc(chatId).delete();
  }

  // =====================================================
  // CHAT METADATA & RECENT CONVERSATIONS (WHATSAPP CHAT LIST)
  // =====================================================

  Future<void> _updateChatMetadata({
    required String chatId,
    required String senderId,
    required String receiverId,
    required String lastMessage,
    required String type,
  }) async {
    try {
      final bool isCompletedCall = type == 'call' && !lastMessage.toLowerCase().contains('missed');

      await _firestore.collection('chats').doc(chatId).set({
        'chatId': chatId,
        'participants': [senderId, receiverId],
        'lastMessage': lastMessage,
        'lastMessageType': type,
        'lastSenderId': senderId,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageStatus': type == 'call' ? 'read' : 'sent',
        if (!isCompletedCall)
          'unread_$receiverId': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating chat metadata: $e');
    }
  }

  /// Mark all messages in a conversation as read and reset unread badge
  Future<void> markChatAsRead({
    required String userId,
    required String otherUserId,
  }) async {
    try {
      final String chatId = getChatId(userId, otherUserId);

      // Reset unread counter for current user immediately
      await _firestore.collection('chats').doc(chatId).set({
        'unread_$userId': 0,
      }, SetOptions(merge: true));

      // Fetch messages without requiring a composite index
      final unreadDocs = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('receiverId', isEqualTo: userId)
          .get();

      final toUpdate = unreadDocs.docs.where((d) {
        final data = d.data();
        return data['status'] != 'read' || data['isSeen'] != true;
      }).toList();

      if (toUpdate.isNotEmpty) {
        final WriteBatch batch = _firestore.batch();
        for (final doc in toUpdate) {
          batch.update(doc.reference, {
            'status': 'read',
            'isSeen': true,
          });
        }
        await batch.commit();
      }

      // If the last message was sent by otherUser, mark lastMessageStatus as 'read'
      final chatSnap = await _firestore.collection('chats').doc(chatId).get();
      if (chatSnap.exists && chatSnap.data()?['lastSenderId'] == otherUserId) {
        await _firestore.collection('chats').doc(chatId).update({
          'lastMessageStatus': 'read',
        });
      }
    } catch (e) {
      debugPrint('Error marking chat as read: $e');
    }
  }

  /// Completely delete a chat conversation and all its messages from Firestore
  Future<void> deleteChatByChatId(String chatId) async {
    try {
      final messagesSnap = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      final batch = _firestore.batch();
      for (final doc in messagesSnap.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_firestore.collection('chats').doc(chatId));
      await batch.commit();
      debugPrint('Chat $chatId completely deleted from Firestore');
    } catch (e) {
      debugPrint('Error deleting chat $chatId: $e');
    }
  }

  /// Completely delete a group and its messages from Firestore
  Future<void> deleteGroup(String groupId) async {
    try {
      final messagesSnap = await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('messages')
          .get();

      final batch = _firestore.batch();
      for (final doc in messagesSnap.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_firestore.collection('groups').doc(groupId));
      await batch.commit();
      debugPrint('Group $groupId completely deleted from Firestore');
    } catch (e) {
      debugPrint('Error deleting group $groupId: $e');
    }
  }

  /// Streams active conversations for current user ordered by most recent message
  Stream<QuerySnapshot<Map<String, dynamic>>> getRecentChatsStream(String currentUserId) {
    return _firestore
        .collection('chats')
        .where('participants', arrayContains: currentUserId)
        .snapshots();
  }

  // =====================================================
  // GROUP CHAT METHODS
  // =====================================================

  /// Creates a new group in Firestore
  Future<String> createGroup({
    required String name,
    required String adminId,
    required List<String> memberIds,
    String description = '',
  }) async {
    final List<String> allMembers = {...memberIds, adminId}.toList();
    final docRef = await _firestore.collection('groups').add({
      'name': name.trim(),
      'adminId': adminId,
      'members': allMembers,
      'description': description.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': 'Group created',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': adminId,
    });

    // Add initial system message
    await docRef.collection('messages').add({
      'senderId': adminId,
      'message': 'Group created by admin',
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'system',
    });

    return docRef.id;
  }

  /// Stream groups the user belongs to
  Stream<QuerySnapshot<Map<String, dynamic>>> getUserGroupsStream(String currentUserId) {
    return _firestore
        .collection('groups')
        .where('members', arrayContains: currentUserId)
        .snapshots();
  }

  /// Send message in a group
  /// Send rich message in a group (text, image, document, audio, location, poll)
  Future<void> sendGroupMessage({
    required String groupId,
    required String senderId,
    required String message,
    String? senderName,
    String type = 'text',
    String? mediaUrl,
    String? fileName,
    String? fileSize,
    double? latitude,
    double? longitude,
    Map<String, dynamic>? pollData,
    Map<String, dynamic>? contactData,
    Map<String, dynamic>? eventData,
    String? replyToId,
    String? replyToText,
    String? replyToSender,
    bool isForwarded = false,
  }) async {
    final Map<String, dynamic> msgData = {
      'senderId': senderId,
      'receiverId': groupId,
      'message': message.trim(),
      'timestamp': FieldValue.serverTimestamp(),
      'type': type,
      'isForwarded': isForwarded,
      'readBy': [senderId],
      if (senderName != null) 'senderName': senderName,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (fileName != null) 'fileName': fileName,
      if (fileSize != null) 'fileSize': fileSize,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (pollData != null) 'pollData': pollData,
      if (contactData != null) 'contactData': contactData,
      if (eventData != null) 'eventData': eventData,
      if (replyToId != null) 'replyToId': replyToId,
      if (replyToText != null) 'replyToText': replyToText,
      if (replyToSender != null) 'replyToSender': replyToSender,
    };

    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .add(msgData);

    String displayLastMsg = message.trim();
    if (type == 'image') {
      displayLastMsg = '📷 Photo';
    } else if (type == 'video') {
      displayLastMsg = '📹 Video';
    } else if (type == 'document') {
      displayLastMsg = '📄 ${fileName ?? 'Document'}';
    } else if (type == 'audio') {
      displayLastMsg = '🎤 Voice note';
    } else if (type == 'location') {
      displayLastMsg = '📍 Location';
    } else if (type == 'poll') {
      displayLastMsg = '📊 Poll';
    } else if (type == 'event') {
      String dateLabel = '';
      if (eventData != null && eventData['date'] != null) {
        final parsed = DateTime.tryParse(eventData['date'].toString());
        if (parsed != null) {
          const months = [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
          ];
          dateLabel = ' (${parsed.day} ${months[parsed.month - 1]})';
        }
      }
      displayLastMsg = 'Event$dateLabel: ${message.trim().isNotEmpty ? message.trim() : 'Scheduled'}';
    }

    final Map<String, dynamic> updateData = {
      'lastMessage': displayLastMsg,
      'lastMessageType': type,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': senderId,
      if (senderName != null) 'lastSenderName': senderName,
    };

    try {
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      final List<dynamic> members = groupDoc.data()?['members'] ?? [];
      for (final m in members) {
        final mId = m.toString();
        if (mId != senderId) {
          updateData['unread_$mId'] = FieldValue.increment(1);
        }
      }
    } catch (_) {}

    await _firestore.collection('groups').doc(groupId).update(updateData);
  }

  /// Send event message in a group
  Future<void> sendGroupEventMessage({
    required String groupId,
    required String senderId,
    String? senderName,
    required String title,
    required DateTime date,
    required TimeOfDay time,
    String? location,
    String? description,
  }) async {
    final String timeFormatted =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    final Map<String, dynamic> eventData = {
      'title': title.trim(),
      'date': date.toIso8601String(),
      'time': timeFormatted,
      if (location != null && location.trim().isNotEmpty) 'location': location.trim(),
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
    };

    await sendGroupMessage(
      groupId: groupId,
      senderId: senderId,
      senderName: senderName,
      message: title.trim(),
      type: 'event',
      eventData: eventData,
    );
  }


  /// Mark all unread group messages as read and reset unread badge for current user
  Future<void> markGroupMessagesAsRead({
    required String groupId,
    required String userId,
  }) async {
    try {
      // 1. Reset unread counter for this user in group doc
      await _firestore.collection('groups').doc(groupId).update({
        'unread_$userId': 0,
      }).catchError((_) {});

      // 2. Mark recent messages as read by adding userId to readBy array
      final query = await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(40)
          .get();

      final WriteBatch batch = _firestore.batch();
      bool hasUpdates = false;

      for (final doc in query.docs) {
        final data = doc.data();
        final List<dynamic> readBy = List.from(data['readBy'] ?? []);
        if (!readBy.contains(userId)) {
          batch.update(doc.reference, {
            'readBy': FieldValue.arrayUnion([userId]),
          });
          hasUpdates = true;
        }
      }

      if (hasUpdates) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error marking group messages as read: $e');
    }
  }

  /// Stream messages in a group
  Stream<QuerySnapshot<Map<String, dynamic>>> getGroupMessages(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  /// Toggle reaction on a group message (👍, ❤️, 😂, 😮, 😢, 🙏)
  Future<void> toggleGroupReaction({
    required String groupId,
    required String messageId,
    required String userId,
    required String emoji,
  }) async {
    final docRef = _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId);

    final snapshot = await docRef.get();
    if (!snapshot.exists) return;

    final data = snapshot.data() ?? {};
    Map<String, dynamic> reactions =
        Map<String, dynamic>.from(data['reactions'] ?? {});

    if (reactions[userId] == emoji) {
      reactions.remove(userId);
    } else {
      reactions[userId] = emoji;
    }

    await docRef.update({'reactions': reactions});
  }

  /// Delete a group message for everyone
  Future<void> deleteGroupMessageForEveryone({
    required String groupId,
    required String messageId,
  }) async {
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  /// Delete a group message for current user only ("Delete for me")
  Future<void> deleteGroupMessageForMe({
    required String groupId,
    required String messageId,
    required String userId,
  }) async {
    await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .doc(messageId)
        .update({
          'deletedFor': FieldValue.arrayUnion([userId]),
        });
  }

  /// Backwards-compatible alias
  Future<void> deleteGroupMessage({
    required String groupId,
    required String messageId,
  }) => deleteGroupMessageForEveryone(
        groupId: groupId,
        messageId: messageId,
      );

  // =====================================================
  // USER STATUS / UPDATES METHODS
  // =====================================================

  /// Upload a new user status (photo or text)
  Future<void> uploadStatus({
    required String userId,
    required String userName,
    required String userPhone,
    String? mediaUrl,
    String? textContent,
    required String type,
    int? bgColor,
  }) async {
    await _firestore.collection('statuses').add({
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'mediaUrl': mediaUrl,
      'textContent': textContent,
      'type': type,
      'bgColor': bgColor,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Stream all recent statuses
  Stream<QuerySnapshot<Map<String, dynamic>>> getStatusesStream() {
    return _firestore
        .collection('statuses')
        .snapshots();
  }

  /// Delete an expired or user-deleted status
  Future<void> deleteStatus(String statusId) async {
    await _firestore.collection('statuses').doc(statusId).delete();
  }

  // =====================================================
  // BATCH MESSAGE FORWARDING
  // =====================================================

  /// Forwards a message to multiple 1-on-1 users and/or group chats
  Future<void> forwardMessage({
    required String senderId,
    String? senderName,
    required List<String> targetUserIds,
    required List<String> targetGroupIds,
    required MessageModel originalMessage,
  }) async {
    // Forward to 1-on-1 chats
    for (final targetUserId in targetUserIds) {
      if (originalMessage.type == 'image' ||
          originalMessage.type == 'video' ||
          originalMessage.type == 'audio') {
        await sendMediaMessage(
          senderId: senderId,
          receiverId: targetUserId,
          mediaUrl: originalMessage.mediaUrl ?? '',
          type: originalMessage.type,
          message: originalMessage.message,
          isForwarded: true,
        );
      } else if (originalMessage.type == 'document') {
        await sendDocumentMessage(
          senderId: senderId,
          receiverId: targetUserId,
          mediaUrl: originalMessage.mediaUrl ?? '',
          fileName: originalMessage.fileName ?? 'Document',
          fileSize: originalMessage.fileSize ?? '',
          message: originalMessage.message,
          isForwarded: true,
        );
      } else if (originalMessage.type == 'location') {
        await sendLocationMessage(
          senderId: senderId,
          receiverId: targetUserId,
          latitude: originalMessage.latitude ?? 0.0,
          longitude: originalMessage.longitude ?? 0.0,
          address: originalMessage.message,
          isForwarded: true,
        );
      } else if (originalMessage.type == 'contact') {
        final contactData = originalMessage.contactData ?? {};
        await sendContactMessage(
          senderId: senderId,
          receiverId: targetUserId,
          contactName: contactData['name']?.toString() ?? originalMessage.message,
          phoneNumber: contactData['phone']?.toString() ?? '',
          isForwarded: true,
        );
      } else {
        await sendMessage(
          senderId: senderId,
          receiverId: targetUserId,
          message: originalMessage.message,
          isForwarded: true,
        );
      }
    }

    // Forward to Group chats
    for (final targetGroupId in targetGroupIds) {
      await sendGroupMessage(
        groupId: targetGroupId,
        senderId: senderId,
        senderName: senderName,
        message: originalMessage.message,
        type: originalMessage.type,
        mediaUrl: originalMessage.mediaUrl,
        fileName: originalMessage.fileName,
        fileSize: originalMessage.fileSize,
        latitude: originalMessage.latitude,
        longitude: originalMessage.longitude,
        pollData: originalMessage.pollData,
        contactData: originalMessage.contactData,
        isForwarded: true,
      );
    }
  }
}