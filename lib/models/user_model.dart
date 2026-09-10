import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String name;
  final String phoneNumber;
  final String fcmToken;
  final bool isOnline;
  final DateTime? lastSeen;
  final DateTime? createdAt;
  final String? avatarUrl;
  final String about;
  final String? upiId;

  UserModel({
    required this.id,
    required this.name,
    required this.phoneNumber,
    this.fcmToken = '',
    this.isOnline = false,
    this.lastSeen,
    this.createdAt,
    this.avatarUrl,
    this.about = 'Hey there! I am using WhatsApp.',
    this.upiId,
  });

  /// Returns user's configured UPI ID or default fallback
  String get effectiveUpiId {
    if (upiId != null && upiId!.trim().isNotEmpty) {
      return upiId!.trim();
    }
    if (name.toLowerCase().contains('dhivya')) {
      return 'dhivya032005-1@okhdfcbank';
    }
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isNotEmpty) {
      return '$cleanPhone@upi';
    }
    return '${name.toLowerCase().replaceAll(RegExp(r'\s+'), '')}@upi';
  }

  // Dart object -> Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'fcmToken': fcmToken,
      'isOnline': isOnline,
      if (lastSeen != null) 'lastSeen': Timestamp.fromDate(lastSeen!),
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      'about': about,
      if (upiId != null) 'upiId': upiId,
    };
  }

  // Firestore -> Dart object
  factory UserModel.fromMap(
    Map<String, dynamic> map, [
    String? documentId,
  ]) {
    final dynamic timestamp = map['createdAt'];
    final dynamic lastSeenTimestamp = map['lastSeen'];
    return UserModel(
      id: documentId ?? map['id'] ?? '',
      name: map['name'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      fcmToken: map['fcmToken'] ?? '',
      isOnline: map['isOnline'] == true,
      lastSeen: lastSeenTimestamp is Timestamp ? lastSeenTimestamp.toDate() : null,
      createdAt: timestamp is Timestamp ? timestamp.toDate() : null,
      avatarUrl: map['avatarUrl'] as String?,
      about: (map['about'] as String?) ?? 'Hey there! I am using WhatsApp.',
      upiId: map['upiId'] as String?,
    );
  }

  factory UserModel.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    return UserModel.fromMap(doc.data() ?? {}, doc.id);
  }
}