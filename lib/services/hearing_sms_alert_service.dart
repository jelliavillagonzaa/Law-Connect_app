import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/philsms_config.dart';
import '../config/semaphore_config.dart';
import '../utils/hearing_sms_formatter.dart';
import 'hearing_calendar_fields.dart';
import 'hearing_party_names.dart';
import 'philsms_service.dart';
import 'semaphore_service.dart';
import 'sms_service.dart';

/// PhilSMS alerts for `hearings` collection — **not** tied to Firestore `notifications` writes.
///
/// Configure token/phones in [philsms_local_overrides.dart] and [PhilSmsHearingAlertConfig].
/// Attorney/staff numbers: [kPhilSmsStaffAttorneyPhones]. Client: sign-up `phone` on `users`.
class HearingSmsAlertService {
  HearingSmsAlertService._();
  static final HearingSmsAlertService instance = HearingSmsAlertService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _hearingsSub;
  int _refCount = 0;

  void attach() {
    _refCount++;
    if (_hearingsSub != null) return;
    unawaited(_startHearingsListener());
  }

  void detach() {
    if (_refCount <= 0) return;
    _refCount--;
    if (_refCount == 0) {
      unawaited(_hearingsSub?.cancel());
      _hearingsSub = null;
    }
  }

  Future<void> _startHearingsListener() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (!await _canListenToFirmHearings(uid)) return;

    try {
      _hearingsSub = _db
          .collection(PhilSmsHearingAlertConfig.hearingCollection)
          .limit(500)
          .snapshots()
          .listen(
            (snap) {
              for (final change in snap.docChanges) {
                if (change.type == DocumentChangeType.added ||
                    change.type == DocumentChangeType.modified) {
                  unawaited(_onHearingDocumentChanged(change.doc));
                }
              }
            },
            onError: (Object e) {
              if (kDebugMode) {
                debugPrint('HearingSmsAlertService listener: $e');
              }
            },
          );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('HearingSmsAlertService could not subscribe: $e');
      }
    }
  }

  Future<bool> _canListenToFirmHearings(String uid) async {
    try {
      final u = await _db.collection('users').doc(uid).get();
      if (!u.exists) return false;
      final role = (u.data()?['role'] as String?)?.toLowerCase().trim() ?? '';
      return role == 'attorney' ||
          role == 'staff' ||
          role == 'admin' ||
          role.contains('paralegal');
    } catch (_) {
      return false;
    }
  }

  /// Skip when Cloud Functions already owns or finished the intake SMS.
  ///
  /// Do **not** treat [fcmPushClaimedAt] as SMS-sent — that flag is push-only
  /// and was blocking texts whenever the phone push was claimed first.
  /// [philsmsIntakeSent] is the SMS claim; on send failure CF clears it.
  static bool _cloudFunctionsSendsIntakeSms(Map<String, dynamic> data) {
    return data['philsmsLastSentAt'] != null ||
        data['philsmsIntakeSent'] == true;
  }

  /// Standalone path: `hearings` doc added/updated → SMS (if content digest is new).
  Future<void> _onHearingDocumentChanged(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (!doc.exists) return;
    final data = doc.data();
    if (data == null || !PhilSmsHearingAlertConfig.isSmsEligibleHearing(data)) {
      return;
    }
    if (_cloudFunctionsSendsIntakeSms(data)) return;

    final clientUids = await _resolveClientUidsByName(data);
    await sendAlertsForHearing(
      hearingDocId: doc.id,
      hearingData: data,
      recipientUserIds: clientUids,
    );
  }

  /// Called from [HearingNotificationFanoutService] after resolving recipients, or from the listener above.
  Future<void> sendAlertsForHearing({
    required String hearingDocId,
    required Map<String, dynamic> hearingData,
    required List<String> recipientUserIds,
    String? title,
    String? body,
    String? summary,
    String? caseLabel,
  }) async {
    if (!PhilSmsConfig.isConfigured && !SemaphoreConfig.isConfigured) {
      if (kDebugMode) {
        debugPrint('HearingSmsAlertService: PhilSMS and Semaphore not configured');
      }
      return;
    }
    if (!PhilSmsHearingAlertConfig.isSmsEligibleHearing(hearingData)) return;
    if (_cloudFunctionsSendsIntakeSms(hearingData)) return;

    final intakeKey = 'hearing_sms_intake_$hearingDocId';
    if (await _alreadySent(intakeKey)) return;
    await _markSent(intakeKey);
    var delivered = false;

    final digestKey =
        PhilSmsHearingAlertConfig.digestForDocument(hearingDocId, hearingData);

    // Match PDF facts: fill missing hearingDate/time and scrub emails from names.
    final enriched = HearingCalendarFields.enrichForAlerts(hearingData);
    final hearingDate =
        HearingCalendarFields.hearingFieldAsString(enriched, 'hearingDate');
    final hearingTime =
        HearingCalendarFields.hearingFieldAsString(enriched, 'hearingTime');
    final caseNo = HearingCalendarFields.asDisplayString(enriched['caseNo']);
    final caseTitle =
        HearingCalendarFields.asDisplayString(enriched['caseTitle']);
    final clientName =
        HearingCalendarFields.asDisplayString(enriched['clientName']);
    final location = _hearingLocation(enriched);

    final phonesAlreadySent = <String>{};
    final clientUids = await _resolveClientUidsByName(hearingData);

    Future<void> sendToPhone(
      String phone,
      String smsDigestKey,
      String roleLabel,
    ) async {
      final normalized = PhilSmsService.normalizeRecipient(phone);
      if (normalized.length < 11) {
        if (kDebugMode) {
          debugPrint(
            'HearingSmsAlertService: invalid phone "$phone" (need 09XXXXXXXXX)',
          );
        }
        return;
      }
      if (!phonesAlreadySent.add(normalized)) return;
      if (await _alreadySent(smsDigestKey)) return;

      final smsText = HearingSmsFormatter.build(
        caseNo: caseNo,
        caseTitle: caseTitle,
        clientName: clientName,
        hearingDate: hearingDate,
        hearingTime: hearingTime,
        location: location,
      );

      if (kIsWeb) {
        try {
          await SmsService().queueSms(
            to: phone,
            body: smsText,
            meta: {
              'type': 'hearing_activity',
              'hearingDocId': hearingDocId,
            },
          );
          delivered = true;
          await _markSent(smsDigestKey);
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              'HearingSmsAlertService web SMS queue [$roleLabel] failed: $e',
            );
          }
        }
        return;
      }

      var philOk = false;
      if (PhilSmsConfig.isConfigured) {
        final result = await PhilSmsService.instance.sendSmsWithResult(
          to: phone,
          message: smsText,
        );
        philOk = result.success;
        if (kDebugMode) {
          debugPrint(
            'HearingSmsAlertService PhilSMS [$roleLabel] → …${normalized.substring(normalized.length - 4)}: '
            '${result.success ? "ok" : result.errorMessage ?? "failed"}',
          );
        }
      }

      var semOk = false;
      if (SemaphoreConfig.isConfigured) {
        final sem = await SemaphoreService.instance.sendSmsWithResult(
          to: phone,
          message: smsText,
        );
        semOk = sem.success;
        if (kDebugMode) {
          debugPrint(
            'HearingSmsAlertService Semaphore [$roleLabel] → …${normalized.substring(normalized.length - 4)}: '
            '${sem.success ? "ok" : sem.errorMessage ?? "failed"}',
          );
        }
      }

      if (philOk || semOk) {
        delivered = true;
        await _markSent(smsDigestKey);
      }
    }

    for (final uid in clientUids) {
      final phone = await _resolvePhoneForUser(uid);
      if (phone == null || phone.isEmpty) continue;
      final normalized = PhilSmsService.normalizeRecipient(phone);
      await sendToPhone(phone, '${digestKey}_client_${uid}_$normalized', 'Client');
    }

    final firmUserIds = await _activeAttorneyAndStaffIds();
    final smsUserIds = <String>{...recipientUserIds, ...firmUserIds};
    for (final uid in smsUserIds) {
      if (clientUids.contains(uid)) continue;
      final phone = await _resolvePhoneForUser(uid);
      if (phone == null || phone.isEmpty) {
        if (kDebugMode) {
          debugPrint('HearingSmsAlertService: no phone for $uid');
        }
        continue;
      }
      final roleLabel = await _roleLabelForUid(uid);
      final normalized = PhilSmsService.normalizeRecipient(phone);
      await sendToPhone(phone, '${digestKey}_uid_${uid}_$normalized', roleLabel);
    }

    if (!delivered) await _unmarkSent(intakeKey);
  }

  static String _formatSmsRole(String? role) {
    final r = (role ?? '').toLowerCase().trim();
    if (r == 'attorney') return 'Attorney';
    if (r == 'staff' || r.contains('paralegal')) return 'Staff';
    if (r == 'client') return 'Client';
    if (r == 'admin') return 'Admin';
    return 'Firm';
  }

  String _hearingLocation(Map<String, dynamic> data) {
    final venue = HearingCalendarFields.resolveVenueForDisplay(data);
    if (venue.isNotEmpty && !HearingCalendarFields.isBareLocation(venue)) {
      return venue;
    }
    final loc = (data['location'] as String?)?.trim() ?? '';
    if (loc.isNotEmpty) return loc;
    return (data['courtBranch'] as String?)?.trim() ?? '';
  }

  Future<String> _roleLabelForUid(String uid) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      if (!snap.exists) return 'Firm';
      return _formatSmsRole(snap.data()?['role'] as String?);
    } catch (_) {
      return 'Firm';
    }
  }

  /// Exact full-name match (case / spaces ignored).
  static bool _clientNameExactMatch(String stored, String hearingName) {
    String norm(String s) =>
        s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final a = norm(stored);
    final b = norm(hearingName);
    return a.isNotEmpty && a == b;
  }

  /// first + last from hearing `clientName` (middle in hearing ignored).
  static ({String first, String last})? _parseFirstLastFromHearing(
    String hearingName,
  ) {
    final cleaned = HearingPartyNames.stripRoles(hearingName);
    final parts = (cleaned.isNotEmpty ? cleaned : hearingName)
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .split(' ')
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 2) return null;
    if (parts.length == 2) {
      return (first: parts[0], last: parts[1]);
    }
    return (first: parts[0], last: parts.last);
  }

  /// Match `fullName`/`name` OR sign-up `firstName`+`lastName` (`middleName` ignored).
  static bool _clientSignUpMatchesHearing(
    Map<String, dynamic> userData,
    String hearingClientName,
  ) {
    final cn = hearingClientName.trim();
    if (cn.isEmpty) return false;

    for (final field in ['fullName', 'name', 'displayName']) {
      final stored = (userData[field] as String?)?.trim() ?? '';
      if (stored.isEmpty) continue;
      if (_clientNameExactMatch(stored, cn)) return true;
      for (final party in HearingPartyNames.split(cn)) {
        if (_clientNameExactMatch(stored, party)) return true;
      }
    }

    final parties = HearingPartyNames.split(cn);
    final candidates = parties.isEmpty ? [cn] : parties;
    String norm(String s) =>
        s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final signUpFirst = norm(userData['firstName']?.toString() ?? '');
    final signUpLast = norm(userData['lastName']?.toString() ?? '');
    if (signUpFirst.isEmpty || signUpLast.isEmpty) return false;

    for (final party in candidates) {
      final hearingParts = _parseFirstLastFromHearing(party);
      if (hearingParts == null) continue;
      if (signUpFirst == norm(hearingParts.first) &&
          signUpLast == norm(hearingParts.last)) {
        return true;
      }
    }
    return false;
  }

  static List<String> _clientNameQueryVariants(String raw) {
    final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return const [];
    final titled = t
        .split(' ')
        .map((w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
    return {t, t.toUpperCase(), t.toLowerCase(), titled}.toList();
  }

  Future<List<String>> _resolveClientUidsByName(Map<String, dynamic> data) async {
    final matched = <String>{};

    for (final key in ['involvedClientIds', 'matchedClientIds']) {
      final arr = data[key];
      if (arr is List) {
        for (final uid in arr) {
          if (uid is String && uid.trim().isNotEmpty) {
            matched.add(uid.trim());
          }
        }
      }
    }
    final owner = (data['ownerClientId'] as String?)?.trim() ?? '';
    if (owner.isNotEmpty) matched.add(owner);

    final clientName = (data['clientName'] as String?)?.trim() ?? '';
    final caseTitle = (data['caseTitle'] as String?)?.trim() ?? '';
    final combinedParties = [clientName, caseTitle].where((s) => s.isNotEmpty).join(', ');
    if (combinedParties.isEmpty && matched.isEmpty) return const [];

    final parties = HearingPartyNames.split(combinedParties);
    const fields = ['fullName', 'name', 'displayName'];

    void tryAdd(Map<String, dynamic> userData, String uid) {
      final role = (userData['role'] as String?)?.toLowerCase().trim() ?? '';
      if (role != 'client') return;
      if (_clientSignUpMatchesHearing(userData, combinedParties)) {
        matched.add(uid);
      }
    }

    try {
      final queryNames = parties.isEmpty ? [combinedParties] : parties;
      for (final party in queryNames.take(16)) {
        final variants = _clientNameQueryVariants(party);
        for (final field in fields) {
          for (final nm in variants) {
            final q = await _db
                .collection('users')
                .where(field, isEqualTo: nm)
                .where('role', isEqualTo: 'client')
                .limit(10)
                .get();
            for (final doc in q.docs) {
              tryAdd(doc.data(), doc.id);
            }
          }
        }

        final hearingParts = _parseFirstLastFromHearing(party);
        if (hearingParts != null) {
          for (final first in _clientNameQueryVariants(hearingParts.first).take(2)) {
            for (final last in _clientNameQueryVariants(hearingParts.last).take(2)) {
              try {
                final q = await _db
                    .collection('users')
                    .where('role', isEqualTo: 'client')
                    .where('firstName', isEqualTo: first)
                    .where('lastName', isEqualTo: last)
                    .limit(10)
                    .get();
                for (final doc in q.docs) {
                  tryAdd(doc.data(), doc.id);
                }
              } catch (_) {}
            }
          }
        }
      }

      final cq = await _db
          .collection('users')
          .where('role', isEqualTo: 'client')
          .limit(300)
          .get();
      for (final doc in cq.docs) {
        if (matched.contains(doc.id)) continue;
        tryAdd(doc.data(), doc.id);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('HearingSmsAlertService client lookup: $e');
      }
    }

    if (kDebugMode && combinedParties.isNotEmpty) {
      debugPrint(
        'HearingSmsAlertService: partyBlob="$combinedParties" matches=${matched.length}',
      );
    }
    return matched.toList();
  }

  /// Active attorney and staff accounts. Court SMS uses each profile phone.
  Future<List<String>> _activeAttorneyAndStaffIds() async {
    final ids = <String>{};
    for (final role in const ['attorney', 'staff']) {
      try {
        final q = await _db
            .collection('users')
            .where('role', isEqualTo: role)
            .limit(80)
            .get();
        for (final doc in q.docs) {
          if (doc.data()['isActive'] == false) continue;
          ids.add(doc.id);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('HearingSmsAlertService firm users ($role): $e');
        }
      }
    }
    return ids.toList();
  }

  Future<String?> _resolvePhoneForUser(String uid) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      if (!snap.exists) return null;
      final data = snap.data() ?? {};
      final profilePhone = (data['phoneNumber'] ??
              data['phone'] ??
              data['contactNumber'] ??
              data['mobileNumber'] ??
              data['contact'])
          ?.toString()
          .trim();
      if (profilePhone == null || profilePhone.isEmpty) return null;
      return profilePhone;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('HearingSmsAlertService phone lookup $uid: $e');
      }
      return null;
    }
  }


  Future<bool> _alreadySent(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(PhilSmsHearingAlertConfig.smsDedupePrefsKey) ??
        [];
    return list.contains(key);
  }

  Future<void> _unmarkSent(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(PhilSmsHearingAlertConfig.smsDedupePrefsKey) ??
        [];
    if (!list.remove(key)) return;
    await prefs.setStringList(PhilSmsHearingAlertConfig.smsDedupePrefsKey, list);
  }

  Future<void> _markSent(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(PhilSmsHearingAlertConfig.smsDedupePrefsKey) ??
        [];
    if (list.contains(key)) return;
    list.insert(0, key);
    final max = PhilSmsHearingAlertConfig.maxDedupeIds;
    final trimmed = list.length > max ? list.sublist(0, max) : list;
    await prefs.setStringList(
      PhilSmsHearingAlertConfig.smsDedupePrefsKey,
      trimmed,
    );
  }
}
