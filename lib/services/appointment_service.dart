import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'notification_service.dart';

/// Example Appointment Service showing how to integrate scheduled reminders
/// 
/// This service demonstrates how to:
/// 1. Create appointments with automatic reminder scheduling
/// 2. Update appointments and update their reminders
/// 3. Cancel appointments and cancel their reminders
/// 4. Schedule reminders for both Admin and Client roles
class AppointmentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();

  /// Create a new appointment and schedule reminder notifications
  /// 
  /// This will:
  /// 1. Create the appointment in Firestore
  /// 2. Schedule reminders for both Admin and Client (if applicable)
  Future<Map<String, dynamic>> createAppointment({
    required String clientId,
    required String clientName,
    String? adminId,
    String? adminName,
    required String appointmentDate, // Format: "YYYY-MM-DD" or "MM/DD/YYYY"
    required String appointmentTime, // Format: "14:30" or "2:30 PM"
    required String title,
    String? description,
    int reminderMinutes = 30, // Default: 30 minutes before
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('═══════════════════════════════════════');
        debugPrint('📅 CREATING APPOINTMENT');
        debugPrint('═══════════════════════════════════════');
      }

      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        return {
          'success': false,
          'message': 'User not authenticated',
        };
      }

      // Create appointment document
      final appointmentData = {
        'clientId': clientId,
        'clientName': clientName,
        if (adminId != null) 'adminId': adminId,
        if (adminName != null) 'adminName': adminName,
        'appointmentDate': appointmentDate,
        'appointmentTime': appointmentTime,
        'title': title,
        if (description != null) 'description': description,
        'status': 'scheduled',
        'reminderMinutes': reminderMinutes,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final appointmentRef = await _firestore.collection('appointments').add(appointmentData);
      final appointmentId = appointmentRef.id;

      if (kDebugMode) {
        debugPrint('✅ Appointment created with ID: $appointmentId');
      }

      // Schedule reminder for CLIENT
      final clientReminderId = appointmentId.hashCode; // Use hash of appointment ID
      final clientReminderScheduled = await _notificationService.scheduleAppointmentReminder(
        appointmentId: clientReminderId,
        appointmentDate: appointmentDate,
        appointmentTime: appointmentTime,
        title: 'Appointment Reminder',
        body: 'You have an appointment: $title at ${_formatTime(appointmentTime)}',
        reminderMinutes: reminderMinutes,
        userId: clientId,
        userRole: 'client',
      );

      if (kDebugMode) {
        if (clientReminderScheduled) {
          debugPrint('✅ Client reminder scheduled successfully');
        } else {
          debugPrint('⚠️ Failed to schedule client reminder');
        }
      }

      // Schedule reminder for ADMIN (if adminId is provided)
      if (adminId != null) {
        // Use negative hash to ensure unique ID for admin
        final adminReminderId = (-appointmentId.hashCode);
        final adminReminderScheduled = await _notificationService.scheduleAppointmentReminder(
          appointmentId: adminReminderId,
          appointmentDate: appointmentDate,
          appointmentTime: appointmentTime,
          title: 'Appointment Reminder',
          body: 'You have an appointment with $clientName: $title at ${_formatTime(appointmentTime)}',
          reminderMinutes: reminderMinutes,
          userId: adminId,
          userRole: 'admin',
        );

        if (kDebugMode) {
          if (adminReminderScheduled) {
            debugPrint('✅ Admin reminder scheduled successfully');
          } else {
            debugPrint('⚠️ Failed to schedule admin reminder');
          }
        }
      }

      // Update appointment with reminder IDs
      await appointmentRef.update({
        'clientReminderId': clientReminderId,
        if (adminId != null) 'adminReminderId': (-appointmentId.hashCode),
        'remindersScheduled': clientReminderScheduled && (adminId == null || true),
      });

      if (kDebugMode) {
        debugPrint('✅ Appointment creation completed');
        debugPrint('═══════════════════════════════════════');
      }

      return {
        'success': true,
        'appointmentId': appointmentId,
        'message': 'Appointment created and reminders scheduled',
      };
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ ERROR CREATING APPOINTMENT');
        debugPrint('🔴 Error: $e');
        debugPrint('🔴 Stack Trace: $stackTrace');
      }
      return {
        'success': false,
        'message': 'Failed to create appointment: $e',
      };
    }
  }

  /// Update an existing appointment and update its reminders
  Future<Map<String, dynamic>> updateAppointment({
    required String appointmentId,
    String? appointmentDate,
    String? appointmentTime,
    String? title,
    String? description,
    int? reminderMinutes,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 Updating appointment: $appointmentId');
      }

      final appointmentRef = _firestore.collection('appointments').doc(appointmentId);
      final appointmentDoc = await appointmentRef.get();

      if (!appointmentDoc.exists) {
        return {
          'success': false,
          'message': 'Appointment not found',
        };
      }

      final appointmentData = appointmentDoc.data()!;
      final finalDate = appointmentDate ?? appointmentData['appointmentDate'] as String;
      final finalTime = appointmentTime ?? appointmentData['appointmentTime'] as String;
      final finalReminderMinutes = reminderMinutes ?? appointmentData['reminderMinutes'] as int? ?? 30;
      final finalTitle = title ?? appointmentData['title'] as String;

      // Update appointment in Firestore
      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (appointmentDate != null) updateData['appointmentDate'] = appointmentDate;
      if (appointmentTime != null) updateData['appointmentTime'] = appointmentTime;
      if (title != null) updateData['title'] = title;
      if (description != null) updateData['description'] = description;
      if (reminderMinutes != null) updateData['reminderMinutes'] = reminderMinutes;

      await appointmentRef.update(updateData);

      // Update client reminder
      final clientReminderId = appointmentId.hashCode;
      await _notificationService.updateAppointmentReminder(
        appointmentId: clientReminderId,
        appointmentDate: finalDate,
        appointmentTime: finalTime,
        title: 'Appointment Reminder',
        body: 'You have an appointment: $finalTitle at ${_formatTime(finalTime)}',
        reminderMinutes: finalReminderMinutes,
        userId: appointmentData['clientId'] as String?,
        userRole: 'client',
      );

      // Update admin reminder if exists
      if (appointmentData['adminId'] != null) {
        final adminReminderId = (-appointmentId.hashCode);
        await _notificationService.updateAppointmentReminder(
          appointmentId: adminReminderId,
          appointmentDate: finalDate,
          appointmentTime: finalTime,
          title: 'Appointment Reminder',
          body: 'You have an appointment: $finalTitle at ${_formatTime(finalTime)}',
          reminderMinutes: finalReminderMinutes,
          userId: appointmentData['adminId'] as String?,
          userRole: 'admin',
        );
      }

      if (kDebugMode) {
        debugPrint('✅ Appointment and reminders updated successfully');
      }

      return {
        'success': true,
        'message': 'Appointment updated and reminders rescheduled',
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error updating appointment: $e');
      }
      return {
        'success': false,
        'message': 'Failed to update appointment: $e',
      };
    }
  }

  /// Cancel an appointment and cancel its reminders
  Future<Map<String, dynamic>> cancelAppointment(String appointmentId) async {
    try {
      if (kDebugMode) {
        debugPrint('🗑️ Cancelling appointment: $appointmentId');
      }

      final appointmentRef = _firestore.collection('appointments').doc(appointmentId);
      final appointmentDoc = await appointmentRef.get();

      if (!appointmentDoc.exists) {
        return {
          'success': false,
          'message': 'Appointment not found',
        };
      }

      // Update appointment status
      await appointmentRef.update({
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Cancel client reminder
      final clientReminderId = appointmentId.hashCode;
      await _notificationService.cancelAppointmentReminder(clientReminderId);

      // Cancel admin reminder if exists
      final appointmentData = appointmentDoc.data()!;
      if (appointmentData['adminId'] != null) {
        final adminReminderId = (-appointmentId.hashCode);
        await _notificationService.cancelAppointmentReminder(adminReminderId);
      }

      if (kDebugMode) {
        debugPrint('✅ Appointment cancelled and reminders removed');
      }

      return {
        'success': true,
        'message': 'Appointment cancelled and reminders removed',
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error cancelling appointment: $e');
      }
      return {
        'success': false,
        'message': 'Failed to cancel appointment: $e',
      };
    }
  }

  /// Helper method to format time for display
  String _formatTime(String time) {
    // Simple formatter - you can enhance this
    return time;
  }
}

