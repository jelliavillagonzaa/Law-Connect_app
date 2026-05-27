import 'package:cloud_firestore/cloud_firestore.dart';

class NotaryRequestModel {
  final String id;
  final String clientId;
  final String? attorneyId;
  final String serviceType;
  final List<String> documents; // Legacy: URLs only
  final List<Map<String, String>>? documentsWithNames; // New: {name, url}
  final String? notes;
  final String status; // pending, accepted, declined, completed
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? releaseDate;
  final DateTime? releaseTime;
  final String? declineReason;

  NotaryRequestModel({
    required this.id,
    required this.clientId,
    this.attorneyId,
    required this.serviceType,
    required this.documents,
    this.documentsWithNames,
    this.notes,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.releaseDate,
    this.releaseTime,
    this.declineReason,
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
      status: data['status'] ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      releaseDate: (data['releaseDate'] as Timestamp?)?.toDate(),
      releaseTime: (data['releaseTime'] as Timestamp?)?.toDate(),
      declineReason: data['declineReason'],
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
    if (updatedAt != null) map['updatedAt'] = Timestamp.fromDate(updatedAt!);
    if (releaseDate != null) map['releaseDate'] = Timestamp.fromDate(releaseDate!);
    if (releaseTime != null) map['releaseTime'] = Timestamp.fromDate(releaseTime!);
    if (declineReason != null && declineReason!.isNotEmpty) map['declineReason'] = declineReason;

    return map;
  }

  NotaryRequestModel copyWith({
    String? id,
    String? clientId,
    String? attorneyId,
    String? serviceType,
    List<String>? documents,
    String? notes,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? releaseDate,
    DateTime? releaseTime,
    String? declineReason,
  }) {
    return NotaryRequestModel(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      attorneyId: attorneyId ?? this.attorneyId,
      serviceType: serviceType ?? this.serviceType,
      documents: documents ?? this.documents,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      releaseDate: releaseDate ?? this.releaseDate,
      releaseTime: releaseTime ?? this.releaseTime,
      declineReason: declineReason ?? this.declineReason,
    );
  }
}

