import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_bootstrap.dart';
import '../supabase/supabase_config.dart';

/// App-wide Supabase access (PostgreSQL REST, Storage, Auth API) after [initializeSupabase] in [main].
///
/// Your dashboard tables/policies apply to calls via [client]. Firebase/Firestore is separate.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  /// Throws if Supabase did not finish startup — use [clientOrNull] when optional.
  SupabaseClient get client {
    if (!isSupabaseClientReady) {
      throw StateError(
        'Supabase is not connected. Set URL + anon key in '
        'lib/supabase/supabase_local_overrides.dart or use --dart-define=SUPABASE_URL / SUPABASE_ANON_KEY.',
      );
    }
    return Supabase.instance.client;
  }

  SupabaseClient? get clientOrNull => supabaseClientOrNull;

  /// Hits the Auth API to confirm the project is reachable (debug log only).
  Future<void> verifyProjectOnline() async {
    if (!isSupabaseClientReady) return;
    final base = SupabaseConfig.projectUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/auth/v1/settings');
    try {
      final res = await http
          .get(
            uri,
            headers: {
              'apikey': SupabaseConfig.publishableAnonKey,
              'Authorization': 'Bearer ${SupabaseConfig.publishableAnonKey}',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (kDebugMode) {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          debugPrint(
            '✅ Supabase: project online (HTTP ${res.statusCode}). '
            'Use SupabaseService.instance.client for tables & storage.',
          );
        } else {
          debugPrint(
            '⚠️ Supabase: unexpected HTTP ${res.statusCode} — check API URL and anon key.',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Supabase: could not reach project — $e');
      }
    }
  }
}
