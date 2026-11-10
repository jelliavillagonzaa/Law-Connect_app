import 'dart:async' show unawaited;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, debugPrint, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import '../utils/out_of_system_notice.dart';
import 'chat_session.dart';
import '../utils/hearing_notification_formatter.dart';
import 'hearing_notification_fanout_service.dart';
import 'notification_service.dart';
import 'firestore_mirror_helper.dart';
import 'system_settings_service.dart';
import 'web_notification.dart';

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
  static final Map<String, int> _recentForegroundPushes = <String, int>{};

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
        await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        await _initializeToken();
      }

      // Set up message handlers (works on all platforms)
      _setupMessageHandlers();
      _hookAuthTokenSave();

      final signedInUid = FirebaseAuth.instance.currentUser?.uid;
      if (signedInUid != null &&
          signedInUid.isNotEmpty &&
          _fcmToken != null &&
          _fcmToken!.isNotEmpty) {
        await _saveTokenToFirestore(_fcmToken!, signedInUid);
      }

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
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          _saveTokenToFirestore(newToken, uid);
        }
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
      if (_isCourtEmailIngestMessage(message)) {
        if (kDebugMode) {
          debugPrint(
            '⏭️ Skipping court email ingest push (IMAP disabled): '
            '${message.notification?.title}',
          );
        }
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          unawaited(
            HearingNotificationFanoutService.instance
                .purgeCourtEmailIngestNotices(uid),
          );
        }
        return;
      }

      if (_isHearingRecordUpdateMessage(message)) {
        if (kDebugMode) {
          debugPrint(
            '⏭️ Skipping duplicate hearing-update push: '
            '${message.notification?.title}',
          );
        }
        return;
      }

      if (kDebugMode) {
        debugPrint(
          '📨 Foreground message received: ${message.notification?.title}',
        );
        debugPrint('📦 Data: ${message.data}');
      }

      final type = '${message.data['type'] ?? ''}'.toLowerCase();
      if (type == 'new_message') {
        final openChat = ChatSession.openChatId;
        final chatId = '${message.data['chatId'] ?? ''}'.trim();
        if (openChat != null && chatId.isNotEmpty && openChat == chatId) {
          return;
        }
      }
      final isHearingPush = type.contains('hearing') ||
          (message.data['caseNo'] ?? '').toString().trim().isNotEmpty;
      final pushDedupeKey = (message.data['hearingDocId'] ??
              message.data['caseNo'] ??
              message.messageId ??
              message.notification?.title ??
              '')
          .toString()
          .trim();
      if (pushDedupeKey.isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        _recentForegroundPushes.removeWhere((_, time) => now - time > 30000);
        if (_recentForegroundPushes.containsKey(pushDedupeKey)) {
          if (kDebugMode) {
            debugPrint(
              '⏭️ Skipping duplicate foreground push card for $pushDedupeKey',
            );
          }
          return;
        }
        _recentForegroundPushes[pushDedupeKey] = now;
      }
      // Browser already paints FCM webpush.notification — a second local card
      // was the "duha ka card" bug for hearing orders.
      if (kIsWeb &&
          isHearingPush &&
          message.notification != null &&
          (message.notification!.title?.trim().isNotEmpty ?? false)) {
        if (kDebugMode) {
          debugPrint(
            '⏭️ Skipping duplicate web local hearing push '
            '(browser already showed FCM card)',
          );
        }
        return;
      }
      final dataTitle = '${message.data['title'] ?? ''}'.trim();
      final dataBody = '${message.data['body'] ?? ''}'.trim();
      final rawTitle = (message.notification?.title ?? dataTitle).trim();
      final rawBody = (message.notification?.body ?? dataBody).trim();
      final title = isHearingPush
          ? HearingNotificationFormatter.buildPopupTitle({
              ...message.data,
              'message': rawBody,
            }, fallback: rawTitle.isNotEmpty
                ? rawTitle
                : 'Court hearing / order — ${message.data['caseNo'] ?? ''}'
                    .trim())
          : (rawTitle.isNotEmpty ? rawTitle : 'Notification');
      final body = isHearingPush
          ? HearingNotificationFormatter.buildPopupBody({
              ...message.data,
              'message': rawBody,
            })
          : rawBody;

      if (title.isNotEmpty && (body.isNotEmpty || isHearingPush)) {
        final hearingTag = '${message.data['hearingDocId'] ?? ''}'.trim();
        final requestId = '${message.data['requestId'] ?? ''}'.trim();
        final notaryTag = type.startsWith('notary') && requestId.isNotEmpty
            ? '$type:$requestId'
            : '';
        final trayTag = notaryTag.isNotEmpty ? notaryTag : hearingTag;

        try {
          await _showForegroundLocalNotification(
            id: notaryTag.isNotEmpty
                ? notaryTag.hashCode & 0x7fffffff
                : _stablePushId(message),
            title: title,
            body: body,
            payload: message.data.toString(),
            tag: trayTag,
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '❌ Error showing foreground notification: $e',
            );
          }
        }

        // Notary / hearing-order: Cloud Function (or prior writer) already
        // created the stable bell row — do not add() a second random card.
        if (type != 'new_message' &&
            !type.startsWith('notary') &&
            !isHearingPush) {
          try {
            await _saveNotificationToFirestore(message);
          } catch (e) {
            if (kDebugMode) {
              debugPrint('❌ Error saving foreground notification: $e');
            }
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

  /// Same hearing keeps one tray row if a second copy arrives.
  int _stablePushId(RemoteMessage message) {
    final hid = '${message.data['hearingDocId'] ?? ''}'.trim();
    if (hid.isEmpty) {
      return DateTime.now().millisecondsSinceEpoch % 100000;
    }
    return hid.hashCode & 0x7fffffff;
  }

  Future<void> _showForegroundLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? tag,
  }) async {
    if (kIsWeb) return;

    final notificationService = NotificationService();
    await notificationService.showNotificationWithSound(
      id: id,
      title: title,
      body: body,
      payload: payload,
      tag: (tag ?? '').isEmpty ? null : tag,
    );
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

  bool _authHooked = false;

  void _hookAuthTokenSave() {
    if (_authHooked) return;
    _authHooked = true;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) return;
      unawaited(saveTokenForUser(user.uid));
    });
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

  String get _tokenPlatform {
    if (kIsWeb) return 'web';
    if (_isAndroid()) return 'android';
    if (_isIOS()) return 'ios';
    return 'other';
  }

  Future<void> _saveTokenToFirestore(String token, [String? userId]) async {
    try {
      final uid = (userId != null && userId.isNotEmpty)
          ? userId
          : FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final platform = _tokenPlatform;
      final existing = await _firestore.collection('users').doc(uid).get();
      final data = existing.data() ?? const <String, dynamic>{};
      final previous = data['fcmToken'];
      final map = data['fcmTokens'];
      final android = map is Map ? map['android'] : null;
      final ios = map is Map ? map['ios'] : null;
      final hasPhone = (android is String && android.length > 20) ||
          (ios is String && ios.length > 20);
      final patch = <String, dynamic>{
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'fcmTokens.$platform': token,
      };
      if (platform == 'web') {
        // Opening the website must not erase the phone token.
        if (!hasPhone &&
            previous is String &&
            previous.length > 20 &&
            previous != token) {
          patch['fcmTokens.android'] = previous;
          patch['fcmToken'] = previous;
        } else if (hasPhone) {
          patch['fcmToken'] =
              (android is String && android.length > 20) ? android : ios;
        } else {
          patch['fcmToken'] = token;
        }
      } else {
        patch['fcmToken'] = token;
      }
      await _firestore.collection('users').doc(uid).set(
        patch,
        SetOptions(merge: true),
      );
      final result = await HybridDatastore.update(
        collection: 'users',
        id: uid,
        patch: patch,
      );
      if (!result.isSuccess) throw Exception(result.failureMessage);
      if (kDebugMode) {
        debugPrint('✅ FCM token saved to Firestore for user: $uid');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error saving token to Firestore: $e');
      }
    }
  }

  /// Phone and browser tokens for one user. The sender is never included.
  Future<List<String>> tokensForUser(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return const [];
      final data = userDoc.data();
      if (data == null) return const [];
      final out = <String>{};
      void add(dynamic raw) {
        if (raw is String && raw.length > 20) out.add(raw);
      }

      final map = data['fcmTokens'];
      String? web;
      if (map is Map) {
        if (map['web'] is String) web = map['web'] as String;
        for (final entry in map.entries) {
          if (entry.key == 'web') continue;
          add(entry.value);
        }
      }
      final top = data['fcmToken'];
      if (top is String && top != web) add(top);
      return out.toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error reading FCM tokens: $e');
      }
      return const [];
    }
  }

  /// Android and iPhone tokens only. The website token is left out.
  Future<List<String>> mobileTokensForUser(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) return const [];
      final data = userDoc.data();
      if (data == null) return const [];
      final out = <String>{};
      void add(dynamic raw) {
        if (raw is String && raw.length > 20) out.add(raw);
      }

      final map = data['fcmTokens'];
      String? web;
      if (map is Map) {
        web = map['web'] is String ? map['web'] as String : null;
        add(map['android']);
        add(map['ios']);
      }
      final top = data['fcmToken'];
      if (top is String && top.length > 20 && top != web) add(top);
      return out.toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error reading mobile FCM tokens: $e');
      }
      return const [];
    }
  }

  /// Push a chat message to one recipient's devices. Does not notify the sender.
  Future<void> sendChatPush({
    required String userId,
    required String title,
    required String body,
    required String chatId,
    required String senderId,
    required String senderName,
  }) async {
    if (userId.isEmpty || userId == senderId) return;
    final settings = await SystemSettingsService.instance.load();
    if (!settings.allowsPush(const {'type': 'new_message'})) return;

    final tokens = await tokensForUser(userId);
    if (tokens.isEmpty) return;

    final data = <String, dynamic>{
      'type': 'new_message',
      'chatId': chatId,
      'senderId': senderId,
      'senderName': senderName,
      'userId': userId,
    };
    for (final token in tokens) {
      await sendNotificationToToken(
        fcmToken: token,
        title: title,
        body: body,
        data: data,
      );
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
      final reqData = <String, dynamic>{
        'fcmToken': fcmToken,
        'title': title,
        'body': body,
        'data': data ?? {},
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      };
      final result = await HybridDatastore.add(
        collection: 'notification_requests',
        data: reqData,
      );
      if (!result.isSuccess) throw Exception(result.failureMessage);

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
    Set<String>? alreadySentTokens,
  }) async {
    try {
      final settings = await SystemSettingsService.instance.load();
      if (!settings.allowsPush(data)) {
        if (kDebugMode) {
          debugPrint('ℹ️ Push skipped by Notification Settings');
        }
        return false;
      }

      if (kDebugMode) {
        debugPrint('═══════════════════════════════════════');
        debugPrint('📤 SENDING FCM NOTIFICATION');
        debugPrint('═══════════════════════════════════════');
        debugPrint('👤 User ID: $userId');
        debugPrint('📋 Title: $title');
        debugPrint('📝 Body: $body');
      }

      final tokens = await tokensForUser(userId);
      if (tokens.isEmpty) {
        if (kDebugMode) {
          debugPrint('❌ No FCM token found for user: $userId');
        }
        return false;
      }

      var queued = false;
      for (final token in tokens) {
        if (alreadySentTokens != null && alreadySentTokens.contains(token)) {
          continue;
        }
        final ok = await sendNotificationToToken(
          fcmToken: token,
          title: title,
          body: body,
          data: data,
        );
        if (ok) {
          queued = true;
          alreadySentTokens?.add(token);
        }
      }
      return queued;
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
    if (_isCourtEmailIngestMessage(message)) return;
    // Hearing/order bell rows use stable IDs from Cloud Functions / fanout.
    final type = '${message.data['type'] ?? ''}'.toLowerCase();
    final hasHearingDoc =
        '${message.data['hearingDocId'] ?? ''}'.trim().isNotEmpty;
    final hasCaseNo = '${message.data['caseNo'] ?? ''}'.trim().isNotEmpty;
    if (type.contains('hearing') || hasHearingDoc || hasCaseNo) return;
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

      final notifData = <String, dynamic>{
        'userId': userId,
        'clientId': userId,
        'title': message.notification?.title ?? 'Notification',
        'message': message.notification?.body ?? '',
        'type': message.data['type'] ?? 'general',
        'data': message.data,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      await HybridDatastore.add(collection: 'notifications', data: notifData);

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
          final chatId = '${data['chatId'] ?? ''}'.trim();
          final senderId = '${data['senderId'] ?? ''}'.trim();
          final senderName = '${data['senderName'] ?? 'Message'}'.trim();
          if (chatId.isNotEmpty && senderId.isNotEmpty) {
            Get.toNamed(
              '/ChatMessage',
              arguments: {
                'chatId': chatId,
                'senderId': senderId,
                'senderName': senderName.isEmpty ? 'Message' : senderName,
              },
            );
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

  bool _isCourtEmailIngestMessage(RemoteMessage message) {
    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    if (isOutOfSystemCourtNoticeTitle(title) ||
        isOutOfSystemPumpedNoticeText('$title\n$body')) {
      return true;
    }

    final type = (message.data['type'] as String? ?? '').toLowerCase();
    if (type == 'court_email_ingest') return true;
    if (type.startsWith('court_') && !type.contains('hearing')) return true;

    final queueDocId = ((message.data['queueDocId'] ??
                message.data['queuedDocId']) as String? ??
            '')
        .toLowerCase();
    if (queueDocId.contains('imap')) return true;

    return false;
  }

  bool _isHearingRecordUpdateMessage(RemoteMessage message) {
    final title = message.notification?.title ?? '';
    final type = (message.data['type'] as String? ?? '').toLowerCase();
    return isHearingRecordUpdateNotification({
      'title': title,
      'type': type,
    });
  }
}
