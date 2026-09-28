import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/case_request_model.dart';
import 'attorney_request_notify.dart';
import 'fcm_service.dart';
import 'firestore_mirror_helper.dart';

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

      final requestResult = await HybridDatastore.add(
        collection: 'case_requests',
        data: requestData,
      );
      if (!requestResult.isSuccess) {
        return {'success': false, 'message': requestResult.failureMessage};
      }
      final requestId = requestResult.id!;

      if (kDebugMode) {
        debugPrint('✅ Case request created: $requestId');
      }

      // Notify attorney(s): FCM + in-app + SMS
      List<String> attorneyIds;
      if (attorneyId != null && attorneyId.isNotEmpty) {
        attorneyIds = [attorneyId];
      } else {
        attorneyIds = await AttorneyRequestNotify.allAttorneyIds();
      }

      final smsSubject = subject.trim().isEmpty ? 'a request' : subject.trim();
      await AttorneyRequestNotify.notifyAttorneys(
        attorneyIds: attorneyIds,
        title: 'New Case Request',
        message: '$clientName: $subject',
        smsBody: 'Law Connect: New request from $clientName: $smsSubject.',
        type: 'case_request',
        data: {
          'requestId': requestId,
          'clientId': clientId,
          'clientName': clientName,
        },
      );

      if (kDebugMode) {
        debugPrint('✅ Notifications sent to ${attorneyIds.length} attorney(s)');
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
      final patch = <String, dynamic>{
        'status': 'reviewed',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final result = await HybridDatastore.update(
        collection: 'case_requests',
        id: requestId,
        patch: patch,
      );
      if (!result.isSuccess) throw Exception(result.failureMessage);
    } catch (e) {
      throw Exception('Failed to mark request as reviewed: $e');
    }
  }

  /// Mark request as converted to case
  Future<void> markRequestAsConverted(String requestId, String caseId) async {
    try {
      final patch = <String, dynamic>{
        'status': 'converted',
        'convertedToCaseId': caseId,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final result = await HybridDatastore.update(
        collection: 'case_requests',
        id: requestId,
        patch: patch,
      );
      if (!result.isSuccess) throw Exception(result.failureMessage);
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
      final acceptPatch = <String, dynamic>{
        'status': 'accepted',
        'attorneyId': attorneyId,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final result = await HybridDatastore.update(
        collection: 'case_requests',
        id: requestId,
        patch: acceptPatch,
      );
      if (!result.isSuccess) throw Exception(result.failureMessage);

      if (kDebugMode) {
        debugPrint('✅ Request accepted: $requestId');
      }

      // Send notification to client
      await _sendAcceptanceNotificationToClient(clientId, clientName, subject);

      // Create in-app notification for client
      final notifData = <String, dynamic>{
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
      };
      await HybridDatastore.add(collection: 'notifications', data: notifData);

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
      final patch = <String, dynamic>{
        'status': 'dismissed',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final result = await HybridDatastore.update(
        collection: 'case_requests',
        id: requestId,
        patch: patch,
      );
      if (!result.isSuccess) throw Exception(result.failureMessage);
    } catch (e) {
      throw Exception('Failed to dismiss request: $e');
    }
  }
}

