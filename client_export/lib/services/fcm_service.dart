import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, debugPrint, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart';
import 'notification_service.dart';

/// FCM Service for sending push notifications
///
/// This service handles:
/// - Getting FCM tokens (compatible with all Android/iOS versions)
/// - Sending FCM notifications to users
/// - Storing FCM tokens in Firestore
/// - Platform-specific handling for Android, iOS, and Web
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _fcmToken;
  bool _isInitialized = false;

  /// Initialize FCM and request permissions
  /// Compatible with all Android and iOS versions
  /// Special handling for Techno and other Chinese Android phones
  Future<void> initialize() async {
    if (_isInitialized) {
      if (kDebugMode) {
        debugPrint('🔔 FCM Service already initialized');
      }
      return;
    }

    try {
      if (kDebugMode) {
        debugPrint('🔔 Initializing FCM Service...');
        debugPrint('📱 Platform: ${_getPlatformName()}');
        if (_isAndroid()) {
          debugPrint('📱 Android Device - Checking for Techno/Chinese phone optimizations...');
        }
      }

      // Skip permission request on web (handled differently)
      if (!kIsWeb) {
        // Request notification permissions (works on all Android/iOS versions)
        NotificationSettings settings = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
          announcement: false,
          carPlay: false,
          criticalAlert: false,
        );

        if (kDebugMode) {
          debugPrint(
            '📱 Notification permission status: ${settings.authorizationStatus}',
          );
          debugPrint(
            '   Alert: ${settings.alert}, Badge: ${settings.badge}, Sound: ${settings.sound}',
          );
        }

        // Try to get token even if permission is provisional (iOS)
        // On Android, token can be obtained even without explicit permission
        // This is especially important for Techno phones which may have strict permissions
        if (settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional) {
          await _initializeToken();
        } else {
          if (kDebugMode) {
            debugPrint('⚠️ Notification permission denied or not determined');
            if (_isAndroid()) {
              debugPrint('   ⚠️ For Techno phones: Please enable notifications in Settings');
              debugPrint('   ⚠️ Settings > Apps > LawConnect > Notifications > Enable');
              debugPrint('   ⚠️ Also check: Battery Optimization > LawConnect > Don\'t optimize');
            }
          }
          // On Android, try to get token anyway (may work on older versions or Techno phones)
          if (_isAndroid()) {
            if (kDebugMode) {
              debugPrint('   Attempting to get token on Android anyway...');
              debugPrint('   This may work on Techno phones even without explicit permission');
            }
            await _initializeToken();
          }
        }
      } else {
        // Web platform - get token directly
        await _initializeToken();
      }

      // Set up message handlers (works on all platforms)
      _setupMessageHandlers();

      _isInitialized = true;

      if (kDebugMode) {
        debugPrint('✅ FCM Service initialized successfully');
        if (_isAndroid()) {
          debugPrint('📱 For Techno phones: If notifications don\'t work, check:');
          debugPrint('   1. Settings > Apps > LawConnect > Notifications (Enable)');
          debugPrint('   2. Settings > Battery > Battery Optimization > LawConnect (Don\'t optimize)');
          debugPrint('   3. Settings > Apps > LawConnect > Auto-start (Enable)');
          debugPrint('   4. Settings > Apps > LawConnect > Background Activity (Enable)');
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ FCM initialization error: $e');
        debugPrint('Stack trace: $stackTrace');
        if (_isAndroid()) {
          debugPrint('⚠️ For Techno phones, this error might be due to:');
          debugPrint('   - Battery optimization blocking FCM');
          debugPrint('   - Auto-start disabled');
          debugPrint('   - Background restrictions');
        }
      }
      // Don't set _isInitialized to true if initialization failed
      // This allows retry on next call
    }
  }

  /// Initialize FCM token with retry logic
  Future<void> _initializeToken() async {
    try {
      // Get FCM token with retry mechanism
      int retries = 3;
      while (retries > 0) {
        try {
          _fcmToken = await _messaging.getToken();
          if (_fcmToken != null && _fcmToken!.isNotEmpty) {
            if (kDebugMode) {
              debugPrint(
                '✅ FCM Token obtained: ${_fcmToken!.substring(0, _fcmToken!.length > 20 ? 20 : _fcmToken!.length)}...',
              );
            }
            break;
          }
        } catch (e) {
          retries--;
          if (retries > 0) {
            if (kDebugMode) {
              debugPrint('⚠️ Failed to get token, retrying... ($retries left)');
            }
            await Future.delayed(const Duration(seconds: 2));
          } else {
            if (kDebugMode) {
              debugPrint('❌ Failed to get FCM token after retries: $e');
              if (kIsWeb &&
                  e.toString().contains('service-worker')) {
                debugPrint(
                  '   Web: add web/firebase-messaging-sw.js (JavaScript, not HTML) '
                  'and do a full restart of flutter run -d chrome.',
                );
              }
            }
          }
        }
      }

      // Listen for token refresh (works on all platforms)
      _messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        if (kDebugMode) {
          debugPrint(
            '🔄 FCM Token refreshed: ${newToken.substring(0, newToken.length > 20 ? 20 : newToken.length)}...',
          );
        }
        _saveTokenToFirestore(newToken);
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error initializing token: $e');
      }
    }
  }

  /// Set up message handlers for all platforms
  void _setupMessageHandlers() {
    // Handle foreground messages - SHOW LOCAL NOTIFICATION
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (kDebugMode) {
        debugPrint(
          '📨 Foreground message received: ${message.notification?.title}',
        );
        debugPrint('📦 Data: ${message.data}');
      }

      // Show local notification when app is in foreground
      if (message.notification != null) {
        try {
          final notificationService = NotificationService();
          await notificationService.showNotificationWithSound(
            id: DateTime.now().millisecondsSinceEpoch % 100000,
            title: message.notification!.title ?? 'Notification',
            body: message.notification!.body ?? '',
            payload: message.data.toString(),
          );

          // Save notification to Firestore
          await _saveNotificationToFirestore(message);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ Error showing foreground notification: $e');
          }
        }
      }
    });

    // Handle when app is opened from notification (background state)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (kDebugMode) {
        debugPrint(
          '📨 App opened from notification: ${message.notification?.title}',
        );
        debugPrint('📦 Data: ${message.data}');
      }
      // Handle navigation based on notification type
      _handleNotificationTap(message);
    });

    // Check if app was opened from a notification (when app was terminated)
    // This works on all platforms
    _messaging.getInitialMessage().then((initialMessage) {
      if (initialMessage != null) {
        if (kDebugMode) {
          debugPrint('📨 App opened from terminated state notification');
        }
        _handleNotificationTap(initialMessage);
      }
    });
  }

  /// Get platform name for debugging
  String _getPlatformName() {
    if (kIsWeb) return 'Web';
    if (_isAndroid()) return 'Android';
    if (_isIOS()) return 'iOS';
    return 'Unknown';
  }

  /// Check if running on Android
  bool _isAndroid() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  /// Check if running on iOS
  bool _isIOS() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Get current FCM token
  /// Compatible with all Android/iOS versions
  Future<String?> getToken() async {
    try {
      if (_fcmToken == null || _fcmToken!.isEmpty) {
        // Try to get token with retry logic
        int retries = 2;
        while (retries > 0) {
          try {
            _fcmToken = await _messaging.getToken();
            if (_fcmToken != null && _fcmToken!.isNotEmpty) {
              break;
            }
          } catch (e) {
            retries--;
            if (retries > 0) {
              await Future.delayed(const Duration(seconds: 1));
            } else {
              if (kDebugMode) {
                debugPrint('❌ Failed to get FCM token: $e');
              }
            }
          }
        }
      }
      return _fcmToken;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error getting FCM token: $e');
      }
      return null;
    }
  }

  /// Save FCM token to Firestore for a user
  Future<void> saveTokenForUser(String userId) async {
    try {
      final token = await getToken();
      if (token != null) {
        await _saveTokenToFirestore(token, userId);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error saving FCM token: $e');
      }
    }
  }

  Future<void> _saveTokenToFirestore(String token, [String? userId]) async {
    try {
      if (userId != null) {
        await _firestore.collection('users').doc(userId).update({
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        });
        if (kDebugMode) {
          debugPrint('✅ FCM token saved to Firestore for user: $userId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error saving token to Firestore: $e');
      }
    }
  }

  /// Get FCM token for a user from Firestore
  Future<String?> getUserFCMToken(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        return userDoc.data()?['fcmToken'] as String?;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error getting user FCM token: $e');
      }
      return null;
    }
  }

  /// Send FCM notification directly to an FCM token
  ///
  /// This is useful for sending notifications to users who don't have an account yet
  /// (e.g., during signup OTP verification)
  ///
  /// [fcmToken] - FCM token to send notification to
  /// [title] - Notification title
  /// [body] - Notification body
  /// [data] - Additional data payload
  Future<bool> sendNotificationToToken({
    required String fcmToken,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('═══════════════════════════════════════');
        debugPrint('📤 SENDING FCM NOTIFICATION TO TOKEN');
        debugPrint('═══════════════════════════════════════');
        debugPrint('🔑 FCM Token: ${fcmToken.substring(0, 20)}...');
        debugPrint('📋 Title: $title');
        debugPrint('📝 Body: $body');
      }

      // Store notification request in Firestore (Cloud Function will send it)
      await _firestore.collection('notification_requests').add({
        'fcmToken': fcmToken,
        'title': title,
        'body': body,
        'data': data ?? {},
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      if (kDebugMode) {
        debugPrint('✅ Notification request queued in Firestore');
        debugPrint('   Cloud Function will process and send the notification');
        debugPrint('═══════════════════════════════════════');
      }

      return true;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ ERROR SENDING FCM NOTIFICATION TO TOKEN');
        debugPrint('🔴 Error: $e');
        debugPrint('🔴 Stack Trace: $stackTrace');
        debugPrint('═══════════════════════════════════════');
      }
      return false;
    }
  }

  /// Send FCM notification to a user
  ///
  /// This uses Firebase Cloud Functions or HTTP API to send notifications
  /// For production, you should use Cloud Functions for security
  ///
  /// [userId] - User ID to send notification to
  /// [title] - Notification title
  /// [body] - Notification body
  /// [data] - Additional data payload
  Future<bool> sendNotificationToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('═══════════════════════════════════════');
        debugPrint('📤 SENDING FCM NOTIFICATION');
        debugPrint('═══════════════════════════════════════');
        debugPrint('👤 User ID: $userId');
        debugPrint('📋 Title: $title');
        debugPrint('📝 Body: $body');
      }

      // Get user's FCM token
      final fcmToken = await getUserFCMToken(userId);

      if (fcmToken == null) {
        if (kDebugMode) {
          debugPrint('❌ No FCM token found for user: $userId');
        }
        return false;
      }

      // For now, we'll use Firestore to trigger Cloud Function
      // Or you can use HTTP API directly (requires server key)
      // This is a simplified version - in production, use Cloud Functions

      // Option 1: Store notification request in Firestore (Cloud Function will send it)
      await _firestore.collection('notification_requests').add({
        'userId': userId,
        'fcmToken': fcmToken,
        'title': title,
        'body': body,
        'data': data ?? {},
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      if (kDebugMode) {
        debugPrint('✅ Notification request queued in Firestore');
        debugPrint('   Cloud Function will process and send the notification');
        debugPrint('═══════════════════════════════════════');
      }

      return true;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ ERROR SENDING FCM NOTIFICATION');
        debugPrint('🔴 Error: $e');
        debugPrint('🔴 Stack Trace: $stackTrace');
        debugPrint('═══════════════════════════════════════');
      }
      return false;
    }
  }

  /// Send appointment scheduled notification to client
  Future<bool> sendAppointmentScheduledToClient({
    required String clientId,
    required String appointmentDate,
    required String appointmentTime,
    required String caseTitle,
  }) async {
    final formattedDate = _formatDate(appointmentDate);
    final formattedTime = _formatTime(appointmentTime);

    return await sendNotificationToUser(
      userId: clientId,
      title: 'Appointment Scheduled',
      body:
          'Your appointment is scheduled on $formattedDate at $formattedTime.',
      data: {
        'type': 'appointment_scheduled',
        'caseTitle': caseTitle,
        'appointmentDate': appointmentDate,
        'appointmentTime': appointmentTime,
      },
    );
  }

  /// Send appointment scheduled notification to attorney
  Future<bool> sendAppointmentScheduledToAttorney({
    required String attorneyId,
    required String appointmentDate,
    required String appointmentTime,
    required String caseTitle,
    String? clientName,
  }) async {
    final formattedDate = _formatDate(appointmentDate);
    final formattedTime = _formatTime(appointmentTime);

    return await sendNotificationToUser(
      userId: attorneyId,
      title: 'Appointment Scheduled',
      body:
          'You have an appointment with ${clientName ?? 'a client'} on $formattedDate at $formattedTime.',
      data: {
        'type': 'appointment_scheduled',
        'caseTitle': caseTitle,
        'appointmentDate': appointmentDate,
        'appointmentTime': appointmentTime,
        'clientName': clientName,
      },
    );
  }

  String _formatDate(String date) {
    // Convert "2024-01-15" to "January 15, 2024"
    try {
      final parts = date.split('-');
      if (parts.length == 3) {
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);
        final months = [
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        ];
        return '${months[month - 1]} $day, $year';
      }
    } catch (e) {
      // If parsing fails, return original
    }
    return date;
  }

  String _formatTime(String time) {
    // Convert "14:30" to "2:30 PM" or keep "2:30 PM" as is
    try {
      if (time.contains('AM') || time.contains('PM')) {
        return time; // Already formatted
      }
      final parts = time.split(':');
      if (parts.length == 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
      }
    } catch (e) {
      // If parsing fails, return original
    }
    return time;
  }

  /// Save notification to Firestore when received
  Future<void> _saveNotificationToFirestore(RemoteMessage message) async {
    try {
      // Get userId from message data or current user
      String? userId = message.data['userId'] as String?;

      if (userId == null || userId.isEmpty) {
        // Try to get current user from Firebase Auth
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          userId = currentUser.uid;
        } else {
          if (kDebugMode) {
            debugPrint(
              '⚠️ No userId found in message data and no current user',
            );
          }
          return;
        }
      }

      await _firestore.collection('notifications').add({
        'userId': userId,
        'clientId': userId, // For client notifications
        'title': message.notification?.title ?? 'Notification',
        'message': message.notification?.body ?? '',
        'type': message.data['type'] ?? 'general',
        'data': message.data,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        debugPrint('✅ Notification saved to Firestore for user: $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error saving notification to Firestore: $e');
      }
    }
  }

  /// Handle notification tap - navigate to relevant screen
  void _handleNotificationTap(RemoteMessage message) {
    try {
      final data = message.data;
      final type = data['type'] as String?;

      if (kDebugMode) {
        debugPrint('🔔 Handling notification tap - Type: $type');
      }

      switch (type) {
        case 'appointment_scheduled':
        case 'appointment_3day_reminder':
          // Navigate to appointments or case details
          final caseId = data['caseId'] as String?;
          if (caseId != null) {
            // Navigate to case detail page if route exists
            // Get.toNamed('/CaseDetail', arguments: {'caseId': caseId});
            if (kDebugMode) {
              debugPrint('📍 Would navigate to case: $caseId');
            }
          }
          break;
        case 'otp_verification':
          // Navigate to OTP verification if needed
          if (kDebugMode) {
            debugPrint('📍 Would navigate to OTP verification');
          }
          break;
        case 'new_message':
          // Navigate to chat
          final chatId = data['chatId'] as String?;
          if (chatId != null) {
            // Get.toNamed('/Chat', arguments: {'chatId': chatId});
            if (kDebugMode) {
              debugPrint('📍 Would navigate to chat: $chatId');
            }
          }
          break;
        case 'court_email_ingest':
          if (kDebugMode) {
            debugPrint(
              '📍 Court email ingested — open AI calendar queue / case from notification list',
            );
          }
          break;
        default:
          // Navigate to notifications screen
          // Get.toNamed('/Notifications');
          if (kDebugMode) {
            debugPrint('📍 Would navigate to notifications screen');
          }
          break;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error handling notification tap: $e');
      }
    }
  }
}
