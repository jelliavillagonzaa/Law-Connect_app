import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../config/semaphore_config.dart';

class SemaphoreSendResult {
  const SemaphoreSendResult({
    required this.success,
    this.errorMessage,
    this.messageId,
  });

  final bool success;
  final String? errorMessage;
  final String? messageId;
}

/// Sends SMS via Cloud Function `sendSemaphoreSms` (server → Semaphore).
/// Does not call api.semaphore.co from the browser. Does not touch PhilSMS.
class SemaphoreService {
  SemaphoreService._();
  static final SemaphoreService instance = SemaphoreService._();

  static String sanitizeMessage(String text) {
    var s = text
        .replaceAll('\u2014', '-')
        .replaceAll('\u2013', '-')
        .replaceAll(RegExp(r'[\u2018\u2019]'), "'")
        .replaceAll(RegExp(r'[\u201C\u201D]'), '"')
        .replaceAll('\u2026', '...');
    if (RegExp(r'^\s*TEST\b', caseSensitive: false).hasMatch(s)) {
      s = s.replaceFirst(RegExp(r'^\s*TEST\b', caseSensitive: false), 'Notice');
    }
    return s;
  }

  /// E.164 / 09… / 639… → Semaphore local `09XXXXXXXXX`.
  static String normalizeRecipient(String input) {
    var s = input.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (s.isEmpty) return s;
    if (s.startsWith('+')) s = s.substring(1);
    if (s.startsWith('63') && s.length >= 12) {
      return '0${s.substring(2)}';
    }
    if (s.startsWith('9') && s.length == 10) {
      return '0$s';
    }
    return s;
  }

  static String? extractOtpCode(String body) {
    return RegExp(r'\b(\d{4,8})\b').firstMatch(body)?.group(1);
  }

  Future<bool> sendSms({
    required String to,
    required String message,
  }) async {
    final result = await sendSmsWithResult(to: to, message: message);
    return result.success;
  }

  Future<SemaphoreSendResult> sendOtpSms({
    required String to,
    required String message,
    String? code,
  }) async {
    final otp = (code ?? extractOtpCode(message))?.trim() ?? '';
    return _callCloudFunction(
      to: to,
      message: message,
      otpCode: otp.isEmpty ? null : otp,
    );
  }

  Future<SemaphoreSendResult> sendSmsWithResult({
    required String to,
    required String message,
  }) {
    return _callCloudFunction(to: to, message: message);
  }

  Future<SemaphoreSendResult> _callCloudFunction({
    required String to,
    required String message,
    String? otpCode,
  }) async {
    if (!SemaphoreConfig.isConfigured) {
      return const SemaphoreSendResult(
        success: false,
        errorMessage:
            'Semaphore is not configured. Set kSemaphoreApiKey in lib/config/semaphore_local_overrides.dart.',
      );
    }

    final body = sanitizeMessage(message.trim());
    if (to.trim().isEmpty || body.isEmpty) {
      return const SemaphoreSendResult(
        success: false,
        errorMessage: 'Invalid phone number or empty message.',
      );
    }

    try {
      final fn = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable(
        'sendSemaphoreSms',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final result = await fn.call(<String, dynamic>{
        'to': to.trim(),
        'body': body.length > 1500 ? body.substring(0, 1500) : body,
        if (otpCode != null && otpCode.isNotEmpty) 'otpCode': otpCode,
      });
      final data = result.data;
      if (data is Map && data['ok'] == true) {
        if (kDebugMode) {
          debugPrint(
            'Semaphore Cloud Function ok provider=${data['provider']} id=${data['providerMessageId']}',
          );
        }
        return SemaphoreSendResult(
          success: true,
          messageId: data['providerMessageId']?.toString(),
        );
      }
      return const SemaphoreSendResult(
        success: false,
        errorMessage: 'Semaphore Cloud Function did not confirm send.',
      );
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('Semaphore Cloud Function (${e.code}): ${e.message}');
      }
      return SemaphoreSendResult(
        success: false,
        errorMessage: e.message ?? e.code,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Semaphore Cloud Function failed: $e');
      return SemaphoreSendResult(
        success: false,
        errorMessage: 'Semaphore request failed: $e',
      );
    }
  }
}
