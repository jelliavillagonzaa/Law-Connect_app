import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/case_model.dart';
import 'fcm_service.dart';
import 'notification_service.dart';

class CaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FCMService _fcmService = FCMService();
  final NotificationService _notificationService = NotificationService();

  // Create a new case
  // Returns caseId if successful, null if failed
  Future<String?> createCase(CaseModel caseModel) async {
    try {
      if (kDebugMode) {
        debugPrint('═══════════════════════════════════════');
        debugPrint('📋 CREATING CASE');
        debugPrint('═══════════════════════════════════════');
        debugPrint('Client ID: ${caseModel.clientId}');
        debugPrint('Attorney ID: ${caseModel.attorneyId}');
        debugPrint('Status: ${caseModel.status}');
        debugPrint('Staff ID: ${caseModel.staffId}');
        debugPrint('Staff Assigned: ${caseModel.staffAssigned}');
      }

      // Use server timestamp for consistency
      final data = caseModel.toFirestore();
      data['createdAt'] = FieldValue.serverTimestamp();
      data['updatedAt'] = FieldValue.serverTimestamp();
      
      if (kDebugMode) {
        debugPrint('📤 Sending case data to Firestore...');
        debugPrint('Data keys: ${data.keys.toList()}');
      }
      
      final caseRef = await _firestore.collection('cases').add(data);
      final caseId = caseRef.id;

      if (kDebugMode) {
        debugPrint('✅ Case created: $caseId');
        debugPrint('📊 Case status: ${caseModel.status}');
      }

      // Only send notification to client if case is not a draft (not 'under_review' status)
      // Draft cases should not notify clients - they need attorney approval first
      if (caseModel.status != 'under_review') {
        try {
          await _sendCaseCreatedNotification(caseModel.clientId, caseModel.caseTitle, caseId);
          if (kDebugMode) {
            debugPrint('✅ Client notification sent');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Failed to send client notification (non-critical): $e');
          }
          // Don't fail the entire operation if notification fails
        }
      } else {
        if (kDebugMode) {
          debugPrint('⏸️ Skipping client notification (draft case)');
        }
      }

      if (kDebugMode) {
        debugPrint('✅ Case creation completed');
        debugPrint('═══════════════════════════════════════');
      }

      return caseId;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error creating case: $e');
        debugPrint('Error type: ${e.runtimeType}');
        final errorString = e.toString();
        if (errorString.contains('permission-denied') || errorString.contains('Missing or insufficient permissions')) {
          debugPrint('⚠️ Permission denied error detected');
          debugPrint('This usually means:');
          debugPrint('  1. Firestore security rules are blocking the operation');
          debugPrint('  2. User role or assigned attorney mismatch');
          debugPrint('  3. Required fields are missing or invalid');
        }
      }
      // Re-throw the error so the caller can handle it appropriately
      rethrow;
    }
  }

  // Send notification to client when case is created
  Future<void> _sendCaseCreatedNotification(
    String clientId,
    String caseTitle,
    String caseId,
  ) async {
    try {
      // Get attorney name for notification
      String? attorneyName;
      try {
        final caseDoc = await _firestore.collection('cases').doc(caseId).get();
        final attorneyId = caseDoc.data()?['attorneyId'] as String?;
        if (attorneyId != null) {
          final attorneyDoc = await _firestore.collection('users').doc(attorneyId).get();
          attorneyName = attorneyDoc.data()?['fullName'] ?? attorneyDoc.data()?['name'] ?? 'Your attorney';
        }
      } catch (e) {
        attorneyName = 'Your attorney';
      }

      // Send FCM notification
      await _fcmService.sendNotificationToUser(
        userId: clientId,
        title: 'New Case Created',
        body: 'A new case "$caseTitle" has been created by ${attorneyName ?? "your attorney"}.',
        data: {
          'type': 'case_created',
          'caseId': caseId,
          'caseTitle': caseTitle,
        },
      );

      // Create in-app notification
      await _firestore.collection('notifications').add({
        'userId': clientId,
        'type': 'case_created',
        'title': 'New Case Created',
        'message': 'A new case "$caseTitle" has been created by ${attorneyName ?? "your attorney"}.',
        'data': {
          'caseId': caseId,
          'caseTitle': caseTitle,
        },
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Show local notification
      await _notificationService.showNotificationWithSound(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: 'New Case Created',
        body: 'A new case "$caseTitle" has been created.',
        payload: caseId,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to send case created notification: $e');
      }
    }
  }

  // Get cases for a user (client or attorney)
  Stream<List<CaseModel>> getCasesForUser(String userId, String role) {
    try {
      Stream<QuerySnapshot> queryStream;
      if (role == 'client') {
        queryStream = _firestore
            .collection('cases')
            .where('clientId', isEqualTo: userId)
            .snapshots();
      } else if (role == 'attorney') {
        queryStream = _firestore
            .collection('cases')
            .where('attorneyId', isEqualTo: userId)
            .snapshots();
      } else {
        // Admin - get all cases
        queryStream = _firestore
            .collection('cases')
            .snapshots();
      }

      return queryStream.map((snapshot) {
        final cases = snapshot.docs
            .map((doc) => CaseModel.fromFirestore(doc))
            .toList();
        // Sort by updatedAt in memory to avoid index requirement
        cases.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return cases;
      });
    } catch (e) {
      throw Exception('Failed to get cases: $e');
    }
  }

  // Get cases by status
  Stream<List<CaseModel>> getCasesByStatus(String status) {
    try {
      return _firestore
          .collection('cases')
          .where('status', isEqualTo: status)
          .snapshots()
          .map((snapshot) {
        final cases = snapshot.docs
            .map((doc) => CaseModel.fromFirestore(doc))
            .toList();
        // Sort by updatedAt in memory to avoid index requirement
        cases.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return cases;
      });
    } catch (e) {
      throw Exception('Failed to get cases by status: $e');
    }
  }

  // Get pending cases (for attorneys to accept/decline)
  Stream<List<CaseModel>> getPendingCases() {
    try {
      return _firestore
          .collection('cases')
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((snapshot) {
        final cases = snapshot.docs
            .map((doc) => CaseModel.fromFirestore(doc))
            .toList();
        // Sort by createdAt in memory to avoid index requirement
        cases.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return cases;
      });
    } catch (e) {
      throw Exception('Failed to get pending cases: $e');
    }
  }

  // Accept a case (attorney)
  Future<void> acceptCase(String caseId, String attorneyId) async {
    try {
      await _firestore.collection('cases').doc(caseId).update({
        'attorneyId': attorneyId,
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to accept case: $e');
    }
  }

  // Decline a case (attorney)
  Future<void> declineCase(String caseId) async {
    try {
      await _firestore.collection('cases').doc(caseId).update({
        'status': 'declined',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to decline case: $e');
    }
  }

  // Update case details (for attorneys to edit case information)
  Future<void> updateCaseDetails({
    required String caseId,
    String? caseTitle,
    String? caseDescription,
    String? caseType,
  }) async {
    try {
      final caseDoc = await _firestore.collection('cases').doc(caseId).get();
      if (!caseDoc.exists) {
        throw Exception('Case not found');
      }

      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (caseTitle != null && caseTitle.isNotEmpty) {
        updateData['caseTitle'] = caseTitle;
      }
      if (caseDescription != null && caseDescription.isNotEmpty) {
        updateData['caseDescription'] = caseDescription;
      }
      if (caseType != null && caseType.isNotEmpty) {
        updateData['caseType'] = caseType;
      }

      await _firestore.collection('cases').doc(caseId).update(updateData);

      // Send notification to client about case update
      final caseData = caseDoc.data()!;
      final clientId = caseData['clientId'] as String?;
      final title = caseTitle ?? caseData['caseTitle'] as String? ?? 'Case';
      
      if (clientId != null) {
        await _sendCaseUpdateNotification(clientId, caseId, title, 'Case details have been updated');
      }
    } catch (e) {
      throw Exception('Failed to update case details: $e');
    }
  }

  // Update case status
  Future<void> updateCaseStatus(String caseId, String status) async {
    try {
      final caseDoc = await _firestore.collection('cases').doc(caseId).get();
      if (!caseDoc.exists) {
        throw Exception('Case not found');
      }

      final caseData = caseDoc.data()!;
      final clientId = caseData['clientId'] as String?;
      final caseTitle = caseData['caseTitle'] as String? ?? 'Case';

      await _firestore.collection('cases').doc(caseId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Send notification to client about status update
      if (clientId != null) {
        await _sendCaseUpdateNotification(clientId, caseId, caseTitle, 'Status updated to: $status');
      }
    } catch (e) {
      throw Exception('Failed to update case status: $e');
    }
  }

  // Update case progress
  Future<void> updateCaseProgress(
    String caseId,
    Map<String, dynamic> progressUpdate,
  ) async {
    try {
      final caseRef = _firestore.collection('cases').doc(caseId);
      final caseDoc = await caseRef.get();
      
      if (caseDoc.exists) {
        final currentProgress = caseDoc.data()?['progress'] as Map? ?? {};
        currentProgress.addAll(progressUpdate);
        
        await caseRef.update({
          'progress': currentProgress,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      throw Exception('Failed to update case progress: $e');
    }
  }

  // Add document URL to case
  Future<void> addDocumentToCase(String caseId, String documentUrl) async {
    try {
      final caseRef = _firestore.collection('cases').doc(caseId);
      final caseDoc = await caseRef.get();
      
      if (caseDoc.exists) {
        final caseData = caseDoc.data()!;
        final clientId = caseData['clientId'] as String?;
        final caseTitle = caseData['caseTitle'] as String? ?? 'Case';

        final documents = List<String>.from(
          caseData['documents'] ?? [],
        );
        documents.add(documentUrl);
        
        await caseRef.update({
          'documents': documents,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Send notification to client about new document
        if (clientId != null) {
          await _sendCaseUpdateNotification(clientId, caseId, caseTitle, 'New document uploaded');
        }
      }
    } catch (e) {
      throw Exception('Failed to add document: $e');
    }
  }

  // Send notification to client when case is updated
  Future<void> _sendCaseUpdateNotification(
    String clientId,
    String caseId,
    String caseTitle,
    String updateMessage,
  ) async {
    try {
      // Send FCM notification
      await _fcmService.sendNotificationToUser(
        userId: clientId,
        title: 'Case Update: $caseTitle',
        body: updateMessage,
        data: {
          'type': 'case_updated',
          'caseId': caseId,
          'caseTitle': caseTitle,
        },
      );

      // Create in-app notification
      await _firestore.collection('notifications').add({
        'userId': clientId,
        'type': 'case_updated',
        'title': 'Case Update: $caseTitle',
        'message': updateMessage,
        'data': {
          'caseId': caseId,
          'caseTitle': caseTitle,
        },
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to send case update notification: $e');
      }
    }
  }

  // Get single case
  Future<CaseModel?> getCase(String caseId) async {
    try {
      final doc = await _firestore.collection('cases').doc(caseId).get();
      if (doc.exists) {
        return CaseModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get case: $e');
    }
  }

  // Get client's assigned attorney ID from their cases
  // Returns the attorneyId from the most recent accepted case
  Future<String?> getClientAttorneyId(String clientId) async {
    try {
      final casesSnapshot = await _firestore
          .collection('cases')
          .where('clientId', isEqualTo: clientId)
          .where('status', isEqualTo: 'accepted')
          .get();

      if (casesSnapshot.docs.isEmpty) {
        return null;
      }

      // Get the most recent case with an attorney
      for (var doc in casesSnapshot.docs) {
        final data = doc.data();
        final attorneyId = data['attorneyId'] as String?;
        if (attorneyId != null && attorneyId.isNotEmpty) {
          return attorneyId;
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Get staff ID assigned to client's attorney
  // Returns the staffId of staff assigned to the client's attorney
  Future<String?> getStaffForClientAttorney(String clientId) async {
    try {
      // First, get the client's attorney
      final attorneyId = await getClientAttorneyId(clientId);
      if (attorneyId == null) {
        return null;
      }

      // Find staff assigned to this attorney
      final staffSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'staff')
          .where('assignedAttorneyId', isEqualTo: attorneyId)
          .limit(1)
          .get();

      if (staffSnapshot.docs.isEmpty) {
        return null;
      }

      return staffSnapshot.docs.first.id;
    } catch (e) {
      return null;
    }
  }
}

