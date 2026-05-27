import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/philsms_config.dart';
import 'philsms_service.dart';
import 'supabase_service.dart';

/// How [SmsService.queueSms] delivered the request.
enum SmsQueueResult {
  /// Sent immediately via PhilSMS API (see [PhilSmsConfig]).
  sentViaPhilSms,
  /// Supabase Edge `send-sms` accepted the call.
  sentViaSupabase,
  /// A document was added to Firestore `sms_requests` for Cloud Function / sms-worker.
  queuedInFirestore,
}

/// Final delivery state after [SmsService.queueSmsAndWait].
enum SmsDeliveryStatus {
  sent,
  failed,
  timeout,
}

class SmsDeliveryOutcome {
  const SmsDeliveryOutcome({
    required this.status,
    this.error,
    this.provider,
    this.queueResult,
    this.requestId,
  });

  final SmsDeliveryStatus status;
  final String? error;
  final String? provider;
  final SmsQueueResult? queueResult;
  final String? requestId;

  bool get isSent => status == SmsDeliveryStatus.sent;
}

/// Sends SMS via **PhilSMS** when configured; else Supabase `send-sms`; else Firestore queue.
/// Sign-up OTP (`meta.type == 'otp'`) uses **PhilSMS only** — no Semaphore/Twilio/Firestore.
class SmsService {
  SmsService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const String _requestsCollection = 'sms_requests';

  static bool _isSignupOtpMeta(Map<String, dynamic>? meta) =>
      meta != null && meta['type'] == 'otp';

  String _normalizePhoneE164Ph(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    s = s.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    if (s.startsWith('+')) return s;

    if (s.startsWith('09') && s.length == 11) {
      return '+63${s.substring(1)}';
    }
    if (s.startsWith('9') && s.length == 10) {
      return '+63$s';
    }
    if (s.startsWith('63') && s.length >= 12) {
      return '+$s';
    }

    return s;
  }

  /// Sign-up / verification OTP — PhilSMS only (no Semaphore, Twilio, or Firestore queue).
  Future<SmsDeliveryOutcome> sendSignupOtpSms({
    required String to,
    required String body,
  }) async {
    final cleanTo = _normalizePhoneE164Ph(to);
    final cleanBody = body.trim();
    if (cleanTo.isEmpty || cleanBody.isEmpty) {
      return const SmsDeliveryOutcome(
        status: SmsDeliveryStatus.failed,
        error: 'Missing phone number or message.',
        provider: 'philsms',
      );
    }
    if (!cleanTo.startsWith('+')) {
      return SmsDeliveryOutcome(
        status: SmsDeliveryStatus.failed,
        error:
            'Phone must be a valid Philippine number (e.g. 09XXXXXXXXX). Got: $cleanTo',
        provider: 'philsms',
      );
    }

    final result = await PhilSmsService.instance.sendSmsWithResult(
      to: cleanTo,
      message: cleanBody,
    );
    if (result.success) {
      if (kDebugMode) debugPrint('✅ Sign-up OTP sent via PhilSMS');
      return const SmsDeliveryOutcome(
        status: SmsDeliveryStatus.sent,
        provider: 'philsms',
        queueResult: SmsQueueResult.sentViaPhilSms,
      );
    }
    return SmsDeliveryOutcome(
      status: SmsDeliveryStatus.failed,
      error: result.errorMessage ??
          'PhilSMS could not send the verification code. Try email instead.',
      provider: 'philsms',
    );
  }

  /// Queues or sends SMS. Returns how it was handed off (not guaranteed delivery).
  Future<({SmsQueueResult result, String? requestId})> queueSms({
    required String to,
    required String body,
    String? userId,
    Map<String, dynamic>? meta,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not logged in');
    }

    final cleanTo = _normalizePhoneE164Ph(to);
    var cleanBody = body.trim();
    if (cleanTo.isEmpty || cleanBody.isEmpty) {
      throw ArgumentError('Missing SMS to/body');
    }
    if (!cleanTo.startsWith('+')) {
      throw ArgumentError(
        'Phone must be E.164 after normalization (e.g. +639XXXXXXXXX). Got: $cleanTo',
      );
    }

    final otpCode = meta?['code']?.toString();
    if (otpCode != null && otpCode.isNotEmpty) {
      cleanBody = cleanBody.replaceAll('{otp}', otpCode);
    }

    if (_isSignupOtpMeta(meta)) {
      final outcome = await sendSignupOtpSms(to: cleanTo, body: cleanBody);
      if (outcome.isSent) {
        return (result: SmsQueueResult.sentViaPhilSms, requestId: null);
      }
      throw StateError(
        outcome.error ?? 'PhilSMS could not send verification code.',
      );
    }

    if (PhilSmsConfig.isConfigured) {
      final sent = await PhilSmsService.instance.sendSms(
        to: cleanTo,
        message: cleanBody,
      );
      if (sent) {
        if (kDebugMode) {
          debugPrint('✅ SMS sent via PhilSMS');
        }
        return (result: SmsQueueResult.sentViaPhilSms, requestId: null);
      }
      if (kDebugMode) {
        debugPrint('⚠️ PhilSMS failed — trying fallback SMS providers');
      }
    }

    final supabase = SupabaseService.instance.clientOrNull;
    if (supabase != null) {
      try {
        final payload = <String, dynamic>{
          'to': cleanTo,
          'body': cleanBody,
          'userId': userId ?? uid,
          'meta': meta ?? <String, dynamic>{},
        };

        final idToken = await _auth.currentUser?.getIdToken();
        if (idToken == null || idToken.isEmpty) {
          throw StateError('Could not get Firebase ID token');
        }

        await supabase.functions.invoke(
          'send-sms',
          body: payload,
          headers: {
            'x-firebase-token': idToken,
          },
        );
        if (kDebugMode) {
          debugPrint('✅ SMS sent via Supabase Edge (send-sms)');
        }
        return (result: SmsQueueResult.sentViaSupabase, requestId: null);
      } on FunctionException catch (e) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ Supabase send-sms failed (${e.status}), queuing Firestore: ${e.details}',
          );
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Supabase send-sms error, queuing Firestore: $e');
        }
      }
    } else if (kDebugMode) {
      debugPrint(
        'ℹ️ Supabase not connected — queuing SMS to Firestore ($_requestsCollection)',
      );
    }

    final requestId = await _queueSmsFirestore(
      cleanTo: cleanTo,
      cleanBody: cleanBody,
      createdBy: uid,
      userId: userId ?? uid,
      meta: meta,
    );
    return (result: SmsQueueResult.queuedInFirestore, requestId: requestId);
  }

  /// Sends SMS and waits for Firestore `sms_requests` status (non-OTP flows).
  /// Sign-up OTP should use [sendSignupOtpSms] instead.
  Future<SmsDeliveryOutcome> queueSmsAndWait({
    required String to,
    required String body,
    String? userId,
    Map<String, dynamic>? meta,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (_isSignupOtpMeta(meta)) {
      return sendSignupOtpSms(to: to, body: body);
    }

    try {
      final handedOff = await queueSms(
        to: to,
        body: body,
        userId: userId,
        meta: meta,
      );
      return _outcomeFromHandoff(handedOff, timeout);
    } on StateError catch (e) {
      return SmsDeliveryOutcome(
        status: SmsDeliveryStatus.failed,
        error: e.message,
        provider: 'philsms',
      );
    }
  }

  Future<SmsDeliveryOutcome> _outcomeFromHandoff(
    ({SmsQueueResult result, String? requestId}) handedOff,
    Duration timeout,
  ) async {

    if (handedOff.result == SmsQueueResult.sentViaPhilSms ||
        handedOff.result == SmsQueueResult.sentViaSupabase) {
      return SmsDeliveryOutcome(
        status: SmsDeliveryStatus.sent,
        queueResult: handedOff.result,
        provider: handedOff.result == SmsQueueResult.sentViaPhilSms
            ? 'philsms'
            : 'supabase',
      );
    }

    final requestId = handedOff.requestId;
    if (requestId == null || requestId.isEmpty) {
      return const SmsDeliveryOutcome(
        status: SmsDeliveryStatus.failed,
        error: 'Could not queue SMS request',
        queueResult: SmsQueueResult.queuedInFirestore,
      );
    }

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final snap =
          await _firestore.collection(_requestsCollection).doc(requestId).get();
      final status = snap.data()?['status'] as String? ?? '';
      if (status == 'sent') {
        return SmsDeliveryOutcome(
          status: SmsDeliveryStatus.sent,
          queueResult: handedOff.result,
          provider: snap.data()?['provider'] as String?,
          requestId: requestId,
        );
      }
      if (status == 'failed') {
        return SmsDeliveryOutcome(
          status: SmsDeliveryStatus.failed,
          error: snap.data()?['error'] as String? ?? 'SMS send failed',
          queueResult: handedOff.result,
          requestId: requestId,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }

    return SmsDeliveryOutcome(
      status: SmsDeliveryStatus.timeout,
      error:
          'SMS still pending. Deploy Cloud Function onSmsRequestSend or run sms-worker.',
      queueResult: handedOff.result,
      requestId: requestId,
    );
  }

  Future<String> _queueSmsFirestore({
    required String cleanTo,
    required String cleanBody,
    required String createdBy,
    required String userId,
    Map<String, dynamic>? meta,
  }) async {
    final data = <String, dynamic>{
      'to': cleanTo,
      'body': cleanBody.length > 1500 ? cleanBody.substring(0, 1500) : cleanBody,
      'status': 'pending',
      'createdBy': createdBy,
      'userId': userId,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (meta != null && meta.isNotEmpty) {
      data['meta'] = meta;
    }

    final ref = await _firestore.collection(_requestsCollection).add(data);
    if (kDebugMode) {
      debugPrint(
        '✅ SMS queued to Firestore ($_requestsCollection/${ref.id}) — waiting for server send',
      );
    }
    return ref.id;
  }
}
