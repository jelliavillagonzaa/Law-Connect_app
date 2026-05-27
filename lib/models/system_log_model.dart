import 'package:cloud_firestore/cloud_firestore.dart';

class SystemLogModel {
  final String id;
  final String userId;
  final String? userName;
  final String action; // 'login', 'logout', 'case_update', 'user_update', etc.
  final String? details;
  final String? resourceType; // 'case', 'user', 'document', etc.
  final String? resourceId;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  SystemLogModel({
    required this.id,
    required this.userId,
    this.userName,
    required this.action,
    this.details,
    this.resourceType,
    this.resourceId,
    required this.timestamp,
    this.metadata,
  });

  factory SystemLogModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SystemLogModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'],
      action: data['action'] ?? '',
      details: data['details'],
      resourceType: data['resourceType'],
      resourceId: data['resourceId'],
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      metadata: data['metadata'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userName': userName,
      'action': action,
      'details': details,
      'resourceType': resourceType,
      'resourceId': resourceId,
      'timestamp': Timestamp.fromDate(timestamp),
      'metadata': metadata,
    };
  }
}

