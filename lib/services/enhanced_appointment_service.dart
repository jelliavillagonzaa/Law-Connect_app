import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/appointment_model.dart';

class EnhancedAppointmentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

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

      final appointment = AppointmentModel(
        id: '', // Will be set by Firestore
        clientId: clientId,
        clientName: clientName,
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

      final docRef = await _firestore
          .collection('appointments')
          .add(appointment.toFirestore());

      final appointmentId = docRef.id;

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

      // Schedule 3-day advance notification
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

      // Schedule same-day morning reminder
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
      await _firestore
          .collection('appointment_reminders')
          .doc(appointmentId)
          .set({
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
          });
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
      await _firestore
          .collection('appointment_reminders')
          .doc('${appointmentId}_sameday')
          .set({
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
          });
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
      await _firestore.collection('notifications').add({
        'userId': userId,
        'type': type,
        'title': title,
        'message': message,
        'appointmentId': appointmentId,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Ignore individual notification failures
      print('Error creating notification for user $userId: $e');
    }
  }

  /// Process and send 3-day advance notifications
  /// This should be called by a Cloud Function scheduled task daily
  Future<void> processThreeDayReminders() async {
    try {
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

      final message =
          'Reminder: Appointment with $clientName (scheduled by $creatorName) on $dateStr at $timeStr ($appointmentTypeStr)';

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

      final batch = _firestore.batch();
      final appointmentsRef = _firestore.collection('appointments');
      final newAppointmentRef = appointmentsRef.doc();

      final now = FieldValue.serverTimestamp();

      // 1. Confirmed appointment document
      batch.set(newAppointmentRef, {
        'clientId': request.clientId,
        'clientName': request.clientName,
        'attorneyId': currentUser.uid,
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
        attorneyId: currentUser.uid,
        appointmentDateTime: finalDateTime,
        appointmentType: appointmentType,
        clientName: request.clientName,
        creatorName: attorneyName,
      );

      // Schedule same-day morning reminder
      await _scheduleSameDayReminder(
        appointmentId: newAppointmentRef.id,
        clientId: request.clientId,
        attorneyId: currentUser.uid,
        appointmentDateTime: finalDateTime,
        appointmentType: appointmentType,
        clientName: request.clientName,
        creatorName: attorneyName,
      );

      // 3. Best-effort notification for the client (legacy support)
      // This is intentionally outside the batch so that stricter
      // security rules on `notifications` do not block the core flow.
      try {
        await _firestore.collection('notifications').add({
          'type': 'appointment_accepted',
          'clientId': request.clientId,
          'attorneyId': currentUser.uid,
          'appointmentId': newAppointmentRef.id,
          'title': 'Appointment Accepted',
          'message':
              'Your appointment request has been accepted and scheduled.',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
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

      if (appointmentDateTime != null) {
        try {
          final snap =
              await _firestore.collection('appointments').doc(appointmentId).get();
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

          await _firestore.collection('notifications').add({
            'type': type,
            'clientId': clientId,
            'attorneyId': existingAttorneyId ?? currentAttorneyId,
            'appointmentId': requestId,
            'title': title,
            'message': message,
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
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
