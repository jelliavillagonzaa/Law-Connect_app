# Scheduled Reminder Notifications - Example Usage

This document shows how to use the scheduled reminder notification system in your Flutter app.

## Basic Usage

### 1. Schedule a Simple Appointment Reminder

```dart
import 'package:your_app/services/notification_service.dart';

final notificationService = NotificationService();

// Schedule a reminder 30 minutes before an appointment
await notificationService.scheduleAppointmentReminder(
  appointmentId: 12345, // Unique ID for this appointment
  appointmentDate: '2024-01-15', // Format: YYYY-MM-DD
  appointmentTime: '14:30', // Format: 24-hour or "2:30 PM"
  title: 'Appointment with John Doe',
  body: 'Meeting to discuss case details',
  reminderMinutes: 30, // Optional, defaults to 30
  userId: 'user123',
  userRole: 'client', // or 'admin'
);
```

### 2. Using the Appointment Service (Recommended)

The `AppointmentService` handles both creating appointments and scheduling reminders automatically:

```dart
import 'package:your_app/services/appointment_service.dart';

final appointmentService = AppointmentService();

// Create an appointment - reminders are scheduled automatically
final result = await appointmentService.createAppointment(
  clientId: 'client123',
  clientName: 'John Doe',
  adminId: 'admin456', // Optional
  adminName: 'Jane Smith', // Optional
  appointmentDate: '2024-01-15',
  appointmentTime: '14:30',
  title: 'Case Consultation',
  description: 'Initial consultation for contract review',
  reminderMinutes: 30, // Optional, defaults to 30
);

if (result['success'] == true) {
  print('Appointment created: ${result['appointmentId']}');
}
```

### 3. Update an Appointment and Its Reminders

```dart
// Update appointment time - reminders are automatically rescheduled
final result = await appointmentService.updateAppointment(
  appointmentId: 'appointment123',
  appointmentDate: '2024-01-16', // New date
  appointmentTime: '15:00', // New time
  title: 'Updated: Case Consultation',
  reminderMinutes: 45, // New reminder time
);
```

### 4. Cancel an Appointment and Its Reminders

```dart
// Cancel appointment - reminders are automatically cancelled
final result = await appointmentService.cancelAppointment('appointment123');
```

### 5. Direct Notification Service Usage (Advanced)

If you need more control, use the notification service directly:

```dart
final notificationService = NotificationService();

// Schedule reminder
await notificationService.scheduleAppointmentReminder(
  appointmentId: 12345,
  appointmentDate: '2024-01-15',
  appointmentTime: '2:30 PM', // 12-hour format also works
  title: 'Appointment Reminder',
  body: 'Your appointment starts in 30 minutes',
  reminderMinutes: 30,
);

// Update reminder
await notificationService.updateAppointmentReminder(
  appointmentId: 12345,
  appointmentDate: '2024-01-16',
  appointmentTime: '15:00',
  title: 'Updated Appointment Reminder',
  reminderMinutes: 45,
);

// Cancel reminder
await notificationService.cancelAppointmentReminder(12345);
```

## Date and Time Formats

### Supported Date Formats:
- `'2024-01-15'` (YYYY-MM-DD) ✅ Recommended
- `'01/15/2024'` (MM/DD/YYYY)

### Supported Time Formats:
- `'14:30'` (24-hour format) ✅ Recommended
- `'2:30 PM'` (12-hour format)
- `'2:30PM'` (12-hour format, no space)

## Integration Examples

### Example 1: Create Appointment from UI Form

```dart
class CreateAppointmentPage extends StatefulWidget {
  @override
  _CreateAppointmentPageState createState() => _CreateAppointmentPageState();
}

class _CreateAppointmentPageState extends State<CreateAppointmentPage> {
  final _appointmentService = AppointmentService();
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  final _titleController = TextEditingController();

  Future<void> _createAppointment() async {
    final result = await _appointmentService.createAppointment(
      clientId: FirebaseAuth.instance.currentUser!.uid,
      clientName: 'Current User',
      appointmentDate: _dateController.text, // e.g., "2024-01-15"
      appointmentTime: _timeController.text, // e.g., "14:30"
      title: _titleController.text,
      reminderMinutes: 30,
    );

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Appointment created! Reminder scheduled.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${result['message']}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Your UI here
  }
}
```

### Example 2: Schedule Reminders for Both Admin and Client

```dart
final notificationService = NotificationService();

// Get appointment data from Firestore
final appointmentDoc = await FirebaseFirestore.instance
    .collection('appointments')
    .doc('appointment123')
    .get();

final appointmentData = appointmentDoc.data()!;

// Schedule for CLIENT
await notificationService.scheduleAppointmentReminder(
  appointmentId: 'appointment123'.hashCode,
  appointmentDate: appointmentData['date'],
  appointmentTime: appointmentData['time'],
  title: 'Your Appointment Reminder',
  body: 'Appointment with ${appointmentData['adminName']}',
  userId: appointmentData['clientId'],
  userRole: 'client',
);

// Schedule for ADMIN (use negative ID to ensure uniqueness)
await notificationService.scheduleAppointmentReminder(
  appointmentId: -'appointment123'.hashCode,
  appointmentDate: appointmentData['date'],
  appointmentTime: appointmentData['time'],
  title: 'Appointment Reminder',
  body: 'Appointment with ${appointmentData['clientName']}',
  userId: appointmentData['adminId'],
  userRole: 'admin',
);
```

### Example 3: Check Pending Notifications (Debugging)

```dart
final notificationService = NotificationService();
final pendingNotifications = await notificationService.getPendingNotifications();

print('Pending notifications: ${pendingNotifications.length}');
for (var notification in pendingNotifications) {
  print('ID: ${notification.id}, Title: ${notification.title}');
}
```

## Important Notes

1. **Notification IDs**: Use unique IDs for each appointment. The `AppointmentService` uses `appointmentId.hashCode` for client reminders and `-appointmentId.hashCode` for admin reminders.

2. **Reminder Time**: The reminder triggers X minutes BEFORE the appointment time. Default is 30 minutes.

3. **Past Dates**: If the reminder time is in the past, the notification won't be scheduled (returns `false`).

4. **App State**: Notifications work even when the app is closed or the phone is locked.

5. **Timezone**: Notifications use the device's local timezone automatically.

6. **Sound**: Make sure you've set up the `alert_sound.wav` file as described in `SOUND_FILE_SETUP.md`.

## Troubleshooting

### Notifications not firing?
1. Check device notification permissions
2. Verify the sound file is in the correct locations
3. Check logs for scheduling errors
4. Ensure the reminder time is in the future

### Sound not playing?
1. See `SOUND_FILE_SETUP.md` for file placement instructions
2. Check device volume settings
3. Verify notification channel is created with sound

### Reminders not updating?
1. Make sure you're using the same `appointmentId` when updating
2. Check that `updateAppointmentReminder` is being called
3. Verify the new time is in the future

## Logs

All scheduling operations are logged with detailed information. Look for:
- `📅 SCHEDULING APPOINTMENT REMINDER` - When scheduling starts
- `✅ Notification scheduled successfully` - When scheduling succeeds
- `❌ ERROR SCHEDULING REMINDER` - When scheduling fails

Use `adb logcat` on Android or Xcode console on iOS to view logs.

