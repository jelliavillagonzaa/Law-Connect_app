# 🧪 Testing Guide - Appointment Reminder System

## ✅ How to Verify Everything is Working

This guide will help you test each component of the appointment reminder system step by step.

---

## 📋 Pre-Testing Checklist

Before testing, ensure:

- [ ] Cloud Function is deployed: `firebase deploy --only functions`
- [ ] Sound file `alert_sound.wav` is in all three locations:
  - `assets/sounds/alert_sound.wav`
  - `android/app/src/main/res/raw/alert_sound.wav`
  - `ios/Runner/Resources/alert_sound.wav`
- [ ] App is built and running on device/emulator
- [ ] User is logged in (attorney/admin for scheduling)
- [ ] User has granted notification permissions
- [ ] User has granted calendar permissions (if prompted)

---

## 🧪 Test 1: Schedule an Appointment

### Steps:

1. **Open the app** and log in as an attorney/admin
2. **Navigate to a case** (or create a test case)
3. **Open Case Details page**
4. **Enter appointment details:**
   - Date: Use a date in the future (e.g., tomorrow)
   - Time: Use a time that's at least 1 hour from now
   - Example: Date = "2024-12-27", Time = "14:30"
5. **Click "Schedule Appointment"**

### What to Look For:

✅ **Success Message:**
- Should see: "Appointment scheduled! Added to calendar and notifications sent."

✅ **Console Logs (if in debug mode):**
```
═══════════════════════════════════════
📅 SCHEDULING APPOINTMENT
═══════════════════════════════════════
   Date: 2024-12-27
   Time: 14:30
✅ Appointment saved to Firestore
✅ Appointment document created in appointments collection
   Cloud Function will send FCM notifications automatically
✅ Appointment added to calendar
✅ Local reminder scheduled
   Reminder will fire at: [30 minutes before appointment]
```

---

## 🔔 Test 2: Verify FCM Push Notification

### Steps:

1. **Check Cloud Function Logs:**
   ```bash
   firebase functions:log
   ```
   Or in Firebase Console: Functions → Logs

2. **Look for:**
   ```
   📅 APPOINTMENT CREATED - SENDING FCM
   👤 Client ID: [user-id]
   👨‍⚖️ Attorney ID: [attorney-id]
   📱 Client FCM Token: Found
   📱 Attorney FCM Token: Found
   ✅ FCM notification sent to CLIENT
   ✅ FCM notification sent to ATTORNEY
   ```

3. **Check Device:**
   - Client's device should receive push notification
   - Attorney's device should receive push notification
   - Notification title: "Appointment Scheduled"
   - Notification body: "Your appointment is scheduled on [date/time]"

### If FCM Not Working:

- Check if user has `fcmToken` in Firestore: `users/{userId}/fcmToken`
- Check Cloud Function logs for errors
- Verify FCM service is initialized in `main.dart`
- Check device notification permissions

---

## 📅 Test 3: Verify Calendar Integration

### Steps:

1. **Open device calendar app:**
   - Android: Google Calendar
   - iOS: Calendar app

2. **Navigate to the appointment date**

3. **Look for:**
   - Event with case title
   - Description: "Appointment for case: [case-title]"
   - Start time matches scheduled time
   - End time is 1 hour after start
   - Reminder set for 30 minutes before

### If Calendar Not Working:

- Check console logs for calendar errors
- Verify `add_2_calendar` package is installed: `flutter pub get`
- Check if calendar permissions are granted
- Try manually adding an event to verify calendar app works

---

## 🔔 Test 4: Verify Local Reminder (30 Minutes Before)

### Steps:

1. **Schedule a test appointment:**
   - Date: Today
   - Time: 35-40 minutes from now
   - This ensures reminder fires in 5-10 minutes

2. **Check Console Logs:**
   ```
   ✅ Local reminder scheduled
   Reminder will fire at: [exact datetime]
   ```

3. **Wait for reminder time** (30 minutes before appointment)

4. **Verify notification appears:**
   - Title: "Appointment Reminder"
   - Body: "Your appointment for '[case-title]' is in 30 minutes"
   - **Sound should play** (alert_sound.wav)

### Quick Test (5 Minutes):

1. **Schedule appointment for 35 minutes from now**
2. **Wait 5 minutes**
3. **Reminder should fire** (30 minutes before = 5 minutes from now)

### If Local Reminder Not Working:

- Check if reminder time is in the past (won't schedule)
- Verify sound file exists in all locations
- Check device notification permissions
- Check console logs for scheduling errors
- Verify `NotificationService` is initialized in `main.dart`

---

## 🔍 Test 5: Check Firestore Data

### Steps:

1. **Open Firebase Console** → Firestore Database

2. **Check `appointments` collection:**
   - Should see new document with appointment ID
   - Fields:
     - `caseId`: Case ID
     - `clientId`: Client user ID
     - `attorneyId`: Attorney user ID
     - `appointmentDate`: Date string
     - `appointmentTime`: Time string
     - `status`: "scheduled"
     - `notificationsSent`: { client: true, attorney: true }
     - `remindersScheduled`: true

3. **Check `cases` collection:**
   - Case document should have:
     - `appointmentDate`: Date string
     - `appointmentTime`: Time string
     - `appointmentId`: Appointment document ID
     - `clientReminderId`: Number
     - `attorneyReminderId`: Number (if attorney assigned)

---

## 📱 Test 6: Verify on Both Devices

### Test Client Device:

1. **Log in as client**
2. **Check for FCM notification** (should arrive immediately)
3. **Check calendar** (if client also gets calendar event)
4. **Wait for local reminder** (30 minutes before)

### Test Attorney Device:

1. **Log in as attorney**
2. **Schedule appointment**
3. **Check for FCM notification**
4. **Check calendar** (should have event)
5. **Wait for local reminder**

---

## 🐛 Troubleshooting Checklist

### FCM Not Received?

- [ ] Check Cloud Function logs: `firebase functions:log`
- [ ] Verify user has `fcmToken` in Firestore
- [ ] Check device notification permissions
- [ ] Verify FCM service initialized in `main.dart`
- [ ] Check if device is online

### Calendar Not Adding?

- [ ] Check console logs for errors
- [ ] Verify `add_2_calendar` package installed
- [ ] Check calendar app permissions
- [ ] Try manually opening calendar app
- [ ] Verify date/time format is correct

### Local Reminder Not Firing?

- [ ] Check if reminder time is in the future
- [ ] Verify sound file exists in all locations
- [ ] Check device notification permissions
- [ ] Check console logs for scheduling errors
- [ ] Verify `NotificationService` initialized
- [ ] Check device battery optimization settings (Android)

### Sound Not Playing?

- [ ] Verify `alert_sound.wav` in:
  - `assets/sounds/`
  - `android/app/src/main/res/raw/`
  - `ios/Runner/Resources/`
- [ ] Check file format (WAV recommended)
- [ ] Check device volume settings
- [ ] Check device notification sound settings

---

## 📊 Expected Results Summary

| Component | Expected Result | How to Verify |
|-----------|----------------|---------------|
| **FCM Push** | Notification received immediately | Check device, check Cloud Function logs |
| **Calendar** | Event added to calendar | Open calendar app, check date/time |
| **Local Reminder** | Notification 30 min before | Wait for scheduled time, check device |
| **Sound** | Custom sound plays | Listen when notification fires |
| **Firestore** | Appointment document created | Check Firebase Console |

---

## 🎯 Quick Test Script

Run this quick test to verify everything:

```bash
# 1. Deploy Cloud Function
cd functions
npm install
firebase deploy --only functions:sendAppointmentNotifications

# 2. Run app in debug mode
flutter run

# 3. Schedule appointment for 35 minutes from now

# 4. Check logs
# - Console logs in Flutter
# - Cloud Function logs: firebase functions:log

# 5. Wait 5 minutes
# - Local reminder should fire

# 6. Check calendar
# - Open device calendar app
# - Verify event exists
```

---

## ✅ Success Indicators

You'll know it's working when:

1. ✅ **FCM Notification Received:**
   - Both client and attorney get push notification
   - Notification has correct title and body
   - Sound plays (if device allows)

2. ✅ **Calendar Event Added:**
   - Event appears in device calendar
   - Date and time are correct
   - Reminder is set for 30 minutes before

3. ✅ **Local Reminder Fires:**
   - Notification appears 30 minutes before appointment
   - Title: "Appointment Reminder"
   - Body: "Your appointment for '[case-title]' is in 30 minutes"
   - Custom sound plays

4. ✅ **Firestore Updated:**
   - Appointment document created
   - `notificationsSent` shows both true
   - `remindersScheduled` is true

---

## 📝 Testing Checklist

Use this checklist when testing:

- [ ] Schedule appointment successfully
- [ ] FCM notification received (client)
- [ ] FCM notification received (attorney)
- [ ] Calendar event added (attorney device)
- [ ] Local reminder scheduled (check logs)
- [ ] Local reminder fires at correct time
- [ ] Custom sound plays
- [ ] Firestore document created correctly
- [ ] All console logs show success

---

## 🆘 Still Not Working?

If something isn't working:

1. **Check all logs:**
   - Flutter console logs
   - Cloud Function logs: `firebase functions:log`
   - Device notification logs

2. **Verify setup:**
   - All files are in place
   - All dependencies installed
   - All permissions granted

3. **Test components individually:**
   - Test calendar separately
   - Test notifications separately
   - Test FCM separately

4. **Check documentation:**
   - See `COMPLETE_APPOINTMENT_REMINDER_SYSTEM.md`
   - See package documentation

---

## 🎉 Success!

If all tests pass, your appointment reminder system is working perfectly! 🚀

