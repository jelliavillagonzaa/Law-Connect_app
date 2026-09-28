import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

bool _supabaseClientReady = false;

/// Whether [initializeSupabase] completed successfully.
bool get isSupabaseClientReady => _supabaseClientReady;

/// Initializes Supabase when URL + publishable key are configured.
/// Firebase/Firestore initialization is independent; this can run after Firebase.
bool _isClientUsable() {
  try {
    final _ = Supabase.instance.client;
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> initializeSupabase() async {
  if (!SupabaseConfig.isConfigured) {
    _supabaseClientReady = false;
    if (kDebugMode) {
      debugPrint(
        'Supabase: skipped (set SUPABASE_URL + SUPABASE_ANON_KEY via '
        '--dart-define or lib/supabase/supabase_local_overrides.dart).',
      );
    }
    return;
  }

  if (_isClientUsable()) {
    _supabaseClientReady = true;
    return;
  }

  _supabaseClientReady = false;

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
    // Hot restart often throws because the client is already running.
    if (_isClientUsable()) {
      _supabaseClientReady = true;
      return;
    }
    if (kDebugMode) {
      debugPrint('⚠️ Supabase initialization failed: $e');
      debugPrint('$st');
    }
  }
}

/// Live client after a successful [initializeSupabase]; otherwise null.
SupabaseClient? get supabaseClientOrNull =>
    _supabaseClientReady ? Supabase.instance.client : null;
