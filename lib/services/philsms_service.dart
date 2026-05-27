import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import '../config/philsms_config.dart';

/// Result of a PhilSMS send attempt (for user-facing OTP errors).
class PhilSmsSendResult {
  const PhilSmsSendResult({
    required this.success,
    this.errorMessage,
  });

  final bool success;
  final String? errorMessage;
}

/// Sends SMS via PhilSMS REST API (Philippines).
class PhilSmsService {
  PhilSmsService._();
  static final PhilSmsService instance = PhilSmsService._();

  /// PhilSMS may reject Unicode punctuation (e.g. em-dash → HTTP 403).
  static String sanitizeMessage(String text) {
    return text
        .replaceAll('\u2014', '-')
        .replaceAll('\u2013', '-')
        .replaceAll(RegExp(r'[\u2018\u2019]'), "'")
        .replaceAll(RegExp(r'[\u201C\u201D]'), '"')
        .replaceAll('\u2026', '...');
  }

  /// E.164 (+639…) or local 09… / 639… → PhilSMS `recipient` (digits, no +).
  static String normalizeRecipient(String input) {
    var s = input.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (s.isEmpty) return s;
    if (s.startsWith('+')) s = s.substring(1);
    if (s.startsWith('09') && (s.length == 10 || s.length == 11)) {
      return '63${s.substring(1)}';
    }
    if (s.startsWith('9') && s.length == 10) {
      return '63$s';
    }
    if (s.startsWith('63')) return s;
    return s;
  }

  /// Returns true when PhilSMS accepted the message (HTTP 2xx + no error status).
  Future<bool> sendSms({
    required String to,
    required String message,
  }) async {
    final result = await sendSmsWithResult(to: to, message: message);
    return result.success;
  }

  Future<PhilSmsSendResult> sendSmsWithResult({
    required String to,
    required String message,
  }) async {
    if (!PhilSmsConfig.isConfigured) {
      return const PhilSmsSendResult(
        success: false,
        errorMessage:
            'PhilSMS is not configured. Set kPhilSmsApiToken in lib/config/philsms_local_overrides.dart.',
      );
    }

    final recipient = normalizeRecipient(to);
    final body = sanitizeMessage(message.trim());
    if (recipient.length < 11 || body.isEmpty) {
      return const PhilSmsSendResult(
        success: false,
        errorMessage: 'Invalid phone number or empty message.',
      );
    }

    final payload = <String, dynamic>{
      'recipient': recipient,
      'sender_id': PhilSmsConfig.senderId,
      'type': 'plain',
      'message': body.length > 1000 ? body.substring(0, 1000) : body,
    };

    try {
      final uri = Uri.parse('${PhilSmsConfig.apiBaseUrl}/sms/send');
      final res = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${PhilSmsConfig.apiToken.trim()}',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final err = _errorFromResponse(res.statusCode, res.body);
        if (kDebugMode) debugPrint('PhilSMS HTTP ${res.statusCode}: $err');
        return PhilSmsSendResult(success: false, errorMessage: err);
      }

      if (res.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map) {
            final status = decoded['status']?.toString().toLowerCase() ?? '';
            if (status == 'error' || status == 'failed') {
              final msg = decoded['message']?.toString() ??
                  decoded['error']?.toString() ??
                  res.body;
              if (kDebugMode) debugPrint('PhilSMS API error: $msg');
              return PhilSmsSendResult(
                success: false,
                errorMessage: _userFacingError(msg),
              );
            }
          }
        } catch (_) {
          /* non-JSON success body is ok */
        }
      }

      if (kDebugMode) {
        debugPrint(
          'PhilSMS sent to …${recipient.substring(recipient.length - 4)}',
        );
      }
      return const PhilSmsSendResult(success: true);
    } catch (e) {
      if (kDebugMode) debugPrint('PhilSMS send failed: $e');
      return PhilSmsSendResult(
        success: false,
        errorMessage: 'PhilSMS request failed: $e',
      );
    }
  }

  static String _errorFromResponse(int statusCode, String body) {
    var detail = body.trim();
    if (detail.length > 280) {
      detail = '${detail.substring(0, 280)}…';
    }
    if (detail.isEmpty) {
      return 'PhilSMS HTTP $statusCode. Check API token, sender ID, and account balance.';
    }
    return _userFacingError('HTTP $statusCode: $detail');
  }

  static String _userFacingError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('unauthenticated')) {
      return 'PhilSMS: Invalid API token. Open https://dashboard.philsms.com/developers, '
          'copy your api_token, paste it in lib/config/philsms_local_overrides.dart '
          '(kPhilSmsApiToken), then hot restart.';
    }
    if (raw.startsWith('PhilSMS:')) return raw;
    return 'PhilSMS: $raw';
  }
}
