import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/feedback_model.dart';

class FeedbackService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Submit feedback
  Future<void> submitFeedback(FeedbackModel feedback) async {
    try {
      await _firestore.collection('feedback').add(feedback.toFirestore());
      
      // Update attorney's average rating
      await _updateAttorneyRating(feedback.attorneyId);
    } catch (e) {
      throw Exception('Failed to submit feedback: $e');
    }
  }

  // Get feedback for an attorney
  Stream<List<FeedbackModel>> getFeedbackForAttorney(String attorneyId) {
    try {
      return _firestore
          .collection('feedback')
          .where('attorneyId', isEqualTo: attorneyId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs
            .map((doc) => FeedbackModel.fromFirestore(doc))
            .toList();
      });
    } catch (e) {
      throw Exception('Failed to get feedback: $e');
    }
  }

  // Get feedback for a case
  Future<FeedbackModel?> getFeedbackForCase(String caseId) async {
    try {
      final snapshot = await _firestore
          .collection('feedback')
          .where('caseId', isEqualTo: caseId)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return FeedbackModel.fromFirestore(snapshot.docs.first);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get feedback for case: $e');
    }
  }

  // Get all feedback (for admin)
  Stream<List<FeedbackModel>> getAllFeedback() {
    try {
      return _firestore
          .collection('feedback')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs
            .map((doc) => FeedbackModel.fromFirestore(doc))
            .toList();
      });
    } catch (e) {
      throw Exception('Failed to get all feedback: $e');
    }
  }

  // Update attorney's average rating
  Future<void> _updateAttorneyRating(String attorneyId) async {
    try {
      final feedbackSnapshot = await _firestore
          .collection('feedback')
          .where('attorneyId', isEqualTo: attorneyId)
          .get();

      if (feedbackSnapshot.docs.isEmpty) return;

      double totalRating = 0;
      int count = 0;

      for (var doc in feedbackSnapshot.docs) {
        final rating = doc.data()['rating'] as int? ?? 0;
        totalRating += rating;
        count++;
      }

      final averageRating = totalRating / count;

      await _firestore.collection('users').doc(attorneyId).update({
        'ratingAverage': averageRating,
      });
    } catch (e) {
      throw Exception('Failed to update attorney rating: $e');
    }
  }

  // Check if feedback exists for a case
  Future<bool> hasFeedbackForCase(String caseId) async {
    try {
      final snapshot = await _firestore
          .collection('feedback')
          .where('caseId', isEqualTo: caseId)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      throw Exception('Failed to check feedback: $e');
    }
  }
}

