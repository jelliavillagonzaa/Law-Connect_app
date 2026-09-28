import 'package:cloud_firestore/cloud_firestore.dart';

/// Saved System Settings that the rest of the app actually reads.
class AppSystemSettings {
  const AppSystemSettings({
    required this.terms,
    required this.privacy,
    required this.emailNotifications,
    required this.pushNotifications,
    required this.caseUpdates,
    required this.appointmentReminders,
    required this.systemAlerts,
    required this.welcomeEmail,
    required this.caseUpdateEmail,
    required this.appointmentEmail,
    required this.minPasswordLength,
    required this.maxLoginAttempts,
    required this.requireUppercase,
    required this.requireLowercase,
    required this.requireNumbers,
    required this.requireSpecialChars,
    required this.enableTwoFactor,
    required this.autoBackup,
  });

  final String terms;
  final String privacy;
  final bool emailNotifications;
  final bool pushNotifications;
  final bool caseUpdates;
  final bool appointmentReminders;
  final bool systemAlerts;
  final String welcomeEmail;
  final String caseUpdateEmail;
  final String appointmentEmail;
  final int minPasswordLength;
  final int maxLoginAttempts;
  final bool requireUppercase;
  final bool requireLowercase;
  final bool requireNumbers;
  final bool requireSpecialChars;
  final bool enableTwoFactor;
  final bool autoBackup;

  static const fallback = AppSystemSettings(
    terms: '',
    privacy: '',
    emailNotifications: true,
    pushNotifications: true,
    caseUpdates: true,
    appointmentReminders: true,
    systemAlerts: true,
    welcomeEmail: '',
    caseUpdateEmail: '',
    appointmentEmail: '',
    minPasswordLength: 8,
    maxLoginAttempts: 5,
    requireUppercase: true,
    requireLowercase: true,
    requireNumbers: true,
    requireSpecialChars: true,
    enableTwoFactor: false,
    autoBackup: true,
  );

  bool allowsPush(Map<String, dynamic>? data) {
    if (!pushNotifications) return false;
    final type = (data?['type'] ?? '').toString().toLowerCase();
    if (type.contains('case') && !caseUpdates) return false;
    if (type.contains('appointment') && !appointmentReminders) return false;
    if ((type.contains('system') || type.contains('alert')) && !systemAlerts) {
      return false;
    }
    return true;
  }

  String? validatePassword(String value) {
    final min = minPasswordLength < 6 ? 6 : minPasswordLength;
    if (value.length < min) {
      return 'Password must be at least $min characters';
    }
    if (requireUppercase && !RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }
    if (requireLowercase && !RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }
    if (requireNumbers && !RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }
    if (requireSpecialChars &&
        !RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return 'Password must contain at least one special character';
    }
    return null;
  }

  /// Uses the admin template when it is filled in. Placeholders: {name} {case} {message} {date} {time}.
  String applyTemplate(String template, String fallback, Map<String, String> vars) {
    var text = template.trim();
    if (text.isEmpty) return fallback;
    vars.forEach((key, value) {
      text = text.replaceAll('{$key}', value).replaceAll('{{$key}}', value);
    });
    if (fallback.isNotEmpty && !text.contains(fallback)) {
      text = '$text $fallback';
    }
    return text.trim();
  }
}

class SystemSettingsService {
  SystemSettingsService._();
  static final SystemSettingsService instance = SystemSettingsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  AppSystemSettings? _cache;
  DateTime? _cachedAt;

  Future<AppSystemSettings> load({bool force = false}) async {
    final cached = _cache;
    final at = _cachedAt;
    if (!force &&
        cached != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 20)) {
      return cached;
    }
    try {
      final snaps = await Future.wait([
        _firestore.collection('system_settings').doc('platform_policies').get(),
        _firestore.collection('system_settings').doc('notifications').get(),
        _firestore.collection('system_settings').doc('email_templates').get(),
        _firestore.collection('system_settings').doc('security').get(),
      ]);
      final policies = snaps[0].data() ?? {};
      final notes = snaps[1].data() ?? {};
      final mail = snaps[2].data() ?? {};
      final security = snaps[3].data() ?? {};
      final loaded = AppSystemSettings(
        terms: (policies['termsAndConditions'] ?? '').toString().trim(),
        privacy: (policies['privacyPolicy'] ?? '').toString().trim(),
        emailNotifications: notes['emailNotifications'] != false,
        pushNotifications: notes['pushNotifications'] != false,
        caseUpdates: notes['caseUpdates'] != false,
        appointmentReminders: notes['appointmentReminders'] != false,
        systemAlerts: notes['systemAlerts'] != false,
        welcomeEmail: (mail['welcomeEmail'] ?? '').toString(),
        caseUpdateEmail: (mail['caseUpdateEmail'] ?? '').toString(),
        appointmentEmail: (mail['appointmentEmail'] ?? '').toString(),
        minPasswordLength: (security['minPasswordLength'] as num?)?.toInt() ?? 8,
        maxLoginAttempts: (security['maxLoginAttempts'] as num?)?.toInt() ?? 5,
        requireUppercase: security['requireUppercase'] != false,
        requireLowercase: security['requireLowercase'] != false,
        requireNumbers: security['requireNumbers'] != false,
        requireSpecialChars: security.isEmpty
            ? true
            : security['requireSpecialChars'] == true,
        enableTwoFactor: security['enableTwoFactor'] == true,
        autoBackup: security['autoBackup'] != false,
      );
      _cache = loaded;
      _cachedAt = DateTime.now();
      return loaded;
    } catch (_) {
      return _cache ?? AppSystemSettings.fallback;
    }
  }

  void invalidate() {
    _cache = null;
    _cachedAt = null;
  }

  String _attemptId(String email) =>
      email.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9@._+-]'), '_');

  /// Null when login may continue.
  Future<String?> loginAttemptBlock(String email) async {
    final settings = await load();
    final max = settings.maxLoginAttempts < 1 ? 1 : settings.maxLoginAttempts;
    try {
      final doc =
          await _firestore.collection('login_attempts').doc(_attemptId(email)).get();
      if (!doc.exists) return null;
      final data = doc.data() ?? {};
      final count = (data['count'] as num?)?.toInt() ?? 0;
      final at = data['updatedAt'];
      if (at is Timestamp &&
          DateTime.now().difference(at.toDate()) > const Duration(minutes: 15)) {
        return null;
      }
      if (count >= max) {
        return 'Too many login attempts. Try again in 15 minutes.';
      }
    } catch (_) {}
    return null;
  }

  Future<void> recordFailedLogin(String email) async {
    final id = _attemptId(email);
    try {
      final ref = _firestore.collection('login_attempts').doc(id);
      final doc = await ref.get();
      var count = 1;
      if (doc.exists) {
        final at = doc.data()?['updatedAt'];
        final previous = (doc.data()?['count'] as num?)?.toInt() ?? 0;
        final fresh = at is Timestamp &&
            DateTime.now().difference(at.toDate()) > const Duration(minutes: 15);
        count = fresh ? 1 : previous + 1;
      }
      await ref.set({
        'email': email.trim().toLowerCase(),
        'count': count,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> clearFailedLogins(String email) async {
    try {
      await _firestore.collection('login_attempts').doc(_attemptId(email)).delete();
    } catch (_) {}
  }
}
