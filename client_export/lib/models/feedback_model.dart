import 'package:cloud_firestore/cloud_firestore.dart';

class FeedbackModel {
  final String id;
  final String caseId;
  final String clientId;
  final String attorneyId;
  final int rating; // 1-5 stars
  final String? comment;
  final DateTime createdAt;

  FeedbackModel({
    required this.id,
    required this.caseId,
    required this.clientId,
    required this.attorneyId,
    required this.rating,
    this.comment,
    required this.createdAt,
  });

  factory FeedbackModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FeedbackModel(
      id: doc.id,
      caseId: data['caseId'] ?? '',
      clientId: data['clientId'] ?? '',
      attorneyId: data['attorneyId'] ?? '',
      rating: data['rating'] ?? 0,
      comment: data['comment'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'caseId': caseId,
      'clientId': clientId,
      'attorneyId': attorneyId,
      'rating': rating,
      if (comment != null) 'comment': comment,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

