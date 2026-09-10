import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../screens/call_screen.dart';
import '../screens/group_call_screen.dart';
import 'notification_service.dart';
import 'user_service.dart';

class CallManager {
  static final CallManager _instance = CallManager._internal();

  factory CallManager() => _instance;

  CallManager._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _incomingCallSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _incomingGroupCallSubscription;

  GlobalKey<NavigatorState>? navigatorKey;

  bool isCallInProgress = false;
  String? _currentCallId;

  DateTime _listenerStartTime = DateTime.now();

  void startListening(
      String userId,
      GlobalKey<NavigatorState> navKey,
      ) {
    navigatorKey = navKey;
    _listenerStartTime = DateTime.now();

    _incomingCallSubscription?.cancel();
    _incomingGroupCallSubscription?.cancel();

    debugPrint(
      'CallManager: Listening for incoming calls for user $userId',
    );

    // 1. One-on-one call listener
    _incomingCallSubscription = _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .listen(
          (snapshot) {
        if (snapshot.docs.isEmpty) return;

        final now = DateTime.now();

        for (final doc in snapshot.docs) {
          final callId = doc.id;
          final data = doc.data();

          final callerId = data['callerId']?.toString() ?? '';

          // Ignore our own call
          if (callerId.isEmpty || callerId == userId) {
            continue;
          }

          // Parse createdAt / timestamp
          final dynamic rawCreatedAt = data['createdAt'] ?? data['timestamp'];
          DateTime? createdTime;
          if (rawCreatedAt is Timestamp) {
            createdTime = rawCreatedAt.toDate();
          } else if (rawCreatedAt is String) {
            createdTime = DateTime.tryParse(rawCreatedAt);
          }

          // Check if call is stale/expired (older than 45 seconds or created long before listener started)
          final bool isStale = (createdTime != null && now.difference(createdTime).inSeconds > 45) ||
              (createdTime != null && createdTime.isBefore(_listenerStartTime.subtract(const Duration(seconds: 15))));

          if (isStale) {
            debugPrint('CallManager: Cleaning up stale call $callId');
            _firestore.collection('calls').doc(callId).update({
              'status': 'missed',
              'endedAt': FieldValue.serverTimestamp(),
            }).catchError((_) {});
            continue;
          }

          // Prevent duplicate incoming call screen
          if (isCallInProgress || _currentCallId == callId) {
            continue;
          }

          final callerName = data['callerName']?.toString() ?? 'Caller';
          final callerPhone = data['callerPhone']?.toString() ?? '';
          final callerAvatarUrl = data['callerAvatarUrl']?.toString();

          final receiverId = data['receiverId']?.toString() ?? '';
          final receiverName = data['receiverName']?.toString() ?? '';
          final receiverPhone = data['receiverPhone']?.toString() ?? '';
          final receiverAvatarUrl = data['receiverAvatarUrl']?.toString();

          final callType = data['type']?.toString() ?? 'voice';

          _currentCallId = callId;
          isCallInProgress = true;

          // Let NotificationService know this call's screen is about to
          // be open, so it doesn't fire a duplicate OS notification.
          NotificationService().activeCallId = callId;

          debugPrint(
            'CallManager: Incoming $callType call from $callerName ($callerPhone)',
          );

          navigatorKey?.currentState?.push(
            MaterialPageRoute(
              builder: (_) => CallScreen(
                callId: callId,
                callerId: callerId,
                callerName: callerName,
                callerPhone: callerPhone,
                callerAvatarUrl: callerAvatarUrl,
                receiverId: receiverId,
                receiverName: receiverName,
                receiverPhone: receiverPhone,
                receiverAvatarUrl: receiverAvatarUrl,
                isIncoming: true,
                callType: callType,
              ),
            ),
          ).then((_) {
            isCallInProgress = false;
            _currentCallId = null;

            // Call screen closed — clear guard + any lingering notification.
            NotificationService().activeCallId = null;
            NotificationService().clearCallNotification();
          });

          // Handled one active call
          break;
        }
      },
      onError: (error) {
        debugPrint(
          'CallManager Error: $error',
        );
      },
    );

    // 2. Group call listener
    _incomingGroupCallSubscription = _firestore
        .collection('group_calls')
        .where('invitedUserIds', arrayContains: userId)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.docs.isEmpty) return;

      final now = DateTime.now();

      for (final doc in snapshot.docs) {
        final callId = doc.id;
        final data = doc.data();

        final callerId = data['callerId']?.toString() ?? '';

        // Ignore our own call
        if (callerId.isEmpty || callerId == userId) {
          continue;
        }

        // Parse createdAt
        final dynamic rawCreatedAt = data['createdAt'];
        DateTime? createdTime;
        if (rawCreatedAt is Timestamp) {
          createdTime = rawCreatedAt.toDate();
        } else if (rawCreatedAt is String) {
          createdTime = DateTime.tryParse(rawCreatedAt);
        }

        final bool isStale = (createdTime != null && now.difference(createdTime).inSeconds > 60) ||
            (createdTime != null && createdTime.isBefore(_listenerStartTime.subtract(const Duration(seconds: 15))));

        if (isStale) continue;

        if (isCallInProgress || _currentCallId == callId) continue;

        final groupId = data['groupId']?.toString() ?? '';
        final groupName = data['groupName']?.toString() ?? 'Group Call';
        final callType = data['callType']?.toString() ?? 'voice';
        final bool isVideo = callType == 'video';

        _currentCallId = callId;
        isCallInProgress = true;
        NotificationService().activeCallId = callId;

        // Fetch user and members
        UserModel? currentUser = await UserService().getUserById(userId);
        currentUser ??= UserModel(
          id: userId,
          name: 'User',
          phoneNumber: '',
          createdAt: DateTime.now(),
        );

        List<UserModel> groupMembers = [currentUser];
        try {
          final groupDoc = await _firestore.collection('groups').doc(groupId).get();
          if (groupDoc.exists) {
            final List<String> memberIds = List<String>.from(groupDoc.data()?['members'] ?? []);
            final futures = memberIds.map((mId) => UserService().getUserById(mId));
            final members = await Future.wait(futures);
            final fetched = members.whereType<UserModel>().toList();
            if (fetched.isNotEmpty) {
              groupMembers = fetched;
            }
          }
        } catch (_) {}

        if (groupMembers.isEmpty) {
          groupMembers.add(currentUser);
        }

        debugPrint('CallManager: Incoming Group Call $callId in $groupName');

        navigatorKey?.currentState?.push(
          MaterialPageRoute(
            builder: (_) => GroupCallScreen(
              callId: callId,
              groupId: groupId,
              groupName: groupName,
              currentUser: currentUser!,
              groupMembers: groupMembers,
              isVideo: isVideo,
              isIncoming: true,
            ),
          ),
        ).then((_) {
          isCallInProgress = false;
          _currentCallId = null;
          NotificationService().activeCallId = null;
          NotificationService().clearCallNotification();
        });

        break;
      }
    }, onError: (err) {
      debugPrint('Group call listener error: $err');
    });
  }

  void stopListening() {
    _incomingCallSubscription?.cancel();
    _incomingCallSubscription = null;
    _incomingGroupCallSubscription?.cancel();
    _incomingGroupCallSubscription = null;
    isCallInProgress = false;
    _currentCallId = null;
  }
}