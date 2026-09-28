import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:intl/intl.dart';
import '../models/case_model.dart';
import '../utils/case_status_filter.dart';
import '../utils/case_history.dart';
import '../utils/case_result.dart';
import '../utils/case_sms_formatter.dart';
import 'fcm_service.dart';
import 'notification_service.dart';
import 'firestore_mirror_helper.dart';
import 'sms_service.dart';
import 'system_settings_service.dart';

class CaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FCMService _fcmService = FCMService();
  final NotificationService _notificationService = NotificationService();
  final SmsService _smsService = SmsService();

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

      final caseId = _firestore.collection('cases').doc().id;

      final result = await HybridDatastore.addCase(
        data: data,
        mirrorModel: CaseModel(
          id: caseId,
          clientId: caseModel.clientId,
          attorneyId: caseModel.attorneyId,
          caseTitle: caseModel.caseTitle,
          caseType: caseModel.caseType,
          caseDescription: caseModel.caseDescription,
          status: caseModel.status,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          documents: caseModel.documents,
          progress: caseModel.progress,
          staffId: caseModel.staffId,
          staffAssigned: caseModel.staffAssigned,
          opposingParty: caseModel.opposingParty,
          caseResult: caseModel.caseResult,
          hearingDate: caseModel.hearingDate,
          isArchived: caseModel.isArchived,
          archivedAt: caseModel.archivedAt,
        ),
      );
      if (!result.isSuccess) {
        throw Exception(result.failureMessage);
      }

      if (kDebugMode) {
        debugPrint('✅ Case created: $caseId');
        debugPrint('📊 Case status: ${caseModel.status}');
      }

      // Only send notification to client if case is not a draft (not 'under_review' status)
      // Draft cases should not notify clients - they need attorney approval first
      if (caseModel.status != 'under_review') {
        try {
          await _sendCaseCreatedNotification(
            caseModel.clientId,
            caseModel.caseTitle,
            caseId,
          );
          if (kDebugMode) {
            debugPrint('✅ Client notification sent');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '⚠️ Failed to send client notification (non-critical): $e',
            );
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
        if (errorString.contains('permission-denied') ||
            errorString.contains('Missing or insufficient permissions')) {
          debugPrint('⚠️ Permission denied error detected');
          debugPrint('This usually means:');
          debugPrint(
            '  1. Firestore security rules are blocking the operation',
          );
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
          final attorneyDoc = await _firestore
              .collection('users')
              .doc(attorneyId)
              .get();
          attorneyName =
              attorneyDoc.data()?['fullName'] ??
              attorneyDoc.data()?['name'] ??
              'Your attorney';
        }
      } catch (e) {
        attorneyName = 'Your attorney';
      }

      final title = 'New Case Created';
      final message =
          'A new case "$caseTitle" has been created by ${attorneyName ?? "your attorney"}.';

      // SMS is independent of push. A failure in FCM or the local
      // notification must not skip the text.
      await _sendCaseSmsToClient(
        clientId: clientId,
        body: CaseSmsFormatter.created(caseTitle),
        smsType: 'case_created',
      );

      await _fcmService.sendNotificationToUser(
        userId: clientId,
        title: title,
        body: message,
        data: {
          'type': 'case_created',
          'caseId': caseId,
          'caseTitle': caseTitle,
        },
      );

      final notifData = <String, dynamic>{
        'userId': clientId,
        'type': 'case_created',
        'title': title,
        'message': message,
        'data': {'caseId': caseId, 'caseTitle': caseTitle},
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await FirestoreMirror.add(collection: 'notifications', data: notifData);

      await _notificationService.showNotificationWithSound(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: title,
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
            .limit(80)
            .snapshots();
      } else {
        // Admin - get all cases
        queryStream = _firestore.collection('cases').snapshots();
      }

      return queryStream.map((snapshot) {
        final cases = snapshot.docs
            .map((doc) => CaseModel.fromFirestore(doc))
            .where((c) => !c.isArchived)
            .where((c) => role != 'client' || CaseStatusFilter.visibleToClient(c))
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
                .where((c) => !c.isArchived)
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
                .where((c) => !c.isArchived)
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
      final result = await HybridDatastore.updateCase(
        id: caseId,
        patch: {
          'attorneyId': attorneyId,
          'status': 'accepted',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      if (!result.isSuccess) throw Exception(result.failureMessage);

      final caseDoc = await _firestore.collection('cases').doc(caseId).get();
      final caseData = caseDoc.data();
      final clientId = caseData?['clientId'] as String?;
      final caseTitle = caseData?['caseTitle'] as String? ?? 'Case';
      if (clientId != null) {
        await _notifyClientOfStatusChange(
          clientId: clientId,
          caseId: caseId,
          caseTitle: caseTitle,
          previousStatus: 'pending',
          newStatus: 'accepted',
        );
      }
    } catch (e) {
      throw Exception('Failed to accept case: $e');
    }
  }

  // Decline a case (attorney)
  Future<void> declineCase(String caseId) async {
    try {
      final result = await HybridDatastore.updateCase(
        id: caseId,
        patch: {
          'status': 'declined',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      if (!result.isSuccess) throw Exception(result.failureMessage);
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

      await HybridDatastore.updateCase(id: caseId, patch: updateData).then((r) {
        if (!r.isSuccess) throw Exception(r.failureMessage);
      });
      final caseData = caseDoc.data()!;
      final clientId = caseData['clientId'] as String?;
      final title = caseTitle ?? caseData['caseTitle'] as String? ?? 'Case';
      final currentStatus = caseData['status'] as String?;

      if (clientId != null && !CaseStatusFilter.isDraft(currentStatus)) {
        await _sendCaseUpdateNotification(
          clientId,
          caseId,
          title,
          'Case details have been updated',
          sendSms: false,
        );
      }
    } catch (e) {
      throw Exception('Failed to update case details: $e');
    }
  }

  // Update case status
  Future<void> updateCaseStatus(
    String caseId,
    String status, {
    String? caseResult,
  }) async {
    try {
      final caseDoc = await _firestore.collection('cases').doc(caseId).get();
      if (!caseDoc.exists) {
        throw Exception('Case not found');
      }

      final caseData = caseDoc.data()!;
      final clientId = caseData['clientId'] as String?;
      final caseTitle = caseData['caseTitle'] as String? ?? 'Case';
      final previousStatus = caseData['status'] as String? ?? '';
      final existingProgress =
          Map<String, dynamic>.from(caseData['progress'] as Map? ?? {});
      final timeline = List<dynamic>.from(existingProgress['timeline'] as List? ?? []);
      final normalizedResult = CaseStatusFilter.isCompleted(status)
          ? CaseResult.normalize(caseResult)
          : null;
      final historyAction = CaseHistory.actionForStatus(
        status,
        caseResult: normalizedResult,
      );
      if (historyAction != null) {
        timeline.add({
          'date': DateTime.now().toIso8601String(),
          'action': historyAction,
          if (normalizedResult != null) 'result': normalizedResult,
        });
        existingProgress['timeline'] = timeline;
      }

      final patch = <String, dynamic>{
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        'progress': existingProgress,
      };
      if (normalizedResult != null) {
        patch['caseResult'] = normalizedResult;
      }

      final result = await HybridDatastore.updateCase(
        id: caseId,
        patch: patch,
      );
      if (result.isSuccess && CaseStatusFilter.isCompleted(status)) {
        await _cancelOpenTasksForCase(caseId);
      }
      if (!result.isSuccess) throw Exception(result.failureMessage);
      if (clientId != null) {
        await _notifyClientOfStatusChange(
          clientId: clientId,
          caseId: caseId,
          caseTitle: caseTitle,
          previousStatus: previousStatus,
          newStatus: status,
          caseResult: normalizedResult,
        );
      }
    } catch (e) {
      throw Exception('Failed to update case status: $e');
    }
  }

  Future<void> _cancelOpenTasksForCase(String caseId) async {
    try {
      final snap = await _firestore
          .collection('tasks')
          .where('caseId', isEqualTo: caseId)
          .get();
      for (final doc in snap.docs) {
        final status =
            (doc.data()['status'] as String? ?? '').toLowerCase().trim();
        if (status != 'pending' &&
            status != 'in_progress' &&
            status != 'in progress') {
          continue;
        }
        await HybridDatastore.update(
          collection: 'tasks',
          id: doc.id,
          patch: {
            'status': 'cancelled',
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to cancel open tasks for case $caseId: $e');
      }
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
        final caseData = caseDoc.data()!;
        final currentProgress =
            Map<String, dynamic>.from(caseData['progress'] as Map? ?? {});
        final oldHearing = _parseHearingDate(currentProgress['hearingDate']) ??
            _parseHearingDate(caseData['hearingDate']);
        currentProgress.addAll(progressUpdate);
        final newHearing = _parseHearingDate(progressUpdate['hearingDate']) ??
            _parseHearingDate(currentProgress['hearingDate']);

        final result = await HybridDatastore.updateCase(
          id: caseId,
          patch: {
            'progress': currentProgress,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        if (!result.isSuccess) throw Exception(result.failureMessage);

        final clientId = caseData['clientId'] as String?;
        final caseTitle = caseData['caseTitle'] as String? ?? 'Case';
        final status = caseData['status'] as String?;
        final hearingChanged = newHearing != null &&
            (oldHearing == null || !_sameDay(oldHearing, newHearing));

        if (clientId != null &&
            hearingChanged &&
            !CaseStatusFilter.isDraft(status)) {
          final dateStr = DateFormat('MMM d, yyyy').format(newHearing);
          await _sendCaseUpdateNotification(
            clientId,
            caseId,
            caseTitle,
            'Hearing scheduled: $dateStr',
            sendSms: true,
            smsBody: CaseSmsFormatter.hearingScheduled(caseTitle, dateStr),
          );
        }
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

        final documents = List<String>.from(caseData['documents'] ?? []);
        documents.add(documentUrl);

        final result = await HybridDatastore.updateCase(
          id: caseId,
          patch: {
            'documents': documents,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        if (!result.isSuccess) throw Exception(result.failureMessage);
        final status = caseData['status'] as String?;
        if (clientId != null && !CaseStatusFilter.isDraft(status)) {
          await _sendCaseUpdateNotification(
            clientId,
            caseId,
            caseTitle,
            'New document uploaded',
            sendSms: false,
          );
        }
      }
    } catch (e) {
      throw Exception('Failed to add document: $e');
    }
  }

  Future<void> _notifyClientOfStatusChange({
    required String clientId,
    required String caseId,
    required String caseTitle,
    required String previousStatus,
    required String newStatus,
    String? caseResult,
  }) async {
    if (CaseStatusFilter.isDraft(newStatus)) return;

    if (CaseStatusFilter.isDraft(previousStatus)) {
      await _sendCaseCreatedNotification(clientId, caseTitle, caseId);
      return;
    }

    final label = CaseStatusFilter.statusLabel(newStatus);
    final resultLabel = CaseResult.label(caseResult);
    final completedWithResult =
        CaseStatusFilter.isCompleted(newStatus) && resultLabel.isNotEmpty;
    final sms = CaseSmsFormatter.statusBody(
      caseTitle,
      newStatus,
      resultLabel: completedWithResult ? resultLabel : null,
    );
    if (sms == null) return;

    await _sendCaseUpdateNotification(
      clientId,
      caseId,
      caseTitle,
      completedWithResult
          ? 'Case completed — $resultLabel'
          : 'Status updated to: $label',
      sendSms: true,
      smsBody: sms,
    );
  }

  // Send notification to client when case is updated
  Future<void> _sendCaseUpdateNotification(
    String clientId,
    String caseId,
    String caseTitle,
    String updateMessage, {
    bool sendSms = false,
    String? smsBody,
  }) async {
    try {
      final settings = await SystemSettingsService.instance.load();
      if (!settings.caseUpdates) return;
      final notice = settings.emailNotifications
          ? settings.applyTemplate(
              settings.caseUpdateEmail,
              updateMessage,
              {'case': caseTitle, 'message': updateMessage},
            )
          : updateMessage;

      // Send FCM notification
      await _fcmService.sendNotificationToUser(
        userId: clientId,
        title: 'Case Update: $caseTitle',
        body: notice,
        data: {
          'type': 'case_updated',
          'caseId': caseId,
          'caseTitle': caseTitle,
        },
      );

      // Create in-app notification
      final notifData = <String, dynamic>{
        'userId': clientId,
        'type': 'case_updated',
        'title': 'Case Update: $caseTitle',
        'message': notice,
        'data': {'caseId': caseId, 'caseTitle': caseTitle},
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await FirestoreMirror.add(collection: 'notifications', data: notifData);

      if (sendSms) {
        await _sendCaseSmsToClient(
          clientId: clientId,
          body: smsBody ?? CaseSmsFormatter.generic(caseTitle, updateMessage),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to send case update notification: $e');
      }
    }
  }

  Future<void> _sendCaseSmsToClient({
    required String clientId,
    required String body,
    String smsType = 'case_update',
  }) async {
    try {
      final userDoc = await _firestore.collection('users').doc(clientId).get();
      final data = userDoc.data();
      if (data == null) {
        if (kDebugMode) {
          debugPrint('ℹ️ Case SMS skipped: no user doc for $clientId');
        }
        return;
      }
      final phone = (data['phoneNumber'] ??
              data['phone'] ??
              data['mobile'] ??
              data['mobileNumber'] ??
              data['contactNumber'])
          ?.toString()
          .trim() ??
          '';
      if (phone.isEmpty) {
        if (kDebugMode) {
          debugPrint('ℹ️ Case SMS skipped: no phone for client $clientId');
        }
        return;
      }
      await _smsService.queueSms(
        to: phone,
        body: body,
        userId: clientId,
        meta: {'type': smsType},
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Case SMS skipped: $e');
      }
    }
  }

  DateTime? _parseHearingDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
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

  /// Assigned attorney from the client's most recent active (non-draft) case.
  Future<String?> findAttorneyIdForClient(String clientId) async {
    try {
      final casesSnapshot = await _firestore
          .collection('cases')
          .where('clientId', isEqualTo: clientId)
          .get();
      if (casesSnapshot.docs.isEmpty) return null;

      final cases = casesSnapshot.docs
          .map(CaseModel.fromFirestore)
          .where((c) => !c.isArchived && !CaseStatusFilter.isDraft(c.status))
          .where((c) => c.attorneyId != null && c.attorneyId!.isNotEmpty)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (cases.isEmpty) return null;
      return cases.first.attorneyId;
    } catch (e) {
      return getClientAttorneyId(clientId);
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
