import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/philsms_config.dart';
import 'philsms_service.dart';

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

  /// Standalone path: `hearings` doc added/updated → SMS (if content digest is new).
  Future<void> _onHearingDocumentChanged(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (!doc.exists) return;
    final data = doc.data();
    if (data == null || !PhilSmsHearingAlertConfig.isSmsEligibleHearing(data)) {
      return;
    }

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
    if (!PhilSmsConfig.isConfigured) {
      if (kDebugMode) {
        debugPrint('HearingSmsAlertService: PhilSMS not configured');
      }
      return;
    }
    if (!PhilSmsHearingAlertConfig.isSmsEligibleHearing(hearingData)) return;

    final digestKey =
        PhilSmsHearingAlertConfig.digestForDocument(hearingDocId, hearingData);

    final hearingDate = (hearingData['hearingDate'] as String?)?.trim() ?? '';
    final hearingTime = (hearingData['hearingTime'] as String?)?.trim() ?? '';
    final caseNo = (hearingData['caseNo'] as String?)?.trim() ?? '';
    final caseTitle = (hearingData['caseTitle'] as String?)?.trim() ?? '';
    final clientName = (hearingData['clientName'] as String?)?.trim() ?? '';
    final location = _hearingLocation(hearingData);

    final phonesAlreadySent = <String>{};
    final clientUids = await _resolveClientUidsByName(hearingData);

    Future<void> sendToPhone(
      String phone,
      String smsDigestKey,
      String roleLabel, {
      String reminderNote = '',
    }) async {
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

      final smsText = _buildSmsText(
        roleLabel: roleLabel,
        caseNo: caseNo,
        caseTitle: caseTitle,
        clientName: clientName,
        hearingDate: hearingDate,
        hearingTime: hearingTime,
        location: location,
        reminderNote: reminderNote,
      );

      final result = await PhilSmsService.instance.sendSmsWithResult(
        to: phone,
        message: smsText,
      );
      if (kDebugMode) {
        debugPrint(
          'HearingSmsAlertService [$roleLabel] → …${normalized.substring(normalized.length - 4)}: '
          '${result.success ? "ok" : result.errorMessage ?? "failed"}',
        );
      }
      if (result.success) await _markSent(smsDigestKey);
    }

    for (final target in PhilSmsConfig.configuredFirmSmsTargets) {
      final normalized = PhilSmsService.normalizeRecipient(target.phone);
      await sendToPhone(
        target.phone,
        '${digestKey}_cfg_$normalized',
        target.roleLabel,
      );
    }

    for (final uid in clientUids) {
      final phone = await _resolvePhoneForUser(uid);
      if (phone == null || phone.isEmpty) continue;
      final normalized = PhilSmsService.normalizeRecipient(phone);
      await sendToPhone(phone, '${digestKey}_client_${uid}_$normalized', 'Client');
    }

    for (final uid in recipientUserIds) {
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
    final parts = hearingName
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
      if (stored.isNotEmpty && _clientNameExactMatch(stored, cn)) {
        return true;
      }
    }

    final hearingParts = _parseFirstLastFromHearing(cn);
    if (hearingParts == null) return false;

    String norm(String s) =>
        s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final signUpFirst = norm(userData['firstName']?.toString() ?? '');
    final signUpLast = norm(userData['lastName']?.toString() ?? '');
    if (signUpFirst.isEmpty || signUpLast.isEmpty) return false;

    return signUpFirst == norm(hearingParts.first) &&
        signUpLast == norm(hearingParts.last);
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
    final clientName = (data['clientName'] as String?)?.trim() ?? '';
    if (clientName.isEmpty) return const [];

    final matched = <String>{};
    final variants = _clientNameQueryVariants(clientName);
    const fields = ['fullName', 'name', 'displayName'];

    void tryAdd(Map<String, dynamic> userData, String uid) {
      final role = (userData['role'] as String?)?.toLowerCase().trim() ?? '';
      if (role != 'client') return;
      if (_clientSignUpMatchesHearing(userData, clientName)) {
        matched.add(uid);
      }
    }

    try {
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

      final hearingParts = _parseFirstLastFromHearing(clientName);
      if (hearingParts != null) {
        for (final first in _clientNameQueryVariants(hearingParts.first)) {
          for (final last in _clientNameQueryVariants(hearingParts.last)) {
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

      if (matched.isEmpty) {
        final cq = await _db
            .collection('users')
            .where('role', isEqualTo: 'client')
            .limit(300)
            .get();
        for (final doc in cq.docs) {
          tryAdd(doc.data(), doc.id);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('HearingSmsAlertService client lookup: $e');
      }
    }

    if (kDebugMode && clientName.isNotEmpty) {
      debugPrint(
        'HearingSmsAlertService: clientName="$clientName" exact matches=${matched.length}',
      );
    }
    return matched.toList();
  }

  Future<String?> _resolvePhoneForUser(String uid) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      if (!snap.exists) {
        return PhilSmsConfig.directPhoneForUserId(uid);
      }
      final data = snap.data() ?? {};
      final role = (data['role'] as String?)?.toLowerCase().trim() ?? '';
      final profilePhone =
          (data['phoneNumber'] ?? data['phone'])?.toString().trim();

      if (role == 'client') {
        return (profilePhone != null && profilePhone.isNotEmpty)
            ? profilePhone
            : null;
      }

      if (role == 'attorney' ||
          role == 'staff' ||
          role.contains('paralegal')) {
        final configured = PhilSmsConfig.directPhoneForStaffOrAttorney(
          uid: uid,
          role: role,
        );
        if (configured != null && configured.isNotEmpty) return configured;
        return profilePhone;
      }

      return PhilSmsConfig.directPhoneForUserId(uid) ?? profilePhone;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('HearingSmsAlertService phone lookup $uid: $e');
      }
      return PhilSmsConfig.directPhoneForUserId(uid);
    }
  }

  String _buildSmsText({
    String roleLabel = '',
    String caseNo = '',
    String caseTitle = '',
    String clientName = '',
    String hearingDate = '',
    String hearingTime = '',
    String location = '',
    String reminderNote = '',
  }) {
    final parts = <String>[PhilSmsHearingAlertConfig.smsBrandLabel];
    if (reminderNote.isNotEmpty) parts.add(reminderNote);
    if (roleLabel.isNotEmpty) parts.add('Role: $roleLabel');
    if (caseNo.isNotEmpty) parts.add(caseNo);
    if (caseTitle.isNotEmpty) parts.add(caseTitle);
    if (clientName.isNotEmpty) parts.add('Client: $clientName');
    if (location.isNotEmpty) {
      parts.add(
        location.length > 90
            ? 'Location: ${location.substring(0, 87)}...'
            : 'Location: $location',
      );
    }
    if (hearingDate.isNotEmpty) parts.add('Date: $hearingDate');
    if (hearingTime.isNotEmpty) parts.add('Time: $hearingTime');
    var text = parts.join(' - ');
    if (text.length > 480) text = '${text.substring(0, 477)}...';
    return text;
  }

  Future<bool> _alreadySent(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(PhilSmsHearingAlertConfig.smsDedupePrefsKey) ??
        [];
    return list.contains(key);
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
