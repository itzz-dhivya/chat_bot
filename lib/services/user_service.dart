import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

class UserService {
  // Singleton pattern
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  UserModel? _cachedCurrentUser;
  UserModel? get currentUser => _cachedCurrentUser;

  String? get currentUserId => _auth.currentUser?.uid;

  /// Ensure user is logged in (anonymously if not authenticated)
  Future<User> ensureUserLoggedIn() async {
    User? user = _auth.currentUser;
    if (user != null) {
      await _loadCurrentUserProfile(user.uid);
      return user;
    }

    final UserCredential credential = await _auth.signInAnonymously();
    user = credential.user!;
    await _loadCurrentUserProfile(user.uid);
    return user;
  }

  /// Load current user profile from Firestore
  Future<UserModel?> _loadCurrentUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        _cachedCurrentUser = UserModel.fromMap(doc.data()!, doc.id);
      }
      return _cachedCurrentUser;
    } catch (e) {
      return null;
    }
  }

  /// Get current user profile
  Future<UserModel?> getCurrentUserProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    return await _loadCurrentUserProfile(uid);
  }

  /// Save or update user profile in Firestore
  Future<void> saveUserProfile({
    required String name,
    required String phoneNumber,
    String? avatarUrl,
    String? about,
    String? upiId,
  }) async {
    final user = await ensureUserLoggedIn();
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '').trim();

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    String effectiveUpi = (upiId ?? '').trim();
    if (effectiveUpi.isEmpty) {
      if (name.toLowerCase().contains('dhivya')) {
        effectiveUpi = 'dhivya032005-1@okhdfcbank';
      }
    }

    final userData = {
      'id': user.uid,
      'name': name.trim(),
      'phoneNumber': cleanPhone,
      'fcmToken': token ?? '',
      'isOnline': true,
      'updatedAt': FieldValue.serverTimestamp(),
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (about != null) 'about': about.trim(),
      if (effectiveUpi.isNotEmpty) 'upiId': effectiveUpi,
    };

    await _firestore.collection('users').doc(user.uid).set(
      userData,
      SetOptions(merge: true),
    );

    // Also update legacy 'user' collection if any existing logic references it
    await _firestore.collection('user').doc(user.uid).set(
      userData,
      SetOptions(merge: true),
    );

    _cachedCurrentUser = UserModel(
      id: user.uid,
      name: name.trim(),
      phoneNumber: cleanPhone,
      fcmToken: token ?? '',
      isOnline: true,
      avatarUrl: avatarUrl ?? _cachedCurrentUser?.avatarUrl,
      about: about?.trim() ?? _cachedCurrentUser?.about ?? 'Hey there! I am using ChatApp.',
      upiId: effectiveUpi.isNotEmpty ? effectiveUpi : _cachedCurrentUser?.upiId,
    );
  }

  /// Update FCM Token for push notifications
  Future<void> updateFcmToken(String token) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      await _firestore.collection('users').doc(uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true));

      await _firestore.collection('user').doc(uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Update online status
  Future<void> setOnlineStatus(bool isOnline) async {
    final uid = currentUserId;
    if (uid == null) return;

    try {
      final data = {
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      };
      await _firestore.collection('users').doc(uid).set(data, SetOptions(merge: true));
      await _firestore.collection('user').doc(uid).set(data, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Stream a specific user's profile for real-time presence and updates
  Stream<UserModel?> streamUser(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return UserModel.fromDocument(doc);
      }
      return null;
    });
  }

  /// Formats last seen timestamp into human readable WhatsApp style
  static String formatLastSeen(DateTime? lastSeen, {bool isOnline = false}) {
    if (isOnline) return 'Online';
    if (lastSeen == null) return 'Offline';

    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    // Format time: e.g. 10:30 AM
    final hour = lastSeen.hour > 12 ? lastSeen.hour - 12 : (lastSeen.hour == 0 ? 12 : lastSeen.hour);
    final period = lastSeen.hour >= 12 ? 'PM' : 'AM';
    final minute = lastSeen.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute $period';

    if (difference.inDays == 0 && now.day == lastSeen.day) {
      return 'Last seen today at $timeStr';
    } else if (difference.inDays <= 1 || (difference.inDays == 0 && now.day != lastSeen.day)) {
      return 'Last seen yesterday at $timeStr';
    } else {
      return 'Last seen ${lastSeen.day}/${lastSeen.month} at $timeStr';
    }
  }

  /// Stream of all registered users (excluding current user)
  Stream<List<UserModel>> getAllUsersStream() {
    final myUid = currentUserId ?? '';

    return _firestore.collection('users').snapshots().map((snapshot) {
      final List<UserModel> users = [];
      for (final doc in snapshot.docs) {
        if (doc.id == myUid) continue;
        final data = doc.data();
        // Only include valid profiles with name or phone number
        final name = data['name']?.toString() ?? '';
        final phone = data['phoneNumber']?.toString() ?? '';
        if (name.isNotEmpty || phone.isNotEmpty) {
          users.add(UserModel.fromMap(data, doc.id));
        }
      }
      return users;
    });
  }

  /// Find user by phone number
  Future<UserModel?> findUserByPhoneNumber(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '').trim();

    final query = await _firestore
        .collection('users')
        .where('phoneNumber', isEqualTo: cleanPhone)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return UserModel.fromDocument(query.docs.first);
    }

    // Check legacy collection as fallback
    final legacyQuery = await _firestore
        .collection('user')
        .where('phoneNumber', isEqualTo: cleanPhone)
        .limit(1)
        .get();

    if (legacyQuery.docs.isNotEmpty) {
      return UserModel.fromDocument(legacyQuery.docs.first);
    }

    return null;
  }

  /// Get user profile by ID
  Future<UserModel?> getUserById(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists && doc.data() != null) {
        return UserModel.fromDocument(doc);
      }
      final legacyDoc = await _firestore.collection('user').doc(userId).get();
      if (legacyDoc.exists && legacyDoc.data() != null) {
        return UserModel.fromDocument(legacyDoc);
      }
    } catch (_) {}
    return null;
  }

  /// Sign out the current user (marks offline, clears cache, signs out Firebase)
  Future<void> signOut() async {
    try {
      final uid = currentUserId;
      if (uid != null) {
        // Mark offline before signing out
        await _firestore.collection('users').doc(uid).set(
          {'isOnline': false, 'lastSeen': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      }
    } catch (_) {}

    _cachedCurrentUser = null;
    await _auth.signOut();
  }

  /// Delete a user document from Firestore (removes person from the database)
  Future<void> deleteUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).delete();
      await _firestore.collection('user').doc(userId).delete().catchError((_) {});
    } catch (e) {
      debugPrint('Error deleting user $userId: $e');
    }
  }
}

