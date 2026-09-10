import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

class GroupCallParticipant {
  final String userId;
  final String userName;
  final String userPhone;
  final String? avatarUrl;
  final bool isMuted;
  final bool isVideoOff;
  final bool isConnected;
  final DateTime? joinedAt;

  const GroupCallParticipant({
    required this.userId,
    required this.userName,
    required this.userPhone,
    this.avatarUrl,
    this.isMuted = false,
    this.isVideoOff = false,
    this.isConnected = false,
    this.joinedAt,
  });

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'userName': userName,
        'userPhone': userPhone,
        'avatarUrl': avatarUrl,
        'isMuted': isMuted,
        'isVideoOff': isVideoOff,
        'isConnected': isConnected,
        'joinedAt': joinedAt != null ? Timestamp.fromDate(joinedAt!) : FieldValue.serverTimestamp(),
      };

  factory GroupCallParticipant.fromMap(Map<String, dynamic> map) {
    DateTime? joined;
    final dynamic rawJoined = map['joinedAt'];
    if (rawJoined is Timestamp) {
      joined = rawJoined.toDate();
    } else if (rawJoined is String) {
      joined = DateTime.tryParse(rawJoined);
    }
    return GroupCallParticipant(
      userId: map['userId']?.toString() ?? '',
      userName: map['userName']?.toString() ?? '',
      userPhone: map['userPhone']?.toString() ?? '',
      avatarUrl: map['avatarUrl']?.toString(),
      isMuted: map['isMuted'] == true,
      isVideoOff: map['isVideoOff'] == true,
      isConnected: map['isConnected'] == true,
      joinedAt: joined,
    );
  }
}

class GroupCallModel {
  final String id;
  final String groupId;
  final String groupName;
  final String callerId;
  final String callerName;
  final String callerPhone;
  final String? callerAvatarUrl;
  final String callType; // 'voice' or 'video'
  final String status; // 'calling', 'ongoing', 'ended'
  final List<String> invitedUserIds;
  final List<GroupCallParticipant> participants;
  final DateTime createdAt;
  final DateTime? endedAt;

  GroupCallModel({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.callerId,
    required this.callerName,
    required this.callerPhone,
    this.callerAvatarUrl,
    required this.callType,
    required this.status,
    required this.invitedUserIds,
    required this.participants,
    required this.createdAt,
    this.endedAt,
  });

  factory GroupCallModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final dynamic rawCreated = data['createdAt'];
    DateTime created = DateTime.now();
    if (rawCreated is Timestamp) created = rawCreated.toDate();

    final dynamic rawEnded = data['endedAt'];
    DateTime? ended;
    if (rawEnded is Timestamp) ended = rawEnded.toDate();

    final List<dynamic> rawParticipants = data['participants'] ?? [];
    final List<GroupCallParticipant> participantsList = rawParticipants
        .map((p) => GroupCallParticipant.fromMap(Map<String, dynamic>.from(p as Map)))
        .toList();

    return GroupCallModel(
      id: doc.id,
      groupId: data['groupId']?.toString() ?? '',
      groupName: data['groupName']?.toString() ?? 'Group Call',
      callerId: data['callerId']?.toString() ?? '',
      callerName: data['callerName']?.toString() ?? '',
      callerPhone: data['callerPhone']?.toString() ?? '',
      callerAvatarUrl: data['callerAvatarUrl']?.toString(),
      callType: data['callType']?.toString() ?? 'voice',
      status: data['status']?.toString() ?? 'calling',
      invitedUserIds: List<String>.from(data['invitedUserIds'] ?? []),
      participants: participantsList,
      createdAt: created,
      endedAt: ended,
    );
  }
}

class GroupCallService {
  static final GroupCallService _instance = GroupCallService._internal();
  factory GroupCallService() => _instance;
  GroupCallService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Creates a new group call document in Firestore
  Future<String> createGroupCall({
    required String groupId,
    required String groupName,
    required UserModel caller,
    required List<UserModel> invitedMembers,
    required bool isVideo,
  }) async {
    final List<String> invitedIds = invitedMembers.map((m) => m.id).toList();
    // Ensure caller is included
    if (!invitedIds.contains(caller.id)) {
      invitedIds.add(caller.id);
    }

    final callerParticipant = GroupCallParticipant(
      userId: caller.id,
      userName: caller.name.isNotEmpty ? caller.name : caller.phoneNumber,
      userPhone: caller.phoneNumber,
      avatarUrl: caller.avatarUrl,
      isMuted: false,
      isVideoOff: !isVideo,
      isConnected: true,
      joinedAt: DateTime.now(),
    );

    final docRef = await _firestore.collection('group_calls').add({
      'groupId': groupId,
      'groupName': groupName,
      'callerId': caller.id,
      'callerName': caller.name.isNotEmpty ? caller.name : caller.phoneNumber,
      'callerPhone': caller.phoneNumber,
      'callerAvatarUrl': caller.avatarUrl,
      'callType': isVideo ? 'video' : 'voice',
      'status': 'calling',
      'invitedUserIds': invitedIds,
      'participants': [callerParticipant.toMap()],
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Also update group last message metadata to reflect group call
    await _firestore.collection('groups').doc(groupId).update({
      'lastMessage': isVideo ? '📹 Group video call' : '📞 Group voice call',
      'lastSenderId': caller.id,
      'lastSenderName': caller.name.isNotEmpty ? caller.name : caller.phoneNumber,
      'lastMessageTime': FieldValue.serverTimestamp(),
    }).catchError((_) {});

    return docRef.id;
  }

  /// Streams the real-time group call document
  Stream<GroupCallModel?> streamGroupCall(String callId) {
    return _firestore
        .collection('group_calls')
        .doc(callId)
        .snapshots()
        .map((snap) => snap.exists ? GroupCallModel.fromDoc(snap) : null);
  }

  /// Joins an ongoing group call
  Future<void> joinGroupCall({
    required String callId,
    required UserModel user,
    required bool isVideo,
  }) async {
    final docRef = _firestore.collection('group_calls').doc(callId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final data = doc.data() ?? {};
    final List<dynamic> currentParticipants = data['participants'] ?? [];

    // Remove existing entry for this user if any, then add fresh
    final updatedList = currentParticipants
        .where((p) => p['userId'] != user.id)
        .toList();

    final newParticipant = GroupCallParticipant(
      userId: user.id,
      userName: user.name.isNotEmpty ? user.name : user.phoneNumber,
      userPhone: user.phoneNumber,
      avatarUrl: user.avatarUrl,
      isMuted: false,
      isVideoOff: !isVideo,
      isConnected: true,
      joinedAt: DateTime.now(),
    );

    updatedList.add(newParticipant.toMap());

    await docRef.update({
      'participants': updatedList,
      'status': 'ongoing',
    });
  }

  /// Updates local mute or video state in Firestore
  Future<void> updateParticipantState({
    required String callId,
    required String userId,
    bool? isMuted,
    bool? isVideoOff,
  }) async {
    final docRef = _firestore.collection('group_calls').doc(callId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final data = doc.data() ?? {};
    final List<dynamic> participants = List.from(data['participants'] ?? []);

    for (int i = 0; i < participants.length; i++) {
      if (participants[i]['userId'] == userId) {
        final Map<String, dynamic> pMap = Map<String, dynamic>.from(participants[i]);
        if (isMuted != null) pMap['isMuted'] = isMuted;
        if (isVideoOff != null) pMap['isVideoOff'] = isVideoOff;
        participants[i] = pMap;
        break;
      }
    }

    await docRef.update({'participants': participants});
  }

  /// Ends the group call and writes a call history bubble into the group chat.
  Future<void> _endAndRecordGroupCall(
    DocumentReference<Map<String, dynamic>> docRef,
    Map<String, dynamic> data, {
    required bool isMissed,
  }) async {
    final groupId = data['groupId']?.toString() ?? '';
    final callerId = data['callerId']?.toString() ?? '';
    final callerName = data['callerName']?.toString() ?? 'Someone';
    final callType = data['callType']?.toString() ?? 'voice';
    final dynamic rawCreatedAt = data['createdAt'];
    DateTime createdAt = DateTime.now();
    if (rawCreatedAt is Timestamp) createdAt = rawCreatedAt.toDate();
    final int duration = isMissed ? 0 : DateTime.now().difference(createdAt).inSeconds;

    await docRef.update({
      'participants': [],
      'status': 'ended',
      'endedAt': FieldValue.serverTimestamp(),
    });

    if (groupId.isNotEmpty && data['historySaved'] != true) {
      try {
        await docRef.update({'historySaved': true});
        await _firestore
            .collection('groups')
            .doc(groupId)
            .collection('messages')
            .add({
          'senderId': callerId,
          'senderName': callerName,
          'receiverId': groupId,
          'message': callType == 'video' ? 'Group video call' : 'Group voice call',
          'timestamp': FieldValue.serverTimestamp(),
          'type': 'call',
          'callType': callType,
          'callStatus': isMissed ? 'missed' : 'ended',
          'callDuration': duration,
          'status': 'read',
          'isSeen': true,
        });

        await _firestore.collection('groups').doc(groupId).update({
          'lastMessage': callType == 'video' ? '📹 Group video call' : '📞 Group voice call',
          'lastSenderId': callerId,
          'lastSenderName': callerName,
          'lastMessageTime': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('GroupCallService: Error saving group call history: $e');
      }
    }
  }

  /// Leaves a group call. If caller leaves while ringing, or no active connected participants remain, marks call ended.
  Future<void> leaveGroupCall({
    required String callId,
    required String userId,
    required String groupId,
  }) async {
    try {
      final docRef = _firestore.collection('group_calls').doc(callId);
      final doc = await docRef.get();
      if (!doc.exists) return;

      final data = doc.data() ?? {};
      final callerId = data['callerId']?.toString() ?? '';
      final currentStatus = data['status']?.toString() ?? 'calling';
      final isCaller = callerId == userId;

      // If caller cancels before anyone answers, end call for everyone and record missed call
      if (isCaller && currentStatus == 'calling') {
        await _endAndRecordGroupCall(docRef, data, isMissed: true);
        return;
      }

      final List<dynamic> participants = List.from(data['participants'] ?? []);

      // Remove the user from connected participants
      participants.removeWhere((p) => p['userId'] == userId);

      if (participants.isEmpty) {
        // Last person left: end the call
        await _endAndRecordGroupCall(docRef, data, isMissed: currentStatus == 'calling');
      } else {
        await docRef.update({'participants': participants});
      }
    } catch (e) {
      debugPrint('GroupCallService: Error leaving group call: $e');
    }
  }

  /// Invites additional members to an active group call
  Future<void> inviteMoreMembers({
    required String callId,
    required List<UserModel> newMembers,
  }) async {
    final docRef = _firestore.collection('group_calls').doc(callId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final data = doc.data() ?? {};
    final List<String> currentInvited = List<String>.from(data['invitedUserIds'] ?? []);

    for (final m in newMembers) {
      if (!currentInvited.contains(m.id)) {
        currentInvited.add(m.id);
      }
    }

    await docRef.update({'invitedUserIds': currentInvited});
  }

  /// Sends a WebRTC signal (offer, answer, or candidate) to a peer in the group call
  Future<void> sendSignal({
    required String callId,
    required String fromUserId,
    required String toUserId,
    required String type, // 'offer', 'answer', 'candidate'
    required dynamic data,
  }) async {
    try {
      await _firestore
          .collection('group_calls')
          .doc(callId)
          .collection('signals')
          .add({
        'fromUserId': fromUserId,
        'toUserId': toUserId,
        'type': type,
        'data': data,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('GroupCallService: Error sending signal ($type): $e');
    }
  }

  /// Streams incoming signals intended for [myUserId] in this call
  Stream<QuerySnapshot<Map<String, dynamic>>> streamIncomingSignals({
    required String callId,
    required String myUserId,
  }) {
    return _firestore
        .collection('group_calls')
        .doc(callId)
        .collection('signals')
        .where('toUserId', isEqualTo: myUserId)
        .snapshots();
  }

  /// Deletes a processed signal from Firestore
  Future<void> deleteSignal({
    required String callId,
    required String signalId,
  }) async {
    try {
      await _firestore
          .collection('group_calls')
          .doc(callId)
          .collection('signals')
          .doc(signalId)
          .delete();
    } catch (_) {}
  }
}
