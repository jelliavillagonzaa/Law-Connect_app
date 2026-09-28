import 'package:cloud_firestore/cloud_firestore.dart';

class NotaryRequestModel {
  final String id;
  final String clientId;
  final String? attorneyId;
  final String serviceType;
  final List<String> documents; // Legacy: URLs only
  final List<Map<String, String>>? documentsWithNames; // New: {name, url}
  final String? notes;
  final DateTime? preferredDateTime;
  final List<String> bringDocuments;
  final String status; // pending, accepted, declined, completed
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? releaseDate;
  final DateTime? releaseTime;
  final String? declineReason;
  final String? scheduleMoveReason;

  NotaryRequestModel({
    required this.id,
    required this.clientId,
    this.attorneyId,
    required this.serviceType,
    required this.documents,
    this.documentsWithNames,
    this.notes,
    this.preferredDateTime,
    this.bringDocuments = const [],
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.releaseDate,
    this.releaseTime,
    this.declineReason,
    this.scheduleMoveReason,
  });

  factory NotaryRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Handle both old format (List<String>) and new format (List<Map>)
    List<String> documents = [];
    List<Map<String, String>>? documentsWithNames;
    
    if (data['documents'] != null) {
      final docsData = data['documents'];
      if (docsData is List) {
        if (docsData.isNotEmpty && docsData[0] is Map) {
          // New format: List<Map<String, String>>
          documentsWithNames = docsData.map((doc) {
            final docMap = doc as Map<String, dynamic>;
            return {
              'name': docMap['name']?.toString() ?? '',
              'url': docMap['url']?.toString() ?? '',
            };
          }).toList();
          // Extract URLs for backward compatibility
          documents = documentsWithNames.map((doc) => doc['url']!).toList();
        } else {
          // Old format: List<String>
          documents = List<String>.from(docsData);
        }
      }
    }
    
    return NotaryRequestModel(
      id: doc.id,
      clientId: data['clientId'] ?? '',
      attorneyId: data['attorneyId'],
      serviceType: data['serviceType'] ?? '',
      documents: documents,
      documentsWithNames: documentsWithNames,
      notes: data['notes'],
      preferredDateTime: (data['preferredDateTime'] as Timestamp?)?.toDate(),
      bringDocuments: data['bringDocuments'] is List
          ? List<String>.from(
              (data['bringDocuments'] as List).map((e) => e.toString()),
            )
          : const [],
      status: data['status'] ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      releaseDate: (data['releaseDate'] as Timestamp?)?.toDate(),
      releaseTime: (data['releaseTime'] as Timestamp?)?.toDate(),
      declineReason: data['declineReason'],
      scheduleMoveReason: (data['scheduleMoveReason'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'clientId': clientId,
      'serviceType': serviceType,
      'documents': documents,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
    };

    if (attorneyId != null) map['attorneyId'] = attorneyId;
    if (notes != null && notes!.isNotEmpty) map['notes'] = notes;
    if (preferredDateTime != null) {
      map['preferredDateTime'] = Timestamp.fromDate(preferredDateTime!);
    }
    if (bringDocuments.isNotEmpty) map['bringDocuments'] = bringDocuments;
    if (updatedAt != null) map['updatedAt'] = Timestamp.fromDate(updatedAt!);
    if (releaseDate != null) map['releaseDate'] = Timestamp.fromDate(releaseDate!);
    if (releaseTime != null) map['releaseTime'] = Timestamp.fromDate(releaseTime!);
    if (declineReason != null && declineReason!.isNotEmpty) map['declineReason'] = declineReason;
    if (scheduleMoveReason != null && scheduleMoveReason!.isNotEmpty) {
      map['scheduleMoveReason'] = scheduleMoveReason;
    }

    return map;
  }

  NotaryRequestModel copyWith({
    String? id,
    String? clientId,
    String? attorneyId,
    String? serviceType,
    List<String>? documents,
    String? notes,
    DateTime? preferredDateTime,
    List<String>? bringDocuments,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? releaseDate,
    DateTime? releaseTime,
    String? declineReason,
    String? scheduleMoveReason,
  }) {
    return NotaryRequestModel(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      attorneyId: attorneyId ?? this.attorneyId,
      serviceType: serviceType ?? this.serviceType,
      documents: documents ?? this.documents,
      notes: notes ?? this.notes,
      preferredDateTime: preferredDateTime ?? this.preferredDateTime,
      bringDocuments: bringDocuments ?? this.bringDocuments,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      releaseDate: releaseDate ?? this.releaseDate,
      releaseTime: releaseTime ?? this.releaseTime,
      declineReason: declineReason ?? this.declineReason,
      scheduleMoveReason: scheduleMoveReason ?? this.scheduleMoveReason,
    );
  }
}

