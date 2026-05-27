import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Staff onboarding: apply → admin approves → applicant completes Firebase registration.
/// Document IDs are derived from email so one application per email (see [applicationDocIdForEmail]).
class StaffApplicationService {
  StaffApplicationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collectionName = 'staff_applications';

  /// Stable Firestore document id from email (lowercase, non-alphanumeric → underscore).
  static String applicationDocIdForEmail(String email) {
    return email
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Future<Map<String, dynamic>> submitApplication({
    required String email,
    required String name,
    required String phone,
    String? address,
    String? message,
    required bool agreedToRequirements,
  }) async {
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      return {'success': false, 'message': 'Please enter a valid email.'};
    }
    if (!agreedToRequirements) {
      return {
        'success': false,
        'message': 'You must confirm you meet the requirements.',
      };
    }

    final docId = applicationDocIdForEmail(trimmedEmail);
    if (docId.isEmpty) {
      return {'success': false, 'message': 'Invalid email for application.'};
    }

    final ref = _firestore.collection(collectionName).doc(docId);

    try {
      // Prefer server read so cached permission/state does not block first-time apply (web).
      final existing = await ref.get(
        const GetOptions(source: Source.server),
      );
      if (existing.exists) {
        final data = existing.data();
        final status = data?['status'] as String? ?? 'pending';
        if (status == 'pending') {
          return {
            'success': false,
            'message':
                'An application is already pending for this email. Please wait for admin review.',
          };
        }
        if (status == 'approved') {
          return {
            'success': false,
            'message':
                'This email was approved. Complete staff registration instead of applying again.',
          };
        }
        if (status == 'registered') {
          return {
            'success': false,
            'message': 'This email already has a registered staff account.',
          };
        }
        // rejected — allow re-apply by overwriting if admin deleted policy; we allow update only via admin.
        // For rejected, admin should delete doc or we need client rule to allow delete — not available.
        // So: rejected applications block until admin deletes. Show message.
        if (status == 'rejected') {
          return {
            'success': false,
            'message':
                'A previous application for this email was rejected. Contact the administrator to re-open your application.',
          };
        }
      }

      await ref.set({
        'email': trimmedEmail,
        'name': name.trim(),
        'phone': phone.trim(),
        if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
        if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
        'status': 'pending',
        'agreedToRequirements': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return {
        'success': true,
        'message': 'Application submitted. An administrator will review it.',
        'applicationDocId': docId,
      };
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('submitStaffApplication FirebaseException: ${e.code} ${e.message}');
      }
      final msg = switch (e.code) {
        'permission-denied' =>
          'Access was denied by the database. Deploy Firestore rules that include '
          'the staff_applications collection (see firestore.rules in the project), '
          'then run: firebase deploy --only firestore:rules',
        'unavailable' =>
          'The database is temporarily unavailable. Check your connection and try again.',
        _ => e.message != null && e.message!.trim().isNotEmpty
            ? e.message!
            : 'Could not submit application (${e.code}).',
      };
      return {'success': false, 'message': msg};
    } catch (e) {
      if (kDebugMode) debugPrint('submitStaffApplication: $e');
      return {
        'success': false,
        'message': 'Could not submit application: $e',
      };
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getApplication(String docId) {
    return _firestore.collection(collectionName).doc(docId).get();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAllApplications() {
    return _firestore
        .collection(collectionName)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<Map<String, dynamic>> approveApplication({
    required String docId,
    required String assignedAttorneyId,
    required String adminUid,
  }) async {
    try {
      await _firestore.collection(collectionName).doc(docId).update({
        'status': 'approved',
        'assignedAttorneyId': assignedAttorneyId,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminUid,
        'rejectionReason': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return {'success': true, 'message': 'Application approved.'};
    } catch (e) {
      if (kDebugMode) debugPrint('approveApplication: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> rejectApplication({
    required String docId,
    required String adminUid,
    String? reason,
  }) async {
    try {
      await _firestore.collection(collectionName).doc(docId).update({
        'status': 'rejected',
        'rejectionReason': reason?.trim() ?? '',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminUid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return {'success': true, 'message': 'Application rejected.'};
    } catch (e) {
      if (kDebugMode) debugPrint('rejectApplication: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Lets an applicant apply again after a rejection (admin only).
  Future<Map<String, dynamic>> deleteApplication(String docId) async {
    try {
      await _firestore.collection(collectionName).doc(docId).delete();
      return {'success': true, 'message': 'Application removed.'};
    } catch (e) {
      if (kDebugMode) debugPrint('deleteApplication: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
}
