import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Password Reset Email Service using EmailJS
///
/// This service sends password reset emails via EmailJS to ensure
/// emails appear in inbox (not spam) with proper formatting
class PasswordResetEmailService {
  // EmailJS Configuration
  // Note: You can use the same template as OTP or create a new one
  // If using OTP template, it will work but message will mention OTP
  // For best results, create a new template with: to_email, to_name, message, app_name
  static const String _serviceId = 'service_h595leh'; // Same service as OTP
  static const String _templateId =
      'template_eae41pq'; // Using OTP template for now
  // TODO: Create a dedicated password reset template in EmailJS and update _templateId

  // EmailJS Public Key (same as OTP service)
  static const String _publicKey = 'public_tMoNNXN_4cNoa_j7w';

  static const String _emailjsApiUrl =
      'https://api.emailjs.com/api/v1.0/email/send';

  /// Send password reset notification email using EmailJS
  ///
  /// This sends a well-formatted email via EmailJS to ensure it appears
  /// in inbox (not spam). The actual password reset is handled by Firebase.
  ///
  /// [email] - User's email address
  /// [name] - Optional user name
  ///
  /// Returns true if email was sent successfully
  Future<bool> sendPasswordResetNotification({
    required String email,
    String? name,
  }) async {
    try {
      // Validate public key
      if (_publicKey == 'YOUR_PUBLIC_KEY_HERE' ||
          _publicKey.isEmpty ||
          !_publicKey.startsWith('public_')) {
        if (kDebugMode) {
          debugPrint('❌ PASSWORD RESET EMAIL: Invalid Public Key!');
        }
        return false;
      }

      // Prepare EmailJS payload
      // Note: The actual reset link will be sent by Firebase
      // This EmailJS email serves as a notification and ensures inbox delivery
      final templateParams = <String, dynamic>{
        'to_email': email,
        'to_name': name ?? 'User',
        'app_name': 'LawConnect',
        'message':
            'Law Connect: a password reset was requested. Firebase will email you the actual reset link — check Inbox and Spam/Promotions, and mark “Not spam” if needed. For best inbox delivery long-term, use a custom domain for Firebase Authentication emails in your Firebase project settings.',
      };

      // Extract user_id from public_key
      final userId = _publicKey.startsWith('public_')
          ? _publicKey.substring(7)
          : _publicKey;

      final payload = {
        'service_id': _serviceId,
        'template_id': _templateId,
        'user_id': userId,
        'template_params': templateParams,
      };

      if (kDebugMode) {
        debugPrint('📧 PASSWORD RESET EMAIL: Sending reset email');
        debugPrint('═══════════════════════════════════════');
        debugPrint('📧 To Email: $email');
        debugPrint('📧 To Name: ${name ?? "User"}');
        debugPrint('📧 Sending notification email via EmailJS');
        debugPrint('═══════════════════════════════════════');
      }

      // Make HTTP POST request to EmailJS
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
                debugPrint('⏱️ PASSWORD RESET EMAIL: Request timed out');
              }
              throw Exception('EmailJS request timed out');
            },
          );

      // Try with full public_key if 400 error
      if (response.statusCode == 400 && _publicKey.startsWith('public_')) {
        if (kDebugMode) {
          debugPrint('⚠️ Trying with full public_key as user_id...');
        }
        final payloadWithFullKey = {
          'service_id': _serviceId,
          'template_id': _templateId,
          'user_id': _publicKey,
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
                throw Exception('EmailJS request timed out');
              },
            );
      }

      if (kDebugMode) {
        debugPrint('📧 Response Status: ${response.statusCode}');
        debugPrint('📧 Response Body: ${response.body}');
      }

      if (response.statusCode == 200) {
        if (kDebugMode) {
          debugPrint('✅ PASSWORD RESET EMAIL: Email sent successfully!');
          debugPrint('✅ Email should appear in inbox (not spam)');
        }
        return true;
      } else {
        if (kDebugMode) {
          debugPrint('❌ PASSWORD RESET EMAIL: Failed to send email');
          debugPrint('❌ Status Code: ${response.statusCode}');
          debugPrint('❌ Response: ${response.body}');
        }
        return false;
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ PASSWORD RESET EMAIL: Exception occurred');
        debugPrint('❌ Error: $e');
        debugPrint('❌ Stack Trace: $stackTrace');
      }
      return false;
    }
  }
}
