import 'package:cloud_firestore/cloud_firestore.dart';

class CaseModel {
  final String id;
  final String clientId;
  final String? attorneyId;
  final String caseTitle;
  final String caseType;
  final String caseDescription;
  final String status; // "pending" | "accepted" | "in_progress" | "completed"
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String>? documents; // URLs to Firebase Storage
  final Map<String, dynamic>? progress; // Case progress updates
  final String? staffId; // Assigned staff member
  final List<String>? staffAssigned; // Multiple staff members (paralegal, secretary, etc.)
  final DateTime? hearingDate; // First hearing date
  final bool isArchived;
  final DateTime? archivedAt;

  CaseModel({
    required this.id,
    required this.clientId,
    this.attorneyId,
    required this.caseTitle,
    required this.caseType,
    required this.caseDescription,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.documents,
    this.progress,
    this.staffId,
    this.staffAssigned,
    this.hearingDate,
    this.isArchived = false,
    this.archivedAt,
  });

  factory CaseModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CaseModel(
      id: doc.id,
      clientId: data['clientId'] ?? '',
      attorneyId: data['attorneyId'],
      caseTitle: data['caseTitle'] ?? '',
      caseType: data['caseType'] ?? '',
      caseDescription: data['caseDescription'] ?? '',
      status: data['status'] ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      documents: data['documents'] != null
          ? List<String>.from(data['documents'])
          : null,
      progress: data['progress'],
      staffId: data['staffId'],
      staffAssigned: data['staffAssigned'] != null
          ? List<String>.from(data['staffAssigned'])
          : null,
      hearingDate: data['hearingDate'] != null
          ? (data['hearingDate'] as Timestamp).toDate()
          : null,
      isArchived: data['isArchived'] == true,
      archivedAt: (data['archivedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'clientId': clientId,
      if (attorneyId != null) 'attorneyId': attorneyId,
      'caseTitle': caseTitle,
      'caseType': caseType,
      'caseDescription': caseDescription,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      if (documents != null) 'documents': documents,
      if (progress != null) 'progress': progress,
      if (staffId != null) 'staffId': staffId,
      if (staffAssigned != null) 'staffAssigned': staffAssigned,
      if (hearingDate != null) 'hearingDate': Timestamp.fromDate(hearingDate!),
      'isArchived': isArchived,
      if (archivedAt != null) 'archivedAt': Timestamp.fromDate(archivedAt!),
    };
  }
}

