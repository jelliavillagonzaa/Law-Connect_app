import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/appointment_model.dart';
import '../models/user_model.dart';
import '../utils/office_time_slots.dart';
import 'attorney_availability_service.dart';
import 'attorney_request_notify.dart';
import 'system_settings_service.dart';
import 'firestore_mirror_helper.dart';

class EnhancedAppointmentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Returned when the requested date/time is already booked.
  static const String scheduleFullCode = 'schedule_full';

  static final Set<String> _syncedSlotAttorneyIds = <String>{};

  static bool isScheduleFull(Map<String, dynamic> result) =>
      result['code'] == scheduleFullCode;

  /// Create a new appointment
  ///
  /// [status] defaults to 'upcoming' for attorney-scheduled appointments.
  /// Client-side requests should pass status: 'pending'.
  Future<Map<String, dynamic>> createAppointment({
    required String clientId,
    required String clientName,
    String? attorneyId,
    String? attorneyName,
    String? caseId,
    String? caseTitle,
    required DateTime appointmentDateTime,
    required String appointmentType,
    String? notes,
    String status = 'upcoming',
    bool notifyClient = true,
    bool notifyStaff = true,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      // For client requests (status == 'pending'), attorneyId MUST be provided
      // For attorney-scheduled appointments, attorneyId defaults to current user
      if (status == 'pending' && (attorneyId == null || attorneyId.isEmpty)) {
        return {
          'success': false,
          'message': 'Attorney ID is required for appointment requests',
        };
      }

      final finalAttorneyId = status == 'pending'
          ? attorneyId! // Client requests: attorneyId is required
          : (attorneyId ??
                currentUser.uid); // Attorney-scheduled: default to current user

      if (await isTimeSlotTaken(
        attorneyId: finalAttorneyId,
        dateTime: appointmentDateTime,
      )) {
        return _scheduleFullResult();
      }

      final appointmentId = _firestore.collection('appointments').doc().id;

      try {
        await _claimTimeSlot(
          attorneyId: finalAttorneyId,
          dateTime: appointmentDateTime,
          appointmentId: appointmentId,
        );
      } catch (_) {}

      try {
        final slotSnap = await _slotRef(
          finalAttorneyId,
          appointmentDateTime,
        ).get();
        if (slotSnap.exists) {
          final ownerId = slotSnap.data()?['appointmentId'] as String?;
          if (ownerId != null &&
              ownerId.isNotEmpty &&
              ownerId != appointmentId) {
            return _scheduleFullResult();
          }
        }
      } catch (_) {}

      var resolvedClientName = clientName.trim();
      if (resolvedClientName.isEmpty ||
          resolvedClientName.contains('@') ||
          (!resolvedClientName.contains(' ') && RegExp(r'\d{3,}').hasMatch(resolvedClientName))) {
        try {
          final clientDoc = await _firestore.collection('users').doc(clientId).get();
          if (clientDoc.exists && clientDoc.data() != null) {
            final docData = clientDoc.data()!;
            final resolved = UserModel.resolveDisplayName(docData).trim();
            if (resolved.isNotEmpty &&
                !resolved.contains('@') &&
                resolved.toLowerCase() != 'client' &&
                resolved.toLowerCase() != 'user' &&
                (resolved.contains(' ') || !RegExp(r'\d{3,}').hasMatch(resolved))) {
              resolvedClientName = resolved;
            }
          }
        } catch (_) {}
      }

      final appointment = AppointmentModel(
        id: appointmentId,
        clientId: clientId,
        clientName: resolvedClientName,
        attorneyId: finalAttorneyId,
        attorneyName: attorneyName,
        caseId: caseId,
        caseTitle: caseTitle,
        appointmentDateTime: appointmentDateTime,
        appointmentType: appointmentType,
        notes: notes,
        status: status,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final addResult = await HybridDatastore.set(
        collection: 'appointments',
        id: appointmentId,
        data: appointment.toFirestore(),
      );
      if (!addResult.isSuccess) {
        try {
          await _releaseTimeSlot(
            attorneyId: finalAttorneyId,
            dateTime: appointmentDateTime,
            appointmentId: appointmentId,
          );
        } catch (_) {}
        return {'success': false, 'message': addResult.failureMessage};
      }

      // Get creator name (who scheduled the appointment)
      final creatorDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final creatorName =
          creatorDoc.data()?['name'] ??
          creatorDoc.data()?['email'] ??
          'Someone';

      // Send immediate notifications based on preferences
      if (status == 'pending') {
        await _notifyAttorneyOfClientAppointmentRequest(
          appointmentId: appointmentId,
          attorneyId: finalAttorneyId,
          clientId: clientId,
          clientName: clientName,
          appointmentDateTime: appointmentDateTime,
          appointmentType: appointmentType,
        );
      } else {
        await _sendImmediateAppointmentNotifications(
          appointmentId: appointmentId,
          clientId: clientId,
          clientName: clientName,
          attorneyId: finalAttorneyId,
          appointmentDateTime: appointmentDateTime,
          appointmentType: appointmentType,
          creatorName: creatorName,
          notifyClient: notifyClient,
          notifyStaff: notifyStaff,
        );

        await _scheduleThreeDayAdvanceNotification(
          appointmentId: appointmentId,
          clientId: clientId,
          attorneyId: finalAttorneyId,
          appointmentDateTime: appointmentDateTime,
          appointmentType: appointmentType,
          clientName: clientName,
          creatorName: creatorName,
          notifyClient: notifyClient,
          notifyStaff: notifyStaff,
        );

        await _scheduleSameDayReminder(
          appointmentId: appointmentId,
          clientId: clientId,
          attorneyId: finalAttorneyId,
          appointmentDateTime: appointmentDateTime,
          appointmentType: appointmentType,
          clientName: clientName,
          creatorName: creatorName,
          notifyClient: notifyClient,
          notifyStaff: notifyStaff,
        );
      }

      if (status.toLowerCase() != 'pending') {
        try {
          await _mirrorAppointmentToCalendarEvent(
            appointmentId: appointmentId,
            attorneyId: finalAttorneyId,
            clientId: clientId,
            clientName: clientName,
            caseId: caseId,
            caseTitle: caseTitle,
            appointmentDateTime: appointmentDateTime,
            appointmentType: appointmentType,
            notes: notes,
          );
        } catch (_) {
          // `appointments` is source of truth; calendar mirror is best-effort.
        }
      }

      return {
        'success': true,
        'appointmentId': appointmentId,
        'message': 'Appointment created successfully',
      };
    } catch (e) {
      return {'success': false, 'message': 'Failed to create appointment: $e'};
    }
  }

  /// Get staff members assigned to an attorney
  Future<List<Map<String, dynamic>>> _getStaffByAttorneyId(
    String attorneyId,
  ) async {
    try {
      final staffSnapshot = await _firestore
          .collection('staff')
          .where('assignedAttorneyId', isEqualTo: attorneyId)
          .get();

      return staffSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? 'Staff Member',
          'email': data['email'] ?? '',
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get all admin users
  Future<List<Map<String, dynamic>>> _getAllAdmins() async {
    try {
      final adminsSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();

      return adminsSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? 'Admin',
          'email': data['email'] ?? '',
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Client submitted a pending appointment request — notify the attorney now.
  Future<void> _notifyAttorneyOfClientAppointmentRequest({
    required String appointmentId,
    required String attorneyId,
    required String clientId,
    required String clientName,
    required DateTime appointmentDateTime,
    required String appointmentType,
  }) async {
    try {
      final dateStr = DateFormat('MMM d, yyyy').format(appointmentDateTime);
      final timeStr = DateFormat('hh:mm a').format(appointmentDateTime);
      final typeLabel = appointmentType
          .replaceAll('_', ' ')
          .split(' ')
          .map((word) => word.isEmpty
              ? word
              : word[0].toUpperCase() + word.substring(1))
          .join(' ');
      final message =
          '$clientName requested a $typeLabel on $dateStr at $timeStr.';
      await AttorneyRequestNotify.notifyAttorneys(
        attorneyIds: [attorneyId],
        title: 'New Appointment Request',
        message: message,
        smsBody:
            'Law Connect: New appointment request from $clientName on $dateStr at $timeStr.',
        type: 'appointment_request',
        data: {
          'appointmentId': appointmentId,
          'clientId': clientId,
          'clientName': clientName,
        },
      );
    } catch (e) {
      print('Error notifying attorney of appointment request: $e');
    }
  }

  /// Send immediate notifications when appointment is scheduled
  Future<void> _sendImmediateAppointmentNotifications({
    required String appointmentId,
    required String clientId,
    required String clientName,
    required String attorneyId,
    required DateTime appointmentDateTime,
    required String appointmentType,
    required String creatorName,
    bool notifyClient = true,
    bool notifyStaff = true,
  }) async {
    try {
      final dateStr = DateFormat('MMM dd, yyyy').format(appointmentDateTime);
      final timeStr = DateFormat('hh:mm a').format(appointmentDateTime);
      final appointmentTypeStr = appointmentType
          .replaceAll('_', ' ')
          .split(' ')
          .map((word) => word[0].toUpperCase() + word.substring(1))
          .join(' ');

      // Notification message
      final message =
          'Appointment scheduled by $creatorName on $dateStr at $timeStr ($appointmentTypeStr)';

      // 1. Notify ATTORNEY (always notified)
      await _createNotification(
        userId: attorneyId,
        type: 'appointment_scheduled',
        title: 'Appointment Scheduled',
        message: message,
        appointmentId: appointmentId,
      );

      // 2. Notify CLIENT (if checked)
      if (notifyClient) {
        await _createNotification(
          userId: clientId,
          type: 'appointment_scheduled',
          title: 'Appointment Scheduled',
          message: message,
          appointmentId: appointmentId,
        );
      }

      // 3. Notify STAFF assigned to attorney (if checked)
      if (notifyStaff) {
        final staffMembers = await _getStaffByAttorneyId(attorneyId);
        for (final staff in staffMembers) {
          await _createNotification(
            userId: staff['id'] as String,
            type: 'appointment_scheduled',
            title: 'Appointment Scheduled',
            message: message,
            appointmentId: appointmentId,
          );
        }
      }
    } catch (e) {
      // Ignore notification errors - don't fail appointment creation
      print('Error sending immediate notifications: $e');
    }
  }

  /// Schedule 3-day advance notification
  Future<void> _scheduleThreeDayAdvanceNotification({
    required String appointmentId,
    required String clientId,
    required String attorneyId,
    required DateTime appointmentDateTime,
    required String appointmentType,
    required String clientName,
    required String creatorName,
    bool notifyClient = true,
    bool notifyStaff = true,
  }) async {
    try {
      // Calculate 3 days before appointment
      final threeDaysBefore = appointmentDateTime.subtract(
        const Duration(days: 3),
      );

      // Only schedule if the appointment is more than 3 days away
      if (threeDaysBefore.isBefore(DateTime.now())) {
        return; // Appointment is less than 3 days away, skip scheduling
      }

      final dateStr = DateFormat('MMM dd, yyyy').format(appointmentDateTime);
      final timeStr = DateFormat('hh:mm a').format(appointmentDateTime);
      final appointmentTypeStr = appointmentType
          .replaceAll('_', ' ')
          .split(' ')
          .map((word) => word[0].toUpperCase() + word.substring(1))
          .join(' ');

      final message =
          'Reminder: Appointment with $clientName on $dateStr at $timeStr ($appointmentTypeStr)';

      // Create scheduled notification document
      final notificationData = {
        'type': 'appointment_3day_reminder',
        'appointmentId': appointmentId,
        'scheduledFor': Timestamp.fromDate(threeDaysBefore),
        'appointmentDateTime': Timestamp.fromDate(appointmentDateTime),
        'title': 'Appointment Reminder (3 Days)',
        'message': message,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'recipients': {'clientId': clientId, 'attorneyId': attorneyId},
      };

      await _firestore
          .collection('scheduled_notifications')
          .add(notificationData);

      // Also create a Cloud Function trigger document for 3-day reminder
      // This will be processed by a Cloud Function scheduled task
      final reminderData = <String, dynamic>{
        'appointmentId': appointmentId,
        'clientId': clientId,
        'attorneyId': attorneyId,
        'clientName': clientName,
        'appointmentDateTime': Timestamp.fromDate(appointmentDateTime),
        'appointmentType': appointmentType,
        'threeDayReminderDate': Timestamp.fromDate(threeDaysBefore),
        'creatorName': creatorName,
        'notifyClient': notifyClient,
        'notifyStaff': notifyStaff,
        'status': 'pending',
        'notificationsSent': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await HybridDatastore.set(
        collection: 'appointment_reminders',
        id: appointmentId,
        data: reminderData,
      );
    } catch (e) {
      // Ignore scheduling errors
      print('Error scheduling 3-day advance notification: $e');
    }
  }

  /// Schedule same-day morning reminder (on the day of appointment)
  Future<void> _scheduleSameDayReminder({
    required String appointmentId,
    required String clientId,
    required String attorneyId,
    required DateTime appointmentDateTime,
    required String appointmentType,
    required String clientName,
    required String creatorName,
    bool notifyClient = true,
    bool notifyStaff = true,
  }) async {
    try {
      // Calculate same day at 8:00 AM (morning reminder)
      final appointmentDate = DateTime(
        appointmentDateTime.year,
        appointmentDateTime.month,
        appointmentDateTime.day,
      );
      final sameDayMorning = appointmentDate.add(const Duration(hours: 8));

      // Only schedule if the appointment is in the future
      if (sameDayMorning.isBefore(DateTime.now())) {
        return; // Appointment day has passed, skip scheduling
      }

      // Create reminder document for same-day reminder
      final sameDayId = '${appointmentId}_sameday';
      final sameDayData = <String, dynamic>{
        'appointmentId': appointmentId,
        'clientId': clientId,
        'attorneyId': attorneyId,
        'clientName': clientName,
        'creatorName': creatorName,
        'notifyClient': notifyClient,
        'notifyStaff': notifyStaff,
        'appointmentDateTime': Timestamp.fromDate(appointmentDateTime),
        'appointmentType': appointmentType,
        'sameDayReminderDate': Timestamp.fromDate(sameDayMorning),
        'reminderType': 'sameday',
        'status': 'pending',
        'notificationsSent': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await HybridDatastore.set(
        collection: 'appointment_reminders',
        id: sameDayId,
        data: sameDayData,
      );
    } catch (e) {
      // Ignore scheduling errors
      print('Error scheduling same-day reminder: $e');
    }
  }

  /// Create a notification in Firestore
  Future<void> _createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String? appointmentId,
  }) async {
    try {
      final notifData = <String, dynamic>{
        'userId': userId,
        'type': type,
        'title': title,
        'message': message,
        if (appointmentId != null) 'appointmentId': appointmentId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await HybridDatastore.add(collection: 'notifications', data: notifData);
    } catch (e) {
      // Ignore individual notification failures
      print('Error creating notification for user $userId: $e');
    }
  }

  /// Process and send 3-day advance notifications
  /// This should be called by a Cloud Function scheduled task daily
  Future<void> processThreeDayReminders() async {
    try {
      final settings = await SystemSettingsService.instance.load();
      if (!settings.appointmentReminders) return;

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      // Find appointments with 3-day reminder date today
      final remindersSnapshot = await _firestore
          .collection('appointment_reminders')
          .where(
            'threeDayReminderDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
          )
          .where(
            'threeDayReminderDate',
            isLessThan: Timestamp.fromDate(todayEnd),
          )
          .where('notificationsSent', isEqualTo: false)
          .get();

      for (final reminderDoc in remindersSnapshot.docs) {
        final data = reminderDoc.data();
        final appointmentId = data['appointmentId'] as String;
        final clientId = data['clientId'] as String;
        final attorneyId = data['attorneyId'] as String;
        final clientName = data['clientName'] as String? ?? 'Client';
        final appointmentDateTime = (data['appointmentDateTime'] as Timestamp)
            .toDate();
        final appointmentType =
            data['appointmentType'] as String? ?? 'in_office';

        // Send 3-day advance notifications
        final creatorName = data['creatorName'] as String? ?? 'Someone';
        final notifyClient = data['notifyClient'] as bool? ?? true;
        final notifyStaff = data['notifyStaff'] as bool? ?? true;
        await _sendThreeDayAdvanceNotifications(
          appointmentId: appointmentId,
          clientId: clientId,
          attorneyId: attorneyId,
          clientName: clientName,
          creatorName: creatorName,
          appointmentDateTime: appointmentDateTime,
          appointmentType: appointmentType,
          notifyClient: notifyClient,
          notifyStaff: notifyStaff,
        );

        // Mark as sent
        await reminderDoc.reference.update({
          'notificationsSent': true,
          'notificationsSentAt': FieldValue.serverTimestamp(),
        });
      }

      // Also process same-day reminders (morning reminders on appointment day)
      await _processSameDayReminders();
    } catch (e) {
      print('Error processing reminders: $e');
    }
  }

  /// Process same-day morning reminders
  Future<void> _processSameDayReminders() async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final morningTime = todayStart.add(const Duration(hours: 8)); // 8:00 AM
      final morningEnd = todayStart.add(const Duration(hours: 9)); // 9:00 AM

      // Find same-day reminders scheduled for this morning (8-9 AM)
      final sameDayRemindersSnapshot = await _firestore
          .collection('appointment_reminders')
          .where(
            'sameDayReminderDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(morningTime),
          )
          .where(
            'sameDayReminderDate',
            isLessThan: Timestamp.fromDate(morningEnd),
          )
          .where('reminderType', isEqualTo: 'sameday')
          .where('notificationsSent', isEqualTo: false)
          .get();

      for (final reminderDoc in sameDayRemindersSnapshot.docs) {
        final data = reminderDoc.data();
        final appointmentId = data['appointmentId'] as String;
        final clientId = data['clientId'] as String;
        final attorneyId = data['attorneyId'] as String;
        final clientName = data['clientName'] as String? ?? 'Client';
        final creatorName = data['creatorName'] as String? ?? 'Someone';
        final appointmentDateTime = (data['appointmentDateTime'] as Timestamp)
            .toDate();
        final appointmentType =
            data['appointmentType'] as String? ?? 'in_office';

        // Send same-day morning notifications
        final notifyClient = data['notifyClient'] as bool? ?? true;
        final notifyStaff = data['notifyStaff'] as bool? ?? true;
        await _sendSameDayReminders(
          appointmentId: appointmentId,
          clientId: clientId,
          attorneyId: attorneyId,
          clientName: clientName,
          creatorName: creatorName,
          appointmentDateTime: appointmentDateTime,
          appointmentType: appointmentType,
          notifyClient: notifyClient,
          notifyStaff: notifyStaff,
        );

        // Mark as sent
        await reminderDoc.reference.update({
          'notificationsSent': true,
          'notificationsSentAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error processing same-day reminders: $e');
    }
  }

  /// Send 3-day advance notifications to admin, staff, and client
  Future<void> _sendThreeDayAdvanceNotifications({
    required String appointmentId,
    required String clientId,
    required String attorneyId,
    required String clientName,
    required String creatorName,
    required DateTime appointmentDateTime,
    required String appointmentType,
    bool notifyClient = true,
    bool notifyStaff = true,
  }) async {
    try {
      final dateStr = DateFormat('MMM dd, yyyy').format(appointmentDateTime);
      final timeStr = DateFormat('hh:mm a').format(appointmentDateTime);
      final appointmentTypeStr = appointmentType
          .replaceAll('_', ' ')
          .split(' ')
          .map((word) => word[0].toUpperCase() + word.substring(1))
          .join(' ');

      final detail =
          'Reminder: Appointment with $clientName (scheduled by $creatorName) on $dateStr at $timeStr ($appointmentTypeStr)';
      final settings = await SystemSettingsService.instance.load();
      final message = settings.emailNotifications
          ? settings.applyTemplate(settings.appointmentEmail, detail, {
              'name': clientName,
              'date': dateStr,
              'time': timeStr,
            })
          : detail;

      // 1. Notify ATTORNEY (always notified)
      await _createNotification(
        userId: attorneyId,
        type: 'appointment_3day_reminder',
        title: 'Appointment Reminder (3 Days)',
        message: message,
        appointmentId: appointmentId,
      );

      // 2. Notify CLIENT (if checked)
      if (notifyClient) {
        await _createNotification(
          userId: clientId,
          type: 'appointment_3day_reminder',
          title: 'Appointment Reminder (3 Days)',
          message: message,
          appointmentId: appointmentId,
        );
      }

      // 3. Notify STAFF assigned to attorney (if checked)
      if (notifyStaff) {
        final staffMembers = await _getStaffByAttorneyId(attorneyId);
        for (final staff in staffMembers) {
          await _createNotification(
            userId: staff['id'] as String,
            type: 'appointment_3day_reminder',
            title: 'Appointment Reminder (3 Days)',
            message: message,
            appointmentId: appointmentId,
          );
        }
      }

      // 4. Notify ALL ADMINS
      final admins = await _getAllAdmins();
      for (final admin in admins) {
        await _createNotification(
          userId: admin['id'] as String,
          type: 'appointment_3day_reminder',
          title: 'Appointment Reminder (3 Days)',
          message: message,
          appointmentId: appointmentId,
        );
      }
    } catch (e) {
      print('Error sending 3-day advance notifications: $e');
    }
  }

  /// Send same-day morning reminders to client, attorney, and staff
  Future<void> _sendSameDayReminders({
    required String appointmentId,
    required String clientId,
    required String attorneyId,
    required String clientName,
    required String creatorName,
    required DateTime appointmentDateTime,
    required String appointmentType,
    bool notifyClient = true,
    bool notifyStaff = true,
  }) async {
    try {
      final timeStr = DateFormat('hh:mm a').format(appointmentDateTime);
      final appointmentTypeStr = appointmentType
          .replaceAll('_', ' ')
          .split(' ')
          .map((word) => word[0].toUpperCase() + word.substring(1))
          .join(' ');

      final message =
          'Reminder: You have an appointment TODAY with $clientName (scheduled by $creatorName) at $timeStr ($appointmentTypeStr)';

      // 1. Notify ATTORNEY (always notified)
      await _createNotification(
        userId: attorneyId,
        type: 'appointment_sameday_reminder',
        title: 'Appointment Today',
        message: message,
        appointmentId: appointmentId,
      );

      // 2. Notify CLIENT (if checked)
      if (notifyClient) {
        await _createNotification(
          userId: clientId,
          type: 'appointment_sameday_reminder',
          title: 'Appointment Today',
          message: message,
          appointmentId: appointmentId,
        );
      }

      // 3. Notify STAFF assigned to attorney (if checked)
      if (notifyStaff) {
        final staffMembers = await _getStaffByAttorneyId(attorneyId);
        for (final staff in staffMembers) {
          await _createNotification(
            userId: staff['id'] as String,
            type: 'appointment_sameday_reminder',
            title: 'Appointment Today',
            message: message,
            appointmentId: appointmentId,
          );
        }
      }
    } catch (e) {
      print('Error sending same-day reminders: $e');
    }
  }

  /// Create a confirmed appointment from a pending request and handle
  /// all related side effects.
  ///
  /// - Create a new document in `appointments` with status `confirmed`
  /// - Update the original request (status `accepted`, link to new appointment)
  /// - Try to create a notification for the client (best-effort; failures are ignored)
  Future<Map<String, dynamic>> createConfirmedAppointment({
    required AppointmentModel request,
    required DateTime finalDateTime,
    required String appointmentType,
    String? notes,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      final effectiveAttorneyId = (request.attorneyId != null &&
              request.attorneyId!.trim().isNotEmpty)
          ? request.attorneyId!.trim()
          : currentUser.uid;

      if (await isTimeSlotTaken(
        attorneyId: effectiveAttorneyId,
        dateTime: finalDateTime,
        excludeAppointmentId: request.id,
      )) {
        return _scheduleFullResult();
      }

      final batch = _firestore.batch();
      final appointmentsRef = _firestore.collection('appointments');
      final newAppointmentRef = appointmentsRef.doc();

      final now = FieldValue.serverTimestamp();

      var effectiveClientName = request.clientName.trim();
      if (effectiveClientName.isEmpty ||
          effectiveClientName.contains('@') ||
          (!effectiveClientName.contains(' ') && RegExp(r'\d{3,}').hasMatch(effectiveClientName))) {
        try {
          final clientDoc = await _firestore.collection('users').doc(request.clientId).get();
          if (clientDoc.exists && clientDoc.data() != null) {
            final resolved = UserModel.resolveDisplayName(clientDoc.data()!).trim();
            if (resolved.isNotEmpty && !resolved.contains('@')) {
              effectiveClientName = resolved;
            }
          }
        } catch (_) {}
      }

      // 1. Confirmed appointment document
      batch.set(newAppointmentRef, {
        'clientId': request.clientId,
        'clientName': effectiveClientName,
        'attorneyId': effectiveAttorneyId,
        'attorneyName': request.attorneyName,
        'caseId': request.caseId,
        'caseTitle': request.caseTitle,
        // Primary datetime used throughout the app
        'appointmentDateTime': Timestamp.fromDate(finalDateTime),
        // Also store explicit finalDate/finalTime for analytics / future UI
        'finalDate': Timestamp.fromDate(finalDateTime),
        'finalTime': Timestamp.fromDate(finalDateTime),
        'appointmentType': appointmentType,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'status': 'confirmed',
        'requestId': request.id,
        'createdAt': now,
        'updatedAt': now,
      });

      // 2. Update original request_appointment document
      final requestRef = _firestore.collection('appointments').doc(request.id);
      batch.update(requestRef, {
        'status': 'accepted',
        'linkedAppointmentId': newAppointmentRef.id,
        'updatedAt': now,
      });

      // Commit appointment + request updates in one atomic batch
      await batch.commit();

      try {
        final requestedSlot = _minuteTruncated(request.appointmentDateTime);
        final finalSlot = _minuteTruncated(finalDateTime);
        if (requestedSlot != finalSlot) {
          await _releaseTimeSlot(
            attorneyId: effectiveAttorneyId,
            dateTime: request.appointmentDateTime,
            appointmentId: request.id,
          );
        }
        await _claimTimeSlot(
          attorneyId: effectiveAttorneyId,
          dateTime: finalDateTime,
          appointmentId: newAppointmentRef.id,
          overwrite: true,
        );
      } catch (_) {}

      try {
        await _removeMirroredAppointmentCalendarEvent(request.id);
        await _mirrorAppointmentToCalendarEvent(
          appointmentId: newAppointmentRef.id,
          attorneyId: currentUser.uid,
          clientId: request.clientId,
          clientName: request.clientName,
          caseId: request.caseId,
          caseTitle: request.caseTitle,
          appointmentDateTime: finalDateTime,
          appointmentType: appointmentType,
          notes: notes,
        );
      } catch (_) {}

      // Get attorney name for notifications
      final attorneyDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final attorneyName = attorneyDoc.data()?['name'] ?? 'Attorney';

      // Send immediate notifications to staff, client, and attorney
      await _sendImmediateAppointmentNotifications(
        appointmentId: newAppointmentRef.id,
        clientId: request.clientId,
        clientName: request.clientName,
        attorneyId: currentUser.uid,
        appointmentDateTime: finalDateTime,
        appointmentType: appointmentType,
        creatorName: attorneyName,
      );

      // Schedule 3-day advance notification
      await _scheduleThreeDayAdvanceNotification(
        appointmentId: newAppointmentRef.id,
        clientId: request.clientId,
        attorneyId: effectiveAttorneyId,
        appointmentDateTime: finalDateTime,
        appointmentType: appointmentType,
        clientName: request.clientName,
        creatorName: attorneyName,
      );

      // Schedule same-day morning reminder
      await _scheduleSameDayReminder(
        appointmentId: newAppointmentRef.id,
        clientId: request.clientId,
        attorneyId: effectiveAttorneyId,
        appointmentDateTime: finalDateTime,
        appointmentType: appointmentType,
        clientName: request.clientName,
        creatorName: attorneyName,
      );

      // 3. Best-effort notification for the client (legacy support)
      // This is intentionally outside the batch so that stricter
      // security rules on `notifications` do not block the core flow.
      try {
        final notifData = <String, dynamic>{
          'type': 'appointment_accepted',
          'clientId': request.clientId,
          'attorneyId': effectiveAttorneyId,
          'appointmentId': newAppointmentRef.id,
          'title': 'Appointment Accepted',
          'message':
              'Your appointment request has been accepted and scheduled.',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        };
        await HybridDatastore.add(collection: 'notifications', data: notifData);
      } catch (_) {
        // Ignore notification write failures (e.g. permission-denied)
      }

      return {
        'success': true,
        'appointmentId': newAppointmentRef.id,
        'message': 'Appointment confirmed successfully',
      };
    } catch (e) {
      return {'success': false, 'message': 'Failed to confirm appointment: $e'};
    }
  }

  /// Get appointments for attorney
  Stream<List<AppointmentModel>> getAttorneyAppointments(String attorneyId) {
    // Avoid Firestore composite index requirement by sorting in memory
    return _firestore
        .collection('appointments')
        .where('attorneyId', isEqualTo: attorneyId)
        .limit(80)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => AppointmentModel.fromFirestore(doc))
              .toList();
          list.sort(
            (a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime),
          );
          return list;
        });
  }

  /// Get appointments for client
  Stream<List<AppointmentModel>> getClientAppointments(String clientId) {
    // Avoid Firestore composite index requirement by sorting in memory
    return _firestore
        .collection('appointments')
        .where('clientId', isEqualTo: clientId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => AppointmentModel.fromFirestore(doc))
              .toList();
          list.sort(
            (a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime),
          );
          return list;
        });
  }

  /// Update appointment
  Future<Map<String, dynamic>> updateAppointment(
    String appointmentId, {
    DateTime? appointmentDateTime,
    String? appointmentType,
    String? notes,
    String? status,
  }) async {
    try {
      final currentSnap = await _firestore
          .collection('appointments')
          .doc(appointmentId)
          .get();
      final currentData = currentSnap.data();
      final oldDateTime = currentData == null
          ? null
          : AppointmentModel.fromFirestore(currentSnap).appointmentDateTime;
      final oldStatus = (currentData?['status'] as String?) ?? '';
      final attorneyId = (currentData?['attorneyId'] as String?) ?? '';

      if (appointmentDateTime != null && attorneyId.isNotEmpty) {
        if (await isTimeSlotTaken(
          attorneyId: attorneyId,
          dateTime: appointmentDateTime,
          excludeAppointmentId: appointmentId,
        )) {
          return _scheduleFullResult();
        }
      }

      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (appointmentDateTime != null) {
        updateData['appointmentDateTime'] = Timestamp.fromDate(
          appointmentDateTime,
        );
      }
      if (appointmentType != null)
        updateData['appointmentType'] = appointmentType;
      if (notes != null) updateData['notes'] = notes;
      if (status != null) updateData['status'] = status;

      await _firestore
          .collection('appointments')
          .doc(appointmentId)
          .update(updateData);

      final nextStatus = (status ?? oldStatus).toLowerCase();
      final nextDateTime = appointmentDateTime ?? oldDateTime;
      if (attorneyId.isNotEmpty) {
        try {
          if (oldDateTime != null) {
            await _releaseTimeSlot(
              attorneyId: attorneyId,
              dateTime: oldDateTime,
              appointmentId: appointmentId,
            );
          }
          if (nextDateTime != null && _statusOccupiesSlot(nextStatus)) {
            await _claimTimeSlot(
              attorneyId: attorneyId,
              dateTime: nextDateTime,
              appointmentId: appointmentId,
            );
          }
        } catch (_) {}
      }

      if (appointmentDateTime != null) {
        try {
          final snap = await _firestore
              .collection('appointments')
              .doc(appointmentId)
              .get();
          final d = snap.data();
          if (d != null) {
            await _mirrorAppointmentToCalendarEvent(
              appointmentId: appointmentId,
              attorneyId: (d['attorneyId'] as String?) ?? '',
              clientId: (d['clientId'] as String?) ?? '',
              clientName: (d['clientName'] as String?) ?? 'Client',
              caseId: d['caseId'] as String?,
              caseTitle: d['caseTitle'] as String?,
              appointmentDateTime: appointmentDateTime,
              appointmentType:
                  (d['appointmentType'] as String?) ?? 'meeting_office',
              notes: d['notes'] as String?,
            );
          }
        } catch (_) {}
      }

      return {'success': true, 'message': 'Appointment updated successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to update appointment: $e'};
    }
  }

  /// Update the status (and optional decline reason) of a request_appointment
  /// document. This is used for attorney-side accept/decline flows.
  Future<Map<String, dynamic>> updateRequestStatus(
    String requestId, {
    required String status,
    String? declineReason,
  }) async {
    try {
      // Load request to know who to notify
      final requestDoc = await _firestore
          .collection('appointments')
          .doc(requestId)
          .get();
      if (!requestDoc.exists) {
        return {'success': false, 'message': 'Request not found'};
      }
      final data = requestDoc.data() as Map<String, dynamic>;
      final String? clientId = data['clientId'] as String?;
      final String? existingAttorneyId = data['attorneyId'] as String?;
      final String? currentAttorneyId = _auth.currentUser?.uid;

      final updateData = <String, dynamic>{
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (declineReason != null && declineReason.trim().isNotEmpty) {
        updateData['declineReason'] = declineReason.trim();
      }

      await requestDoc.reference.update(updateData);

      final lowered = status.toLowerCase();
      if (lowered == 'declined' || lowered == 'cancelled') {
        try {
          final apt = AppointmentModel.fromFirestore(requestDoc);
          final attorneyIdForSlot =
              existingAttorneyId ?? currentAttorneyId ?? '';
          if (attorneyIdForSlot.isNotEmpty) {
            await _releaseTimeSlot(
              attorneyId: attorneyIdForSlot,
              dateTime: apt.appointmentDateTime,
              appointmentId: requestId,
            );
          }
          await _removeMirroredAppointmentCalendarEvent(requestId);
        } catch (_) {}
      }

      // Best-effort client notification (outside main try/catch below)
      try {
        if (clientId != null && clientId.isNotEmpty) {
          String type;
          String title;
          String message;

          if (status.toLowerCase() == 'declined') {
            type = 'appointment_declined';
            title = 'Appointment Declined';
            message = declineReason != null && declineReason.trim().isNotEmpty
                ? 'Your appointment request was declined: ${declineReason.trim()}'
                : 'Your appointment request was declined.';
          } else if (status.toLowerCase() == 'accepted') {
            // Fallback path if updateRequestStatus is ever used for accept
            type = 'appointment_accepted';
            title = 'Appointment Accepted';
            message = 'Your appointment request has been accepted.';
          } else {
            type = 'appointment_updated';
            title = 'Appointment Updated';
            message = 'Your appointment request status changed to $status.';
          }

          final notifData = <String, dynamic>{
            'type': type,
            'clientId': clientId,
            'attorneyId': existingAttorneyId ?? currentAttorneyId,
            'appointmentId': requestId,
            'title': title,
            'message': message,
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
          };
          await HybridDatastore.add(
            collection: 'notifications',
            data: notifData,
          );
        }
      } catch (_) {
        // Ignore notification failures
      }

      return {'success': true, 'message': 'Request updated successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to update request: $e'};
    }
  }

  /// Complete appointment
  Future<Map<String, dynamic>> completeAppointment(String appointmentId) async {
    return updateAppointment(appointmentId, status: 'completed');
  }

  /// Cancel appointment
  Future<Map<String, dynamic>> cancelAppointment(String appointmentId) async {
    return updateAppointment(appointmentId, status: 'cancelled');
  }

  /// Reschedule appointment
  Future<Map<String, dynamic>> rescheduleAppointment(
    String appointmentId,
    DateTime newDateTime,
  ) async {
    return updateAppointment(
      appointmentId,
      appointmentDateTime: newDateTime,
      status: 'rescheduled',
    );
  }

  static String calendarEventDocIdForAppointment(String appointmentId) =>
      'appt_$appointmentId';

  Map<String, dynamic> _scheduleFullResult() => {
        'success': false,
        'code': scheduleFullCode,
        'message':
            'The schedule for this day is already full at the selected time.',
      };

  DateTime _minuteTruncated(DateTime dateTime) => DateTime(
        dateTime.year,
        dateTime.month,
        dateTime.day,
        dateTime.hour,
        dateTime.minute,
      );

  bool _statusOccupiesSlot(String status) {
    switch (status.toLowerCase().trim()) {
      case 'upcoming':
      case 'confirmed':
      case 'scheduled':
      case 'rescheduled':
        return true;
      default:
        return false;
    }
  }

  bool _statusBlocksSlot(String status) {
    switch (status.toLowerCase().trim()) {
      case 'pending':
      case 'upcoming':
      case 'confirmed':
      case 'scheduled':
      case 'rescheduled':
        return true;
      default:
        return false;
    }
  }

  String _slotDocId(String attorneyId, DateTime dateTime) {
    final slot = _minuteTruncated(dateTime);
    final y = slot.year.toString().padLeft(4, '0');
    final m = slot.month.toString().padLeft(2, '0');
    final d = slot.day.toString().padLeft(2, '0');
    final h = slot.hour.toString().padLeft(2, '0');
    final min = slot.minute.toString().padLeft(2, '0');
    return '${attorneyId}_${y}${m}${d}_$h$min';
  }

  DocumentReference<Map<String, dynamic>> _slotRef(
    String attorneyId,
    DateTime dateTime,
  ) {
    return _firestore
        .collection('appointment_slots')
        .doc(_slotDocId(attorneyId, dateTime));
  }

  /// True when this attorney already has a confirmed booking (or hearing)
  /// at the same date and time.
  Future<bool> isTimeSlotTaken({
    required String attorneyId,
    required DateTime dateTime,
    String? excludeAppointmentId,
  }) async {
    if (attorneyId.isEmpty) return false;
    final target = _minuteTruncated(dateTime);
    final window = OfficeTimeSlots.windowStart(dateTime);

    if (window != null &&
        await AttorneyAvailabilityService().isWindowTaken(
          attorneyId: attorneyId,
          dateTime: window,
          exceptHolderId: excludeAppointmentId,
        )) {
      return true;
    }

    try {
      final slotSnap = await _slotRef(attorneyId, target).get();
      if (slotSnap.exists) {
        final existingId = slotSnap.data()?['appointmentId'] as String?;
        if (excludeAppointmentId == null ||
            existingId == null ||
            existingId != excludeAppointmentId) {
          return true;
        }
      }
    } catch (_) {}

    try {
      final snap = await _firestore
          .collection('appointments')
          .where('attorneyId', isEqualTo: attorneyId)
          .get();
      for (final doc in snap.docs) {
        if (excludeAppointmentId != null && doc.id == excludeAppointmentId) {
          continue;
        }
        final apt = AppointmentModel.fromFirestore(doc);
        if (!_statusBlocksSlot(apt.status)) continue;
        if (window != null) {
          if (OfficeTimeSlots.occupies(window, apt.appointmentDateTime)) {
            return true;
          }
        } else if (_minuteTruncated(apt.appointmentDateTime) == target) {
          return true;
        }
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') {
        // Ignore; slot doc is the client-safe source of truth.
      }
    } catch (_) {}

    try {
      final events = await _firestore
          .collection('calendar_events')
          .where('assignedTo', isEqualTo: attorneyId)
          .get();
      for (final doc in events.docs) {
        final data = doc.data();
        final type = (data['eventType'] as String?)?.toLowerCase() ?? '';
        if (type != 'hearing' && type != 'deadline' && type != 'filing') {
          continue;
        }
        final raw = data['eventDate'];
        DateTime? eventDate;
        if (raw is Timestamp) eventDate = raw.toDate();
        if (raw is DateTime) eventDate = raw;
        if (eventDate == null) continue;
        if (type == 'hearing' && window != null) {
          if (OfficeTimeSlots.occupies(window, eventDate)) return true;
          continue;
        }
        if (_minuteTruncated(eventDate) == target) return true;
      }
    } catch (_) {}

    return false;
  }

  Future<void> _claimTimeSlot({
    required String attorneyId,
    required DateTime dateTime,
    required String appointmentId,
    bool overwrite = false,
  }) async {
    if (attorneyId.isEmpty || appointmentId.isEmpty) return;
    final slot = _minuteTruncated(dateTime);
    final ref = _slotRef(attorneyId, slot);
    final existing = await ref.get();
    if (existing.exists && !overwrite) {
      final existingId = existing.data()?['appointmentId'] as String?;
      if (existingId != null &&
          existingId.isNotEmpty &&
          existingId != appointmentId) {
        return;
      }
    }
    await ref.set({
      'attorneyId': attorneyId,
      'appointmentId': appointmentId,
      'startAt': Timestamp.fromDate(slot),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _releaseTimeSlot({
    required String attorneyId,
    required DateTime dateTime,
    required String appointmentId,
  }) async {
    if (attorneyId.isEmpty) return;
    final ref = _slotRef(attorneyId, dateTime);
    try {
      final snap = await ref.get();
      if (!snap.exists) return;
      final existingId = snap.data()?['appointmentId'] as String?;
      if (existingId != null &&
          existingId.isNotEmpty &&
          existingId != appointmentId) {
        return;
      }
      await ref.delete();
    } catch (_) {}
  }

  /// Writes missing occupancy docs for already-confirmed appointments so
  /// later client requests can detect a full slot.
  Future<void> syncOccupiedTimeSlotsIfNeeded(
    String attorneyId,
    List<AppointmentModel> appointments,
  ) async {
    final aid = attorneyId.trim();
    if (aid.isEmpty || _syncedSlotAttorneyIds.contains(aid)) return;
    _syncedSlotAttorneyIds.add(aid);

    for (final apt in appointments) {
      if (!_statusBlocksSlot(apt.status) || apt.id.isEmpty) continue;
      try {
        final ref = _slotRef(aid, apt.appointmentDateTime);
        final snap = await ref.get();
        if (!snap.exists) {
          await _claimTimeSlot(
            attorneyId: aid,
            dateTime: apt.appointmentDateTime,
            appointmentId: apt.id,
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _removeMirroredAppointmentCalendarEvent(
    String appointmentId,
  ) async {
    if (appointmentId.isEmpty) return;
    try {
      await _firestore
          .collection('calendar_events')
          .doc(calendarEventDocIdForAppointment(appointmentId))
          .delete();
    } catch (_) {}
  }

  /// Manual client appointments (not AI hearings) — shown on attorney day dialog.
  Future<void> _mirrorAppointmentToCalendarEvent({
    required String appointmentId,
    required String attorneyId,
    required String clientId,
    required String clientName,
    String? caseId,
    String? caseTitle,
    required DateTime appointmentDateTime,
    required String appointmentType,
    String? notes,
  }) async {
    if (appointmentId.isEmpty || attorneyId.isEmpty) return;

    final title = clientName.trim().isNotEmpty
        ? clientName.trim()
        : _calendarTitleForAppointmentType(appointmentType);

    final payload = <String, dynamic>{
      'eventType': 'appointment',
      'eventDate': Timestamp.fromDate(appointmentDateTime),
      'title': title,
      'assignedTo': attorneyId,
      'source': 'manual',
      'clientId': clientId,
      'clientName': clientName,
      'appointmentId': appointmentId,
      'appointmentType': appointmentType,
      'readOnly': false,
      'updatedAt': FieldValue.serverTimestamp(),
      if (caseId != null && caseId.trim().isNotEmpty) 'caseId': caseId.trim(),
      if (caseTitle != null && caseTitle.trim().isNotEmpty)
        'caseTitle': caseTitle.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };

    final ref = _firestore
        .collection('calendar_events')
        .doc(calendarEventDocIdForAppointment(appointmentId));

    final existing = await ref.get();
    if (!existing.exists) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      payload['createdBy'] = _auth.currentUser?.uid ?? attorneyId;
      payload['createdByRole'] = 'attorney';
      payload['notificationSent'] = false;
      payload['remindAttorney'] = false;
      payload['remindClient'] = false;
      payload['selectedClientIds'] = <String>[];
      payload['notifyStaff'] = false;
    }

    await ref.set(payload, SetOptions(merge: true));
  }

  String _calendarTitleForAppointmentType(String type) {
    switch (type) {
      case 'meeting_office':
      case 'in_office':
        return 'Office meeting';
      case 'phone_call':
        return 'Phone call';
      case 'online_meeting':
        return 'Online meeting';
      case 'hearing_court':
        return 'Court hearing';
      case 'consultation':
        return 'Consultation';
      default:
        return 'Client appointment';
    }
  }
}
