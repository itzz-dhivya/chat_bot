import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'ringtone_service.dart';
import 'user_service.dart';

// Top-level background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background message: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messageSubscription;

  // ---------------------------------------------------------
  // CALL NOTIFICATION LISTENER STATE
  // ---------------------------------------------------------

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _callSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _groupCallSubscription;

  // Prevents showing more than one notification for the same call doc
  final Set<String> _notifiedCallIds = {};

  DateTime _listenerStartTime = DateTime.now();

  // Currently active chat user ID (so we don't spam notifications if user is already looking at that chat)
  String? activeChatUserId;

  // Currently active call ID (so we don't double-notify while the call
  // screen is already open for that call). Set this from CallManager /
  // CallScreen if you want to suppress the OS notification while the
  // in-app call screen is already showing.
  String? activeCallId;

  static const AndroidNotificationChannel _chatChannel =
  AndroidNotificationChannel(
    'chat_messages_channel',
    'Chat Messages',
    description:
    'Instant notifications with sound for incoming chat messages',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel _callChannel =
  AndroidNotificationChannel(
    'incoming_calls_channel',
    'Incoming Calls',
    description: 'High-priority notifications for incoming calls',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    enableLights: true,
  );

  /// Initialize Notifications
  Future<void> initialize() async {
    // 1. Request system notification permissions
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('Notification permission status: ${settings.authorizationStatus}');

    // 2. Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 3. Local notification settings
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification tapped: ${response.payload}');
      },
    );

    // 4. Create high-priority Android notification channels
    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_chatChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_callChannel);

    // 5. Handle foreground FCM messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground FCM received: ${message.data}');
      final type = message.data['type'] ?? '';
      final title = message.notification?.title ??
          message.data['title'] ??
          'Notification';
      final body =
          message.notification?.body ?? message.data['body'] ?? '';

      if (type == 'incoming_call') {
        showCallNotification(title: title, body: body);
      } else {
        showChatNotification(title: title, body: body);
      }
    });

    // 6. Handle notification click when app opened
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('App opened from notification: ${message.data}');
    });
  }

  /// Show a local chat notification with sound and vibration
  Future<void> showChatNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    final int notificationId =
        DateTime.now().millisecondsSinceEpoch ~/ 1000;

    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'chat_messages_channel',
      'Chat Messages',
      channelDescription:
      'Instant notifications with sound for incoming chat messages',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: 'ticker',
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Play default notification chime
    RingtoneService().playNotificationSound();

    await _localNotifications.show(
      notificationId,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Show a high-priority incoming call notification
  Future<void> showCallNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    // Use a fixed ID so repeated call notifications replace the old one
    const int callNotificationId = 9999;

    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'incoming_calls_channel',
      'Incoming Calls',
      channelDescription: 'High-priority notifications for incoming calls',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      ticker: 'Incoming call',
      icon: '@mipmap/ic_launcher',
      autoCancel: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      callNotificationId,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Clear the active call notification (call it once the call screen
  /// is dismissed / call is over, so it doesn't linger in the tray).
  Future<void> clearCallNotification() async {
    const int callNotificationId = 9999;
    await _localNotifications.cancel(callNotificationId);
  }

  /// Show a generic notification (kept for backward compatibility)
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await showChatNotification(
      title: title,
      body: body,
      payload: payload,
    );
  }

  /// Start real-time Firestore listener for all incoming messages for the logged-in user
  void startMessageNotificationListener(String currentUserId) {
    _messageSubscription?.cancel();
    _listenerStartTime = DateTime.now().subtract(const Duration(seconds: 3));

    debugPrint('NotificationService: Listening for messages for user $currentUserId');

    // Subscribe to individual chats where the current user is a participant
    _messageSubscription = _firestore
        .collection('chats')
        .where('participants', arrayContains: currentUserId)
        .snapshots()
        .listen((chatSnap) async {
      for (final chatChange in chatSnap.docChanges) {
        // No need to process deletions
        if (chatChange.type == DocumentChangeType.removed) continue;

        final chatData = chatChange.doc.data();
        if (chatData == null) continue;

        // Only care if the last sender is NOT the current user
        final lastSenderId = chatData['lastSenderId']?.toString() ?? '';
        if (lastSenderId.isEmpty || lastSenderId == currentUserId) continue;

        // Only notify if the chat metadata itself changed (new message)
        if (chatChange.type != DocumentChangeType.modified &&
            chatChange.type != DocumentChangeType.added) {
          continue;
        }

        final lastMsgTime = chatData['lastMessageTime'];
        DateTime msgTime = DateTime.now();
        if (lastMsgTime is Timestamp) {
          msgTime = lastMsgTime.toDate();
        }

        // Only process recent messages
        if (msgTime.isBefore(_listenerStartTime)) continue;

        // Don't notify if user is inside that specific chat right now
        if (activeChatUserId == lastSenderId) continue;

        final lastMsg = chatData['lastMessage']?.toString() ?? 'New message';

        String senderName = 'New Message';
        try {
          final senderUser = await UserService().getUserById(lastSenderId);
          if (senderUser != null && senderUser.name.isNotEmpty) {
            senderName = senderUser.name;
          }
        } catch (_) {}

        debugPrint('NotificationService: Chat message from $senderName: $lastMsg');
        await showChatNotification(
          title: '💬 $senderName',
          body: lastMsg,
          payload: lastSenderId,
        );
      }
    }, onError: (err) {
      debugPrint('Message notification listener error: $err');
    });
  }

  /// Stop listening for messages
  void stopMessageNotificationListener() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
  }

  // ===========================================================
  // CALL NOTIFICATION LISTENER
  // ===========================================================

  /// Start real-time Firestore listener for incoming calls for the
  /// logged-in user. Shows a high-priority local notification the
  /// moment someone starts calling this user.
  void startCallNotificationListener(String currentUserId) {
    _callSubscription?.cancel();
    _groupCallSubscription?.cancel();
    _notifiedCallIds.clear();

    final DateTime listenerStartTime = DateTime.now();

    debugPrint(
      'NotificationService: Listening for incoming calls for user $currentUserId',
    );

    // 1. One-to-one calls
    _callSubscription = _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .listen((snapshot) async {
      final now = DateTime.now();

      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) {
          continue;
        }

        final data = change.doc.data();
        if (data == null) continue;

        final String callId = change.doc.id;
        final String callerId = data['callerId']?.toString() ?? '';

        // Ignore our own call
        if (callerId == currentUserId || callerId.isEmpty) {
          continue;
        }

        // Ignore stale / expired calls (> 45s or created prior to app session)
        final dynamic rawCreatedAt = data['createdAt'] ?? data['timestamp'];
        DateTime? createdTime;
        if (rawCreatedAt is Timestamp) {
          createdTime = rawCreatedAt.toDate();
        } else if (rawCreatedAt is String) {
          createdTime = DateTime.tryParse(rawCreatedAt);
        }

        if (createdTime != null) {
          if (now.difference(createdTime).inSeconds > 45 ||
              createdTime.isBefore(listenerStartTime.subtract(const Duration(seconds: 15)))) {
            continue;
          }
        }

        // Don't notify twice for the same call
        if (_notifiedCallIds.contains(callId)) {
          continue;
        }

        // Skip if the in-app call screen for this call is already open
        if (activeCallId == callId) {
          continue;
        }

        _notifiedCallIds.add(callId);

        final String callerName =
        (data['callerName']?.toString().isNotEmpty ?? false)
            ? data['callerName'].toString()
            : 'Someone';

        final String callType = data['type']?.toString() ?? 'voice';

        debugPrint(
          'NotificationService: Incoming $callType call from $callerName',
        );

        await showCallNotification(
          title: callType == 'video'
              ? '📹 Incoming video call'
              : '📞 Incoming call',
          body: '$callerName is calling...',
          payload: callId,
        );
      }
    }, onError: (err) {
      debugPrint('Call notification listener error: $err');
    });

    // 2. Group calls
    _groupCallSubscription = _firestore
        .collection('group_calls')
        .where('invitedUserIds', arrayContains: currentUserId)
        .where('status', isEqualTo: 'calling')
        .snapshots()
        .listen((snapshot) async {
      final now = DateTime.now();

      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;

        final data = change.doc.data();
        if (data == null) continue;

        final String callId = change.doc.id;
        final String callerId = data['callerId']?.toString() ?? '';

        if (callerId == currentUserId || callerId.isEmpty) continue;

        final dynamic rawCreatedAt = data['createdAt'];
        DateTime? createdTime;
        if (rawCreatedAt is Timestamp) {
          createdTime = rawCreatedAt.toDate();
        } else if (rawCreatedAt is String) {
          createdTime = DateTime.tryParse(rawCreatedAt);
        }

        if (createdTime != null) {
          if (now.difference(createdTime).inSeconds > 60 ||
              createdTime.isBefore(listenerStartTime.subtract(const Duration(seconds: 15)))) {
            continue;
          }
        }

        if (_notifiedCallIds.contains(callId) || activeCallId == callId) continue;
        _notifiedCallIds.add(callId);

        final String callerName = data['callerName']?.toString() ?? 'Someone';
        final String groupName = data['groupName']?.toString() ?? 'Group';
        final String callType = data['callType']?.toString() ?? 'voice';

        await showCallNotification(
          title: callType == 'video'
              ? '📹 Group Video Call • $groupName'
              : '📞 Group Voice Call • $groupName',
          body: '$callerName started a group call',
          payload: callId,
        );
      }
    }, onError: (err) {
      debugPrint('Group call notification listener error: $err');
    });
  }

  /// Stop listening for calls
  void stopCallNotificationListener() {
    _callSubscription?.cancel();
    _callSubscription = null;
    _groupCallSubscription?.cancel();
    _groupCallSubscription = null;
  }

  /// Convenience — call this at logout to tear down all listeners.
  void stopAllListeners() {
    stopMessageNotificationListener();
    stopCallNotificationListener();
  }
}