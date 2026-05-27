import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/system_log_model.dart';
import 'fcm_service.dart';
import 'staff_auth_service.dart';
import 'backup_service.dart';
import 'sms_service.dart';

enum _CaseAnalyticsBucket { pending, inProgress, completed }

_CaseAnalyticsBucket _bucketForCaseStatus(dynamic raw) {
  final s = (raw as String?)?.toLowerCase().trim() ?? 'pending';
  if (s == 'completed' ||
      s == 'closed' ||
      s == 'resolved' ||
      s == 'declined' ||
      s == 'dismissed') {
    return _CaseAnalyticsBucket.completed;
  }
  if (s == 'pending' || s == 'under_review' || s == 'draft') {
    return _CaseAnalyticsBucket.pending;
  }
  return _CaseAnalyticsBucket.inProgress;
}

String _analyticsCaseTypeLabel(dynamic raw) {
  if (raw == null) return 'Unspecified';
  final s = raw.toString().trim();
  return s.isEmpty ? 'Unspecified' : s;
}

class AdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Expose firestore for announcements stream
  FirebaseFirestore get firestore => _firestore;

  // System Logs
  Future<void> logAction({
    required String action,
    String? details,
    String? resourceType,
    String? resourceId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Get user name
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userName = userDoc.data()?['name'] ?? 'Unknown';

      final entry = <String, dynamic>{
        'userId': user.uid,
        'userName': userName,
        'action': action,
        'timestamp': FieldValue.serverTimestamp(),
        'metadata': metadata ?? <String, dynamic>{},
      };
      if (details != null && details.trim().isNotEmpty) {
        entry['details'] = details.trim();
      }
      if (resourceType != null && resourceType.trim().isNotEmpty) {
        entry['resourceType'] = resourceType.trim();
      }
      if (resourceId != null && resourceId.trim().isNotEmpty) {
        entry['resourceId'] = resourceId.trim();
      }

      await _firestore.collection('system_logs').add(entry);
    } catch (e) {
      // Silently fail logging - don't break the app
      if (kDebugMode) {
        debugPrint('Failed to log action: $e');
      }
    }
  }

  // Get all unique dates that have logs
  Future<List<DateTime>> getDatesWithLogs() async {
    try {
      final snapshot = await _firestore
          .collection('system_logs')
          .orderBy('timestamp', descending: true)
          .limit(5000) // Get a reasonable number of logs
          .get();

      final dates = <DateTime>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final timestamp = data['timestamp'] as Timestamp?;
        if (timestamp != null) {
          final date = timestamp.toDate();
          // Normalize to start of day
          final dateOnly = DateTime(date.year, date.month, date.day);
          dates.add(dateOnly);
        }
      }

      final sortedDates = dates.toList()..sort((a, b) => b.compareTo(a));
      return sortedDates;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting dates with logs: $e');
      }
      return [];
    }
  }

  Stream<List<SystemLogModel>> getSystemLogs({
    DateTime? startDate,
    DateTime? endDate,
    String? userId,
    String? action,
  }) {
    try {
      // Count filters to determine if we need in-memory filtering
      final filterCount = [
        startDate != null,
        endDate != null,
        userId != null,
        action != null,
      ].where((f) => f).length;

      // If we have multiple filters, use a simpler query and filter in memory
      // This avoids Firestore composite index requirements
      if (filterCount > 2) {
        // Use base query with just orderBy, then filter in memory
        Query baseQuery = _firestore.collection('system_logs');

        // Apply only timestamp filters if present (these work with orderBy)
        if (startDate != null) {
          baseQuery = baseQuery.where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          );
        }
        if (endDate != null) {
          baseQuery = baseQuery.where(
            'timestamp',
            isLessThan: Timestamp.fromDate(endDate),
          );
        }

        return baseQuery
            .orderBy('timestamp', descending: true)
            .limit(2000) // Get more to filter in memory
            .snapshots()
            .map((snapshot) {
              try {
                var logs = snapshot.docs
                    .map((doc) {
                      try {
                        return SystemLogModel.fromFirestore(doc);
                      } catch (e) {
                        print('Error parsing log document ${doc.id}: $e');
                        return null;
                      }
                    })
                    .where((log) => log != null)
                    .cast<SystemLogModel>()
                    .toList();

                // Apply in-memory filters
                if (userId != null) {
                  logs = logs.where((log) => log.userId == userId).toList();
                }
                if (action != null) {
                  logs = logs.where((log) => log.action == action).toList();
                }
                if (startDate != null) {
                  logs = logs
                      .where(
                        (log) =>
                            log.timestamp.isAfter(startDate) ||
                            log.timestamp.isAtSameMomentAs(startDate),
                      )
                      .toList();
                }
                if (endDate != null) {
                  logs = logs
                      .where((log) => log.timestamp.isBefore(endDate))
                      .toList();
                }

                // Ensure sorted by timestamp descending
                logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

                return logs.take(1000).toList();
              } catch (e) {
                print('Error mapping system logs: $e');
                return <SystemLogModel>[];
              }
            })
            .handleError((error, stackTrace) {
              print('Error fetching system logs: $error');
              print('Stack trace: $stackTrace');
            });
      } else {
        // Simple case - can use Firestore query directly
        Query query = _firestore.collection('system_logs');

        if (startDate != null) {
          query = query.where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          );
        }
        if (endDate != null) {
          query = query.where(
            'timestamp',
            isLessThan: Timestamp.fromDate(endDate),
          );
        }
        if (userId != null) {
          query = query.where('userId', isEqualTo: userId);
        }
        if (action != null) {
          query = query.where('action', isEqualTo: action);
        }

        return query
            .orderBy('timestamp', descending: true)
            .limit(1000)
            .snapshots()
            .map((snapshot) {
              try {
                return snapshot.docs
                    .map((doc) {
                      try {
                        return SystemLogModel.fromFirestore(doc);
                      } catch (e) {
                        print('Error parsing log document ${doc.id}: $e');
                        return null;
                      }
                    })
                    .where((log) => log != null)
                    .cast<SystemLogModel>()
                    .toList();
              } catch (e) {
                print('Error mapping system logs: $e');
                return <SystemLogModel>[];
              }
            })
            .handleError((error, stackTrace) {
              print('Error fetching system logs: $error');
              print('Stack trace: $stackTrace');
            });
      }
    } catch (e) {
      print('Error creating system logs query: $e');
      // Return an empty stream on error
      return Stream.value(<SystemLogModel>[]);
    }
  }

  // User Management
  Future<void> updateUserRole(String userId, String newRole) async {
    await _firestore.collection('users').doc(userId).update({'role': newRole});
    await logAction(
      action: 'user_role_updated',
      resourceType: 'user',
      resourceId: userId,
      metadata: {'newRole': newRole},
    );
  }

  Future<void> deactivateUser(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'isActive': false,
      'deactivatedAt': FieldValue.serverTimestamp(),
    });
    await logAction(
      action: 'user_deactivated',
      resourceType: 'user',
      resourceId: userId,
    );
  }

  Future<void> activateUser(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'isActive': true,
      'deactivatedAt': FieldValue.delete(),
    });
    await logAction(
      action: 'user_activated',
      resourceType: 'user',
      resourceId: userId,
    );
  }

  Future<void> resetUserPassword(String userId) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final email = userDoc.data()?['email'];
    if (email != null) {
      // Send password reset email without ActionCodeSettings to avoid domain allowlist issues
      await _auth.sendPasswordResetEmail(email: email);
      await logAction(
        action: 'password_reset_sent',
        resourceType: 'user',
        resourceId: userId,
      );
    }
  }

  // Case Management
  Future<void> reassignCase(String caseId, String newAttorneyId) async {
    await _firestore.collection('cases').doc(caseId).update({
      'attorneyId': newAttorneyId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await logAction(
      action: 'case_reassigned',
      resourceType: 'case',
      resourceId: caseId,
      metadata: {'newAttorneyId': newAttorneyId},
    );
  }

  Future<void> lockCase(String caseId, String reason) async {
    await _firestore.collection('cases').doc(caseId).update({
      'isLocked': true,
      'lockReason': reason,
      'lockedAt': FieldValue.serverTimestamp(),
    });
    await logAction(
      action: 'case_locked',
      resourceType: 'case',
      resourceId: caseId,
      details: reason,
    );
  }

  Future<void> unlockCase(String caseId) async {
    await _firestore.collection('cases').doc(caseId).update({
      'isLocked': false,
      'lockReason': FieldValue.delete(),
      'lockedAt': FieldValue.delete(),
    });
    await logAction(
      action: 'case_unlocked',
      resourceType: 'case',
      resourceId: caseId,
    );
  }

  /// Moves a case to archive storage (hidden from Case Oversight).
  Future<void> archiveCase(String caseId) async {
    await _firestore.collection('cases').doc(caseId).update({
      'isArchived': true,
      'archivedAt': FieldValue.serverTimestamp(),
      'archivedBy': _auth.currentUser?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await logAction(
      action: 'case_archived',
      resourceType: 'case',
      resourceId: caseId,
    );
  }

  /// Restores a case from archive storage back to Case Oversight.
  Future<void> restoreArchivedCase(String caseId) async {
    await _firestore.collection('cases').doc(caseId).update({
      'isArchived': false,
      'archivedAt': FieldValue.delete(),
      'archivedBy': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await logAction(
      action: 'case_restored_from_archive',
      resourceType: 'case',
      resourceId: caseId,
    );
  }

  /// Backs up then permanently removes an archived case (appears in Backup).
  Future<void> deleteArchivedCaseToBackup(String caseId) async {
    final caseDoc = await _firestore.collection('cases').doc(caseId).get();
    if (!caseDoc.exists) {
      throw Exception('Case not found');
    }
    // Save as active case so Backup → Restore returns to Case Oversight.
    final backupData = Map<String, dynamic>.from(caseDoc.data()!);
    backupData['isArchived'] = false;
    backupData.remove('archivedAt');
    backupData.remove('archivedBy');

    final backupService = BackupService();
    await backupService.backupBeforeDelete(
      collection: 'cases',
      documentId: caseId,
      data: backupData,
      deletedBy: _auth.currentUser?.uid,
    );
    await _firestore.collection('cases').doc(caseId).delete();
    await logAction(
      action: 'case_deleted_to_backup',
      resourceType: 'case',
      resourceId: caseId,
    );
  }

  Stream<List<Map<String, dynamic>>> watchArchivedCases() {
    return _firestore.collection('cases').snapshots().map((snapshot) {
      final items = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['isArchived'] != true) continue;
        items.add({
          'id': doc.id,
          ...data,
        });
      }
      items.sort((a, b) {
        final ta = a['archivedAt'] as Timestamp?;
        final tb = b['archivedAt'] as Timestamp?;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
      return items;
    });
  }

  // System Settings
  Future<void> setMaintenanceMode(bool enabled) async {
    try {
      // Use set with merge to handle both create and update
      await _firestore.collection('system_settings').doc('maintenance').set({
        'maintenanceMode': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await logAction(
        action: 'maintenance_mode_${enabled ? 'enabled' : 'disabled'}',
      );
    } catch (e) {
      print('Error setting maintenance mode: $e');
      rethrow;
    }
  }

  Future<bool> getMaintenanceMode() async {
    final doc = await _firestore
        .collection('system_settings')
        .doc('maintenance')
        .get();
    return doc.data()?['maintenanceMode'] ?? false;
  }

  Stream<bool> watchMaintenanceMode() {
    return _firestore
        .collection('system_settings')
        .doc('maintenance')
        .snapshots()
        .map((doc) => doc.data()?['maintenanceMode'] ?? false);
  }

  // Analytics
  /// Loads all [cases] by default so totals match the dashboard (no hidden 30-day window).
  /// Pass both [startDate] and [endDate] to restrict to that range (e.g. export).
  /// Distinct years from case [createdAt], newest first. Always includes current year.
  Future<List<int>> getCaseYears() async {
    final snapshot = await _firestore.collection('cases').get();
    final years = <int>{DateTime.now().year};
    for (final doc in snapshot.docs) {
      final createdAt = doc.data()['createdAt'];
      if (createdAt is Timestamp) {
        years.add(createdAt.toDate().year);
      }
    }
    final list = years.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  static const _monthShortNames = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  Future<Map<String, dynamic>> getAnalytics({
    DateTime? startDate,
    DateTime? endDate,
    int? year,
    /// 1–12; with [year] limits to that calendar month.
    int? month,
  }) async {
    DateTime? rangeStart = startDate;
    DateTime? rangeEnd = endDate;
    if (year != null && month != null && month >= 1 && month <= 12) {
      rangeStart = DateTime(year, month, 1);
      rangeEnd = DateTime(year, month + 1, 0, 23, 59, 59, 999);
    } else if (year != null) {
      rangeStart = DateTime(year, 1, 1);
      rangeEnd = DateTime(year, 12, 31, 23, 59, 59, 999);
    }
    final useDateRange = rangeStart != null && rangeEnd != null;

    // Get users
    final usersSnapshot = await _firestore.collection('users').get();
    final users = usersSnapshot.docs;
    final clients = users.where((u) => u.data()['role'] == 'client').length;
    final attorneys = users.where((u) => u.data()['role'] == 'attorney').length;
    final admins = users.where((u) => u.data()['role'] == 'admin').length;

    // Load all cases then filter by date in memory so missing indexes / null
    // createdAt do not hide data from the Cases by Type chart.
    final casesSnapshot = await _firestore.collection('cases').get();
    final cases = casesSnapshot.docs.where((doc) {
      if (!useDateRange) return true;
      final createdAt = doc.data()['createdAt'];
      if (createdAt is! Timestamp) return false;
      final dt = createdAt.toDate();
      if (dt.isBefore(rangeStart!)) return false;
      if (dt.isAfter(rangeEnd!)) return false;
      return true;
    }).toList();

    var pending = 0;
    var inProgress = 0;
    var completed = 0;

    final casesByType = <String, int>{};
    final monthlyCases = <String, int>{};

    for (final caseDoc in cases) {
      final data = caseDoc.data();
      switch (_bucketForCaseStatus(data['status'])) {
        case _CaseAnalyticsBucket.pending:
          pending++;
          break;
        case _CaseAnalyticsBucket.inProgress:
          inProgress++;
          break;
        case _CaseAnalyticsBucket.completed:
          completed++;
          break;
      }

      final typeLabel = _analyticsCaseTypeLabel(data['caseType']);
      casesByType[typeLabel] = (casesByType[typeLabel] ?? 0) + 1;

      final createdAt = data['createdAt'];
      if (createdAt is Timestamp) {
        final dt = createdAt.toDate();
        final monthKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        monthlyCases[monthKey] = (monthlyCases[monthKey] ?? 0) + 1;
      }
    }

    String? peakMonthLabel;
    int? peakMonthNumber;
    var peakMonthCount = 0;
    if (year != null && month == null && monthlyCases.isNotEmpty) {
      final prefix = '$year-';
      Iterable<MapEntry<String, int>> yearMonths = monthlyCases.entries
          .where((e) => e.key.startsWith(prefix));
      if (yearMonths.isNotEmpty) {
        final peak = yearMonths.reduce(
          (a, b) => a.value >= b.value ? a : b,
        );
        peakMonthCount = peak.value;
        final parts = peak.key.split('-');
        if (parts.length == 2) {
          final m = int.tryParse(parts[1]);
          if (m != null && m >= 1 && m <= 12) {
            peakMonthNumber = m;
            peakMonthLabel = _monthShortNames[m];
          }
        }
      }
    }

    return {
      'totalUsers': users.length,
      'clients': clients,
      'attorneys': attorneys,
      'admins': admins,
      'totalCases': cases.length,
      'pendingCases': pending,
      'inProgressCases': inProgress,
      'completedCases': completed,
      'casesByType': Map<String, dynamic>.from(casesByType),
      'monthlyCases': monthlyCases,
      'analyticsDateFiltered': useDateRange,
      'filterYear': year,
      'filterMonth': month,
      'peakMonthLabel': peakMonthLabel,
      'peakMonthNumber': peakMonthNumber,
      'peakMonthCount': peakMonthCount,
    };
  }

  // Document Management
  Future<List<Map<String, dynamic>>> getAllDocuments() async {
    final casesSnapshot = await _firestore.collection('cases').get();
    final documents = <Map<String, dynamic>>[];

    for (var caseDoc in casesSnapshot.docs) {
      final caseData = caseDoc.data();
      final docs = caseData['documents'] as List<dynamic>? ?? [];
      for (var doc in docs) {
        documents.add({
          'caseId': caseDoc.id,
          'caseTitle': caseData['caseTitle'] ?? '',
          'url': doc,
          'uploadedAt': caseData['updatedAt'],
        });
      }
    }

    return documents;
  }

  /// Queue SMS via [SmsService] (Supabase Edge and/or Firestore `sms_requests` → Cloud Function).
  Future<Map<String, dynamic>> queueManualSms({
    required String to,
    required String body,
    String? relatedUserId,
  }) async {
    try {
      final me = _auth.currentUser;
      if (me == null) {
        return {'success': false, 'message': 'Not signed in'};
      }
      final smsResult = await SmsService().queueSms(
        to: to,
        body: body,
        userId: relatedUserId ?? me.uid,
        meta: {
          'type': 'admin_manual',
          'channel': 'sms',
          if (relatedUserId != null) 'relatedUserId': relatedUserId,
        },
      );
      final sentNow = smsResult.result == SmsQueueResult.sentViaSupabase;
      await logAction(
        action: sentNow ? 'sms_sent_manual' : 'sms_queued_manual',
        details: sentNow
            ? 'Admin sent SMS via Supabase send-sms from User Management'
            : 'Admin queued an SMS from User Management',
        resourceType: 'sms_request',
        resourceId: relatedUserId,
      );
      return {
        'success': true,
        'message': sentNow
            ? 'SMS sent successfully.'
            : 'SMS queued (${smsResult.requestId ?? "id unknown"}). Deploy onSmsRequestSend with SEMAPHORE_API_KEY or Twilio, or run sms-worker.',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // Admin Messaging
  Future<void> sendAnnouncement({
    required String title,
    required String message,
    required List<String> recipientRoles, // ['attorney', 'client', 'all']
  }) async {
    await _firestore.collection('announcements').add({
      'title': title,
      'message': message,
      'recipientRoles': recipientRoles,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid,
    });
    await logAction(
      action: 'announcement_sent',
      details: 'Title: $title',
      metadata: {'recipientRoles': recipientRoles},
    );
  }

  // Create staff user with custom password
  Future<Map<String, dynamic>> createStaffUser({
    required String email,
    required String name,
    required String password,
    String? assignedAttorneyId,
    String? phone,
    String? address,
  }) async {
    try {
      // Import staff service
      final staffService = StaffAuthService();

      // Get first attorney if none specified
      String? attorneyId = assignedAttorneyId;
      if (attorneyId == null || attorneyId.isEmpty) {
        final attorneys = await getAllAttorneys();
        if (attorneys.isNotEmpty) {
          attorneyId = attorneys.first['id'] as String;
        } else {
          attorneyId = ''; // Will need to assign later
        }
      }

      final result = await staffService.createStaff(
        email: email,
        name: name,
        assignedAttorneyId: attorneyId,
        password: password,
        phone: phone,
        address: address,
      );

      if (result['success'] == true) {
        await logAction(
          action: 'staff_created',
          resourceType: 'user',
          resourceId: result['staffId'],
          details: 'Created staff: $name',
        );
      }

      return result;
    } catch (e) {
      return {'success': false, 'message': 'Failed to create staff: $e'};
    }
  }

  // Add new attorney user
  Future<Map<String, dynamic>> createAttorney({
    required String name,
    required String email,
    String? specialization,
  }) async {
    try {
      // Check if user already exists
      final existingUsers = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .get();

      if (existingUsers.docs.isNotEmpty) {
        return {
          'success': false,
          'message': 'User with this email already exists',
        };
      }

      // Create Firebase Auth user
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: 'TempPassword123!', // Temporary password - user should reset
      );

      if (credential.user == null) {
        return {'success': false, 'message': 'Failed to create user account'};
      }

      final userId = credential.user!.uid;

      // Create user document in Firestore
      await _firestore.collection('users').doc(userId).set({
        'name': name,
        'email': email,
        'role': 'attorney',
        'isActive': true,
        'isAvailable': true,
        'specializations': specialization != null && specialization.isNotEmpty
            ? specialization.split(',').map((s) => s.trim()).toList()
            : [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Send password reset email so attorney can set their own password
      await _auth.sendPasswordResetEmail(email: email);

      await logAction(
        action: 'attorney_created',
        resourceType: 'user',
        resourceId: userId,
        details: 'Attorney: $name',
      );

      return {
        'success': true,
        'message': 'Attorney created successfully. Password reset email sent.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Failed to create attorney: $e'};
    }
  }

  // Activate attorney account (approve signup)
  Future<Map<String, dynamic>> activateAttorney(String attorneyId) async {
    try {
      final attorneyDoc = await _firestore
          .collection('users')
          .doc(attorneyId)
          .get();

      if (!attorneyDoc.exists) {
        return {'success': false, 'message': 'Attorney not found'};
      }

      final attorneyData = attorneyDoc.data()!;
      final role = attorneyData['role'] as String?;

      if (role != 'attorney') {
        return {'success': false, 'message': 'User is not an attorney'};
      }

      // Activate the attorney account
      await _firestore.collection('users').doc(attorneyId).update({
        'isActive': true,
        'pendingApproval': false,
        'activatedAt': FieldValue.serverTimestamp(),
        'activatedBy': _auth.currentUser?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Log the action
      await logAction(
        action: 'attorney_activated',
        resourceType: 'user',
        resourceId: attorneyId,
        details:
            'Activated attorney: ${attorneyData['name'] ?? attorneyData['fullName']}',
      );

      // Send notification to attorney about activation
      try {
        final fcmService = FCMService();
        final fcmToken = attorneyData['fcmToken'] as String?;

        if (fcmToken != null) {
          await fcmService.sendNotificationToUser(
            userId: attorneyId,
            title: 'Account Activated',
            body:
                'Your attorney account has been activated. You can now access all features.',
            data: {'type': 'attorney_activated', 'attorneyId': attorneyId},
          );
        }

        // Create notification in Firestore
        await _firestore.collection('notifications').add({
          'userId': attorneyId,
          'clientId': attorneyId, // For compatibility with notification screen
          'title': 'Account Activated',
          'message':
              'Your attorney account has been activated. You can now access all features.',
          'type': 'attorney_activated',
          'data': {'attorneyId': attorneyId},
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ Could not send activation notification to attorney: $e',
          );
        }
        // Don't fail activation if notification fails
      }

      return {'success': true, 'message': 'Attorney activated successfully'};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error activating attorney: $e');
      }
      return {'success': false, 'message': 'Failed to activate attorney: $e'};
    }
  }

  // Deactivate attorney account
  Future<Map<String, dynamic>> deactivateAttorney(String attorneyId) async {
    try {
      final attorneyDoc = await _firestore
          .collection('users')
          .doc(attorneyId)
          .get();

      if (!attorneyDoc.exists) {
        return {'success': false, 'message': 'Attorney not found'};
      }

      // Deactivate the attorney account
      await _firestore.collection('users').doc(attorneyId).update({
        'isActive': false,
        'deactivatedAt': FieldValue.serverTimestamp(),
        'deactivatedBy': _auth.currentUser?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Log the action
      await logAction(
        action: 'attorney_deactivated',
        resourceType: 'user',
        resourceId: attorneyId,
        details:
            'Deactivated attorney: ${attorneyDoc.data()?['name'] ?? attorneyDoc.data()?['fullName']}',
      );

      return {'success': true, 'message': 'Attorney deactivated successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to deactivate attorney: $e'};
    }
  }

  // Get pending attorneys (those needing approval)
  Stream<List<Map<String, dynamic>>> getPendingAttorneys() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'attorney')
        .where('pendingApproval', isEqualTo: true)
        .where('isActive', isEqualTo: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            return {'id': doc.id, ...data};
          }).toList(),
        );
  }

  // Update user information
  Future<Map<String, dynamic>> updateUserInfo({
    required String userId,
    String? name,
    String? email,
    bool? isActive,
    bool? isAvailable,
    List<String>? specializations,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (name != null) updateData['name'] = name;
      if (email != null) updateData['email'] = email;
      if (isActive != null) {
        updateData['isActive'] = isActive;
        if (isActive == true) {
          updateData['staffPendingAdminActivation'] = FieldValue.delete();
        }
      }
      if (isAvailable != null) updateData['isAvailable'] = isAvailable;
      if (specializations != null)
        updateData['specializations'] = specializations;

      await _firestore.collection('users').doc(userId).update(updateData);

      await logAction(
        action: 'user_updated',
        resourceType: 'user',
        resourceId: userId,
        metadata: updateData,
      );

      return {'success': true, 'message': 'User updated successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to update user: $e'};
    }
  }

  // Get all attorneys for selection
  Future<List<Map<String, dynamic>>> getAllAttorneys() async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'attorney')
        .where('isActive', isEqualTo: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': data['name'] ?? 'Unknown',
        'email': data['email'] ?? '',
        'specializations': data['specializations'] ?? [],
      };
    }).toList();
  }

  // Permanently delete a user (Firestore document only)
  Future<Map<String, dynamic>> deleteUser(String userId) async {
    try {
      // Backup before deletion
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final backupService = BackupService();
        await backupService.backupBeforeDelete(
          collection: 'users',
          documentId: userId,
          data: userDoc.data()!,
          deletedBy: _auth.currentUser?.uid,
        );
      }

      await _firestore.collection('users').doc(userId).delete();

      await logAction(
        action: 'user_deleted',
        resourceType: 'user',
        resourceId: userId,
      );

      return {'success': true, 'message': 'User deleted successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete user: $e'};
    }
  }

  // Delete document from case
  Future<Map<String, dynamic>> deleteDocument(
    String caseId,
    String documentUrl,
  ) async {
    try {
      final caseDoc = await _firestore.collection('cases').doc(caseId).get();
      if (!caseDoc.exists) {
        return {'success': false, 'message': 'Case not found'};
      }

      final caseData = caseDoc.data()!;
      final documents = (caseData['documents'] as List<dynamic>?) ?? [];

      documents.remove(documentUrl);

      await _firestore.collection('cases').doc(caseId).update({
        'documents': documents,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await logAction(
        action: 'document_deleted',
        resourceType: 'case',
        resourceId: caseId,
        details: 'Document URL removed',
      );

      return {'success': true, 'message': 'Document deleted successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete document: $e'};
    }
  }

  // Export system logs as CSV string
  Future<String> exportSystemLogs({
    DateTime? startDate,
    DateTime? endDate,
    String? action,
  }) async {
    final logs = await getSystemLogs(
      startDate: startDate,
      endDate: endDate,
      action: action,
    ).first;

    final csv = StringBuffer();
    csv.writeln('Timestamp,Action,User,Details,Resource Type,Resource ID');

    for (final log in logs) {
      csv.writeln(
        [
              log.timestamp.toIso8601String(),
              log.action,
              log.userName ?? 'Unknown',
              log.details ?? '',
              log.resourceType ?? '',
              log.resourceId ?? '',
            ]
            .map((field) => '"${field.toString().replaceAll('"', '""')}"')
            .join(','),
      );
    }

    return csv.toString();
  }

  // Export analytics report as JSON string
  Future<String> exportAnalyticsReport({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final analytics = await getAnalytics(
      startDate: startDate,
      endDate: endDate,
    );

    final byType = analytics['casesByType'];
    final typeMap = byType is Map<String, int>
        ? Map<String, dynamic>.from(byType)
        : Map<String, dynamic>.from(
            (byType as Map?)?.map(
                  (k, v) => MapEntry(k.toString(), v is num ? v.toInt() : v),
                ) ??
                {},
          );

    final periodStart = startDate != null && endDate != null
        ? startDate.toIso8601String()
        : 'all_time';
    final periodEnd = startDate != null && endDate != null
        ? endDate.toIso8601String()
        : 'all_time';

    // Convert to JSON string
    final jsonString =
        '''
{
  "generatedAt": "${DateTime.now().toIso8601String()}",
  "period": {
    "start": "$periodStart",
    "end": "$periodEnd"
  },
  "userStatistics": {
    "totalUsers": ${analytics['totalUsers']},
    "clients": ${analytics['clients']},
    "attorneys": ${analytics['attorneys']},
    "admins": ${analytics['admins']}
  },
  "caseStatistics": {
    "totalCases": ${analytics['totalCases']},
    "pendingCases": ${analytics['pendingCases']},
    "inProgressCases": ${analytics['inProgressCases']},
    "completedCases": ${analytics['completedCases']}
  },
  "casesByType": ${_mapToJsonString(typeMap)}
}
''';

    return jsonString;
  }

  String _mapToJsonString(Map<String, dynamic> map) {
    if (map.isEmpty) return '{}';
    final entries = map.entries.map((e) {
      final safeKey = e.key.replaceAll('\\', r'\\').replaceAll('"', r'\"');
      return '"$safeKey": ${e.value}';
    });
    return '{${entries.join(', ')}}';
  }
}
