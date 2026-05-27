import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

bool _supabaseClientReady = false;

/// Whether [initializeSupabase] completed successfully.
bool get isSupabaseClientReady => _supabaseClientReady;

/// Initializes Supabase when URL + publishable key are configured.
/// Firebase/Firestore initialization is independent; this can run after Firebase.
Future<void> initializeSupabase() async {
  _supabaseClientReady = false;

  if (!SupabaseConfig.isConfigured) {
    if (kDebugMode) {
      debugPrint(
        'Supabase: skipped (set SUPABASE_URL + SUPABASE_ANON_KEY via '
        '--dart-define or lib/supabase/supabase_local_overrides.dart).',
      );
    }
    return;
  }

  try {
    await Supabase.initialize(
      url: SupabaseConfig.projectUrl,
      anonKey: SupabaseConfig.publishableAnonKey,
    );
    _supabaseClientReady = true;
    if (kDebugMode) {
      debugPrint('✅ Supabase initialized (${SupabaseConfig.projectUrl})');
    }
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('⚠️ Supabase initialization failed: $e');
      debugPrint('$st');
    }
  }
}

/// Live client after a successful [initializeSupabase]; otherwise null.
SupabaseClient? get supabaseClientOrNull =>
    _supabaseClientReady ? Supabase.instance.client : null;
