import 'package:cloud_firestore/cloud_firestore.dart';

import 'philsms_local_overrides.dart';

/// PhilSMS (https://dashboard.philsms.com) — client-side hearing alerts.
///
/// Configure:
/// `flutter run --dart-define=PHILSMS_API_TOKEN=your_token --dart-define=PHILSMS_SENDER_ID=YourSender`
///
/// Or set [kPhilSmsApiToken] / [kPhilSmsStaffAttorneyPhones] in [philsms_local_overrides.dart].
class PhilSmsConfig {
  PhilSmsConfig._();

  static const String _envToken = String.fromEnvironment(
    'PHILSMS_API_TOKEN',
    defaultValue: '3121|EcLePG3aVbu2YUoc6nxNVONdIW1BFThS1CN9ZxBqf680e780',
  );
  static const String _envSender = String.fromEnvironment(
    'PHILSMS_SENDER_ID',
    defaultValue: 'PhilSMS',
  );

  /// Tokens from https://dashboard.philsms.com/developers use this host (not app.philsms.com).
  static const String apiBaseUrl = 'https://dashboard.philsms.com/api/v3';

  /// Prefer [kPhilSmsApiToken] in overrides; use --dart-define only when non-empty.
  static String get apiToken {
    final fromOverrides = kPhilSmsApiToken.trim();
    if (fromOverrides.isNotEmpty) return fromOverrides;
    return _envToken.trim();
  }

  /// Prefer [kPhilSmsSenderId] in overrides; use --dart-define only when non-empty.
  static String get senderId {
    final fromOverrides = kPhilSmsSenderId.trim();
    if (fromOverrides.isNotEmpty) return fromOverrides;
    final fromEnv = _envSender.trim();
    if (fromEnv.isNotEmpty) return fromEnv;
    return 'PhilSMS';
  }

  static bool get isConfigured => apiToken.trim().isNotEmpty;

  /// Staff / attorney: phone by Firebase uid (see overrides file).
  static String? directPhoneForUserId(String uid) {
    final t = kPhilSmsStaffAttorneyPhones[uid.trim()]?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  /// Staff / attorney: phone by role key (`attorney`, `staff`, etc.).
  static String? directPhoneForRole(String role) {
    var r = role.toLowerCase().trim();
    if (r.isEmpty) return null;
    if (r.contains('paralegal')) r = 'staff';
    final t = kPhilSmsStaffAttorneyPhones[r]?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  /// UID map first, then role key (`attorney` / `staff`).
  static String? directPhoneForStaffOrAttorney({
    required String uid,
    required String role,
  }) {
    return directPhoneForUserId(uid) ?? directPhoneForRole(role);
  }

  /// Unique alert numbers from [kPhilSmsStaffAttorneyPhones] (attorney + staff, etc.).
  static List<String> get configuredFirmAlertPhones {
    return configuredFirmSmsTargets.map((t) => t.phone).toList();
  }

  /// Firm default numbers with role labels (Attorney, Staff, or Attorney/Staff).
  static List<({String phone, String roleLabel})> get configuredFirmSmsTargets {
    final byNormalized = <String, ({String phone, Set<String> roles})>{};

    void addRole(String roleKey, String phoneRaw) {
      final phone = phoneRaw.trim();
      if (phone.isEmpty) return;
      final roleLabel = roleKey == 'staff' ? 'Staff' : 'Attorney';
      var normalized = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
      if (normalized.startsWith('+')) normalized = normalized.substring(1);
      if (normalized.startsWith('09') &&
          (normalized.length == 10 || normalized.length == 11)) {
        normalized = '63${normalized.substring(1)}';
      } else if (normalized.startsWith('9') && normalized.length == 10) {
        normalized = '63$normalized';
      }
      if (normalized.length < 11) return;
      final existing = byNormalized[normalized];
      if (existing == null) {
        byNormalized[normalized] = (phone: phone, roles: {roleLabel});
      } else {
        existing.roles.add(roleLabel);
      }
    }

    for (final entry in kPhilSmsStaffAttorneyPhones.entries) {
      final key = entry.key.toLowerCase().trim();
      if (key == 'attorney') {
        addRole('attorney', entry.value);
      } else if (key == 'staff' || key.contains('paralegal')) {
        addRole('staff', entry.value);
      }
    }

    return byNormalized.values
        .map(
          (entry) => (
            phone: entry.phone,
            roleLabel: (entry.roles.toList()..sort()).join('/'),
          ),
        )
        .toList();
  }
}

/// PhilSMS alerts for Firestore `hearings` documents (separate from in-app fan-out).
class PhilSmsHearingAlertConfig {
  PhilSmsHearingAlertConfig._();

  static const String hearingCollection = 'hearings';
  static const String smsDedupePrefsKey = 'hearing_philsms_sent_ids_v3';
  static const int maxDedupeIds = 1500;
  static const String smsBrandLabel = 'JurisLink Hearing';

  /// Any change to these fields on a `hearings` doc sends a new SMS (deduped).
  static const List<String> hearingDigestFieldKeys = [
    'caseNo',
    'caseTitle',
    'clientName',
    'courtBranch',
    'documentType',
    'fullText',
    'hearingDate',
    'hearingTime',
    'judgeName',
    'location',
    'summary',
    'hearingDateTime',
    'updatedAt',
    'createdAt',
  ];

  static bool isSmsEligibleHearing(Map<String, dynamic> data) {
    final caseNo = (data['caseNo'] as String?)?.trim() ?? '';
    if (caseNo.isEmpty) return false;
    final fullText = (data['fullText'] as String?)?.trim() ?? '';
    final summary = (data['summary'] as String?)?.trim() ?? '';
    final hearingDate = (data['hearingDate'] as String?)?.trim() ?? '';
    return fullText.isNotEmpty || summary.isNotEmpty || hearingDate.isNotEmpty;
  }

  /// Stable digest from [hearingDigestFieldKeys] — new/updated hearing content → new SMS.
  static String digestForDocument(String docId, Map<String, dynamic> data) {
    String ts(dynamic value) {
      if (value is Timestamp) return '${value.seconds}';
      return value?.toString() ?? '';
    }

    final parts = <String>[docId];
    for (final key in hearingDigestFieldKeys) {
      final v = data[key];
      if (key == 'updatedAt' || key == 'createdAt' || key == 'hearingDateTime') {
        parts.add(ts(v));
      } else {
        parts.add(v?.toString().trim() ?? '');
      }
    }
    return parts.join('|').hashCode.toString();
  }

  static String caseLabelFromHearing(Map<String, dynamic> data) {
    final caseNo = (data['caseNo'] as String?)?.trim() ?? '';
    final caseTitle = (data['caseTitle'] as String?)?.trim() ?? '';
    if (caseNo.isNotEmpty && caseTitle.isNotEmpty) {
      return '$caseNo - $caseTitle';
    }
    return caseNo.isNotEmpty ? caseNo : caseTitle;
  }

  static String titleFromHearing(Map<String, dynamic> data) {
    final docType = (data['documentType'] as String?)?.trim();
    final branch = (data['courtBranch'] as String?)?.trim();
    if (docType != null && docType.isNotEmpty && branch != null && branch.isNotEmpty) {
      return '$docType - $branch';
    }
    return docType ?? branch ?? 'Court hearing update';
  }

  static String summaryFromHearing(Map<String, dynamic> data) {
    final summary = (data['summary'] as String?)?.trim();
    if (summary != null && summary.isNotEmpty) return summary;
    final date = (data['hearingDate'] as String?)?.trim() ?? '';
    final time = (data['hearingTime'] as String?)?.trim() ?? '';
    if (date.isNotEmpty && time.isNotEmpty) return 'Hearing $date at $time';
    if (date.isNotEmpty) return 'Hearing on $date';
    return '';
  }
}
