import 'dart:io' show Platform;

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Service for adding appointments to device calendar
/// 
/// Supports both Android (Google Calendar) and iOS (Calendar app)
class CalendarService {
  static final CalendarService _instance = CalendarService._internal();
  factory CalendarService() => _instance;
  CalendarService._internal();

  /// Add an appointment to the device calendar
  /// Alias: addToCalendar (for consistency)
  Future<bool> addToCalendar({
    required String title,
    String? description,
    String? location,
    required DateTime startDate,
    DateTime? endDate,
    int reminderMinutes = 30,
  }) async {
    return addAppointmentToCalendar(
      title: title,
      description: description,
      location: location,
      startDate: startDate,
      endDate: endDate,
      reminderMinutes: reminderMinutes,
    );
  }

  /// Add an appointment to the device calendar
  /// 
  /// [title] - Title of the appointment (e.g., "Case Consultation")
  /// [description] - Description/details of the appointment
  /// [location] - Location of the appointment (optional)
  /// [startDate] - DateTime when the appointment starts
  /// [endDate] - DateTime when the appointment ends (defaults to startDate + 1 hour)
  /// [reminderMinutes] - Minutes before appointment to set reminder (default: 30)
  /// 
  /// Returns true if successfully added, false otherwise
  Future<bool> addAppointmentToCalendar({
    required String title,
    String? description,
    String? location,
    required DateTime startDate,
    DateTime? endDate,
    int reminderMinutes = 30,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('═══════════════════════════════════════');
        debugPrint('📅 ADDING APPOINTMENT TO CALENDAR');
        debugPrint('═══════════════════════════════════════');
        debugPrint('📝 Title: $title');
        debugPrint('📅 Start Date: $startDate');
        debugPrint('⏰ End Date: ${endDate ?? startDate.add(const Duration(hours: 1))}');
        debugPrint('🔔 Reminder: $reminderMinutes minutes before');
      }

      // Calculate end date (default to 1 hour after start)
      final appointmentEndDate = endDate ?? startDate.add(const Duration(hours: 1));

      // Create event
      final Event event = Event(
        title: title,
        description: description ?? 'Appointment scheduled through JurisLink',
        location: location,
        startDate: startDate,
        endDate: appointmentEndDate,
        iosParams: IOSParams(
          reminder: Duration(minutes: reminderMinutes),
        ),
        androidParams: AndroidParams(
          emailInvites: [], // Can add email invites if needed
        ),
      );

      // Add to calendar
      final result = await Add2Calendar.addEvent2Cal(event);

      if (kDebugMode) {
        if (result) {
          debugPrint('✅ Appointment added to calendar successfully');
          debugPrint('   Calendar: ${Platform.isIOS ? "iOS Calendar" : "Google Calendar"}');
        } else {
          debugPrint('⚠️ Failed to add appointment to calendar');
        }
        debugPrint('═══════════════════════════════════════');
      }

      return result;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ ERROR ADDING TO CALENDAR');
        debugPrint('═══════════════════════════════════════');
        debugPrint('🔴 Error: $e');
        debugPrint('🔴 Type: ${e.runtimeType}');
        debugPrint('🔴 Stack Trace: $stackTrace');
        debugPrint('═══════════════════════════════════════');
      }
      return false;
    }
  }

  /// Add appointment with parsed date and time strings
  /// 
  /// [title] - Title of the appointment
  /// [description] - Description of the appointment
  /// [appointmentDate] - Date string (e.g., "2024-01-15" or "01/15/2024")
  /// [appointmentTime] - Time string (e.g., "14:30" or "2:30 PM")
  /// [durationHours] - Duration in hours (default: 1)
  /// [reminderMinutes] - Minutes before to set reminder (default: 30)
  /// 
  /// Returns true if successfully added, false otherwise
  Future<bool> addAppointmentFromStrings({
    required String title,
    String? description,
    String? location,
    required String appointmentDate,
    required String appointmentTime,
    int durationHours = 1,
    int reminderMinutes = 30,
  }) async {
    try {
      // Parse date and time
      final appointmentDateTime = _parseAppointmentDateTime(
        appointmentDate,
        appointmentTime,
      );

      if (appointmentDateTime == null) {
        if (kDebugMode) {
          debugPrint('❌ Failed to parse appointment date/time');
        }
        return false;
      }

      // Calculate end date
      final endDate = appointmentDateTime.add(Duration(hours: durationHours));

      // Add to calendar
      return await addAppointmentToCalendar(
        title: title,
        description: description,
        location: location,
        startDate: appointmentDateTime,
        endDate: endDate,
        reminderMinutes: reminderMinutes,
      );
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ ERROR ADDING APPOINTMENT FROM STRINGS');
        debugPrint('🔴 Error: $e');
        debugPrint('🔴 Stack Trace: $stackTrace');
      }
      return false;
    }
  }

  /// Parse appointment date and time strings into DateTime
  DateTime? _parseAppointmentDateTime(String date, String time) {
    try {
      // Parse date (assuming format: "YYYY-MM-DD" or "MM/DD/YYYY")
      DateTime datePart;
      if (date.contains('-')) {
        datePart = DateTime.parse(date);
      } else if (date.contains('/')) {
        final parts = date.split('/');
        if (parts.length == 3) {
          datePart = DateTime(
            int.parse(parts[2]), // year
            int.parse(parts[0]), // month
            int.parse(parts[1]), // day
          );
        } else {
          return null;
        }
      } else {
        return null;
      }

      // Parse time (handling both 24-hour and 12-hour formats)
      final timeLower = time.toLowerCase().trim();
      int hour, minute;

      if (timeLower.contains('am') || timeLower.contains('pm')) {
        // 12-hour format (e.g., "2:30 PM" or "2:30PM")
        final timeStr = timeLower.replaceAll(RegExp(r'[ap]m'), '').trim();
        final parts = timeStr.split(':');
        hour = int.parse(parts[0]);
        minute = parts.length > 1 ? int.parse(parts[1]) : 0;

        if (timeLower.contains('pm') && hour != 12) {
          hour += 12;
        } else if (timeLower.contains('am') && hour == 12) {
          hour = 0; // Midnight
        }
      } else {
        // 24-hour format (e.g., "14:30")
        final parts = time.split(':');
        hour = int.parse(parts[0]);
        minute = parts.length > 1 ? int.parse(parts[1]) : 0;
      }

      return DateTime(
        datePart.year,
        datePart.month,
        datePart.day,
        hour,
        minute,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error parsing date/time: $e');
        debugPrint('   Date: $date, Time: $time');
      }
      return null;
    }
  }
}

