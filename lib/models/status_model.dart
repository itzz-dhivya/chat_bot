import 'package:cloud_firestore/cloud_firestore.dart';

class StatusModel {
  final String id;
  final String userId;
  final String userName;
  final String userPhone;
  final String? mediaUrl;
  final String? textContent;
  final String type; // 'image' or 'text'
  final int? bgColor;
  final DateTime timestamp;

  StatusModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPhone,
    this.mediaUrl,
    this.textContent,
    required this.type,
    this.bgColor,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'mediaUrl': mediaUrl,
      'textContent': textContent,
      'type': type,
      'bgColor': bgColor,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  factory StatusModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final ts = data['timestamp'];
    DateTime dt = DateTime.now();
    if (ts is Timestamp) {
      dt = ts.toDate();
    }

    return StatusModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'User',
      userPhone: data['userPhone'] ?? '',
      mediaUrl: data['mediaUrl'],
      textContent: data['textContent'],
      type: data['type'] ?? 'text',
      bgColor: data['bgColor'] is int ? data['bgColor'] : null,
      timestamp: dt,
    );
  }
}
