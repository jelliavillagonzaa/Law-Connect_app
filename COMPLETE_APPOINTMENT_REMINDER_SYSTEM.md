# 📅 Complete Appointment Reminder System - Full Implementation

## ✅ Implementation Complete!

This document provides the complete implementation of the appointment reminder system with:
- ✅ Calendar Integration (Google Calendar / iOS Calendar)
- ✅ FCM Push Notifications (via Cloud Function)
- ✅ Local Notifications (30 minutes before)
- ✅ Custom Sound Support

---

## 📁 Files Created/Updated

### ✅ Created Files:
1. **`lib/services/calendar_service.dart`** - Calendar integration service
2. **`COMPLETE_APPOINTMENT_REMINDER_SYSTEM.md`** - This documentation

### ✅ Updated Files:
1. **`lib/services/case_service.dart`** - Returns appointmentDateTime for calendar
2. **`lib/pages/case/case_detail_page.dart`** - Integrated calendar and local reminders
3. **`functions/index.js`** - Cloud Function for FCM (already exists)
4. **`lib/services/notification_service.dart`** - Local notifications (already exists)
5. **`lib/main.dart`** - Initialization (already correct)
6. **`pubspec.yaml`** - Dependencies (already correct)

---

## 1. 📅 Calendar Service (`lib/services/calendar_service.dart`)

**Complete File:**

```dart
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
```

---

## 2. 🔔 Cloud Function (`functions/index.js`)

**Already exists and is correct!** The Cloud Function:
- Triggers on `appointments/{appointmentId}` creation
- Sends FCM to client and attorney
- Uses custom sound `alert_sound` (Android) and `alert_sound.wav` (iOS)

**Deploy command:**
```bash
cd functions
npm install
firebase deploy --only functions:sendAppointmentNotifications
```

---

## 3. 📱 Case Details Page Integration

**Key Code Block in `lib/pages/case/case_detail_page.dart`:**

```dart
// After successful appointment scheduling:
if (result['success'] == true) {
  // Step 1: Appointment saved to Firestore ✅
  // Step 2: Cloud Function sends FCM ✅
  
  // Step 3: Add to device calendar
  final calendarService = CalendarService();
  final caseTitle = result['caseTitle'] as String? ?? caseModel.caseTitle;
  final appointmentDateTimeStr = result['appointmentDateTime'] as String?;

  if (appointmentDateTimeStr != null) {
    final appointmentDateTime = DateTime.parse(appointmentDateTimeStr);
    
    // Add to calendar
    await calendarService.addAppointmentToCalendar(
      title: caseTitle,
      description: 'Appointment for case: ${caseModel.caseTitle}',
      startDate: appointmentDateTime,
      endDate: appointmentDateTime.add(const Duration(hours: 1)),
      reminderMinutes: 30,
    );

    // Step 4: Schedule local reminder (30 minutes before)
    final notificationService = NotificationService();
    final reminderDateTime = appointmentDateTime.subtract(
      const Duration(minutes: 30),
    );

    await notificationService.scheduleReminder(
      reminderId: (result['appointmentId'] as String).hashCode,
      scheduledDateTime: reminderDateTime,
      title: 'Appointment Reminder',
      body: 'Your appointment for "$caseTitle" is in 30 minutes',
    );
  }
}
```

---

## 4. 📦 Pubspec.yaml

**Already correct!** Contains:
```yaml
dependencies:
  add_2_calendar: ^3.0.1
  flutter_local_notifications: ^17.2.2
  timezone: ^0.9.4
  firebase_messaging: ^15.1.3

flutter:
  assets:
    - assets/sounds/
    - assets/images/
```

---

## 5. 🎵 Sound File Setup

### Required Files:

1. **`assets/sounds/alert_sound.wav`** - For Flutter assets
2. **`android/app/src/main/res/raw/alert_sound.wav`** - For Android
3. **`ios/Runner/Resources/alert_sound.wav`** - For iOS

### Steps:

1. **Get/create `alert_sound.wav`** (1-3 seconds, WAV format)

2. **Copy to Flutter assets:**
   ```bash
   cp alert_sound.wav assets/sounds/
   ```

3. **Copy to Android:**
   ```bash
   mkdir -p android/app/src/main/res/raw
   cp alert_sound.wav android/app/src/main/res/raw/
   ```

4. **Copy to iOS:**
   ```bash
   cp alert_sound.wav ios/Runner/Resources/
   # Then add to Xcode project manually
   ```

---

## 6. 🔧 Android Configuration

**Already configured!** `AndroidManifest.xml` has:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

**For Calendar (add_2_calendar):**
- No additional permissions needed (uses system calendar)

---

## 7. 🍎 iOS Configuration

**Already configured!** `Info.plist` has:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

**For Calendar (add_2_calendar):**
- No additional permissions needed (uses system calendar)

---

## 8. 🚀 Complete Flow

### When Attorney Schedules Appointment:

1. **User enters date/time** → Case Details Page
2. **Save to Firestore** → `appointments/{id}` collection
3. **Cloud Function triggers** → Sends FCM to client & attorney
4. **Add to calendar** → Google Calendar (Android) / Calendar (iOS)
5. **Schedule local reminder** → 30 minutes before appointment
6. **Reminder fires** → Local notification with custom sound

### Notification Types:

1. **FCM Push Notification** (Immediate)
   - Title: "Appointment Scheduled"
   - Body: "Your appointment is set on <date/time>"
   - Sound: `alert_sound` / `alert_sound.wav`

2. **Calendar Reminder** (30 min before)
   - System calendar reminder
   - Works even when app is closed

3. **Local Notification** (30 min before)
   - Title: "Appointment Reminder"
   - Body: "Your appointment is in 30 minutes"
   - Sound: `alert_sound` / `alert_sound.wav`

---

## 9. ✅ Testing Checklist

- [ ] Schedule an appointment
- [ ] Verify FCM notification received (check Cloud Function logs)
- [ ] Verify calendar event added (check device calendar)
- [ ] Verify local reminder scheduled (check logs)
- [ ] Wait 30 minutes before appointment
- [ ] Verify local reminder fires with sound
- [ ] Test on both Android and iOS

---

## 10. 🐛 Troubleshooting

### Calendar not adding?
- Check device calendar permissions
- Verify `add_2_calendar` package is installed
- Check logs for errors

### FCM not received?
- Check Cloud Function logs: `firebase functions:log`
- Verify user has `fcmToken` in Firestore
- Check device notification permissions

### Local reminder not firing?
- Check sound file exists in all locations
- Verify reminder time is in the future
- Check device notification permissions
- Check logs for scheduling errors

### Sound not playing?
- Verify `alert_sound.wav` is in:
  - `assets/sounds/`
  - `android/app/src/main/res/raw/`
  - `ios/Runner/Resources/`
- Check file format (WAV recommended)
- Check device volume settings

---

## 11. 📚 Related Files

- `lib/services/calendar_service.dart` - Calendar integration
- `lib/services/notification_service.dart` - Local notifications
- `lib/services/case_service.dart` - Appointment scheduling
- `lib/pages/case/case_detail_page.dart` - UI integration
- `functions/index.js` - Cloud Function for FCM
- `lib/main.dart` - Initialization

---

## 🎉 System Ready!

All code is implemented and ready to use. Just:
1. **Deploy Cloud Function**: `firebase deploy --only functions`
2. **Add sound file**: See Sound File Setup section
3. **Test the flow**: Schedule appointment and verify all notifications

Everything else is already configured! 🚀

