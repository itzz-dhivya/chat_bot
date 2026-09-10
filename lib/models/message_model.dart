import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String? id;
  final String senderId;
  final String receiverId;
  final String message;
  final DateTime timestamp;

  final String type; // 'text', 'call', 'image', 'video', 'location', 'document', 'audio', 'poll', 'contact'
  final String? callType;
  final String? callStatus;
  final int? callDuration;

  final String? mediaUrl;
  final double? latitude;
  final double? longitude;

  // Rich WhatsApp Chat Extensions
  final String? fileName;
  final String? fileSize;
  final String? senderName;
  final Map<String, String>? reactions; // {userId: emoji}
  final String? replyToId;
  final String? replyToText;
  final String? replyToSender;
  final bool isForwarded;
  final Map<String, dynamic>? pollData;
  final Map<String, dynamic>? contactData;
  final Map<String, dynamic>? eventData;
  final Map<String, dynamic>? linkPreview;
  final String status; // 'sent', 'delivered', 'read'
  final bool isSeen;
  final List<String>? readBy;
  final List<String>? deletedFor; // User IDs who clicked "Delete for me"

  MessageModel({
    this.id,
    required this.senderId,
    required this.receiverId,
    required this.message,
    required this.timestamp,
    this.type = 'text',
    this.callType,
    this.callStatus,
    this.callDuration,
    this.mediaUrl,
    this.latitude,
    this.longitude,
    this.fileName,
    this.fileSize,
    this.senderName,
    this.reactions,
    this.replyToId,
    this.replyToText,
    this.replyToSender,
    this.isForwarded = false,
    this.pollData,
    this.contactData,
    this.eventData,
    this.linkPreview,
    this.status = 'sent',
    this.isSeen = false,
    this.readBy,
    this.deletedFor,
  });

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'message': message,
      'timestamp': Timestamp.fromDate(timestamp),
      'type': type,
      if (callType != null) 'callType': callType,
      if (callStatus != null) 'callStatus': callStatus,
      if (callDuration != null) 'callDuration': callDuration,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (fileName != null) 'fileName': fileName,
      if (fileSize != null) 'fileSize': fileSize,
      if (senderName != null) 'senderName': senderName,
      if (reactions != null) 'reactions': reactions,
      if (replyToId != null) 'replyToId': replyToId,
      if (replyToText != null) 'replyToText': replyToText,
      if (replyToSender != null) 'replyToSender': replyToSender,
      'isForwarded': isForwarded,
      if (pollData != null) 'pollData': pollData,
      if (contactData != null) 'contactData': contactData,
      if (eventData != null) 'eventData': eventData,
      if (linkPreview != null) 'linkPreview': linkPreview,
      'status': status,
      'isSeen': isSeen,
      if (readBy != null) 'readBy': readBy,
      if (deletedFor != null) 'deletedFor': deletedFor,
    };
  }

  factory MessageModel.fromMap(
    Map<String, dynamic> map, [
    String? docId,
  ]) {
    final dynamic timestamp = map['timestamp'];

    Map<String, String>? parsedReactions;
    if (map['reactions'] is Map) {
      parsedReactions = (map['reactions'] as Map).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }

    final bool isSeenVal = map['isSeen'] == true || map['status'] == 'read';
    final String statusVal = map['status']?.toString() ?? (isSeenVal ? 'read' : 'sent');

    List<String>? parsedReadBy;
    if (map['readBy'] is List) {
      parsedReadBy = List<String>.from(map['readBy'] as List);
    }

    List<String>? parsedDeletedFor;
    if (map['deletedFor'] is List) {
      parsedDeletedFor = List<String>.from(map['deletedFor'] as List);
    }

    return MessageModel(
      id: docId ?? map['id'],
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      message: map['message'] ?? '',
      timestamp: timestamp is Timestamp
          ? timestamp.toDate()
          : DateTime.now(),
      type: map['type'] ?? 'text',
      callType: map['callType'],
      callStatus: map['callStatus'],
      callDuration: map['callDuration'],
      mediaUrl: map['mediaUrl'],
      latitude: map['latitude']?.toDouble(),
      longitude: map['longitude']?.toDouble(),
      fileName: map['fileName'],
      fileSize: map['fileSize'],
      senderName: map['senderName'],
      reactions: parsedReactions,
      replyToId: map['replyToId'],
      replyToText: map['replyToText'],
      replyToSender: map['replyToSender'],
      isForwarded: map['isForwarded'] ?? false,
      pollData: map['pollData'] is Map<String, dynamic>
          ? map['pollData'] as Map<String, dynamic>
          : (map['pollData'] is Map ? Map<String, dynamic>.from(map['pollData']) : null),
      contactData: map['contactData'] is Map<String, dynamic>
          ? map['contactData'] as Map<String, dynamic>
          : (map['contactData'] is Map ? Map<String, dynamic>.from(map['contactData']) : null),
      eventData: map['eventData'] is Map<String, dynamic>
          ? map['eventData'] as Map<String, dynamic>
          : (map['eventData'] is Map ? Map<String, dynamic>.from(map['eventData']) : null),
      linkPreview: map['linkPreview'] is Map<String, dynamic>
          ? map['linkPreview'] as Map<String, dynamic>
          : (map['linkPreview'] is Map ? Map<String, dynamic>.from(map['linkPreview']) : null),
      status: statusVal,
      isSeen: isSeenVal,
      readBy: parsedReadBy,
      deletedFor: parsedDeletedFor,
    );
  }
}