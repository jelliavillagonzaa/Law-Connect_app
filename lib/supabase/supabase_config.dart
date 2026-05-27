import 'supabase_local_overrides.dart';

/// Supabase (PostgreSQL + Storage + Auth API) alongside Firebase/Firestore.
///
/// Configure using compile-time defines (recommended for CI):
/// `flutter run --dart-define=SUPABASE_URL=https://YOUR_REF.supabase.co --dart-define=SUPABASE_ANON_KEY=sb_publishable_...`
///
/// Or set non-empty values in [supabase_local_overrides.dart] for local dev only.
///
/// Never embed the **secret** / service_role key (`sb_secret_...`) in the client app.
class SupabaseConfig {
  SupabaseConfig._();

  static const String _envUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String _envKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Project URL from Supabase Dashboard → Settings → API → Project URL.
  static String get projectUrl =>
      _envUrl.isNotEmpty ? _envUrl : kDevSupabaseUrl;

  /// Publishable (anon) key from the same page — safe in the client if RLS is enabled.
  static String get publishableAnonKey =>
      _envKey.isNotEmpty ? _envKey : kDevSupabaseAnonKey;

  static bool get isConfigured =>
      projectUrl.isNotEmpty && publishableAnonKey.isNotEmpty;
}
