import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/philsms_config.dart';
import '../config/semaphore_config.dart';
import 'philsms_service.dart';
import 'semaphore_service.dart';
import 'firestore_mirror_helper.dart';
import 'supabase_service.dart';

/// How [SmsService.queueSms] delivered the request.
enum SmsQueueResult {
  /// Sent immediately via PhilSMS API (see [PhilSmsConfig]).
  sentViaPhilSms,
  /// Sent immediately via Semaphore API (see [SemaphoreConfig]).
  sentViaSemaphore,
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

/// Sends SMS via **PhilSMS** (unchanged) and **Semaphore** in parallel when both are set.
/// Sign-up OTP also uses both; success if either provider accepts the message.
class SmsService {
  SmsService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const String _requestsCollection = 'sms_requests';

  static bool _isSignupOtpMeta(Map<String, dynamic>? meta) =>
      meta != null && meta['type'] == 'otp';

  String _normalizePhoneE164Ph(String input) => normalizePhoneE164Ph(input);

  /// `09…` and `+63…` for the same SIM become one key.
  static String normalizePhoneE164Ph(String input) {
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

  /// Sign-up / verification OTP — PhilSMS (unchanged) plus Semaphore when configured.
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
    var semOk = false;
    String? semError;
    if (SemaphoreConfig.isConfigured) {
      final sem = await SemaphoreService.instance.sendOtpSms(
        to: cleanTo,
        message: cleanBody,
      );
      semOk = sem.success;
      semError = sem.errorMessage;
      if (kDebugMode) {
        debugPrint(
          semOk
              ? '✅ Sign-up OTP sent via Semaphore'
              : '⚠️ Semaphore OTP failed: ${sem.errorMessage}',
        );
      }
    }
    if (result.success) {
      if (kDebugMode) debugPrint('✅ Sign-up OTP sent via PhilSMS');
      return SmsDeliveryOutcome(
        status: SmsDeliveryStatus.sent,
        provider: semOk ? 'philsms+semaphore' : 'philsms',
        queueResult: SmsQueueResult.sentViaPhilSms,
      );
    }
    if (semOk) {
      return const SmsDeliveryOutcome(
        status: SmsDeliveryStatus.sent,
        provider: 'semaphore',
        queueResult: SmsQueueResult.sentViaSemaphore,
      );
    }
    return SmsDeliveryOutcome(
      status: SmsDeliveryStatus.failed,
      error: result.errorMessage ??
          semError ??
          'Could not send the verification code via SMS. Try email instead.',
      provider: SemaphoreConfig.isConfigured ? 'philsms+semaphore' : 'philsms',
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
        return (
          result: outcome.queueResult ?? SmsQueueResult.sentViaPhilSms,
          requestId: null,
        );
      }
      throw StateError(
        outcome.error ?? 'Could not send verification code via SMS.',
      );
    }

    // Browser calls to PhilSMS are blocked by CORS. Web queues the SMS so
    // Cloud Function onSmsRequestSend sends it (same path as push).
    // One provider only. A second success was a duplicate text of the same body.
    if (!kIsWeb && PhilSmsConfig.isConfigured) {
      final philOk = await PhilSmsService.instance.sendSms(
        to: cleanTo,
        message: cleanBody,
      );
      if (philOk) {
        if (kDebugMode) {
          debugPrint('✅ SMS sent via PhilSMS');
        }
        return (result: SmsQueueResult.sentViaPhilSms, requestId: null);
      }
      if (kDebugMode) {
        debugPrint('⚠️ PhilSMS failed — Semaphore / fallback still attempted');
      }
    }

    if (SemaphoreConfig.isConfigured) {
      final semOk = await SemaphoreService.instance.sendSms(
        to: cleanTo,
        message: cleanBody,
      );
      if (kDebugMode) {
        debugPrint(semOk ? '✅ SMS sent via Semaphore' : '⚠️ Semaphore SMS failed');
      }
      if (semOk) {
        return (result: SmsQueueResult.sentViaSemaphore, requestId: null);
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
        handedOff.result == SmsQueueResult.sentViaSemaphore ||
        handedOff.result == SmsQueueResult.sentViaSupabase) {
      final provider = switch (handedOff.result) {
        SmsQueueResult.sentViaPhilSms => 'philsms',
        SmsQueueResult.sentViaSemaphore => 'semaphore',
        SmsQueueResult.sentViaSupabase => 'supabase',
        SmsQueueResult.queuedInFirestore => 'firestore',
      };
      return SmsDeliveryOutcome(
        status: SmsDeliveryStatus.sent,
        queueResult: handedOff.result,
        provider: provider,
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

    final result = await HybridDatastore.add(
      collection: _requestsCollection,
      data: data,
    );
    if (!result.isSuccess) throw Exception(result.failureMessage);
    if (kDebugMode) {
      debugPrint(
        '✅ SMS queued to Firestore ($_requestsCollection/${result.id}) — waiting for server send',
      );
    }
    return result.id!;
  }

  /// Sends a Notary Document Checklist to a client's phone via SMS.
  Future<bool> sendNotaryChecklistSms({
    required String to,
    required String documentTitle,
    required List<String> requirements,
    String? officeHours,
  }) async {
    final cleanTo = _normalizePhoneE164Ph(to);
    if (cleanTo.isEmpty || !cleanTo.startsWith('+')) return false;

    final reqSummary = requirements.take(4).map((r) => '• $r').join('\n');
    final message = '''
LawConnect Notary Requirements
$documentTitle:
$reqSummary
⚠️ Note: Bring 2 valid photo IDs. Do NOT sign before arrival!
Walk-in: ${officeHours ?? 'Mon-Fri 8:00 AM - 5:00 PM'}
'''.trim();

    try {
      if (!kIsWeb && PhilSmsConfig.isConfigured) {
        final ok = await PhilSmsService.instance.sendSms(
          to: cleanTo,
          message: message,
        );
        if (ok) return true;
      }

      if (SemaphoreConfig.isConfigured) {
        final ok = await SemaphoreService.instance.sendSms(
          to: cleanTo,
          message: message,
        );
        if (ok) return true;
      }

      if (_auth.currentUser != null) {
        await queueSms(
          to: cleanTo,
          body: message,
          meta: {'type': 'notary_checklist', 'doc': documentTitle},
        );
        return true;
      }
    } catch (_) {}
    return false;
  }
}

