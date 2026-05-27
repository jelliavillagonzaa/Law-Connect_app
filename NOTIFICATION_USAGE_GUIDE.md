# 📱 Notification Usage Guide - Step by Step

This guide will walk you through using the scheduled reminder notifications in your Flutter app.

## 📋 Table of Contents
1. [Quick Start](#quick-start)
2. [Step-by-Step Integration](#step-by-step-integration)
3. [Common Use Cases](#common-use-cases)
4. [Testing](#testing)
5. [Troubleshooting](#troubleshooting)

---

## 🚀 Quick Start

### The Simplest Way (Using AppointmentService)

```dart
import 'package:your_app/services/appointment_service.dart';

// 1. Create an instance
final appointmentService = AppointmentService();

// 2. Create an appointment - reminder is scheduled automatically!
final result = await appointmentService.createAppointment(
  clientId: 'user123',
  clientName: 'John Doe',
  appointmentDate: '2024-01-15',  // Format: YYYY-MM-DD
  appointmentTime: '14:30',       // Format: 24-hour (14:30) or 12-hour (2:30 PM)
  title: 'Case Consultation',
);

// 3. Check if it worked
if (result['success'] == true) {
  print('✅ Appointment created! Reminder scheduled.');
} else {
  print('❌ Error: ${result['message']}');
}
```

**That's it!** The reminder will automatically fire 30 minutes before the appointment.

---

## 📝 Step-by-Step Integration

### Step 1: Import the Service

Add this import at the top of your file:

```dart
import 'package:your_app/services/appointment_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
```

### Step 2: Create an Appointment with Reminder

Here's a complete example from a form submission:

```dart
class CreateAppointmentPage extends StatefulWidget {
  @override
  _CreateAppointmentPageState createState() => _CreateAppointmentPageState();
}

class _CreateAppointmentPageState extends State<CreateAppointmentPage> {
  final _appointmentService = AppointmentService();
  final _formKey = GlobalKey<FormState>();
  
  // Your form controllers
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  Future<void> _submitAppointment() async {
    // Validate form
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Get current user
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please login first')),
      );
      return;
    }

    // Show loading
    setState(() => _isLoading = true);

    try {
      // Create appointment - reminder is scheduled automatically!
      final result = await _appointmentService.createAppointment(
        clientId: currentUser.uid,
        clientName: currentUser.displayName ?? 'User',
        appointmentDate: _dateController.text,  // e.g., "2024-01-15"
        appointmentTime: _timeController.text,   // e.g., "14:30" or "2:30 PM"
        title: _titleController.text,
        description: _descriptionController.text,
        reminderMinutes: 30, // Optional: 30 minutes before (default)
      );

      if (result['success'] == true) {
        // Success!
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Appointment created! Reminder scheduled.'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Navigate back or to appointment list
        Navigator.pop(context);
      } else {
        // Error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: ${result['message']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Create Appointment')),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Your form fields here
            TextFormField(
              controller: _dateController,
              decoration: InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a date';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _timeController,
              decoration: InputDecoration(labelText: 'Time (14:30 or 2:30 PM)'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a time';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(labelText: 'Title'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a title';
                }
                return null;
              },
            ),
            
            // Submit button
            ElevatedButton(
              onPressed: _isLoading ? null : _submitAppointment,
              child: _isLoading 
                ? CircularProgressIndicator() 
                : Text('Create Appointment'),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Step 3: Update an Appointment

When a user updates an appointment, the reminder is automatically updated:

```dart
final result = await _appointmentService.updateAppointment(
  appointmentId: 'appointment123',
  appointmentDate: '2024-01-16',  // New date
  appointmentTime: '15:00',       // New time
  title: 'Updated: Case Consultation',
  reminderMinutes: 45,            // New reminder time (45 min before)
);
```

### Step 4: Cancel an Appointment

When an appointment is cancelled, the reminder is automatically cancelled:

```dart
final result = await _appointmentService.cancelAppointment('appointment123');
```

---

## 💡 Common Use Cases

### Use Case 1: Client Creates Appointment

```dart
// Client creates appointment with attorney
final result = await appointmentService.createAppointment(
  clientId: currentUser.uid,
  clientName: currentUser.displayName ?? 'Client',
  adminId: selectedAttorneyId,        // Attorney/Admin ID
  adminName: selectedAttorneyName,    // Attorney/Admin name
  appointmentDate: selectedDate,        // e.g., "2024-01-15"
  appointmentTime: selectedTime,       // e.g., "14:30"
  title: 'Legal Consultation',
  description: 'Discuss contract terms',
  reminderMinutes: 30,                // Remind 30 min before
);

// Both client AND admin will get reminders!
```

### Use Case 2: Admin Creates Appointment for Client

```dart
// Admin schedules appointment for a client
final result = await appointmentService.createAppointment(
  clientId: selectedClientId,
  clientName: selectedClientName,
  adminId: currentUser.uid,            // Current admin
  adminName: currentUser.displayName ?? 'Admin',
  appointmentDate: '2024-01-15',
  appointmentTime: '14:30',
  title: 'Case Review Meeting',
  reminderMinutes: 60,                 // Remind 1 hour before
);
```

### Use Case 3: Direct Notification Service Usage

If you need more control, use the notification service directly:

```dart
import 'package:your_app/services/notification_service.dart';

final notificationService = NotificationService();

// Schedule a reminder
await notificationService.scheduleAppointmentReminder(
  appointmentId: 12345,                    // Unique ID
  appointmentDate: '2024-01-15',
  appointmentTime: '14:30',
  title: 'Appointment Reminder',
  body: 'Your appointment starts in 30 minutes',
  reminderMinutes: 30,
  userId: currentUser.uid,
  userRole: 'client',                      // or 'admin'
);
```

### Use Case 4: Schedule Multiple Reminders

You can schedule multiple reminders for the same appointment:

```dart
// Reminder 1: 1 hour before
await notificationService.scheduleAppointmentReminder(
  appointmentId: 12345,
  appointmentDate: '2024-01-15',
  appointmentTime: '14:30',
  title: 'Appointment in 1 hour',
  reminderMinutes: 60,
);

// Reminder 2: 30 minutes before (use different ID)
await notificationService.scheduleAppointmentReminder(
  appointmentId: 12346,  // Different ID!
  appointmentDate: '2024-01-15',
  appointmentTime: '14:30',
  title: 'Appointment in 30 minutes',
  reminderMinutes: 30,
);
```

---

## 🧪 Testing

### Test 1: Schedule a Reminder for 1 Minute from Now

```dart
// Get current time + 1 minute
final now = DateTime.now();
final inOneMinute = now.add(Duration(minutes: 1));

// Schedule reminder
await notificationService.scheduleAppointmentReminder(
  appointmentId: 99999,
  appointmentDate: '${inOneMinute.year}-${inOneMinute.month.toString().padLeft(2, '0')}-${inOneMinute.day.toString().padLeft(2, '0')}',
  appointmentTime: '${inOneMinute.hour}:${inOneMinute.minute.toString().padLeft(2, '0')}',
  title: 'Test Reminder',
  body: 'This is a test notification',
  reminderMinutes: 1,  // Will fire in 1 minute
);

print('✅ Test reminder scheduled! Wait 1 minute to see it.');
```

### Test 2: Check Pending Notifications

```dart
final notificationService = NotificationService();
final pending = await notificationService.getPendingNotifications();

print('Pending notifications: ${pending.length}');
for (var notif in pending) {
  print('ID: ${notif.id}, Title: ${notif.title}');
}
```

### Test 3: Cancel a Test Reminder

```dart
await notificationService.cancelAppointmentReminder(99999);
print('✅ Test reminder cancelled');
```

---

## 📅 Date and Time Formats

### Supported Date Formats:
- ✅ `'2024-01-15'` (YYYY-MM-DD) - **Recommended**
- ✅ `'01/15/2024'` (MM/DD/YYYY)

### Supported Time Formats:
- ✅ `'14:30'` (24-hour format) - **Recommended**
- ✅ `'2:30 PM'` (12-hour format with space)
- ✅ `'2:30PM'` (12-hour format without space)

### Examples:
```dart
// All of these work:
appointmentDate: '2024-01-15'
appointmentTime: '14:30'        // ✅ Best

appointmentDate: '01/15/2024'
appointmentTime: '2:30 PM'     // ✅ Also works

appointmentTime: '2:30PM'       // ✅ Also works
```

---

## 🔍 Viewing Logs

The notification service logs everything. To see the logs:

### Android:
```bash
adb logcat | grep -E "SCHEDULING|Notification|reminder"
```

### iOS:
View logs in Xcode console when running the app.

### What You'll See:
```
═══════════════════════════════════════
📅 SCHEDULING APPOINTMENT REMINDER
═══════════════════════════════════════
📋 Appointment ID: 12345
📅 Date: 2024-01-15
⏰ Time: 14:30
⏱️ Reminder: 30 minutes before
✅ Notification scheduled successfully
```

---

## ⚠️ Troubleshooting

### Problem: Notifications not appearing

**Solutions:**
1. Check device notification permissions:
   - Android: Settings → Apps → Your App → Notifications
   - iOS: Settings → Notifications → Your App
2. Verify the reminder time is in the future
3. Check logs for errors
4. Make sure the app has notification permissions

### Problem: Sound not playing

**Solutions:**
1. Check that `alert_sound.wav` is in:
   - `android/app/src/main/res/raw/alert_sound.wav`
   - `ios/Runner/Resources/alert_sound.wav`
2. Check device volume
3. See `SOUND_FILE_SETUP.md` for detailed instructions

### Problem: Reminder time is wrong

**Solutions:**
1. Check date/time format matches examples above
2. Verify timezone (notifications use device local time)
3. Check logs to see the parsed DateTime

### Problem: Reminder not updating

**Solutions:**
1. Make sure you're using the same `appointmentId`
2. Call `updateAppointmentReminder()` after changing appointment
3. Check logs to verify update was scheduled

---

## 📚 Complete Example

Here's a complete working example:

```dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:your_app/services/appointment_service.dart';

class AppointmentExample extends StatefulWidget {
  @override
  _AppointmentExampleState createState() => _AppointmentExampleState();
}

class _AppointmentExampleState extends State<AppointmentExample> {
  final _service = AppointmentService();
  final _dateController = TextEditingController(text: '2024-12-25');
  final _timeController = TextEditingController(text: '14:30');
  final _titleController = TextEditingController(text: 'Christmas Consultation');

  Future<void> _createAppointment() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please login')),
      );
      return;
    }

    final result = await _service.createAppointment(
      clientId: user.uid,
      clientName: user.displayName ?? 'User',
      appointmentDate: _dateController.text,
      appointmentTime: _timeController.text,
      title: _titleController.text,
      reminderMinutes: 30,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['success'] == true
              ? '✅ Appointment created!'
              : '❌ Error: ${result['message']}'),
          backgroundColor: result['success'] == true ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Create Appointment')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _dateController,
              decoration: InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _timeController,
              decoration: InputDecoration(labelText: 'Time (14:30)'),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(labelText: 'Title'),
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: _createAppointment,
              child: Text('Create Appointment & Schedule Reminder'),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## ✅ Checklist

Before using notifications, make sure:

- [ ] Sound file `alert_sound.wav` is in both Android and iOS locations
- [ ] Notification permissions are granted on device
- [ ] You're using correct date/time formats
- [ ] Reminder time is in the future
- [ ] You've tested with a sample appointment

---

## 🎯 Quick Reference

```dart
// Create appointment (reminder auto-scheduled)
appointmentService.createAppointment(...)

// Update appointment (reminder auto-updated)
appointmentService.updateAppointment(...)

// Cancel appointment (reminder auto-cancelled)
appointmentService.cancelAppointment(...)

// Direct notification scheduling
notificationService.scheduleAppointmentReminder(...)

// Cancel a specific reminder
notificationService.cancelAppointmentReminder(id)

// Update a specific reminder
notificationService.updateAppointmentReminder(...)
```

---

**That's it!** You're ready to use scheduled reminder notifications in your app. 🎉

For more details, see:
- `EXAMPLE_USAGE.md` - More code examples
- `SOUND_FILE_SETUP.md` - Sound file setup
- `NOTIFICATION_SETUP_SUMMARY.md` - Complete setup summary

