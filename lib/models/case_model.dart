import 'package:cloud_firestore/cloud_firestore.dart';

class CaseModel {
  final String id;
  final String clientId;
  final String? attorneyId;
  final String caseTitle;
  final String caseType;
  final String caseDescription;
  final String caseDescriptionDelta;
  final String status; // pending (Open) | under_review (Draft) | in_progress | completed
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String>? documents; // URLs to Firebase Storage
  final Map<String, dynamic>? progress; // Case progress updates
  final String? staffId; // Assigned staff member
  final List<String>? staffAssigned; // Multiple staff members (paralegal, secretary, etc.)
  final String? opposingParty;
  final String? caseResult; // won | lost | settled | dismissed
  final DateTime? hearingDate; // First hearing date
  final bool isArchived;
  final DateTime? archivedAt;
  final String? clientName;
  final String? clientEmail;
  final String? clientPhone;
  final String? clientAddress;
  final String? court;
  final String? courtBranch;
  final String? courtRegion;
  final String? courtEmail;
  final String? courtContact;
  final String? caseNumber;
  final String? natureOfAction;

  CaseModel({
    required this.id,
    required this.clientId,
    this.attorneyId,
    required this.caseTitle,
    required this.caseType,
    required this.caseDescription,
    this.caseDescriptionDelta = '',
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.documents,
    this.progress,
    this.staffId,
    this.staffAssigned,
    this.opposingParty,
    this.caseResult,
    this.hearingDate,
    this.isArchived = false,
    this.archivedAt,
    this.clientName,
    this.clientEmail,
    this.clientPhone,
    this.clientAddress,
    this.court,
    this.courtBranch,
    this.courtRegion,
    this.courtEmail,
    this.courtContact,
    this.caseNumber,
    this.natureOfAction,
  });

  /// Staff remarks or review notes stored in case progress.
  String? get remarks {
    final r = progress?['remarks'];
    if (r is String && r.trim().isNotEmpty) return r.trim();
    return null;
  }

  factory CaseModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CaseModel(
      id: doc.id,
      clientId: data['clientId'] ?? '',
      attorneyId: data['attorneyId'],
      caseTitle: data['caseTitle'] ?? '',
      caseType: data['caseType'] ?? '',
      caseDescription: data['caseDescription'] ?? '',
      caseDescriptionDelta: (data['caseDescriptionDelta'] as String?) ?? '',
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
      opposingParty: (data['opposingParty'] as String?)?.trim().isNotEmpty == true
          ? (data['opposingParty'] as String).trim()
          : null,
      caseResult: (data['caseResult'] as String?)?.trim().isNotEmpty == true
          ? (data['caseResult'] as String).trim().toLowerCase()
          : null,
      hearingDate: _parseDate(data['hearingDate']),
      isArchived: data['isArchived'] == true,
      archivedAt: (data['archivedAt'] as Timestamp?)?.toDate(),
      clientName: (data['clientName'] as String?)?.trim(),
      clientEmail: (data['clientEmail'] as String?)?.trim(),
      clientPhone: (data['clientPhone'] ?? data['clientNumber'])?.toString().trim(),
      clientAddress: (data['clientAddress'] ?? data['clientLocation'])?.toString().trim(),
      court: (data['court'] as String?)?.trim(),
      courtBranch: (data['courtBranch'] as String?)?.trim(),
      courtRegion: (data['courtRegion'] as String?)?.trim(),
      courtEmail: (data['courtEmail'] as String?)?.trim(),
      courtContact: (data['courtContact'] as String?)?.trim(),
      caseNumber: (data['caseNumber'] ?? data['civilCaseNo'])?.toString().trim(),
      natureOfAction: (data['natureOfAction'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'clientId': clientId,
      if (attorneyId != null) 'attorneyId': attorneyId,
      'caseTitle': caseTitle,
      'caseType': caseType,
      'caseDescription': caseDescription,
      if (caseDescriptionDelta.trim().isNotEmpty)
        'caseDescriptionDelta': caseDescriptionDelta,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      if (documents != null) 'documents': documents,
      if (progress != null) 'progress': progress,
      if (staffId != null) 'staffId': staffId,
      if (staffAssigned != null) 'staffAssigned': staffAssigned,
      if (opposingParty != null && opposingParty!.trim().isNotEmpty)
        'opposingParty': opposingParty!.trim(),
      if (caseResult != null && caseResult!.trim().isNotEmpty)
        'caseResult': caseResult!.trim().toLowerCase(),
      if (hearingDate != null) 'hearingDate': Timestamp.fromDate(hearingDate!),
      'isArchived': isArchived,
      if (archivedAt != null) 'archivedAt': Timestamp.fromDate(archivedAt!),
      if (clientName != null && clientName!.trim().isNotEmpty)
        'clientName': clientName!.trim(),
      if (clientEmail != null && clientEmail!.trim().isNotEmpty)
        'clientEmail': clientEmail!.trim(),
      if (clientPhone != null && clientPhone!.trim().isNotEmpty)
        'clientPhone': clientPhone!.trim(),
      if (clientAddress != null && clientAddress!.trim().isNotEmpty)
        'clientAddress': clientAddress!.trim(),
      if (court != null && court!.trim().isNotEmpty) 'court': court!.trim(),
      if (courtBranch != null && courtBranch!.trim().isNotEmpty)
        'courtBranch': courtBranch!.trim(),
      if (courtRegion != null && courtRegion!.trim().isNotEmpty)
        'courtRegion': courtRegion!.trim(),
      if (courtEmail != null && courtEmail!.trim().isNotEmpty)
        'courtEmail': courtEmail!.trim(),
      if (courtContact != null && courtContact!.trim().isNotEmpty)
        'courtContact': courtContact!.trim(),
      if (caseNumber != null && caseNumber!.trim().isNotEmpty)
        'caseNumber': caseNumber!.trim(),
      if (natureOfAction != null && natureOfAction!.trim().isNotEmpty)
        'natureOfAction': natureOfAction!.trim(),
    };
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

