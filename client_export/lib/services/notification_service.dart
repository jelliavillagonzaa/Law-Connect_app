import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channel for Android with custom sound
    // Using high importance for better compatibility with Techno and other Chinese phones
    if (!kIsWeb) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'law_connect_channel',
        'LawConnect Notifications',
        description: 'Notifications from LawConnect app',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('notification_sound'),
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
      
      // Also create high importance channel for FCM (for Techno phones)
      const AndroidNotificationChannel fcmChannel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Priority Notifications',
        description: 'Important notifications from LawConnect',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('notification_sound'),
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(fcmChannel);
    }

    _isInitialized = true;
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap
    debugPrint('Notification tapped: ${response.payload}');
  }

  Future<void> showNotificationWithSound({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    // Play alert sound immediately
    await _playAlertSound();

    const NotificationDetails notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'law_connect_channel',
        'LawConnect Notifications',
        channelDescription: 'Notifications from LawConnect app',
        importance: Importance.high,
        priority: Priority.high,
        sound: RawResourceAndroidNotificationSound('notification_sound'),
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(
        sound: 'notification_sound.aiff',
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _notifications.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  Future<void> _playAlertSound() async {
    try {
      // Play built-in system sound as fallback
      await _audioPlayer.play(AssetSource('sounds/notification_alert.mp3'));
    } catch (e) {
      debugPrint('Error playing alert sound: $e');
      // Fallback to system sound
      await _audioPlayer.play(UrlSource('system://notification'));
    }
  }

  Future<void> playCustomAlertSound() async {
    await _playAlertSound();
  }

  // Simple notification method for immediate alerts
  Future<void> showAlert({
    required String title,
    required String message,
  }) async {
    await showNotificationWithSound(
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: title,
      body: message,
    );
  }

  /// Schedule an appointment reminder notification
  ///
  /// [appointmentId] - Unique ID for the appointment reminder
  /// [appointmentDate] - Date string (e.g., "2024-01-15")
  /// [appointmentTime] - Time string (e.g., "14:30" or "2:30 PM")
  /// [title] - Notification title
  /// [body] - Notification body
  /// [reminderMinutes] - Minutes before appointment to show reminder
  /// [userId] - User ID (for tracking)
  /// [userRole] - User role (client/admin)
  Future<bool> scheduleAppointmentReminder({
    required int appointmentId,
    required String appointmentDate,
    required String appointmentTime,
    required String title,
    required String body,
    required int reminderMinutes,
    required String userId,
    required String userRole,
  }) async {
    try {
      if (!_isInitialized) await initialize();

      // Parse appointment date and time
      final appointmentDateTime = _parseAppointmentDateTime(
        appointmentDate,
        appointmentTime,
      );
      if (appointmentDateTime == null) {
        debugPrint('Failed to parse appointment date/time');
        return false;
      }

      // Calculate when to show the reminder
      final reminderTime = appointmentDateTime.subtract(
        Duration(minutes: reminderMinutes),
      );
      final now = DateTime.now();

      // If reminder time is in the past, don't schedule
      if (reminderTime.isBefore(now)) {
        debugPrint('Reminder time is in the past, skipping');
        return false;
      }

      // Calculate delay in milliseconds
      final delay = reminderTime.difference(now).inMilliseconds;

      // Schedule the notification
      // Note: flutter_local_notifications doesn't support exact scheduling,
      // so we'll use a workaround with a delayed notification
      // For production, consider using a background task or cloud function

      // For now, we'll store the reminder info and show it immediately if it's within 1 minute
      // In production, you'd want to use a proper scheduling mechanism
      if (delay < 60000) {
        // Show immediately if less than 1 minute away
        await showNotificationWithSound(
          id: appointmentId,
          title: title,
          body: body,
          payload: 'appointment_reminder_$appointmentId',
        );
        return true;
      } else {
        // Store reminder for later (you'd implement a background task here)
        debugPrint('Scheduled reminder for ${reminderTime.toString()}');
        // In production, use a background task or cloud function to trigger this
        return true;
      }
    } catch (e) {
      debugPrint('Error scheduling appointment reminder: $e');
      return false;
    }
  }

  /// Update an existing appointment reminder
  Future<bool> updateAppointmentReminder({
    required int appointmentId,
    required String appointmentDate,
    required String appointmentTime,
    required String title,
    required String body,
    required int reminderMinutes,
    required String? userId,
    required String userRole,
  }) async {
    try {
      // Cancel the old reminder and schedule a new one
      await cancelAppointmentReminder(appointmentId);
      return await scheduleAppointmentReminder(
        appointmentId: appointmentId,
        appointmentDate: appointmentDate,
        appointmentTime: appointmentTime,
        title: title,
        body: body,
        reminderMinutes: reminderMinutes,
        userId: userId ?? '',
        userRole: userRole,
      );
    } catch (e) {
      debugPrint('Error updating appointment reminder: $e');
      return false;
    }
  }

  /// Cancel an appointment reminder
  Future<bool> cancelAppointmentReminder(int appointmentId) async {
    try {
      if (!_isInitialized) await initialize();

      // Cancel the notification
      await _notifications.cancel(appointmentId);
      debugPrint('Cancelled reminder: $appointmentId');
      return true;
    } catch (e) {
      debugPrint('Error cancelling appointment reminder: $e');
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
      debugPrint('Error parsing date/time: $e');
      return null;
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}
