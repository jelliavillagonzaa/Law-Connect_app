import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:intl/intl.dart';
import 'notification_service.dart';
import 'fcm_service.dart';

/// Service to monitor and send early reminders for upcoming important deadlines
/// Supports reminders at 7 days, 3 days, and 1 day before deadlines
///
/// Works for:
/// - Staff: Deadlines from assigned attorney's calendar events
/// - Attorneys: All deadlines assigned to them
/// - Clients: Deadlines related to their cases
class DeadlineReminderService {
  static final DeadlineReminderService _instance =
      DeadlineReminderService._internal();
  factory DeadlineReminderService() => _instance;
  DeadlineReminderService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();
  final FCMService _fcmService = FCMService();

  Timer? _periodicTimer;
  StreamSubscription? _deadlineStreamSubscription;
  bool _isRunning = false;

  // Track which reminders have been sent to avoid duplicates
  final Set<String> _sentReminders = <String>{};

  /// Start checking for deadline reminders
  /// This should be called when user logs in
  void startDeadlineReminderCheck() {
    if (_isRunning) return; // Already running

    _isRunning = true;
    if (kDebugMode) {
      debugPrint('🔔 Starting deadline reminder service...');
    }

    // Initialize notification service
    _notificationService.initialize();

    // Check immediately on start
    _checkAndProcessDeadlineReminders();

    // Set up Firestore listener for upcoming deadlines
    _setupDeadlineListener();

    // Also check periodically (every 6 hours) as backup
    _periodicTimer = Timer.periodic(const Duration(hours: 6), (_) {
      _checkAndProcessDeadlineReminders();
    });
  }

  /// Stop checking deadline reminders
  /// This should be called when user logs out
  void stopDeadlineReminderCheck() {
    if (!_isRunning) return;

    _isRunning = false;
    if (kDebugMode) {
      debugPrint('⏹️ Stopping deadline reminder service...');
    }

    _periodicTimer?.cancel();
    _periodicTimer = null;
    _deadlineStreamSubscription?.cancel();
    _deadlineStreamSubscription = null;
    _sentReminders.clear();
  }

  /// Set up Firestore listener to watch for upcoming deadlines
  void _setupDeadlineListener() {
    try {
      final now = DateTime.now();
      final nextWeek = now.add(const Duration(days: 8)); // Look 8 days ahead

      // Listen for calendar events with deadlines in the next week
      _deadlineStreamSubscription = _firestore
          .collection('calendar_events')
          .where('eventType', whereIn: ['deadline', 'filing', 'hearing'])
          .where('eventDate', isGreaterThan: Timestamp.fromDate(now))
          .where('eventDate', isLessThanOrEqualTo: Timestamp.fromDate(nextWeek))
          .snapshots()
          .listen((snapshot) {
            if (snapshot.docs.isNotEmpty) {
              if (kDebugMode) {
                debugPrint(
                  '📅 Found ${snapshot.docs.length} upcoming deadlines to check',
                );
              }
              _checkAndProcessDeadlineReminders();
            }
          });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error setting up deadline listener: $e');
      }
    }
  }

  /// Check and process upcoming deadline reminders
  Future<void> _checkAndProcessDeadlineReminders() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return; // User not logged in

      // Get user role
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return;

      final userData = userDoc.data();
      final userRole = userData?['role'] ?? 'client';

      if (kDebugMode) {
        debugPrint(
          '🔍 Checking deadline reminders for user: ${user.uid} ($userRole)',
        );
      }

      // Get relevant deadlines based on user role
      List<Map<String, dynamic>> relevantDeadlines = [];

      if (userRole == 'attorney') {
        // Attorneys see all deadlines assigned to them
        relevantDeadlines = await _getAttorneyDeadlines(user.uid);
      } else if (userRole == 'staff') {
        // Staff see deadlines from their assigned attorney
        relevantDeadlines = await _getStaffDeadlines(user.uid);
      } else if (userRole == 'client') {
        // Clients see deadlines from their cases
        relevantDeadlines = await _getClientDeadlines(user.uid);
      } else if (userRole == 'admin') {
        // Admins see all deadlines
        relevantDeadlines = await _getAllDeadlines();
      }

      if (relevantDeadlines.isEmpty) {
        if (kDebugMode) {
          debugPrint('   No relevant deadlines found');
        }
        return;
      }

      // Process each deadline
      for (final deadline in relevantDeadlines) {
        await _processDeadlineReminder(deadline, user.uid, userRole);
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ Error checking deadline reminders: $e');
        debugPrint('Stack trace: $stackTrace');
      }
    }
  }

  /// Get deadlines assigned to an attorney
  Future<List<Map<String, dynamic>>> _getAttorneyDeadlines(
    String attorneyId,
  ) async {
    try {
      final now = DateTime.now();
      final nextWeek = now.add(const Duration(days: 8));

      final snapshot = await _firestore
          .collection('calendar_events')
          .where('assignedTo', isEqualTo: attorneyId)
          .where('eventType', whereIn: ['deadline', 'filing', 'hearing'])
          .where('eventDate', isGreaterThan: Timestamp.fromDate(now))
          .where('eventDate', isLessThanOrEqualTo: Timestamp.fromDate(nextWeek))
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
          'eventDate': (data['eventDate'] as Timestamp?)?.toDate(),
        };
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting attorney deadlines: $e');
      }
      return [];
    }
  }

  /// Get deadlines for staff (from assigned attorney)
  Future<List<Map<String, dynamic>>> _getStaffDeadlines(String staffId) async {
    try {
      // Get staff's assigned attorney
      final staffDoc = await _firestore.collection('staff').doc(staffId).get();
      if (!staffDoc.exists) {
        // Try users collection with role='staff'
        final userDoc = await _firestore.collection('users').doc(staffId).get();
        if (!userDoc.exists) return [];

        final assignedAttorneyId = userDoc.data()?['assignedAttorneyId'];
        if (assignedAttorneyId == null) return [];

        return await _getAttorneyDeadlines(assignedAttorneyId);
      }

      final assignedAttorneyId = staffDoc.data()?['assignedAttorneyId'];
      if (assignedAttorneyId == null) return [];

      return await _getAttorneyDeadlines(assignedAttorneyId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting staff deadlines: $e');
      }
      return [];
    }
  }

  /// Get deadlines for a client (from their cases)
  Future<List<Map<String, dynamic>>> _getClientDeadlines(
    String clientId,
  ) async {
    try {
      final now = DateTime.now();
      final nextWeek = now.add(const Duration(days: 8));

      // Get all cases for this client
      final casesSnapshot = await _firestore
          .collection('cases')
          .where('clientId', isEqualTo: clientId)
          .get();

      if (casesSnapshot.docs.isEmpty) return [];

      final caseIds = casesSnapshot.docs.map((doc) => doc.id).toList();

      // Get deadlines related to client's cases
      final deadlines = <Map<String, dynamic>>[];

      // Get deadlines by caseId
      for (final caseId in caseIds) {
        final snapshot = await _firestore
            .collection('calendar_events')
            .where('caseId', isEqualTo: caseId)
            .where('eventType', whereIn: ['deadline', 'filing', 'hearing'])
            .where('eventDate', isGreaterThan: Timestamp.fromDate(now))
            .where(
              'eventDate',
              isLessThanOrEqualTo: Timestamp.fromDate(nextWeek),
            )
            .get();

        deadlines.addAll(
          snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              ...data,
              'eventDate': (data['eventDate'] as Timestamp?)?.toDate(),
            };
          }),
        );
      }

      // Get deadlines by clientId
      final clientDeadlinesSnapshot = await _firestore
          .collection('calendar_events')
          .where('clientId', isEqualTo: clientId)
          .where('eventType', whereIn: ['deadline', 'filing', 'hearing'])
          .where('eventDate', isGreaterThan: Timestamp.fromDate(now))
          .where('eventDate', isLessThanOrEqualTo: Timestamp.fromDate(nextWeek))
          .get();

      deadlines.addAll(
        clientDeadlinesSnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            ...data,
            'eventDate': (data['eventDate'] as Timestamp?)?.toDate(),
          };
        }),
      );

      // Remove duplicates
      final uniqueDeadlines = <String, Map<String, dynamic>>{};
      for (final deadline in deadlines) {
        uniqueDeadlines[deadline['id']] = deadline;
      }

      return uniqueDeadlines.values.toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting client deadlines: $e');
      }
      return [];
    }
  }

  /// Get all deadlines (for admin)
  Future<List<Map<String, dynamic>>> _getAllDeadlines() async {
    try {
      final now = DateTime.now();
      final nextWeek = now.add(const Duration(days: 8));

      final snapshot = await _firestore
          .collection('calendar_events')
          .where('eventType', whereIn: ['deadline', 'filing', 'hearing'])
          .where('eventDate', isGreaterThan: Timestamp.fromDate(now))
          .where('eventDate', isLessThanOrEqualTo: Timestamp.fromDate(nextWeek))
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          ...data,
          'eventDate': (data['eventDate'] as Timestamp?)?.toDate(),
        };
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error getting all deadlines: $e');
      }
      return [];
    }
  }

  /// Process reminder for a single deadline
  Future<void> _processDeadlineReminder(
    Map<String, dynamic> deadline,
    String userId,
    String userRole,
  ) async {
    try {
      final deadlineId = deadline['id'] as String;
      final eventDate = deadline['eventDate'] as DateTime?;
      if (eventDate == null) return;

      final now = DateTime.now();

      // Calculate days until deadline (date-only comparison)
      final deadlineDateOnly = DateTime(
        eventDate.year,
        eventDate.month,
        eventDate.day,
      );
      final nowDateOnly = DateTime(now.year, now.month, now.day);
      final daysUntilDeadline = deadlineDateOnly.difference(nowDateOnly).inDays;

      // Check if we should send a reminder (7 days, 3 days, or 1 day before)
      // Only send if exactly 7, 3, or 1 day before (not less)
      int? reminderDays;
      if (daysUntilDeadline == 7) {
        reminderDays = 7;
      } else if (daysUntilDeadline == 3) {
        reminderDays = 3;
      } else if (daysUntilDeadline == 1) {
        reminderDays = 1;
      } else if (daysUntilDeadline < 0) {
        // Deadline has passed - no reminder needed
        return;
      } else {
        return; // Not time for reminder yet
      }

      // Create reminder key to avoid duplicates
      final reminderKey = '${deadlineId}_${userId}_${reminderDays}';
      if (_sentReminders.contains(reminderKey)) {
        return; // Already sent
      }

      // Check if reminder was already sent (stored in Firestore)
      final reminderSent = await _checkReminderSent(
        deadlineId,
        userId,
        reminderDays,
      );
      if (reminderSent) {
        _sentReminders.add(reminderKey);
        return;
      }

      // Get deadline details
      final title = deadline['title'] as String? ?? 'Important Deadline';
      final description = deadline['description'] as String? ?? '';
      final caseId = deadline['caseId'] as String?;

      // Format deadline date
      final dateFormat = DateFormat('MMM dd, yyyy');
      final dateStr = dateFormat.format(eventDate);

      // Create reminder message
      String reminderTitle;
      String reminderMessage;

      if (reminderDays == 7) {
        reminderTitle = '⏰ Deadline Reminder - 7 Days';
        reminderMessage = '$title is due in 7 days ($dateStr)';
      } else if (reminderDays == 3) {
        reminderTitle = '⚠️ Deadline Reminder - 3 Days';
        reminderMessage = '$title is due in 3 days ($dateStr)';
      } else {
        reminderTitle = '🚨 Urgent Deadline - Tomorrow';
        reminderMessage = '$title is due TOMORROW ($dateStr)';
      }

      if (description.isNotEmpty) {
        reminderMessage += '\n$description';
      }

      // Send notification with sound
      await _sendDeadlineReminder(
        userId: userId,
        title: reminderTitle,
        message: reminderMessage,
        deadlineId: deadlineId,
        caseId: caseId,
        eventDate: eventDate,
        reminderDays: reminderDays,
      );

      // Mark reminder as sent
      await _markReminderSent(deadlineId, userId, reminderDays);
      _sentReminders.add(reminderKey);

      if (kDebugMode) {
        debugPrint('✅ Sent $reminderDays-day reminder for deadline: $title');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ Error processing deadline reminder: $e');
        debugPrint('Stack trace: $stackTrace');
      }
    }
  }

  /// Send deadline reminder notification with sound
  Future<void> _sendDeadlineReminder({
    required String userId,
    required String title,
    required String message,
    required String deadlineId,
    String? caseId,
    required DateTime eventDate,
    required int reminderDays,
  }) async {
    try {
      // Send local notification with sound
      await _notificationService.showNotificationWithSound(
        id: deadlineId.hashCode + reminderDays,
        title: title,
        body: message,
        payload: 'deadline_$deadlineId',
      );

      // Also send FCM push notification
      try {
        await _fcmService.sendNotificationToUser(
          userId: userId,
          title: title,
          body: message,
          data: {
            'type': 'deadline_reminder',
            'deadlineId': deadlineId,
            'reminderDays': reminderDays.toString(),
            if (caseId != null) 'caseId': caseId,
          },
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Failed to send FCM notification: $e');
        }
        // Continue even if FCM fails
      }

      // Store notification in Firestore
      await _firestore.collection('notifications').add({
        'userId': userId,
        'type': 'deadline_reminder',
        'title': title,
        'message': message,
        'deadlineId': deadlineId,
        'caseId': caseId,
        'eventDate': Timestamp.fromDate(eventDate),
        'reminderDays': reminderDays,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error sending deadline reminder: $e');
      }
      rethrow;
    }
  }

  /// Check if reminder was already sent
  Future<bool> _checkReminderSent(
    String deadlineId,
    String userId,
    int reminderDays,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('deadline_reminders_sent')
          .where('deadlineId', isEqualTo: deadlineId)
          .where('userId', isEqualTo: userId)
          .where('reminderDays', isEqualTo: reminderDays)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error checking reminder sent: $e');
      }
      return false;
    }
  }

  /// Mark reminder as sent
  Future<void> _markReminderSent(
    String deadlineId,
    String userId,
    int reminderDays,
  ) async {
    try {
      await _firestore.collection('deadline_reminders_sent').add({
        'deadlineId': deadlineId,
        'userId': userId,
        'reminderDays': reminderDays,
        'sentAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error marking reminder as sent: $e');
      }
    }
  }

  /// Manually trigger deadline reminder check
  Future<void> checkDeadlinesNow() async {
    await _checkAndProcessDeadlineReminders();
  }
}
