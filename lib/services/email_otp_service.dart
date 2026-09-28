import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'fcm_service.dart';
import 'firestore_mirror_helper.dart';
import '../config/email_branding.dart';

class EmailOtpSendResult {
  const EmailOtpSendResult({
    required this.emailSent,
    this.pushSent = false,
    this.error,
    this.statusCode,
  });

  final bool emailSent;
  final bool pushSent;
  final String? error;
  final int? statusCode;

  bool get success => emailSent;
}

/// Sends signup / verification OTPs through EmailJS.
///
/// Android/Flutter is not a browser. EmailJS rejects those calls unless we send
/// a browser-like Origin header, and the public key must be the dashboard key
/// (not a `public_` prefix we invented).
class EmailOtpService {
  static const String _serviceId = 'service_55uzrrn';
  static const String _templateId = 'template_h3geajd';

  /// Stored as `public_…` in older builds. EmailJS public keys do not use that
  /// prefix — we try both the raw value and the stripped key.
  static const String _configuredKey = '5hqM06GrxyJLvL7fM';

  static const String _emailjsApiUrl =
      'https://api.emailjs.com/api/v1.0/email/send';

  static String get _strippedKey => _configuredKey.startsWith('public_')
      ? _configuredKey.substring(7)
      : _configuredKey;

  Future<bool> sendOtp({
    required String email,
    required String otp,
    String? name,
    String? replyTo,
    String? fcmToken,
  }) async {
    final result = await sendOtpDetailed(
      email: email,
      otp: otp,
      name: name,
      replyTo: replyTo,
      fcmToken: fcmToken,
    );
    return result.emailSent;
  }

  Future<EmailOtpSendResult> sendOtpDetailed({
    required String email,
    required String otp,
    String? name,
    String? replyTo,
    String? fcmToken,
  }) async {
    final recipient = email.trim();
    if (recipient.isEmpty || !recipient.contains('@')) {
      return const EmailOtpSendResult(
        emailSent: false,
        error: 'Invalid email address.',
      );
    }

    final expiresAt = DateTime.now().add(const Duration(minutes: 15));
    final timeLabel = _formatExpiry(expiresAt);

    // EmailJS One-Time Password template uses {{email}}, {{passcode}}, {{time}}.
    final templateParams = <String, dynamic>{
      'email': recipient,
      'to_email': recipient,
      'user_email': recipient,
      'to_name': name ?? 'User',
      'user_name': name ?? 'User',
      'name': name ?? 'User',
      'passcode': otp,
      'otp': otp,
      'code': otp,
      'time': timeLabel,
      // EmailJS template should use hardcoded logo URL OR {{{logo_html}}}.
      'logo_url': EmailBranding.logoUrl,
      'logo': EmailBranding.logoUrl,
      'image_url': EmailBranding.logoUrl,
      'logo_html': EmailBranding.emailJsLogoHtml,
    };
    if (replyTo != null && replyTo.isNotEmpty) {
      templateParams['reply_to'] = replyTo;
    }

    final keyCandidates = <String>{
      _strippedKey,
      _configuredKey,
    }.where((k) => k.isNotEmpty).toList();

    final serviceCandidates = <String>{
      _serviceId,
      'default_service',
    }.toList();

    http.Response? lastResponse;
    Object? lastError;

    for (final userId in keyCandidates) {
      for (final serviceId in serviceCandidates) {
        try {
          final response = await _postEmailJs(
            userId: userId,
            serviceId: serviceId,
            templateParams: templateParams,
          );
          lastResponse = response;

          if (kDebugMode) {
            debugPrint(
              '📧 EMAILJS ${response.statusCode} service=$serviceId '
              'body=${response.body}',
            );
          }

          if (response.statusCode == 200) {
            _sendPushBestEffort(
              fcmToken: fcmToken,
              otp: otp,
              email: recipient,
              name: name,
            );
            return const EmailOtpSendResult(emailSent: true);
          }
          await Future<void>.delayed(const Duration(milliseconds: 1100));
        } catch (e) {
          lastError = e;
          if (kDebugMode) debugPrint('📧 EMAILJS request failed: $e');
        }
      }
    }

    final queuedId = await _queueOtpEmail(
      email: recipient,
      otp: otp,
      name: name,
    );
    if (queuedId != null) {
      final fallbackSent = await _waitForQueuedEmail(queuedId);
      if (fallbackSent) {
        _sendPushBestEffort(
          fcmToken: fcmToken,
          otp: otp,
          email: recipient,
          name: name,
        );
        return const EmailOtpSendResult(emailSent: true);
      }
    }

    _sendPushBestEffort(
      fcmToken: fcmToken,
      otp: otp,
      email: recipient,
      name: name,
    );

    return EmailOtpSendResult(
      emailSent: false,
      statusCode: lastResponse?.statusCode,
      error: _humanError(lastResponse, lastError),
    );
  }

  String _formatExpiry(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final ampm = time.hour >= 12 ? 'PM' : 'AM';
    return '${time.month}/${time.day}/${time.year} $hour:$minute $ampm';
  }

  Future<http.Response> _postEmailJs({
    required String userId,
    required String serviceId,
    required Map<String, dynamic> templateParams,
  }) {
    // Same payload shape as the official EmailJS Flutter SDK.
    final payload = {
      'lib_version': '4.0.0',
      'service_id': serviceId,
      'template_id': _templateId,
      'user_id': userId,
      'template_params': templateParams,
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    // Flutter web forbids setting Origin. Native/desktop need it or the
    // EmailJS "non-browser API" toggle, or both.
    if (!kIsWeb) {
      headers['origin'] = 'http://localhost';
    }

    return http
        .post(
          Uri.parse(_emailjsApiUrl),
          headers: headers,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));
  }

  String _humanError(http.Response? response, Object? error) {
    final body = (response?.body ?? '').toLowerCase();
    final status = response?.statusCode;

    if (status == 403 ||
        body.contains('non-browser') ||
        body.contains('api calls are disabled')) {
      return 'Gmail send is blocked for this app. In EmailJS go to '
          'Account → Security and enable “Allow EmailJS API for non-browser applications”.';
    }
    if (status == 400 && body.contains('template')) {
      return 'EmailJS template is missing the recipient. Set the template To Email to {{email}}.';
    }
    if (status == 400 &&
        (body.contains('user_id') || body.contains('public key'))) {
      return 'EmailJS public key is invalid. Paste the key from '
          'https://dashboard.emailjs.com/admin/account into EmailOtpService.';
    }
    if (status == 412 || body.contains('recipients address is empty')) {
      return 'EmailJS did not get a To address. Set the template To Email to {{email}}.';
    }
    if (status == 422) {
      return 'EmailJS Gmail service is disconnected. Reconnect Gmail in EmailJS → Email Services.';
    }
    if (error != null && error.toString().toLowerCase().contains('timeout')) {
      return 'Timed out sending the code to Gmail. Check internet and try Resend.';
    }
    if (status != null) {
      return 'Could not send the code to Gmail (error $status). Check spam, then tap Resend.';
    }
    return 'Could not send the code to Gmail. Check your internet and tap Resend.';
  }

  void _sendPushBestEffort({
    required String? fcmToken,
    required String otp,
    required String email,
    String? name,
  }) {
    if (fcmToken == null || fcmToken.isEmpty) return;
    Future<void>(() async {
      try {
        await FCMService().sendNotificationToToken(
          fcmToken: fcmToken,
          title: 'Verification Code',
          body:
              'Your verification code is: $otp\n\nUse this code to complete your registration.',
          data: {
            'type': 'otp_verification',
            'otp': otp,
            'email': email,
            'name': name ?? 'User',
          },
        );
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ OTP push failed: $e');
      }
    });
  }

  Future<String?> _queueOtpEmail({
    required String email,
    required String otp,
    String? name,
  }) async {
    try {
      final result = await FirestoreMirror.add(
        collection: 'email_requests',
        data: {
          'to': email,
          'email': email,
          'otp': otp,
          'passcode': otp,
          'name': name ?? 'User',
          'subject': 'Law Connect verification code',
          'text':
              'Hi ${name ?? 'there'},\n\n'
              'Your Law Connect verification code is: $otp\n\n'
              'Do not share this code with anyone. It expires in 15 minutes.\n',
          'status': 'pending',
          'type': 'otp',
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
      if (result.isSuccess && result.id != null && result.id!.isNotEmpty) {
        return result.id;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ EMAIL OTP SERVICE: email_requests fallback blocked: $e');
      }
    }
    return null;
  }

  Future<bool> _waitForQueuedEmail(String docId) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('email_requests')
          .doc(docId);
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        final snap = await ref.get();
        final status = snap.data()?['status']?.toString();
        if (status == 'sent') return true;
        if (status == 'failed' || status == 'skipped_config') return false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ EMAIL OTP SERVICE: queue wait failed: $e');
    }
    return false;
  }

  static String generateOtp() {
    final random = DateTime.now().millisecondsSinceEpoch;
    final otp = (100000 + (random % 900000)).toString();
    return otp;
  }

  static bool isValidOtpFormat(String otp) {
    return RegExp(r'^\d{6}$').hasMatch(otp);
  }
}
