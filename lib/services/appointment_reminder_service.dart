import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'enhanced_appointment_service.dart';

/// Service to process 3-day appointment reminders
/// This runs client-side and doesn't require Cloud Functions (Blaze plan)
///
/// Uses a combination of:
/// 1. Firestore listener to watch for reminders due today
/// 2. Periodic check (every hour) as backup
/// 3. Check on app startup
class AppointmentReminderService {
  static final AppointmentReminderService _instance =
      AppointmentReminderService._internal();
  factory AppointmentReminderService() => _instance;
  AppointmentReminderService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final EnhancedAppointmentService _appointmentService =
      EnhancedAppointmentService();
  Timer? _periodicTimer;
  StreamSubscription? _reminderStreamSubscription;
  bool _isRunning = false;

  /// Start checking for reminders
  /// This should be called when user logs in
  void startReminderCheck() {
    if (_isRunning) return; // Already running

    _isRunning = true;
    if (kDebugMode) debugPrint('🔄 Starting appointment reminder service...');

    // Check immediately on start
    _checkAndProcessReminders();

    // Set up Firestore listener for reminders due today
    _setupReminderListener();

    // Also check periodically (every hour) as backup
    _periodicTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _checkAndProcessReminders();
    });
  }

  /// Stop checking reminders
  /// This should be called when user logs out
  void stopReminderCheck() {
    if (!_isRunning) return;

    _isRunning = false;
    if (kDebugMode) debugPrint('⏹️ Stopping appointment reminder service...');

    _periodicTimer?.cancel();
    _periodicTimer = null;
    _reminderStreamSubscription?.cancel();
    _reminderStreamSubscription = null;
  }

  /// Set up Firestore listener to watch for reminders due today
  void _setupReminderListener() {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      final morningTime = todayStart.add(const Duration(hours: 8)); // 8:00 AM
      final morningEnd = todayStart.add(const Duration(hours: 9)); // 9:00 AM

      // Listen for 3-day reminders
      _firestore
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
          .snapshots()
          .listen((snapshot) {
            if (snapshot.docs.isNotEmpty) {
              if (kDebugMode) {
                debugPrint(
                  '📅 Found ${snapshot.docs.length} 3-day reminders due today',
                );
              }
              _checkAndProcessReminders();
            }
          });

      // Also listen for same-day morning reminders (8-9 AM)
      _firestore
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
          .snapshots()
          .listen((snapshot) {
            if (snapshot.docs.isNotEmpty) {
              if (kDebugMode) {
                debugPrint(
                  '📅 Found ${snapshot.docs.length} same-day reminders for this morning',
                );
              }
              _checkAndProcessReminders();
            }
          });
    } catch (e) {
      if (kDebugMode) debugPrint('Error setting up reminder listener: $e');
    }
  }

  /// Check and process pending 3-day reminders
  Future<void> _checkAndProcessReminders() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return; // User not logged in

      // Only admins and attorneys should process reminders
      // (to avoid duplicate processing)
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userRole = userDoc.data()?['role'];

      // Allow admins, attorneys, and staff to process reminders
      if (userRole != 'admin' &&
          userRole != 'attorney' &&
          userRole != 'staff') {
        return; // Clients don't process reminders
      }

      if (kDebugMode)
        debugPrint('🔍 Checking for 3-day appointment reminders...');

      // Process reminders using the appointment service
      await _appointmentService.processThreeDayReminders();
    } catch (e) {
      if (kDebugMode) debugPrint('Error checking reminders: $e');
    }
  }

  /// Manually trigger reminder check (can be called from admin panel)
  Future<void> checkRemindersNow() async {
    await _checkAndProcessReminders();
  }
}
