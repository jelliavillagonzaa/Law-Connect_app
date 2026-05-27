import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'fcm_service.dart';

/// Email OTP Service using EmailJS
///
/// Configuration:
/// - Service ID: service_h595leh
/// - Template ID: template_eae41pq
/// - Public Key: (to be provided)
class EmailOtpService {
  // EmailJS Configuration
  static const String _serviceId = 'service_h595leh';
  static const String _templateId = 'template_eae41pq';

  // EmailJS Public Key
  // Format: "public_YOUR_KEY_HERE" (must start with "public_")
  static const String _publicKey = 'public_tMoNNXN_4cNoa_j7w';

  static const String _emailjsApiUrl =
      'https://api.emailjs.com/api/v1.0/email/send';

  /// Send OTP code via email using EmailJS and FCM push notification
  ///
  /// [email] - Recipient email address
  /// [otp] - The OTP code to send
  /// [name] - Optional recipient name (defaults to "User")
  /// [replyTo] - Optional reply-to email address
  /// [fcmToken] - Optional FCM token to send push notification
  ///
  /// Returns true if email or push notification was sent successfully, false otherwise
  Future<bool> sendOtp({
    required String email,
    required String otp,
    String? name,
    String? replyTo,
    String? fcmToken,
  }) async {
    try {
      // Validate public key
      if (_publicKey == 'YOUR_PUBLIC_KEY_HERE' ||
          _publicKey.isEmpty ||
          !_publicKey.startsWith('public_')) {
        if (kDebugMode) {
          debugPrint('❌ EMAIL OTP SERVICE: Invalid Public Key!');
          debugPrint('❌ Current key: $_publicKey');
          debugPrint(
            '❌ Please update _publicKey in lib/services/email_otp_service.dart',
          );
          debugPrint(
            '❌ Get your Public Key from: https://dashboard.emailjs.com/admin/account',
          );
          debugPrint('❌ Format: "public_YOUR_KEY_HERE"');
        }
        return false;
      }

      // Prepare EmailJS payload
      // Note: EmailJS expects template_params to match template variable names exactly
      final templateParams = <String, dynamic>{
        'to_email': email,
        'to_name': name ?? 'User',
        'otp': otp,
      };

      // Add reply_to only if provided
      if (replyTo != null && replyTo.isNotEmpty) {
        templateParams['reply_to'] = replyTo;
      }

      // EmailJS REST API uses 'user_id' (not 'public_key')
      // Extract user_id from public_key (remove 'public_' prefix if present)
      final userId = _publicKey.startsWith('public_')
          ? _publicKey.substring(7)
          : _publicKey;

      final payload = {
        'service_id': _serviceId,
        'template_id': _templateId,
        'user_id': userId, // EmailJS REST API requires 'user_id'
        'template_params': templateParams,
      };

      if (kDebugMode) {
        debugPrint('📧 EMAIL OTP SERVICE: Sending OTP');
        debugPrint('═══════════════════════════════════════');
        debugPrint('📧 To Email: $email');
        debugPrint('📧 To Name: ${name ?? "User"}');
        debugPrint('📧 OTP Code: $otp');
        debugPrint('📧 Service ID: $_serviceId');
        debugPrint('📧 Template ID: $_templateId');
        debugPrint('📧 Public Key: ${_publicKey.substring(0, 10)}...');
        debugPrint('📧 Full Payload: ${jsonEncode(payload)}');
        debugPrint('═══════════════════════════════════════');
      }

      // Make HTTP POST request to EmailJS
      // Try with public key as-is first
      var response = await http
          .post(
            Uri.parse(_emailjsApiUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              if (kDebugMode) {
                debugPrint(
                  '⏱️ EMAIL OTP SERVICE: Request timed out after 30 seconds',
                );
              }
              throw Exception('EmailJS request timed out');
            },
          );

      // If we get a 400 error, try with full public_key as user_id
      if (response.statusCode == 400 && _publicKey.startsWith('public_')) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ EMAIL OTP SERVICE: Got 400 error, trying with full public_key as user_id...',
          );
        }
        final payloadWithFullKey = {
          'service_id': _serviceId,
          'template_id': _templateId,
          'user_id':
              _publicKey, // Try with full public_key including 'public_' prefix
          'template_params': templateParams,
        };

        response = await http
            .post(
              Uri.parse(_emailjsApiUrl),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode(payloadWithFullKey),
            )
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                if (kDebugMode) {
                  debugPrint(
                    '⏱️ EMAIL OTP SERVICE: Alternative request timed out',
                  );
                }
                throw Exception('EmailJS request timed out');
              },
            );
      }

      if (kDebugMode) {
        debugPrint(
          '📧 EMAIL OTP SERVICE: Response Status: ${response.statusCode}',
        );
        debugPrint('📧 EMAIL OTP SERVICE: Response Body: ${response.body}');
      }

      // Check response
      bool emailSent = false;
      if (response.statusCode == 200) {
        try {
          final responseData = jsonDecode(response.body);
          if (kDebugMode) {
            debugPrint('✅ EMAIL OTP SERVICE: Email sent successfully!');
            debugPrint('✅ Response: $responseData');
          }
          emailSent = true;
        } catch (e) {
          // Response is 200 but might not be valid JSON
          if (kDebugMode) {
            debugPrint('⚠️ EMAIL OTP SERVICE: Status 200 but invalid JSON: $e');
            debugPrint('⚠️ Response body: ${response.body}');
          }
          // Still consider email sent if status is 200
          emailSent = true;
        }
      } else {
        if (kDebugMode) {
          debugPrint('❌ EMAIL OTP SERVICE: Failed to send email');
          debugPrint('❌ Status Code: ${response.statusCode}');
          debugPrint('❌ Response Headers: ${response.headers}');
          debugPrint('❌ Response Body: ${response.body}');

          // Try to parse error message
          try {
            final errorData = jsonDecode(response.body);
            debugPrint('❌ Parsed Error Data: $errorData');
            if (errorData.containsKey('error')) {
              debugPrint('❌ Error Message: ${errorData['error']}');
            }
            if (errorData.containsKey('text')) {
              debugPrint('❌ Error Text: ${errorData['text']}');
            }
            if (errorData.containsKey('message')) {
              debugPrint('❌ Error Message: ${errorData['message']}');
            }
          } catch (e) {
            debugPrint('❌ Could not parse error response as JSON: $e');
            debugPrint('❌ Raw response body: ${response.body}');
          }
        }
        emailSent = false;
      }

      // Send FCM push notification if token is provided
      bool pushSent = false;
      if (fcmToken != null && fcmToken.isNotEmpty) {
        try {
          if (kDebugMode) {
            debugPrint(
              '📱 EMAIL OTP SERVICE: Sending FCM push notification...',
            );
          }

          final fcmService = FCMService();
          pushSent = await fcmService.sendNotificationToToken(
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

          if (kDebugMode) {
            if (pushSent) {
              debugPrint(
                '✅ EMAIL OTP SERVICE: FCM push notification sent successfully!',
              );
            } else {
              debugPrint('⚠️ EMAIL OTP SERVICE: FCM push notification failed');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '⚠️ EMAIL OTP SERVICE: Error sending FCM push notification: $e',
            );
          }
          // Don't fail the whole operation if push notification fails
        }
      }

      // Return true if either email or push notification was sent successfully
      return emailSent || pushSent;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ EMAIL OTP SERVICE: Exception occurred');
        debugPrint('❌ Error: $e');
        debugPrint('❌ Stack Trace: $stackTrace');
      }
      return false;
    }
  }

  /// Generate a random 6-digit OTP code
  static String generateOtp() {
    final random = DateTime.now().millisecondsSinceEpoch;
    final otp = (100000 + (random % 900000)).toString();
    return otp;
  }

  /// Validate OTP format (6 digits)
  static bool isValidOtpFormat(String otp) {
    return RegExp(r'^\d{6}$').hasMatch(otp);
  }
}
