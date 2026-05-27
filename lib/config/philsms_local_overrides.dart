// Local PhilSMS settings (or use --dart-define=PHILSMS_API_TOKEN=...).
// Hearing SMS logic: lib/services/hearing_sms_alert_service.dart
// Hearing field/dedupe config: PhilSmsHearingAlertConfig in philsms_config.dart
//
// API token (NOT your login password):
//   https://dashboard.philsms.com/developers → copy api_token (looks like 3121|abc...)
//
// Sender ID: your screenshot shows ACTIVE "PhilSMS" (₱0) — that is enough.
// Top-up credits (100 SMS units) + active sender = you can send. No extra sender payment needed.
//
// Do not commit real tokens to a public repository.

/// PhilSMS API token — from https://dashboard.philsms.com/developers (api_token field).
const String kPhilSmsApiToken =
    '3121|EcLePG3aVbu2YUoc6nxNVONdIW1BFThS1CN9ZxBqf680e780';

/// Active sender ID from Sending → Sender ID.
const String kPhilSmsSenderId = 'PhilSMS';

/// SMS numbers for firm roles when a hearing is fan-out.
///
/// Keys (first match wins for attorney/staff):
/// - `'attorney'` / `'staff'` — any user with that role (easiest)
/// - Firebase uid — one specific user (from Firestore `users` document id)
///
/// Clients are NOT listed here; they use `phone` / `phoneNumber` from sign-up.
const Map<String, String> kPhilSmsStaffAttorneyPhones = {
  'attorney': '09351914214',
  'staff': '09351914214',
};
