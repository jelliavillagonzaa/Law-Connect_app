import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'fcm_service.dart';
import 'firestore_mirror_helper.dart';
import 'sms_service.dart';

/// Push + in-app + SMS to attorneys when a client submits a request.
class AttorneyRequestNotify {
  AttorneyRequestNotify._();

  static final _firestore = FirebaseFirestore.instance;
  static final _fcm = FCMService();
  static final _sms = SmsService();

  static Future<void> notifyAttorneys({
    required List<String> attorneyIds,
    required String title,
    required String message,
    required String smsBody,
    required String type,
    Map<String, dynamic>? data,
  }) async {
    final ids = attorneyIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;

    final smsSentTo = <String>{};
    for (final attorneyId in ids) {
      await _sendInApp(
        attorneyId: attorneyId,
        title: title,
        message: message,
        type: type,
        data: data,
      );
      try {
        await _fcm.sendNotificationToUser(
          userId: attorneyId,
          title: title,
          body: message,
          data: {
            'type': type,
            ...?data,
          },
        );
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Attorney FCM failed ($attorneyId): $e');
      }
      final phone = await _resolveAttorneyPhone(attorneyId);
      if (phone == null || phone.isEmpty) continue;
      if (!smsSentTo.add(phone)) continue;
      try {
        await _sms.queueSms(
          to: phone,
          body: smsBody,
          userId: attorneyId,
          meta: {'type': type},
        );
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Attorney SMS failed ($attorneyId): $e');
      }
    }
  }

  static Future<List<String>> allAttorneyIds() async {
    try {
      final snap = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'attorney')
          .limit(40)
          .get()
          .timeout(const Duration(seconds: 8));
      return snap.docs.map((d) => d.id).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Failed to load attorneys: $e');
      return [];
    }
  }

  static Future<void> _sendInApp({
    required String attorneyId,
    required String title,
    required String message,
    required String type,
    Map<String, dynamic>? data,
    bool isClient = false,
  }) async {
    final payload = <String, dynamic>{
      'userId': attorneyId,
      if (isClient) 'clientId': attorneyId,
      if (!isClient) 'attorneyId': attorneyId,
      'type': type,
      'title': title,
      'message': message,
      'summary': message,
      if (data != null) 'data': data,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    try {
      final result = await HybridDatastore.add(
        collection: 'notifications',
        data: payload,
      );
      if (result.firestoreOk) return;
      if (kDebugMode) {
        debugPrint(
          '⚠️ Attorney in-app Firestore failed: ${result.firestoreError}',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Attorney in-app notify failed: $e');
    }
    try {
      await _firestore.collection('notifications').add(payload);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Attorney in-app Firestore fallback failed: $e');
      }
    }
  }

  /// In-app bell, optional FCM push, optional SMS.
  static Future<void> notifyParty({
    required String userId,
    required String title,
    required String message,
    required String type,
    String? smsBody,
    bool sendSms = true,
    bool sendPush = true,
    bool sendInApp = true,
    bool isClient = false,
    Map<String, dynamic>? data,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;

    if (sendInApp) {
      await _sendInApp(
        attorneyId: uid,
        title: title,
        message: message,
        type: type,
        data: data,
        isClient: isClient,
      );
    }

    if (sendPush) {
      try {
        await _fcm.sendNotificationToUser(
          userId: uid,
          title: title,
          body: message,
          data: {
            'type': type,
            ...?data,
          },
        );
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ FCM failed ($uid): $e');
      }
    }

    if (!sendSms || smsBody == null || smsBody.trim().isEmpty) return;
    final phone = await _resolveAttorneyPhone(uid);
    if (phone == null || phone.isEmpty) return;
    try {
      await _sms.queueSms(
        to: phone,
        body: smsBody,
        userId: uid,
        meta: {'type': type},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ SMS failed ($uid): $e');
    }
  }

  static Future<String?> _resolveAttorneyPhone(String attorneyId) async {
    try {
      final snap = await _firestore.collection('users').doc(attorneyId).get();
      final data = snap.data() ?? {};
      final profile =
          (data['phone'] ?? data['phoneNumber'])?.toString().trim() ?? '';
      if (profile.isNotEmpty) return profile;
      return null;
    } catch (_) {
      return null;
    }
  }
}
