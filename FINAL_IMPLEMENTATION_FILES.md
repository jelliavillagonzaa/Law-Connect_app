# 📄 Complete File Contents - Appointment Notification System

This document contains the **exact file contents** for all updated files in the appointment notification system.

---

## 1. Cloud Functions: `functions/index.js`

```javascript
/**
 * Firebase Cloud Functions for JurisLink App
 * 
 * This file contains Cloud Functions that handle:
 * - FCM push notifications when appointments are scheduled
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin
admin.initializeApp();

/**
 * Cloud Function: Send FCM notifications when appointment is created
 * 
 * Trigger: When a new document is created in "appointments/{appointmentId}"
 * 
 * This function:
 * 1. Fetches clientId and attorneyId from the appointment document
 * 2. Looks up each user's deviceToken (fcmToken) in the "users" collection
 * 3. Sends FCM notification to both client and attorney
 * 4. Uses custom sound "alert_sound" for Android and "alert_sound.wav" for iOS
 */
exports.sendAppointmentNotifications = functions.firestore
  .document('appointments/{appointmentId}')
  .onCreate(async (snap, context) => {
    const appointmentData = snap.data();
    const appointmentId = context.params.appointmentId;

    console.log('═══════════════════════════════════════');
    console.log('📅 APPOINTMENT CREATED - SENDING FCM');
    console.log('═══════════════════════════════════════');
    console.log('📋 Appointment ID:', appointmentId);
    console.log('📦 Appointment Data:', JSON.stringify(appointmentData, null, 2));

    try {
      const clientId = appointmentData.clientId;
      const attorneyId = appointmentData.attorneyId || null;
      const appointmentDate = appointmentData.appointmentDate;
      const appointmentTime = appointmentData.appointmentTime;
      const caseTitle = appointmentData.title || appointmentData.caseTitle || 'Appointment';

      // Format date and time for notification
      const formattedDate = formatDate(appointmentDate);
      const formattedTime = formatTime(appointmentTime);
      const dateTimeString = `${formattedDate} at ${formattedTime}`;

      console.log('👤 Client ID:', clientId);
      console.log('👨‍⚖️ Attorney ID:', attorneyId);
      console.log('📅 Date/Time:', dateTimeString);

      // Get FCM tokens for client and attorney
      const clientToken = await getFCMToken(clientId);
      const attorneyToken = attorneyId ? await getFCMToken(attorneyId) : null;

      console.log('📱 Client FCM Token:', clientToken ? 'Found' : 'Not found');
      console.log('📱 Attorney FCM Token:', attorneyToken ? 'Found' : 'Not found');

      const results = {
        client: false,
        attorney: false,
      };

      // Send notification to CLIENT
      if (clientToken) {
        try {
          const clientMessage = {
            notification: {
              title: 'Appointment Scheduled',
              body: `Your appointment is scheduled on ${dateTimeString}.`,
            },
            data: {
              type: 'appointment_scheduled',
              appointmentId: appointmentId,
              appointmentDate: appointmentDate,
              appointmentTime: appointmentTime,
              caseTitle: caseTitle,
            },
            token: clientToken,
            android: {
              priority: 'high',
              notification: {
                sound: 'alert_sound',
                channelId: 'appointment_reminders',
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: 'alert_sound.wav',
                  badge: 1,
                },
              },
            },
          };

          await admin.messaging().send(clientMessage);
          results.client = true;
          console.log('✅ FCM notification sent to CLIENT');
        } catch (error) {
          console.error('❌ Error sending FCM to client:', error);
        }
      } else {
        console.warn('⚠️ Client FCM token not found, skipping notification');
      }

      // Send notification to ATTORNEY (if assigned)
      if (attorneyToken) {
        try {
          const clientName = appointmentData.clientName || 'a client';
          const attorneyMessage = {
            notification: {
              title: 'Appointment Scheduled',
              body: `You have an appointment with ${clientName} on ${dateTimeString}.`,
            },
            data: {
              type: 'appointment_scheduled',
              appointmentId: appointmentId,
              appointmentDate: appointmentDate,
              appointmentTime: appointmentTime,
              caseTitle: caseTitle,
              clientName: clientName,
            },
            token: attorneyToken,
            android: {
              priority: 'high',
              notification: {
                sound: 'alert_sound',
                channelId: 'appointment_reminders',
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: 'alert_sound.wav',
                  badge: 1,
                },
              },
            },
          };

          await admin.messaging().send(attorneyMessage);
          results.attorney = true;
          console.log('✅ FCM notification sent to ATTORNEY');
        } catch (error) {
          console.error('❌ Error sending FCM to attorney:', error);
        }
      } else if (attorneyId) {
        console.warn('⚠️ Attorney FCM token not found, skipping notification');
      }

      // Update appointment document with notification status
      await snap.ref.update({
        notificationsSent: results,
        notificationsSentAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log('✅ Notification results:', results);
      console.log('═══════════════════════════════════════');

      return results;
    } catch (error) {
      console.error('❌ ERROR IN CLOUD FUNCTION');
      console.error('🔴 Error:', error);
      console.error('🔴 Stack:', error.stack);
      console.error('═══════════════════════════════════════');

      // Update appointment with error
      await snap.ref.update({
        notificationError: error.message,
        notificationErrorAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      throw error;
    }
  });

/**
 * Helper function: Get FCM token for a user
 */
async function getFCMToken(userId) {
  try {
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    if (userDoc.exists) {
      const userData = userDoc.data();
      return userData.fcmToken || null;
    }
    return null;
  } catch (error) {
    console.error(`Error getting FCM token for user ${userId}:`, error);
    return null;
  }
}

/**
 * Helper function: Format date string
 * Converts "2024-01-15" to "January 15, 2024"
 */
function formatDate(dateString) {
  try {
    const parts = dateString.split('-');
    if (parts.length === 3) {
      const year = parseInt(parts[0]);
      const month = parseInt(parts[1]);
      const day = parseInt(parts[2]);
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return `${months[month - 1]} ${day}, ${year}`;
    }
  } catch (error) {
    console.error('Error formatting date:', error);
  }
  return dateString;
}

/**
 * Helper function: Format time string
 * Converts "14:30" to "2:30 PM"
 */
function formatTime(timeString) {
  try {
    // Check if already formatted (contains AM/PM)
    if (timeString.includes('AM') || timeString.includes('PM')) {
      return timeString;
    }

    // Parse 24-hour format
    const parts = timeString.split(':');
    if (parts.length === 2) {
      const hour = parseInt(parts[0]);
      const minute = parseInt(parts[1]);
      const period = hour >= 12 ? 'PM' : 'AM';
      const displayHour = hour > 12 ? hour - 12 : (hour === 0 ? 12 : hour);
      return `${displayHour}:${minute.toString().padStart(2, '0')} ${period}`;
    }
  } catch (error) {
    console.error('Error formatting time:', error);
  }
  return timeString;
}
```

---

## 2. Notification Service: `lib/services/notification_service.dart`

**Key Method Added:**

```dart
/// Schedule a reminder notification (simplified version)
/// 
/// [reminderId] - Unique ID for the reminder (used as notification ID)
/// [scheduledDateTime] - DateTime when the reminder should fire
/// [title] - Title for the notification
/// [body] - Body text for the notification
/// 
/// Returns true if scheduled successfully, false otherwise
Future<bool> scheduleReminder({
  required int reminderId,
  required DateTime scheduledDateTime,
  required String title,
  required String body,
}) async {
  if (!_isInitialized) {
    await initialize();
  }

  try {
    if (kDebugMode) {
      debugPrint('═══════════════════════════════════════');
      debugPrint('📅 SCHEDULING REMINDER');
      debugPrint('═══════════════════════════════════════');
      debugPrint('📋 Reminder ID: $reminderId');
      debugPrint('⏰ Scheduled DateTime: $scheduledDateTime');
      debugPrint('📝 Title: $title');
    }

    // Check if reminder time is in the past
    if (scheduledDateTime.isBefore(DateTime.now())) {
      if (kDebugMode) {
        debugPrint('⚠️ WARNING: Reminder time is in the past');
        debugPrint('   Reminder time: $scheduledDateTime');
        debugPrint('   Current time: ${DateTime.now()}');
      }
      return false;
    }

    // Convert to local timezone
    final localLocation = tz.local;
    final scheduledDate = tz.TZDateTime.from(scheduledDateTime, localLocation);

    if (kDebugMode) {
      debugPrint('🌍 Scheduled in timezone: ${localLocation.name}');
      debugPrint('📅 Scheduled Date (TZ): $scheduledDate');
    }

    // Notification details with custom sound
    const NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _appointmentChannelId,
        _appointmentChannelName,
        channelDescription: _appointmentChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        sound: RawResourceAndroidNotificationSound('alert_sound'),
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        sound: 'alert_sound.wav',
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    // Schedule the notification
    await _notifications.zonedSchedule(
      reminderId,
      title,
      body,
      scheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'reminder_$reminderId',
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );

    if (kDebugMode) {
      debugPrint('✅ Reminder scheduled successfully');
      debugPrint('   Notification ID: $reminderId');
      debugPrint('   Scheduled for: $scheduledDate');
      debugPrint('═══════════════════════════════════════');
    }

    return true;
  } catch (e, stackTrace) {
    if (kDebugMode) {
      debugPrint('❌ ERROR SCHEDULING REMINDER');
      debugPrint('═══════════════════════════════════════');
      debugPrint('🔴 Error: $e');
      debugPrint('🔴 Type: ${e.runtimeType}');
      debugPrint('🔴 Stack Trace: $stackTrace');
      debugPrint('═══════════════════════════════════════');
    }
    return false;
  }
}
```

**Full file is already updated with this method.**

---

## 3. Case Service: `lib/services/case_service.dart`

**Key Method Updated - `scheduleAppointment()`:**

The method now:
1. Saves appointment to `cases` collection
2. Creates appointment in `appointments` collection (triggers Cloud Function)
3. Schedules local reminders using `scheduleReminder()`

**Key Code Snippet:**

```dart
// Step 1: Save appointment to cases collection
await _firestore.collection('cases').doc(caseId).update({
  'appointmentDate': appointmentDate,
  'appointmentTime': appointmentTime,
  'updatedAt': FieldValue.serverTimestamp(),
});

// Step 2: Create appointment document in appointments collection
// This will trigger Cloud Function to send FCM notifications
final appointmentData = {
  'caseId': caseId,
  'clientId': clientId,
  'clientName': clientName,
  if (attorneyId != null) 'attorneyId': attorneyId,
  'appointmentDate': appointmentDate,
  'appointmentTime': appointmentTime,
  'title': caseTitle,
  'caseTitle': caseTitle,
  'status': 'scheduled',
  'createdAt': FieldValue.serverTimestamp(),
  'updatedAt': FieldValue.serverTimestamp(),
};

final appointmentRef = await _firestore.collection('appointments').add(appointmentData);
final appointmentId = appointmentRef.id;

// Step 3: Schedule local reminders (30 minutes before)
final appointmentDateTime = _parseAppointmentDateTime(appointmentDate, appointmentTime);
if (appointmentDateTime != null) {
  final reminderDateTime = appointmentDateTime.subtract(const Duration(minutes: 30));
  
  // Schedule for CLIENT
  await notificationService.scheduleReminder(
    reminderId: appointmentId.hashCode,
    scheduledDateTime: reminderDateTime,
    title: 'Appointment Reminder',
    body: 'Your appointment for "$caseTitle" is in 30 minutes',
  );
  
  // Schedule for ATTORNEY (if assigned)
  if (attorneyId != null) {
    await notificationService.scheduleReminder(
      reminderId: -appointmentId.hashCode,
      scheduledDateTime: reminderDateTime,
      title: 'Appointment Reminder',
      body: 'You have an appointment for "$caseTitle" in 30 minutes',
    );
  }
}
```

**Full file is already updated.**

---

## 4. Main.dart: `lib/main.dart`

**Already has all initialization:**

```dart
// Initialize notification service (local notifications)
await NotificationService().initialize();

// Initialize FCM service (push notifications)
FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
await FCMService().initialize();
```

**Full file is already correct.**

---

## 5. Pubspec.yaml: `pubspec.yaml`

**Already has all required packages:**

```yaml
dependencies:
  flutter_local_notifications: ^17.2.2
  timezone: ^0.9.4
  firebase_messaging: ^15.1.3
  # ... other packages

flutter:
  assets:
    - assets/sounds/
```

**Full file is already correct.**

---

## 6. AndroidManifest.xml: `android/app/src/main/AndroidManifest.xml`

**Already has all required permissions:**

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
<uses-permission android:name="android.permission.WAKE_LOCK" />

<application
    android:usesCleartextTraffic="true">
    <!-- ... -->
</application>
```

**Full file is already correct.**

---

## 7. iOS Info.plist: `ios/Runner/Info.plist`

**Already has background modes:**

```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

**Full file is already correct.**

---

## 📋 Deployment Checklist

### 1. Deploy Cloud Function

```bash
cd functions
npm install
firebase deploy --only functions:sendAppointmentNotifications
```

### 2. Add Sound File

**Create/obtain `alert_sound.wav`** (1-3 seconds, WAV format)

**Copy to three locations:**
```bash
# 1. Flutter assets
cp alert_sound.wav assets/sounds/

# 2. Android
mkdir -p android/app/src/main/res/raw
cp alert_sound.wav android/app/src/main/res/raw/

# 3. iOS
cp alert_sound.wav ios/Runner/Resources/
# Then add to Xcode project manually
```

### 3. Test

1. Run `flutter pub get`
2. Build and run app
3. Schedule an appointment
4. Check Cloud Function logs
5. Verify notifications are received

---

## ✅ All Files Ready!

All code is implemented and ready. Just:
1. Deploy Cloud Function
2. Add sound file
3. Test!

See `COMPLETE_APPOINTMENT_SYSTEM.md` for detailed documentation.

