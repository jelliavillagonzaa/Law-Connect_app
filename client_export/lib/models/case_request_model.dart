import 'package:cloud_firestore/cloud_firestore.dart';

class CaseRequestModel {
  final String id;
  final String clientId;
  final String? attorneyId; // Optional - if client already has an attorney
  final String clientName;
  final String clientEmail;
  final String? clientPhone;
  final String subject; // "Need legal help" or "I have a concern"
  final String message; // Detailed inquiry
  final String status; // "pending" | "accepted" | "reviewed" | "converted" | "dismissed"
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? convertedToCaseId; // If attorney creates case from this request

  CaseRequestModel({
    required this.id,
    required this.clientId,
    this.attorneyId,
    required this.clientName,
    required this.clientEmail,
    this.clientPhone,
    required this.subject,
    required this.message,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.convertedToCaseId,
  });

  factory CaseRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CaseRequestModel(
      id: doc.id,
      clientId: data['clientId'] ?? '',
      attorneyId: data['attorneyId'],
      clientName: data['clientName'] ?? '',
      clientEmail: data['clientEmail'] ?? '',
      clientPhone: data['clientPhone'],
      subject: data['subject'] ?? '',
      message: data['message'] ?? '',
      status: data['status'] ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      convertedToCaseId: data['convertedToCaseId'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'clientId': clientId,
      if (attorneyId != null) 'attorneyId': attorneyId,
      'clientName': clientName,
      'clientEmail': clientEmail,
      if (clientPhone != null) 'clientPhone': clientPhone,
      'subject': subject,
      'message': message,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      if (convertedToCaseId != null) 'convertedToCaseId': convertedToCaseId,
    };
  }
}

