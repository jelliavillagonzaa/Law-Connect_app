import 'semaphore_local_overrides.dart';

/// Semaphore SMS (https://www.semaphore.co) — hybrid alongside PhilSMS.
///
/// PhilSMS stays on its own token/config. This class only reads Semaphore keys.
class SemaphoreConfig {
  SemaphoreConfig._();

  static const String _envKey = String.fromEnvironment(
    'SEMAPHORE_API_KEY',
    defaultValue: '',
  );
  static const String _envSender = String.fromEnvironment(
    'SEMAPHORE_SENDER_NAME',
    defaultValue: '',
  );

  static const String apiBaseUrl = 'https://api.semaphore.co/api/v4';

  static String get apiKey {
    final fromOverrides = kSemaphoreApiKey.trim();
    if (fromOverrides.isNotEmpty) return fromOverrides;
    return _envKey.trim();
  }

  static String get senderName {
    final fromOverrides = kSemaphoreSenderName.trim();
    if (fromOverrides.isNotEmpty) return fromOverrides;
    final fromEnv = _envSender.trim();
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'LAWCONNECT';
  }

  static bool get isConfigured => apiKey.isNotEmpty;
}
