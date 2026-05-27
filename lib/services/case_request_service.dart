import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/case_request_model.dart';
import 'fcm_service.dart';

class CaseRequestService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FCMService _fcmService = FCMService();

  /// Client sends a request/inquiry to attorney
  /// This creates a request that appears in attorney's inbox
  Future<Map<String, dynamic>> createCaseRequest({
    required String clientId,
    String? attorneyId, // Optional - if client already has an attorney
    required String subject,
    required String message,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('═══════════════════════════════════════');
        debugPrint('📝 CREATING CASE REQUEST');
        debugPrint('═══════════════════════════════════════');
      }

      // Get client info
      final clientDoc = await _firestore.collection('users').doc(clientId).get();
      if (!clientDoc.exists) {
        return {
          'success': false,
          'message': 'Client not found',
        };
      }

      final clientData = clientDoc.data()!;
      final clientName = clientData['fullName'] ?? clientData['name'] ?? 'Client';
      final clientEmail = clientData['email'] ?? '';
      final clientPhone = clientData['phone'];

      // Create request document
      final requestData = {
        'clientId': clientId,
        if (attorneyId != null) 'attorneyId': attorneyId,
        'clientName': clientName,
        'clientEmail': clientEmail,
        if (clientPhone != null) 'clientPhone': clientPhone,
        'subject': subject,
        'message': message,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final requestRef = await _firestore.collection('case_requests').add(requestData);
      final requestId = requestRef.id;

      if (kDebugMode) {
        debugPrint('✅ Case request created: $requestId');
      }

      // Send notification to attorney(s)
      if (attorneyId != null) {
        // Send to specific attorney
        await _sendRequestNotificationToAttorney(attorneyId, clientName, subject);
      } else {
        // Send to all attorneys (or you can implement a broadcast)
        // For now, we'll just save the notification in Firestore
        // Attorneys will see it in their dashboard
        await _createInAppNotificationForAllAttorneys(clientName, subject, requestId);
      }

      // Also create in-app notification
      await _firestore.collection('notifications').add({
        'userId': attorneyId ?? 'all_attorneys', // Use 'all_attorneys' if no specific attorney
        'type': 'case_request',
        'title': 'New Case Request',
        'message': '$clientName: $subject',
        'data': {
          'requestId': requestId,
          'clientId': clientId,
          'clientName': clientName,
        },
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        debugPrint('✅ Notifications sent');
        debugPrint('═══════════════════════════════════════');
      }

      return {
        'success': true,
        'requestId': requestId,
        'message': 'Request sent successfully',
      };
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ ERROR CREATING CASE REQUEST');
        debugPrint('🔴 Error: $e');
        debugPrint('🔴 Stack Trace: $stackTrace');
      }
      return {
        'success': false,
        'message': 'Failed to create request: $e',
      };
    }
  }

  /// Send FCM notification to specific attorney
  Future<void> _sendRequestNotificationToAttorney(
    String attorneyId,
    String clientName,
    String subject,
  ) async {
    try {
      await _fcmService.sendNotificationToUser(
        userId: attorneyId,
        title: 'New Case Request',
        body: '$clientName: $subject',
        data: {
          'type': 'case_request',
          'clientName': clientName,
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to send FCM to attorney: $e');
      }
    }
  }

  /// Create in-app notification for all attorneys
  Future<void> _createInAppNotificationForAllAttorneys(
    String clientName,
    String subject,
    String requestId,
  ) async {
    try {
      // Get all attorneys
      final attorneysSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'attorney')
          .get();

      // Create notification for each attorney
      final batch = _firestore.batch();
      for (var doc in attorneysSnapshot.docs) {
        final notificationRef = _firestore.collection('notifications').doc();
        batch.set(notificationRef, {
          'userId': doc.id,
          'type': 'case_request',
          'title': 'New Case Request',
          'message': '$clientName: $subject',
          'data': {
            'requestId': requestId,
            'clientName': clientName,
          },
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to create notifications for attorneys: $e');
      }
    }
  }

  /// Get all pending case requests for an attorney
  Stream<List<CaseRequestModel>> getAttorneyCaseRequests(String attorneyId) {
    try {
      // Try to get all pending requests first (may need Firestore index)
      // If that fails, get all requests and filter by status in memory
      return _firestore
          .collection('case_requests')
          .snapshots()
          .map((snapshot) {
        final requests = snapshot.docs
            .map((doc) {
              try {
                return CaseRequestModel.fromFirestore(doc);
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('Error parsing request ${doc.id}: $e');
                }
                return null;
              }
            })
            .whereType<CaseRequestModel>()
            .toList();

        // Filter in memory:
        // 1. Status must be 'pending' or 'accepted' (show accepted ones too)
        // 2. attorneyId must be null (general) OR match this attorney OR status is 'accepted' by this attorney
        final filtered = requests.where((req) {
          final isPending = req.status == 'pending' && (req.attorneyId == null || req.attorneyId == attorneyId);
          final isAccepted = req.status == 'accepted' && req.attorneyId == attorneyId;
          return isPending || isAccepted;
        }).toList();

        // Sort by createdAt descending
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return filtered;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting case requests: $e');
      }
      // Return empty stream on error
      return Stream.value(<CaseRequestModel>[]);
    }
  }

  /// Get all case requests for a client
  Stream<List<CaseRequestModel>> getClientCaseRequests(String clientId) {
    try {
      return _firestore
          .collection('case_requests')
          .where('clientId', isEqualTo: clientId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs
            .map((doc) => CaseRequestModel.fromFirestore(doc))
            .toList();
      });
    } catch (e) {
      throw Exception('Failed to get client case requests: $e');
    }
  }

  /// Mark request as reviewed
  Future<void> markRequestAsReviewed(String requestId) async {
    try {
      await _firestore.collection('case_requests').doc(requestId).update({
        'status': 'reviewed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to mark request as reviewed: $e');
    }
  }

  /// Mark request as converted to case
  Future<void> markRequestAsConverted(String requestId, String caseId) async {
    try {
      await _firestore.collection('case_requests').doc(requestId).update({
        'status': 'converted',
        'convertedToCaseId': caseId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to mark request as converted: $e');
    }
  }

  /// Accept a request (attorney accepts the inquiry)
  Future<void> acceptRequest(String requestId, String attorneyId) async {
    try {
      if (kDebugMode) {
        debugPrint('═══════════════════════════════════════');
        debugPrint('✅ ACCEPTING CASE REQUEST');
        debugPrint('═══════════════════════════════════════');
      }

      // Get request data to notify client
      final requestDoc = await _firestore.collection('case_requests').doc(requestId).get();
      if (!requestDoc.exists) {
        throw Exception('Request not found');
      }

      final requestData = requestDoc.data()!;
      final clientId = requestData['clientId'] as String;
      final clientName = requestData['clientName'] as String;
      final subject = requestData['subject'] as String;

      // Update request status to accepted
      await _firestore.collection('case_requests').doc(requestId).update({
        'status': 'accepted',
        'attorneyId': attorneyId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        debugPrint('✅ Request accepted: $requestId');
      }

      // Send notification to client
      await _sendAcceptanceNotificationToClient(clientId, clientName, subject);

      // Create in-app notification for client
      await _firestore.collection('notifications').add({
        'userId': clientId,
        'type': 'inquiry_accepted',
        'title': 'Inquiry Accepted',
        'message': 'Your inquiry "$subject" has been accepted by your attorney.',
        'data': {
          'requestId': requestId,
          'attorneyId': attorneyId,
        },
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        debugPrint('✅ Client notified');
        debugPrint('═══════════════════════════════════════');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ ERROR ACCEPTING REQUEST: $e');
      }
      throw Exception('Failed to accept request: $e');
    }
  }

  /// Send acceptance notification to client
  Future<void> _sendAcceptanceNotificationToClient(
    String clientId,
    String clientName,
    String subject,
  ) async {
    try {
      await _fcmService.sendNotificationToUser(
        userId: clientId,
        title: 'Inquiry Accepted',
        body: 'Your inquiry "$subject" has been accepted by your attorney.',
        data: {
          'type': 'inquiry_accepted',
          'clientName': clientName,
          'subject': subject,
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to send FCM to client: $e');
      }
    }
  }

  /// Dismiss a request
  Future<void> dismissRequest(String requestId) async {
    try {
      await _firestore.collection('case_requests').doc(requestId).update({
        'status': 'dismissed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to dismiss request: $e');
    }
  }
}

