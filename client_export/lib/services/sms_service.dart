import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class SmsService {
  SmsService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String _normalizePhoneE164Ph(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    // Remove common separators.
    s = s.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Already E.164
    if (s.startsWith('+')) return s;

    // Philippines common formats → E.164 (+63...)
    // 09XXXXXXXXX (11 digits)
    if (s.startsWith('09') && s.length == 11) {
      return '+63${s.substring(1)}';
    }
    // 9XXXXXXXXX (10 digits, mobile without leading 0)
    if (s.startsWith('9') && s.length == 10) {
      return '+63$s';
    }
    // 63XXXXXXXXXXX (no '+')
    if (s.startsWith('63') && s.length >= 12) {
      return '+$s';
    }

    // Unknown format; return as-is (will fail validation server-side).
    return s;
  }

  /// Sends SMS via **Supabase Edge Function** `send-sms` (Twilio) when connected;
  /// otherwise throws (no Firestore fallback).
  ///
  /// Phone is normalized to **E.164** (e.g. `+639XXXXXXXXX`).
  Future<void> queueSms({
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
    final cleanBody = body.trim();
    if (cleanTo.isEmpty || cleanBody.isEmpty) {
      throw ArgumentError('Missing SMS to/body');
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

        // Non-2xx responses throw [FunctionException].
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
        return;
      } on FunctionException catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Supabase send-sms failed (${e.status}): ${e.details}');
        }
        rethrow;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Supabase send-sms error: $e');
        }
        rethrow;
      }
    }

    throw StateError(
      'Supabase not connected; cannot send SMS. Configure Supabase URL/anon key and deploy Edge Function send-sms.',
    );
  }
}
