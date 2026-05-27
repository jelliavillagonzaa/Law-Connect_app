# ⏰ Deadline Reminder System with Sound Notifications

## Overview

The deadline reminder system automatically sends early reminders with sound notifications for upcoming important deadlines to staff, attorneys, and clients. Reminders are sent 7 days, 3 days, and 1 day before each deadline.

---

## ✅ Features Implemented

### 1. **Automatic Reminder System**
- ✅ Monitors `calendar_events` collection for upcoming deadlines
- ✅ Sends reminders at **7 days**, **3 days**, and **1 day** before deadlines
- ✅ Works automatically when app is running
- ✅ Checks every 6 hours as backup

### 2. **Sound Notifications**
- ✅ Local notifications with custom sound
- ✅ FCM push notifications with sound
- ✅ Notification stored in Firestore for in-app viewing

### 3. **Multi-User Support**
- ✅ **Staff**: Gets reminders for deadlines from assigned attorney
- ✅ **Attorneys**: Gets reminders for all deadlines assigned to them
- ✅ **Clients**: Gets reminders for deadlines related to their cases
- ✅ **Admins**: Gets reminders for all deadlines

### 4. **Smart Reminder Logic**
- ✅ Prevents duplicate reminders (tracks sent reminders)
- ✅ Date-only comparisons (ignores time of day)
- ✅ Only sends reminders for upcoming deadlines (not past)
- ✅ Handles deadlines, filings, and hearings

---

## 📁 Files Created/Modified

### Created Files:
- ✅ `lib/services/deadline_reminder_service.dart` - Main reminder service

### Modified Files:
- ✅ `lib/pages/splash_screen.dart` - Integrated deadline reminder service on login

---

## 🔄 How It Works

### 1. **Service Initialization**
The service starts automatically when users log in (all user types):

```dart
// In splash_screen.dart
final deadlineReminderService = DeadlineReminderService();
deadlineReminderService.startDeadlineReminderCheck();
```

### 2. **Deadline Monitoring**
- Service listens to `calendar_events` collection
- Filters for events with `eventType` in: `['deadline', 'filing', 'hearing']`
- Monitors events within the next 8 days

### 3. **Reminder Processing**
For each relevant deadline:
1. Calculates days until deadline (date-only comparison)
2. Checks if reminder should be sent (7, 3, or 1 day before)
3. Verifies reminder hasn't been sent already
4. Sends notification with sound
5. Marks reminder as sent in Firestore

### 4. **Notification Delivery**
Each reminder sends:
- **Local notification** with sound (via NotificationService)
- **FCM push notification** with sound (via FCMService)
- **Firestore notification** (stored in `notifications` collection)

---

## 📊 Data Structure

### Calendar Events (Source)
```dart
{
  'eventType': 'deadline' | 'filing' | 'hearing',
  'eventDate': Timestamp,
  'title': String,
  'description': String?,
  'caseId': String?,
  'assignedTo': String?, // attorneyId
  'clientId': String?,
  // ... other fields
}
```

### Reminder Tracking (Prevents Duplicates)
```dart
// Collection: deadline_reminders_sent
{
  'deadlineId': String,
  'userId': String,
  'reminderDays': int, // 7, 3, or 1
  'sentAt': Timestamp,
}
```

### Notifications (Stored in Firestore)
```dart
// Collection: notifications
{
  'userId': String,
  'type': 'deadline_reminder',
  'title': String,
  'message': String,
  'deadlineId': String,
  'caseId': String?,
  'eventDate': Timestamp,
  'reminderDays': int,
  'isRead': bool,
  'createdAt': Timestamp,
}
```

---

## 🎯 User Role Logic

### Staff
- Gets deadlines from their assigned attorney
- Checks `staff` collection or `users` collection for `assignedAttorneyId`
- Queries calendar events where `assignedTo == assignedAttorneyId`

### Attorneys
- Gets all deadlines assigned to them
- Queries calendar events where `assignedTo == attorneyId`

### Clients
- Gets deadlines related to their cases
- Queries calendar events:
  - Where `clientId == clientId`, OR
  - Where `caseId` matches one of their cases

### Admins
- Gets all deadlines in the system
- Queries all calendar events (no filters)

---

## 🔔 Reminder Messages

### 7 Days Before
- Title: `⏰ Deadline Reminder - 7 Days`
- Message: `{Title} is due in 7 days (MMM dd, yyyy)`

### 3 Days Before
- Title: `⚠️ Deadline Reminder - 3 Days`
- Message: `{Title} is due in 3 days (MMM dd, yyyy)`

### 1 Day Before
- Title: `🚨 Urgent Deadline - Tomorrow`
- Message: `{Title} is due TOMORROW (MMM dd, yyyy)`

---

## 🔧 Configuration

### Reminder Intervals
Currently set to:
- **7 days** before deadline
- **3 days** before deadline
- **1 day** before deadline

To change intervals, modify `_processDeadlineReminder()` in `deadline_reminder_service.dart`.

### Check Frequency
- **Real-time**: Firestore listener (immediate updates)
- **Periodic**: Every 6 hours as backup

To change check frequency, modify `_periodicTimer` interval in `startDeadlineReminderCheck()`.

### Lookahead Period
Service monitors deadlines within the next **8 days**.

To change, modify `nextWeek` calculation in `_setupDeadlineListener()` and deadline query methods.

---

## 🚀 Usage

### Automatic (Recommended)
Service starts automatically on login - no action needed!

### Manual Trigger
```dart
final deadlineReminderService = DeadlineReminderService();
await deadlineReminderService.checkDeadlinesNow();
```

### Stop Service
```dart
final deadlineReminderService = DeadlineReminderService();
deadlineReminderService.stopDeadlineReminderCheck();
```

---

## 📱 Notification Types

### 1. Local Notification (In-App)
- Shows immediately when app is open
- Uses custom sound from `assets/sounds/notification_alert.mp3`
- Android: Custom notification channel with sound
- iOS: Custom sound file

### 2. FCM Push Notification (Background)
- Works when app is in background or closed
- Includes custom sound
- Triggers notification badge

### 3. Firestore Notification (In-App List)
- Stored in `notifications` collection
- Appears in app's notification center
- Marked as read/unread

---

## 🛡️ Error Handling

- ✅ Service gracefully handles missing data
- ✅ Continues working even if FCM fails
- ✅ Prevents duplicate reminders
- ✅ Handles user logout automatically (stops processing when user is null)
- ✅ Logs errors in debug mode

---

## 🧪 Testing

### Test Scenarios

1. **Create a deadline 8 days from now**
   - Should receive reminder in 1 day (7 days before)
   - Should receive reminder 4 days later (3 days before)
   - Should receive reminder 6 days later (1 day before)

2. **Test with different user roles**
   - Staff: Should see deadlines from assigned attorney
   - Attorney: Should see all assigned deadlines
   - Client: Should see deadlines from their cases
   - Admin: Should see all deadlines

3. **Test duplicate prevention**
   - Create same deadline
   - Verify reminder only sent once per interval

---

## 🔍 Debugging

Enable debug logging:
```dart
// Already enabled in debug mode
if (kDebugMode) {
  debugPrint('🔔 Starting deadline reminder service...');
  debugPrint('🔍 Checking deadline reminders for user...');
  debugPrint('✅ Sent 7-day reminder for deadline: ...');
}
```

---

## 📝 Notes

- Service requires app to be running to send reminders
- Reminders are checked every 6 hours (or on calendar event changes)
- Sound notifications require proper audio file setup (see `NOTIFICATION_SETUP_SUMMARY.md`)
- Service automatically stops when user logs out (checks `currentUser`)

---

## 🎉 Benefits

1. **Never miss deadlines** - Automatic reminders prevent missed deadlines
2. **Multi-level alerts** - 7, 3, and 1 day reminders ensure awareness
3. **Sound notifications** - Important alerts are hard to miss
4. **Role-based** - Each user sees only relevant deadlines
5. **Automatic** - Works without manual setup
6. **Integrated** - Works seamlessly with existing calendar system

---

## 🔄 Future Enhancements

Potential improvements:
- [ ] Same-day reminder (on deadline day)
- [ ] Customizable reminder intervals per user
- [ ] Email reminders for critical deadlines
- [ ] Background task support (reminders even when app is closed)
- [ ] Deadline priority levels (urgent, normal, low)
- [ ] Reminder snooze functionality

---

## ✅ Implementation Status

- ✅ Deadline reminder service created
- ✅ Sound notifications implemented
- ✅ Multi-user support (staff, attorney, client, admin)
- ✅ Integrated into login flow
- ✅ Duplicate prevention
- ✅ Firestore notifications
- ✅ FCM push notifications
- ✅ Error handling

**Status**: ✅ **COMPLETE AND READY TO USE**

