import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'services/hearing_calendar_fields.dart';
import 'utils/hearing_sms_formatter.dart';
import 'utils/out_of_system_notice.dart';

/// Top-level function for handling background messages
/// This must be a top-level function, not a class method
///
/// IMPORTANT: This function must be registered in main.dart:
/// FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized
  await Firebase.initializeApp();

  if (kDebugMode) {
    debugPrint('═══════════════════════════════════════');
    debugPrint('📨 BACKGROUND MESSAGE RECEIVED');
    debugPrint('═══════════════════════════════════════');
    debugPrint('📋 Title: ${message.notification?.title}');
    debugPrint('📝 Body: ${message.notification?.body}');
    debugPrint('📦 Data: ${message.data}');
    debugPrint('═══════════════════════════════════════');
  }

  final incomingTitle = message.notification?.title ?? '';
  final incomingBody = message.notification?.body ?? '';
  if (isOutOfSystemCourtNoticeTitle(incomingTitle) ||
      isOutOfSystemPumpedNoticeText('$incomingTitle\n$incomingBody')) {
    if (kDebugMode) {
      debugPrint('⏭️ Skipping out-of-system court notice in background');
    }
    return;
  }

  final incomingType = (message.data['type'] as String? ?? '').toLowerCase();
  if (incomingType == 'new_message') {
    return;
  }
  // Notary already wrote the bell row before this push was queued.
  if (incomingType.startsWith('notary')) {
    return;
  }

  // Hearing: replace the system card when Date is missing from the body.
  // Same Android [tag] as FCM so this stays one card.
  if (incomingType.contains('hearing') ||
      '${message.data['caseNo'] ?? ''}'.trim().isNotEmpty) {
    final systemBody =
        (message.notification?.body ?? message.data['body'] ?? '')
            .toString()
            .trim();
    final hearingDate = '${message.data['hearingDate'] ?? ''}'.trim();
    final hasDateLine = hearingDate.isNotEmpty &&
        (systemBody.startsWith('Date:') ||
            systemBody.contains('Date: $hearingDate'));
    if (hearingDate.isNotEmpty && !hasDateLine) {
      await _showHearingBackgroundPopup(message);
    }
    return;
  }

  // FCM already posted the card. A second local popup was the extra push.
  final hasSystemNotification =
      (message.notification?.title ?? '').trim().isNotEmpty ||
      (message.notification?.body ?? '').trim().isNotEmpty;
  if (!hasSystemNotification) {
    await _showBackgroundPopup(message);
  }

  // Save notification to Firestore
  try {
    final firestore = FirebaseFirestore.instance;
    final userId = message.data['userId'] as String?;

    if (userId != null && userId.isNotEmpty) {
      await firestore.collection('notifications').add({
        'userId': userId,
        'clientId': userId,
        'title': message.notification?.title ?? 'Notification',
        'message': message.notification?.body ?? '',
        'type': message.data['type'] ?? 'general',
        'data': message.data,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        debugPrint(
          '✅ Background notification saved to Firestore for user: $userId',
        );
      }
    } else {
      if (kDebugMode) {
        debugPrint('⚠️ No userId found in background message data');
      }
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('❌ Error saving background notification: $e');
    }
  }
}

Future<void> _showHearingBackgroundPopup(RemoteMessage message) async {
  final rawMap = Map<String, dynamic>.from(message.data);
  final caseNo = '${message.data['caseNo'] ?? ''}'.trim();
  final hearingDate = '${message.data['hearingDate'] ?? ''}'.trim();
  final hearingTime = '${message.data['hearingTime'] ?? ''}'.trim();
  final venue = HearingCalendarFields.resolveVenueForDisplay(rawMap);
  final location = (venue.isNotEmpty && !HearingCalendarFields.isBareLocation(venue))
      ? venue
      : '${message.data['location'] ?? message.data['courtBranch'] ?? ''}'.trim();
  final caseTitle = '${message.data['caseTitle'] ?? ''}'.trim();
  final clientName = '${message.data['clientName'] ?? ''}'.trim();
  final reminderKind = '${message.data['reminderKind'] ?? ''}'.trim();

  // Same body as PhilSMS / Semaphore hearing texts (includes Date:).
  final body = HearingSmsFormatter.build(
    caseNo: caseNo,
    caseTitle: caseTitle,
    clientName: clientName,
    hearingDate: hearingDate,
    hearingTime: hearingTime,
    location: location,
    reminderKind: reminderKind,
  );

  var title = (message.notification?.title ?? message.data['title'] ?? '')
      .toString()
      .trim();
  if (title.isEmpty) {
    final validCaseNo = (caseNo.isNotEmpty && !HearingCalendarFields.isPlaceholderCaseNo(caseNo))
        ? caseNo
        : (caseTitle.isNotEmpty ? caseTitle : '');
    title = validCaseNo.isNotEmpty
        ? 'Court hearing / order — $validCaseNo'
        : 'Court hearing / order';
  }
  if (hearingDate.isNotEmpty && !title.contains(hearingDate)) {
    title = '$title · $hearingDate';
  }

  if (body.isEmpty && title.isEmpty) return;
  await _showTaggedPopup(
    message: message,
    title: title,
    body: body.isEmpty ? title : body,
  );
}

Future<void> _showBackgroundPopup(RemoteMessage message) async {
  final title = (message.notification?.title ??
          message.data['title'] ??
          '')
      .toString()
      .trim();
  var body = (message.notification?.body ?? message.data['body'] ?? '')
      .toString()
      .trim();
  if (body.isEmpty || !body.contains('Order / notice:')) {
    final caseNo = '${message.data['caseNo'] ?? ''}'.trim();
    final client = '${message.data['clientName'] ?? ''}'.trim();
    final branch = '${message.data['courtBranch'] ?? ''}'.trim();
    final caseTitle = '${message.data['caseTitle'] ?? ''}'.trim();
    final hearingDate = '${message.data['hearingDate'] ?? ''}'.trim();
    final rebuilt = <String>[];
    if (hearingDate.isNotEmpty) rebuilt.add('Date: $hearingDate');
    if (caseNo.isNotEmpty) rebuilt.add('Case No.: $caseNo');
    if (client.isNotEmpty) rebuilt.add('Client: $client');
    if (branch.isNotEmpty) rebuilt.add('Court / Branch: $branch');
    if (caseTitle.isNotEmpty) {
      rebuilt.add('');
      rebuilt.add('Order / notice:');
      rebuilt.add(caseTitle);
    }
    if (rebuilt.isNotEmpty) body = rebuilt.join('\n');
  }
  if (title.isEmpty && body.isEmpty) return;
  await _showTaggedPopup(
    message: message,
    title: title.isEmpty ? 'Law Connect' : title,
    body: body,
  );
}

Future<void> _showTaggedPopup({
  required RemoteMessage message,
  required String title,
  required String body,
}) async {
  final hid = '${message.data['hearingDocId'] ?? ''}'.trim();
  final id = hid.isEmpty
      ? DateTime.now().millisecondsSinceEpoch % 100000
      : hid.hashCode & 0x7fffffff;

  try {
    final plugin = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(
      const InitializationSettings(android: androidInit),
    );
    const channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Priority Notifications',
      description: 'Important notifications from LawConnect',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    await plugin.show(
      id,
      title.isEmpty ? 'Law Connect' : title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Priority Notifications',
          channelDescription: 'Important notifications from LawConnect',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.public,
          tag: hid.isEmpty ? null : hid,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title.isEmpty ? 'Law Connect' : title,
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('❌ Background popup failed: $e');
    }
  }
}
