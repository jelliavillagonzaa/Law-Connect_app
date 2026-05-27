import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/hearing_notification_formatter.dart';
import 'hearing_calendar_fields.dart';
import 'hearing_sms_alert_service.dart';
import 'staff_application_service.dart';

/// Inbox / fan-out must not spam the console when switching attorney tabs.
void _fanoutLog(String message) {}

/// Top-level (not on the singleton) so Flutter web hot reload does not leave the map undefined.
final Map<String, _InboxStreamBundle> _hearingInboxBundles =
    <String, _InboxStreamBundle>{};

/// In-memory read-hearing ids (avoids awaiting SharedPreferences on every emit).
final Map<String, Set<String>> _readHearingIdsMem = <String, Set<String>>{};

/// Last bell badge count — shown instantly before Firestore catches up.
final Map<String, int> _bellCountMem = <String, int>{};
const String _bellCountPrefsPrefix = 'inbox_bell_count_v2_';

void _cacheBellCount(String userId, List<HearingInboxRow> rows) {
  if (userId.isEmpty) return;
  final n = rows.where((r) => r.isUnread).length;
  _bellCountMem[userId] = n;
  unawaited(() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_bellCountPrefsPrefix$userId', n);
    } catch (_) {}
  }());
}

Future<void> _loadBellCountFromPrefs(String userId) async {
  if (userId.isEmpty || _bellCountMem.containsKey(userId)) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    _bellCountMem[userId] = prefs.getInt('$_bellCountPrefsPrefix$userId') ?? 0;
  } catch (_) {
    _bellCountMem[userId] = 0;
  }
}

/// Writes one `notifications` row per involved user from a `hearings` document — **no Cloud Functions required**.
///
/// - Resolves `cases` by `caseId`, or by `caseNo` / client name (same idea as server logic).
/// - Recipients: client, attorney, `staffId`, `staffAssigned`, and all `users` with `role == staff` and `assignedAttorneyId` for that attorney.
/// - Dedupes via [SharedPreferences] so the bell does not re-spam on every app restart.
/// Optional field `clientFanoutComplete` on the hearing doc (when rules allow) was used by older
/// Cloud Functions to skip duplicate in-app writes; deployed functions now merge the same doc IDs
/// and always send push + reminder scheduling.
class HearingNotificationFanoutService {
  HearingNotificationFanoutService._();
  static final HearingNotificationFanoutService instance =
      HearingNotificationFanoutService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _clientHearingSubs = [];
  int _refCount = 0;

  /// Throttle client hearing sync so read notifications are not constantly re-merged.
  static final Map<String, DateTime> _lastClientSyncAt = <String, DateTime>{};
  static const _clientSyncMinInterval = Duration(minutes: 5);

  /// Bump when matching logic changes so older hearings can fan out again (doc IDs are stable; merge avoids dup spam).
  static const _prefsKey = 'hearing_inapp_fanout_ids_v8';
  static const _inboxReadHearingsKeyPrefix = 'inbox_read_hearing_ids_v1_';
  static const _maxIds = 1500;
  static const _maxReadHearingIds = 500;

  /// Always merged into the reminders inbox (not only the recent-200 cap).
  static const _inboxHearingNotificationTypes = [
    'hearing_activity',
    'hearing_activity_update',
  ];

  static const _inboxAppointmentNotificationTypes = [
    'appointment_scheduled',
    'appointment_3day_reminder',
    'appointment_sameday_reminder',
  ];

  String _inboxStreamCacheKey(
    String userId,
    bool allNotificationTypes, {
    bool includeGlobalHearingsFallback = true,
    bool hearingsOnly = false,
  }) =>
      '${userId}_${allNotificationTypes ? 'all' : 'bell'}_${includeGlobalHearingsFallback ? 'gh' : 'nogh'}_${hearingsOnly ? 'ho' : 'allt'}';

  _InboxStreamBundle _inboxBundle(
    String userId, {
    bool allNotificationTypes = false,
    bool includeGlobalHearingsFallback = true,
    bool hearingsOnly = false,
  }) {
    final key = _inboxStreamCacheKey(
      userId,
      allNotificationTypes,
      includeGlobalHearingsFallback: includeGlobalHearingsFallback,
      hearingsOnly: hearingsOnly,
    );
    return _hearingInboxBundles.putIfAbsent(
      key,
      () => _InboxStreamBundle(
        userId: userId,
        allNotificationTypes: allNotificationTypes,
        includeGlobalHearingsFallback: includeGlobalHearingsFallback,
        hearingsOnly: hearingsOnly,
        emitRows: _emitInboxRows,
        attachListeners: _attachInboxListeners,
      ),
    );
  }

  /// Loads last saved badge count from disk (call before [warmInbox] on dashboard).
  Future<void> prepareBellCount(String userId) =>
      _loadBellCountFromPrefs(userId);

  /// Instant badge number for the reminders bell (memory / prefs / cached rows).
  int peekInboxBellCount(
    String userId, {
    bool allNotificationTypes = false,
    bool includeGlobalHearingsFallback = true,
    bool hearingsOnly = false,
  }) {
    if (userId.isEmpty) return 0;
    if (_bellCountMem.containsKey(userId)) {
      return _bellCountMem[userId]!;
    }
    final rows = peekInboxRows(
      userId,
      allNotificationTypes: allNotificationTypes,
      includeGlobalHearingsFallback: includeGlobalHearingsFallback,
      hearingsOnly: hearingsOnly,
    );
    if (rows != null) {
      return rows.where((r) => r.isUnread).length;
    }
    return 0;
  }

  /// Starts Firestore listeners early (e.g. from dashboard) so reminders open instantly.
  void warmInbox(
    String userId, {
    bool allNotificationTypes = false,
    bool includeGlobalHearingsFallback = true,
    bool hearingsOnly = false,
  }) {
    if (userId.isEmpty) return;
    unawaited(_loadBellCountFromPrefs(userId));
    unawaited(_ensureReadHearingIdsLoaded(userId));
    _inboxBundle(
      userId,
      allNotificationTypes: allNotificationTypes,
      includeGlobalHearingsFallback: includeGlobalHearingsFallback,
      hearingsOnly: hearingsOnly,
    );
  }

  /// Last rendered rows — show immediately when opening reminders (no spinner).
  List<HearingInboxRow>? peekInboxRows(
    String userId, {
    bool allNotificationTypes = false,
    bool includeGlobalHearingsFallback = true,
    bool hearingsOnly = false,
  }) {
    return _hearingInboxBundles[_inboxStreamCacheKey(
          userId,
          allNotificationTypes,
          includeGlobalHearingsFallback: includeGlobalHearingsFallback,
          hearingsOnly: hearingsOnly,
        )]
        ?.lastRows;
  }

  void _refreshInboxStreamsForUser(String userId) {
    for (final bundle in _hearingInboxBundles.values) {
      if (bundle.userId == userId) {
        unawaited(bundle.emit());
      }
    }
  }

  Future<void> _ensureReadHearingIdsLoaded(String userId) async {
    if (_readHearingIdsMem.containsKey(userId)) return;
    _readHearingIdsMem[userId] = await _getReadHearingIdsFromPrefs(userId);
  }

  Future<void> _emitInboxRows(
    String userId,
    bool allNotificationTypes,
    bool hearingsOnly,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> notifDocs,
    QuerySnapshot<Map<String, dynamic>>? hearings,
    void Function(List<HearingInboxRow>) deliver,
  ) async {
    var readHearingIds = _readHearingIdsMem[userId];
    if (readHearingIds == null) {
      readHearingIds = await _getReadHearingIdsFromPrefs(userId);
      _readHearingIdsMem[userId] = readHearingIds;
    }
    deliver(
      buildInboxRowsFromSnapshots(
        notifDocs,
        hearings?.docs ?? const [],
        allNotificationTypes: allNotificationTypes,
        hearingsOnly: hearingsOnly,
        readHearingIds: readHearingIds,
      ),
    );
  }

  void _attachInboxListeners(
    String userId,
    bool allNotificationTypes,
    bool includeGlobalHearingsFallback,
    bool hearingsOnly,
    void Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> notifDocs,
      QuerySnapshot<Map<String, dynamic>>? hearings,
    )
    onData,
  ) {
    QuerySnapshot<Map<String, dynamic>>? lastHearings;
    Timer? refreshDebounce;
    var refreshGen = 0;

    Future<void> refreshNotifDocs({bool allowGlobalHearings = false}) async {
      final gen = ++refreshGen;
      try {
        final merged = await _notificationDocsForInbox(
          userId,
          hearingsOnly: hearingsOnly,
        );
        if (gen != refreshGen) return;
        QuerySnapshot<Map<String, dynamic>>? hearingsSnap;
        if (allowGlobalHearings) {
          hearingsSnap = lastHearings;
        }
        onData(merged, hearingsSnap);
      } catch (e) {
        if (kDebugMode) _fanoutLog('inbox refreshNotifDocs: $e');
        if (gen != refreshGen) return;
        onData(const [], allowGlobalHearings ? lastHearings : null);
      }
    }

    void scheduleRefresh({required bool allowGlobalHearings}) {
      refreshDebounce?.cancel();
      refreshDebounce = Timer(const Duration(milliseconds: 250), () {
        unawaited(refreshNotifDocs(allowGlobalHearings: allowGlobalHearings));
      });
    }

    unawaited(() async {
      if (!await _waitForInboxAuth(userId)) {
        if (kDebugMode) {
          _fanoutLog('inbox: skip listeners — auth uid != $userId');
        }
        onData(const [], null);
        return;
      }

      final allowGlobalHearings = includeGlobalHearingsFallback &&
          await _canUseGlobalHearingsInbox(userId);

      _listenFirestore(
        _userNotificationsInboxStream(userId),
        (_) => scheduleRefresh(allowGlobalHearings: allowGlobalHearings),
        debugLabel: 'inbox notifications stream',
      );

      final isStaff = await _isStaffAccount(userId);
      if (!isStaff) {
        _listenFirestore(
          _db
              .collection('notifications')
              .where('clientId', isEqualTo: userId)
              .limit(200)
              .snapshots(),
          (_) => scheduleRefresh(allowGlobalHearings: allowGlobalHearings),
          debugLabel: 'inbox clientId stream',
        );
      }

      if (allowGlobalHearings) {
        _listenFirestore(
          _hearingsInboxStream(),
          (snap) {
            lastHearings = snap;
            scheduleRefresh(allowGlobalHearings: true);
          },
          debugLabel: 'inbox hearings listener',
        );
      }

      await refreshNotifDocs(allowGlobalHearings: allowGlobalHearings);
    }());
  }

  String _inboxReadHearingsKey(String userId) =>
      '$_inboxReadHearingsKeyPrefix$userId';

  Future<Set<String>> _getReadHearingIdsFromPrefs(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_inboxReadHearingsKey(userId)) ?? []).toSet();
  }

  Future<void> _addReadHearingId(String userId, String hearingDocId) async {
    final mem = _readHearingIdsMem.putIfAbsent(userId, () => <String>{});
    mem.add(hearingDocId);

    final prefs = await SharedPreferences.getInstance();
    final key = _inboxReadHearingsKey(userId);
    final list = prefs.getStringList(key) ?? [];
    if (list.contains(hearingDocId)) return;
    list.insert(0, hearingDocId);
    final trimmed = list.length > _maxReadHearingIds
        ? list.sublist(0, _maxReadHearingIds)
        : list;
    await prefs.setStringList(key, trimmed);
  }

  static String _normalizeCaseRefWhitespace(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _alnumLower(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// True when the user already opened this inbox row (do not mark unread again).
  static bool _notificationWasRead(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['isRead'] == true) return true;
    if (data['readAt'] != null) return true;
    return false;
  }

  /// Court PDFs may use en-dash or spacing differences vs app `caseNo`.
  static bool _textContainsCaseReference(String haystack, String caseRef) {
    final needle = caseRef.trim();
    if (needle.length < 4) return false;
    final h0 = haystack.trim();
    if (h0.isEmpty) return false;
    final h = h0
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    final n = needle
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    if (h.contains(n)) return true;
    final hc = _alnumLower(h0);
    final nc = _alnumLower(needle);
    return nc.length >= 4 && hc.contains(nc);
  }

  static bool _fieldMatchesCaseReference(String? fieldValue, String caseNo) {
    if (fieldValue == null) return false;
    final v = fieldValue.trim();
    if (v.isEmpty) return false;
    if (v == caseNo) return true;
    final nv = _normalizeCaseRefWhitespace(caseNo);
    if (_textContainsCaseReference(v, nv)) return true;
    final av = _alnumLower(v);
    final an = _alnumLower(caseNo);
    return an.length >= 4 && (av == an || av.contains(an) || an.contains(av));
  }

  static List<String> _caseNumberQueryVariants(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return const [];
    final out = <String>{t, t.toUpperCase(), t.toLowerCase()};
    final collapsed = t.replaceAll(RegExp(r'\s+'), '');
    if (collapsed.isNotEmpty) out.add(collapsed);
    const prefixes = [
      'Civil Case No.',
      'Civil Case No',
      'CRM. No.',
      'Criminal Case No.',
      'Case No.',
      'Case No',
    ];
    for (final p in prefixes) {
      if (t.length > p.length && t.toLowerCase().startsWith(p.toLowerCase())) {
        out.add(t.substring(p.length).trim());
      }
    }
    return out.where((e) => e.isNotEmpty).toList();
  }

  static bool _caseMapMatchesHearing(
    Map<String, dynamic> m,
    String caseNo,
    Map<String, dynamic> hearing,
  ) {
    for (final f in [
      'caseNumber',
      'caseNo',
      'docketNumber',
      'criminalCaseNo',
    ]) {
      if (_fieldMatchesCaseReference(m[f] as String?, caseNo)) return true;
    }
    final title = (m['caseTitle'] as String?) ?? '';
    if (_textContainsCaseReference(title, caseNo)) return true;
    final ft = (hearing['fullText'] as String?)?.trim() ?? '';
    if (ft.isNotEmpty) {
      for (final f in [
        'caseNumber',
        'caseNo',
        'docketNumber',
        'criminalCaseNo',
      ]) {
        final v = (m[f] as String?)?.trim() ?? '';
        if (v.length >= 6 && _textContainsCaseReference(ft, v)) return true;
      }
      if (_textContainsCaseReference(ft, caseNo)) return true;
    }
    return false;
  }

  /// Whether a `hearings` row belongs on an attorney's calendar (case link or explicit notify).
  static bool hearingMatchesAttorneyCases(
    Map<String, dynamic> hearing,
    List<Map<String, dynamic>> attorneyCaseMaps,
    String attorneyId,
  ) {
    final aid = attorneyId.trim();
    if (aid.isEmpty) return false;

    final attorneyUid = (hearing['attorneyUid'] as String?)?.trim() ?? '';
    if (attorneyUid == aid) return true;

    final notify = hearing['notifyUserIds'];
    if (notify is List && notify.contains(aid)) return true;

    final caseId = (hearing['caseId'] as String?)?.trim() ?? '';
    if (caseId.isNotEmpty) {
      return attorneyCaseMaps.any((c) => (c['id'] as String?) == caseId);
    }

    final caseNo = (hearing['caseNo'] as String?)?.trim() ?? '';
    if (caseNo.isNotEmpty) {
      if (attorneyCaseMaps.any(
        (c) => _caseMapMatchesHearing(c, caseNo, hearing),
      )) {
        return true;
      }
      final normH = _normalizeCaseRefWhitespace(caseNo).toLowerCase();
      if (normH.isNotEmpty) {
        for (final c in attorneyCaseMaps) {
          for (final f in [
            'caseNumber',
            'caseNo',
            'docketNumber',
            'criminalCaseNo',
          ]) {
            final raw = (c[f] as String?)?.trim() ?? '';
            if (raw.isEmpty) continue;
            final v = _normalizeCaseRefWhitespace(raw).toLowerCase();
            if (v.isNotEmpty && (v == normH || v.contains(normH))) {
              return true;
            }
          }
        }
      }
    }

    final clientName =
        (hearing['clientName'] as String?)?.trim().toLowerCase() ?? '';
    if (clientName.isNotEmpty) {
      for (final c in attorneyCaseMaps) {
        final title = ((c['caseTitle'] as String?) ?? '').toLowerCase();
        if (title.contains(clientName)) return true;
        final first = clientName.split(RegExp(r'\s+')).first;
        if (first.length > 2 && title.contains(first)) return true;
      }
    }

    if (HearingCalendarFields.isCourtImportRow(hearing) &&
        attorneyCaseMaps.isNotEmpty &&
        (caseNo.isNotEmpty || clientName.isNotEmpty)) {
      return true;
    }

    return false;
  }

  /// Call when attorney / staff / admin dashboard mounts, or client notifications.
  void attach() {
    _refCount++;
    // Heavy hearings snapshot — defer so bottom nav stays responsive.
    if (!kIsWeb) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (_refCount > 0) {
          HearingSmsAlertService.instance.attach();
        }
      });
    }
    if (_sub != null || _clientHearingSubs.isNotEmpty) return;
    unawaited(_startListener());
  }

  /// Call from dashboard [dispose] (paired with [attach]).
  void detach() {
    if (_refCount <= 0) return;
    _refCount--;
    if (_refCount == 0) {
      unawaited(_sub?.cancel());
      _sub = null;
      for (final sub in _clientHearingSubs) {
        unawaited(sub.cancel());
      }
      _clientHearingSubs.clear();
      HearingSmsAlertService.instance.detach();
    }
  }

  /// After creating a hearing from the app, queue a one-shot fan-out.
  void scheduleProcess(DocumentReference<Map<String, dynamic>> ref) {
    scheduleMicrotask(() async {
      try {
        final snap = await ref.get();
        if (snap.exists) await processDocumentIfNeeded(snap);
      } catch (e) {
        if (kDebugMode) {
          _fanoutLog('HearingNotificationFanout.scheduleProcess: $e');
        }
      }
    });
  }

  Future<void> _startListener() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final u = await _db.collection('users').doc(uid).get();
      final role = (u.data()?['role'] as String?)?.toLowerCase() ?? '';
      if (role == 'client') {
        await _startClientHearingListener(uid);
        return;
      }
    } catch (_) {
      return;
    }

    try {
      _sub = _db
          .collection('hearings')
          .limit(500)
          .snapshots()
          .listen(
            (snap) {
              for (final change in snap.docChanges) {
                if (change.type == DocumentChangeType.added ||
                    change.type == DocumentChangeType.modified) {
                  unawaited(processDocumentIfNeeded(change.doc));
                }
              }
            },
            onError: (_) {},
          );
    } catch (e) {
      if (kDebugMode) {
        _fanoutLog('HearingNotificationFanout could not subscribe: $e');
      }
    }
  }

  Future<void> _cancelClientHearingSubs() async {
    for (final sub in _clientHearingSubs) {
      await sub.cancel();
    }
    _clientHearingSubs.clear();
  }

  void _listenClientHearingQuery(
    Query<Map<String, dynamic>> query,
    String debugLabel,
  ) {
    _clientHearingSubs.add(
      query.snapshots().listen(
        (snap) {
          for (final change in snap.docChanges) {
            if (change.type == DocumentChangeType.removed) continue;
            unawaited(
              ensureClientHearingNotification(
                change.doc,
                trustClientNameMatch: true,
              ),
            );
          }
        },
        onError: (Object e) {
          if (kDebugMode) {
            _fanoutLog('HearingNotificationFanout $debugLabel: $e');
          }
        },
        cancelOnError: true,
      ),
    );
  }

  /// Writes client link fields on `hearings` so rules + queries include this client.
  Future<void> _linkHearingToClients(
    DocumentReference<Map<String, dynamic>> ref,
    Set<String> clientUids, {
    String? caseId,
    bool firmMaySetCaseId = false,
  }) async {
    if (clientUids.isEmpty) return;
    final link = <String, dynamic>{
      'involvedClientIds': FieldValue.arrayUnion(clientUids.toList()),
      'matchedClientIds': FieldValue.arrayUnion(clientUids.toList()),
    };
    if (clientUids.length == 1) {
      link['ownerClientId'] = clientUids.first;
    }
    final cid = caseId?.trim() ?? '';
    if (cid.isNotEmpty && (firmMaySetCaseId || clientUids.length == 1)) {
      link['caseId'] = cid;
    }
    try {
      await ref.set(link, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Resolves a `cases` doc id for this hearing + client (for linking / rules).
  Future<String?> _caseIdForClientOnHearing(
    String clientUid,
    Map<String, dynamic> d,
  ) async {
    final onHearing = (d['caseId'] as String?)?.trim() ?? '';
    if (onHearing.isNotEmpty) {
      try {
        final snap = await _db.collection('cases').doc(onHearing).get();
        if (snap.exists && snap.data()?['clientId'] == clientUid) {
          return onHearing;
        }
      } catch (_) {}
    }
    final resolved = await _resolveCase(d);
    if (resolved != null) {
      try {
        final snap = await _db.collection('cases').doc(resolved.id).get();
        if (snap.exists && snap.data()?['clientId'] == clientUid) {
          return resolved.id;
        }
      } catch (_) {}
    }
    final caseNo = (d['caseNo'] as String?)?.trim() ?? '';
    if (caseNo.isEmpty) return null;
    try {
      final cq = await _db
          .collection('cases')
          .where('clientId', isEqualTo: clientUid)
          .limit(30)
          .get();
      for (final c in cq.docs) {
        if (_caseMapMatchesHearing(c.data(), caseNo, d)) return c.id;
      }
    } catch (_) {}
    return null;
  }

  /// Real-time sync for clients: linked hearings + periodic name/case backfill.
  Future<void> _startClientHearingListener(String uid) async {
    await _cancelClientHearingSubs();

    unawaited(syncClientHearingNotifications(force: true));

    try {
      _listenClientHearingQuery(
        _db
            .collection('hearings')
            .where('involvedClientIds', arrayContains: uid),
        'client involvedClientIds',
      );
      _listenClientHearingQuery(
        _db.collection('hearings').where('ownerClientId', isEqualTo: uid),
        'client ownerClientId',
      );
      _listenClientHearingQuery(
        _db
            .collection('hearings')
            .where('matchedClientIds', arrayContains: uid),
        'client matchedClientIds',
      );
    } catch (e) {
      if (kDebugMode) {
        _fanoutLog('HearingNotificationFanout client listener setup: $e');
      }
    }
  }

  /// One entry per (hearing doc + content revision) so new messages and edits can fan out again.
  static String _fanoutDigest(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    String ts(dynamic t) {
      if (t is Timestamp) return '${t.seconds}';
      return '';
    }

    final sig = [
      d['message'],
      d['activityType'],
      d['fullText'],
      d['caseNo'],
      d['hearingDateTime']?.toString(),
      ts(d['updatedAt']),
      ts(d['createdAt']),
    ].join('|');
    return '${doc.id}_$sig'.hashCode.toString();
  }

  Future<bool> _alreadyProcessed(String digest) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? [];
    return list.contains(digest);
  }

  Future<void> _markProcessed(String digest) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? [];
    if (list.contains(digest)) return;
    list.insert(0, digest);
    final trimmed = list.length > _maxIds ? list.sublist(0, _maxIds) : list;
    await prefs.setStringList(_prefsKey, trimmed);
  }

  /// Resolves case id + title from a hearing map (matches Cloud Functions behavior closely).
  Future<({String id, String title})?> _resolveCase(
    Map<String, dynamic> d,
  ) async {
    final explicit = (d['caseId'] as String?)?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      final s = await _db.collection('cases').doc(explicit).get();
      if (s.exists) {
        final t = (s.data()?['caseTitle'] as String?)?.trim();
        return (
          id: explicit,
          title: (t != null && t.isNotEmpty) ? t : explicit,
        );
      }
    }

    final caseNo = (d['caseNo'] as String?)?.trim() ?? '';
    if (caseNo.isEmpty) return null;

    final variants = _caseNumberQueryVariants(caseNo);
    for (final field in [
      'caseNumber',
      'caseNo',
      'docketNumber',
      'criminalCaseNo',
    ]) {
      for (final v in variants) {
        try {
          final q = await _db
              .collection('cases')
              .where(field, isEqualTo: v)
              .limit(5)
              .get();
          if (q.docs.isNotEmpty) {
            final doc = q.docs.first;
            final t = (doc.data()['caseTitle'] as String?)?.trim();
            return (
              id: doc.id,
              title: (t != null && t.isNotEmpty) ? t : caseNo,
            );
          }
        } catch (_) {
          /* field or index */
        }
      }
    }

    final clientName = (d['clientName'] as String?)?.trim() ?? '';
    if (clientName.isNotEmpty) {
      final nameKeys = <String>{
        clientName,
        _normalizeCaseRefWhitespace(clientName),
      };
      try {
        for (final nm in nameKeys) {
          if (nm.isEmpty) continue;
          final uq = await _db
              .collection('users')
              .where('name', isEqualTo: nm)
              .limit(25)
              .get();
          for (final u in uq.docs) {
            if (((u.data()['role'] as String?) ?? '').toLowerCase() !=
                'client') {
              continue;
            }
            final cq = await _db
                .collection('cases')
                .where('clientId', isEqualTo: u.id)
                .limit(50)
                .get();
            for (final c in cq.docs) {
              final title = (c.data()['caseTitle'] as String?) ?? '';
              if (_textContainsCaseReference(title, caseNo)) {
                final t = title.trim();
                return (id: c.id, title: t.isNotEmpty ? t : caseNo);
              }
            }
          }
        }
      } catch (_) {}
    }

    try {
      final end = '$caseNo\uf8ff';
      final pq = await _db
          .collection('cases')
          .where('caseTitle', isGreaterThanOrEqualTo: caseNo)
          .where('caseTitle', isLessThanOrEqualTo: end)
          .limit(5)
          .get();
      if (pq.docs.isNotEmpty) {
        final doc = pq.docs.first;
        final t = (doc.data()['caseTitle'] as String?)?.trim();
        return (id: doc.id, title: (t != null && t.isNotEmpty) ? t : caseNo);
      }
    } catch (_) {}

    return null;
  }

  /// When `caseNumber` / client match fails, match [caseNo] against cases for the
  /// signed-in attorney (or staff's [assignedAttorneyId]) — common for imported hearings.
  Future<({String id, String title})?> _resolveCaseByListenerAttorney(
    Map<String, dynamic> d,
  ) async {
    final caseNo = (d['caseNo'] as String?)?.trim() ?? '';
    if (caseNo.isEmpty) return null;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final udoc = await _db.collection('users').doc(uid).get();
    if (!udoc.exists) return null;
    final ud = udoc.data()!;
    final role = (ud['role'] as String?)?.toLowerCase() ?? '';
    String? attorneyId;
    if (role == 'attorney') {
      attorneyId = uid;
    } else if (role == 'staff') {
      attorneyId = (ud['assignedAttorneyId'] as String?)?.trim();
    } else {
      return null;
    }
    if (attorneyId == null || attorneyId.isEmpty) return null;

    try {
      final q = await _db
          .collection('cases')
          .where('attorneyId', isEqualTo: attorneyId)
          .limit(500)
          .get();
      for (final cdoc in q.docs) {
        final m = cdoc.data();
        if (_caseMapMatchesHearing(m, caseNo, d)) {
          final t = (m['caseTitle'] as String?)?.trim();
          return (id: cdoc.id, title: (t != null && t.isNotEmpty) ? t : caseNo);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        _fanoutLog(
          'HearingNotificationFanout _resolveCaseByListenerAttorney: $e',
        );
      }
    }
    return null;
  }

  Future<Set<String>> _recipientsForCase(
    DocumentSnapshot<Map<String, dynamic>> caseDoc,
  ) async {
    final c = caseDoc.data();
    if (c == null) return {};
    final ids = <String>{};
    final clientId = c['clientId'] as String?;
    final attorneyId = c['attorneyId'] as String?;
    final staffId = c['staffId'] as String?;
    if (clientId != null && clientId.isNotEmpty) ids.add(clientId);
    if (attorneyId != null && attorneyId.isNotEmpty) ids.add(attorneyId);
    if (staffId != null && staffId.isNotEmpty) ids.add(staffId);
    final sa = c['staffAssigned'];
    if (sa is List) {
      for (final x in sa) {
        if (x is String && x.isNotEmpty) ids.add(x);
      }
    }
    final aid = (attorneyId ?? '').trim();
    if (aid.isNotEmpty) {
      try {
        final staffSnap = await _db
            .collection('users')
            .where('assignedAttorneyId', isEqualTo: aid)
            .limit(100)
            .get();
        for (final udoc in staffSnap.docs) {
          final r = (udoc.data()['role'] as String?)?.toLowerCase() ?? '';
          if (r == 'staff') {
            ids.add(udoc.id);
          }
        }
      } catch (_) {}
    }
    return ids;
  }

  Set<String> _extraUidsFromHearing(Map<String, dynamic> d) {
    final out = <String>{};
    void addUid(String? s) {
      final t = s?.trim();
      if (t != null && t.length > 8) out.add(t);
    }

    addUid(d['senderId'] as String?);
    addUid(d['uploadedBy'] as String?);
    addUid(d['createdBy'] as String?);
    addUid(d['handledBy'] as String?);
    addUid(d['staffUid'] as String?);
    addUid(d['attorneyUid'] as String?);
    final arr = d['notifyUserIds'];
    if (arr is List) {
      for (final x in arr) {
        if (x is String) addUid(x);
      }
    }
    return out;
  }

  static bool _isImportedCourtRow(Map<String, dynamic> d) {
    final cn = (d['caseNo'] as String?)?.trim() ?? '';
    final ft = (d['fullText'] as String?)?.trim() ?? '';
    return cn.isNotEmpty && ft.isNotEmpty;
  }

  Future<bool> _isStaffAccount(String uid) async {
    try {
      final u = await _db.collection('users').doc(uid).get();
      if (u.exists) {
        final data = u.data() ?? {};
        final role = (data['role'] as String?)?.toLowerCase().trim() ?? '';
        if (role == 'staff' ||
            role.contains('paralegal') ||
            role.contains('assistant')) {
          return data['isActive'] != false;
        }
      }
      if ((await _db.collection('staff').doc(uid).get()).exists) {
        return true;
      }
      final email =
          (u.data()?['email'] as String?)?.trim().toLowerCase() ?? '';
      if (email.isNotEmpty) {
        final appId = StaffApplicationService.applicationDocIdForEmail(email);
        if (appId.isNotEmpty) {
          final app = await _db
              .collection(StaffApplicationService.collectionName)
              .doc(appId)
              .get();
          if (app.exists) {
            final status =
                (app.data()?['status'] as String?)?.toLowerCase() ?? '';
            if (status == 'approved' || status == 'registered') return true;
          }
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Subset of [uids] whose Firestore `users` doc has `role == client`.
  Future<Set<String>> _clientUidsAmong(Set<String> uids) async {
    final out = <String>{};
    for (final uid in uids) {
      if (uid.isEmpty) continue;
      try {
        final snap = await _db.collection('users').doc(uid).get();
        if (!snap.exists) continue;
        if ((snap.data()?['role'] as String?)?.toLowerCase() == 'client') {
          out.add(uid);
        }
      } catch (_) {}
    }
    return out;
  }

  /// Values safe for Firestore `clientName ==` queries (must match profile field text).
  static Set<String> _clientNameFirestoreQueryVariants(Map<String, dynamic> ud) {
    final out = <String>{};
    for (final field in ['fullName', 'name', 'displayName']) {
      final v = (ud[field] as String?)?.trim();
      if (v == null || v.isEmpty) continue;
      final t = _normalizeCaseRefWhitespace(v);
      out.add(t);
      out.add(t.toLowerCase());
      out.add(t.toUpperCase());
      final titled = t
          .split(' ')
          .map((w) {
            if (w.isEmpty) return w;
            if (w.length == 1) return w.toUpperCase();
            return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
          })
          .join(' ');
      out.add(titled);
    }
    return out;
  }

  /// In-memory name variants (includes "Last, First" — do not use for Firestore queries).
  static List<String> _clientNameMatchVariants(String raw) {
    final t = _normalizeCaseRefWhitespace(raw);
    if (t.isEmpty) return const [];
    final out = <String>{t, t.toUpperCase(), t.toLowerCase()};
    final titled = t
        .split(' ')
        .map((w) {
          if (w.isEmpty) return w;
          if (w.length == 1) return w.toUpperCase();
          return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
        })
        .join(' ');
    out.add(titled);
    final parts = t.split(' ').where((w) => w.isNotEmpty).toList();
    if (parts.length >= 2) {
      final last = parts.last;
      final first = parts.sublist(0, parts.length - 1).join(' ');
      out.add('$last, $first');
      out.add('$last,$first');
      out.add('$last $first');
    }
    return out.where((e) => e.isNotEmpty).toList();
  }

  static bool _namesMatchForClient(String stored, String hearingClientName) {
    final a = _alnumLower(stored);
    final b = _alnumLower(hearingClientName);
    if (a.length < 3 || b.length < 3) return false;
    return a == b;
  }

  static bool _namesPartialMatchForClient(
    String stored,
    String hearingClientName,
  ) {
    if (_namesMatchForClient(stored, hearingClientName)) return true;
    final storedNorm = _normalizeCaseRefWhitespace(stored);
    final hearingNorm = _normalizeCaseRefWhitespace(hearingClientName);
    if (storedNorm.toLowerCase() == hearingNorm.toLowerCase()) return true;
    final words = hearingNorm
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toList();
    if (words.isEmpty) return false;
    final storedLower = storedNorm.toLowerCase();
    if (words.length == 1) return storedLower.contains(words.first);
    return words.every(storedLower.contains);
  }

  /// Resolve client user IDs from [d]['clientName'] (exact + scan fallback).
  Future<Set<String>> _resolveClientUidsFromHearingName(
    Map<String, dynamic> d,
  ) async {
    final clientName = (d['clientName'] as String?)?.trim() ?? '';
    if (clientName.isEmpty) return {};

    final matched = <String>{};
    final nameKeys = _clientNameMatchVariants(clientName);

    for (final field in ['fullName', 'name', 'displayName']) {
      for (final nm in nameKeys) {
        try {
          final uq = await _db
              .collection('users')
              .where(field, isEqualTo: nm)
              .limit(15)
              .get();
          for (final u in uq.docs) {
            final role = (u.data()['role'] as String?)?.toLowerCase() ?? '';
            if (role != 'client') continue;
            matched.add(u.id);
          }
        } catch (_) {}
      }
    }

    if (matched.isEmpty) {
      try {
        final cq = await _db
            .collection('users')
            .where('role', isEqualTo: 'client')
            .limit(250)
            .get();
        for (final u in cq.docs) {
          final data = u.data();
          for (final field in ['fullName', 'name', 'displayName']) {
            final stored = (data[field] as String?)?.trim() ?? '';
            if (stored.isNotEmpty &&
                _namesPartialMatchForClient(stored, clientName)) {
              matched.add(u.id);
              break;
            }
          }
        }
      } catch (_) {}
    }

    return matched;
  }

  /// Match `hearings.clientName` to registered clients (always, not only when staff list is empty).
  Future<void> _addClientsByNameFromHearing(
    Set<String> recipients,
    Map<String, dynamic> d,
  ) async {
    final matched = await _resolveClientUidsFromHearingName(d);

    for (final uid in matched) {
      recipients.add(uid);
      try {
        final u = await _db.collection('users').doc(uid).get();
        final att = (u.data()?['assignedAttorneyId'] as String?)?.trim();
        if (att != null && att.isNotEmpty) {
          recipients.add(att);
          final staffSnap = await _db
              .collection('users')
              .where('assignedAttorneyId', isEqualTo: att)
              .where('role', isEqualTo: 'staff')
              .limit(50)
              .get();
          for (final s in staffSnap.docs) {
            recipients.add(s.id);
          }
        }
      } catch (_) {}
    }
  }

  /// When OCR/import rows have no matching `cases` doc, still notify firm users.
  Future<void> _addRecipientsForUnmatchedImport(
    Set<String> recipients,
    Map<String, dynamic> d,
  ) async {
    if (!_isImportedCourtRow(d)) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) recipients.add(uid);

    await _addClientsByNameFromHearing(recipients, d);

    for (final role in ['attorney', 'staff', 'admin']) {
      try {
        final q = await _db
            .collection('users')
            .where('role', isEqualTo: role)
            .limit(80)
            .get();
        for (final doc in q.docs) {
          recipients.add(doc.id);
        }
      } catch (_) {}
    }
  }

  /// Every active staff user gets court hearing alerts (same as attorneys).
  Future<void> _addAllActiveStaff(Set<String> recipients) async {
    try {
      final q = await _db
          .collection('users')
          .where('role', isEqualTo: 'staff')
          .limit(100)
          .get();
      for (final doc in q.docs) {
        if (doc.data()['isActive'] == false) continue;
        recipients.add(doc.id);
      }
    } catch (e) {
      if (kDebugMode) _fanoutLog('HearingNotificationFanout._addAllActiveStaff: $e');
    }
    try {
      final legacy = await _db.collection('staff').limit(100).get();
      for (final doc in legacy.docs) {
        recipients.add(doc.id);
      }
    } catch (_) {}
  }

  /// Writes resolved caption to notification docs; removes stale placeholders.
  void _applyResolvedCaseTitleOnPayload(
    Map<String, dynamic> payload,
    Map<String, dynamic> prepared,
  ) {
    final title = HearingCalendarFields.fieldAsDisplayString(
      prepared,
      'caseTitle',
    );
    if (title.isNotEmpty &&
        !HearingCalendarFields.isLowQualityCaseTitle(title)) {
      payload['caseTitle'] = title;
    } else {
      payload['caseTitle'] = FieldValue.delete();
    }
  }

  String _caseLabelForDisplay(
    Map<String, dynamic> d, {
    List<Map<String, dynamic>> caseMaps = const [],
  }) {
    final direct = (d['caseTitle'] as String?)?.trim() ?? '';
    if (direct.isNotEmpty &&
        !HearingCalendarFields.isLowQualityCaseTitle(direct)) {
      return direct;
    }
    final prepared = HearingCalendarFields.prepareForNotificationDisplay(
      d,
      caseMaps: caseMaps,
    );
    final title = HearingCalendarFields.fieldAsDisplayString(
      prepared,
      'caseTitle',
    );
    if (title.isNotEmpty &&
        !HearingCalendarFields.isLowQualityCaseTitle(title)) {
      return title;
    }
    return (prepared['caseNo'] as String?)?.trim() ?? 'Hearing';
  }

  /// Display helpers for reminders UI (raw `hearings` docs).
  String inboxTitleFromHearing(Map<String, dynamic> d) {
    final prepared = HearingCalendarFields.prepareForNotificationDisplay(d);
    return _buildTitle(prepared, _caseLabelForDisplay(prepared));
  }

  String inboxSummaryFromHearing(Map<String, dynamic> d) =>
      _buildSummary(d, _caseLabelForDisplay(d));

  String inboxBodyFromHearing(Map<String, dynamic> d) =>
      _buildBody(d, (id: 'hearing', title: _caseLabelForDisplay(d)));

  static bool isDisplayableHearingRow(Map<String, dynamic> d) {
    final cn = (d['caseNo'] as String?)?.trim() ?? '';
    final ft = (d['fullText'] as String?)?.trim() ?? '';
    final msg = (d['message'] as String?)?.trim() ?? '';
    final summary = (d['summary'] as String?)?.trim() ?? '';
    final caseId = (d['caseId'] as String?)?.trim() ?? '';
    final activity = (d['activityType'] as String?)?.trim() ?? '';
    // Show court imports with case number and/or any body text (OCR may omit fullText).
    return caseId.isNotEmpty ||
        cn.isNotEmpty ||
        ft.isNotEmpty ||
        msg.isNotEmpty ||
        summary.isNotEmpty ||
        activity.isNotEmpty;
  }

  /// Merges recent notifications + explicit hearing-type queries (appointments used to fill the 200 cap).
  /// Never throws — hearings fallback still renders when notification queries are denied.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _notificationDocsForInbox(String userId, {bool hearingsOnly = false}) async {
    final seen = <String>{};
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    if (!await _waitForInboxAuth(userId)) {
      return docs;
    }

    void addDocs(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> add) {
      for (final d in add) {
        if (clientCourtEmailSpamNotification(d.data())) continue;
        if (seen.add(d.id)) docs.add(d);
      }
    }

    try {
      final userNotifFuture = _db
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .limit(300)
          .get();
      final isStaffFuture = _isStaffAccount(userId);
      final recent = await userNotifFuture;
      addDocs(recent.docs);
      final isStaff = await isStaffFuture;
      if (!isStaff) {
        try {
          final byClientId = await _db
              .collection('notifications')
              .where('clientId', isEqualTo: userId)
              .limit(300)
              .get();
          addDocs(byClientId.docs);
        } catch (e) {
          if (kDebugMode) _fanoutLog('inbox notifications clientId: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) _fanoutLog('inbox notifications userId: $e');
    }

    final typesToQuery = hearingsOnly
        ? _inboxHearingNotificationTypes
        : [
            ..._inboxHearingNotificationTypes,
            ..._inboxAppointmentNotificationTypes,
          ];
    final typeSnaps = await Future.wait(
      typesToQuery.map((type) async {
        try {
          return await _db
              .collection('notifications')
              .where('userId', isEqualTo: userId)
              .where('type', isEqualTo: type)
              .limit(100)
              .get();
        } catch (e) {
          if (kDebugMode) _fanoutLog('inbox notifications type=$type: $e');
          return null;
        }
      }),
    );
    for (final snap in typeSnaps) {
      if (snap != null) addDocs(snap.docs);
    }

    return docs;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _hearingsInboxStream() {
    return _db.collection('hearings').limit(100).snapshots();
  }

  Future<QuerySnapshot<Map<String, dynamic>>?>
  _hearingsSnapshotForInbox({String? forUserId}) async {
    final uid = forUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty || !await _canUseGlobalHearingsInbox(uid)) {
      return null;
    }
    try {
      return await _db.collection('hearings').limit(100).get();
    } catch (e) {
      if (kDebugMode) _fanoutLog('inbox hearings snapshot: $e');
      return null;
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _userNotificationsInboxStream(
    String userId,
  ) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .limit(200)
        .snapshots();
  }

  /// Client bell/reminders title (not generic email-ingest "New court notice").
  static String clientInboxTitleFromHearing(Map<String, dynamic> d) {
    final cn = (d['caseNo'] as String?)?.trim() ?? '';
    final hid = (d['hearingDocId'] as String?)?.trim() ?? '';
    if (_isImportedCourtRow(d) || cn.isNotEmpty || hid.isNotEmpty) {
      return cn.isNotEmpty
          ? 'New notice court hearings — $cn'
          : 'New notice court hearings';
    }
    final label = (d['caseTitle'] as String?)?.trim() ?? 'Hearing';
    return 'New notice court hearings — $label';
  }

  /// Subtitle for client hearing cards when only `notifications` fields exist.
  static String clientSummaryFromNotificationMap(Map<String, dynamic> d) {
    final existing = (d['summary'] as String?)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;

    final parts = <String>[];
    final cl = (d['clientName'] as String?)?.trim();
    final br = (d['courtBranch'] as String?)?.trim();
    final cn = (d['caseNo'] as String?)?.trim();
    if (cl != null && cl.isNotEmpty) parts.add(cl);
    if (br != null && br.isNotEmpty) parts.add(br);
    if (cn != null && cn.isNotEmpty) parts.add('Case: $cn');
    if (parts.isNotEmpty) return parts.join(' • ');
    return 'Court hearing order';
  }

  String _buildTitle(Map<String, dynamic> d, String caseLabel) {
    if (_isImportedCourtRow(d)) {
      final cn = (d['caseNo'] as String?)?.trim() ?? '';
      return cn.isNotEmpty
          ? 'Court hearing / order — $cn'
          : 'Court hearing / order — $caseLabel';
    }
    final act = (d['activityType'] as String?)?.trim() ?? 'message';
    if (act == 'schedule') return 'Hearing scheduled — $caseLabel';
    if (act == 'update') return 'Hearing updated — $caseLabel';
    return 'Hearing message — $caseLabel';
  }

  /// Short line for notification list rows.
  String _buildSummary(Map<String, dynamic> d, String caseLabel) {
    final line = HearingNotificationFormatter.buildSummary(d);
    if (line.isNotEmpty &&
        line != 'Court hearing notice' &&
        line != caseLabel) {
      return line;
    }
    return caseLabel;
  }

  String _buildBody(
    Map<String, dynamic> d,
    ({String id, String title}) resolved,
  ) {
    final merged = Map<String, dynamic>.from(d);
    if ((merged['caseTitle'] as String?)?.trim().isEmpty != false &&
        resolved.title.isNotEmpty) {
      merged['caseTitle'] = resolved.title;
    }
    return HearingNotificationFormatter.buildBody(merged);
  }

  bool hearingDocMatchesClientProfile(
    Map<String, dynamic> hearingData,
    Map<String, dynamic> userData,
  ) {
    final hearingClient = (hearingData['clientName'] as String?)?.trim() ?? '';
    if (hearingClient.isEmpty) return false;
    for (final field in ['fullName', 'name', 'displayName']) {
      final stored = (userData[field] as String?)?.trim() ?? '';
      if (stored.isNotEmpty &&
          _namesPartialMatchForClient(stored, hearingClient)) {
        return true;
      }
    }
    return false;
  }

  /// Whether [uid] (client) is named on or linked to this hearing row.
  Future<bool> hearingInvolvesClientUser(
    String uid,
    Map<String, dynamic> d,
  ) async {
    try {
      final udoc = await _db.collection('users').doc(uid).get();
      if (!udoc.exists) return false;
      final ud = udoc.data() ?? {};
      if ((ud['role'] as String?)?.toLowerCase() != 'client') return false;

      if (hearingDocMatchesClientProfile(d, ud)) return true;

      if ((d['ownerClientId'] as String?)?.trim() == uid) return true;

      final involved = d['involvedClientIds'];
      if (involved is List && involved.contains(uid)) return true;

      final matched = d['matchedClientIds'];
      if (matched is List && matched.contains(uid)) return true;

      final caseId = (d['caseId'] as String?)?.trim() ?? '';
      if (caseId.isNotEmpty) {
        try {
          final caseSnap = await _db.collection('cases').doc(caseId).get();
          if (caseSnap.exists && caseSnap.data()?['clientId'] == uid) {
            return true;
          }
        } catch (_) {}
      }

      final hearingClient = (d['clientName'] as String?)?.trim() ?? '';
      if (hearingClient.isNotEmpty) {
        for (final field in ['fullName', 'name', 'displayName']) {
          final stored = (ud[field] as String?)?.trim() ?? '';
          if (stored.isNotEmpty &&
              _namesPartialMatchForClient(stored, hearingClient)) {
            return true;
          }
        }
      }

      var resolved = await _resolveCase(d);
      if (resolved != null) {
        final caseSnap = await _db.collection('cases').doc(resolved.id).get();
        if (caseSnap.exists && caseSnap.data()?['clientId'] == uid) {
          return true;
        }
      }

      final caseNo = (d['caseNo'] as String?)?.trim() ?? '';
      if (caseNo.isNotEmpty) {
        final cq = await _db
            .collection('cases')
            .where('clientId', isEqualTo: uid)
            .limit(50)
            .get();
        for (final c in cq.docs) {
          if (_caseMapMatchesHearing(c.data(), caseNo, d)) return true;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        _fanoutLog('hearingInvolvesClientUser: $e');
      }
    }
    return false;
  }

  static bool _isWrongClientCourtNoticeTitle(String title) {
    final t = title.toLowerCase().trim();
    if (t.isEmpty) return false;
    return t == 'new court notice' ||
        (t.startsWith('new court notice') && !t.contains('court hearings'));
  }

  /// Wrong rows for clients (email queue / "New court notice"), not court hearing orders.
  static bool shouldRemoveClientNotification(Map<String, dynamic> data) {
    final title = (data['title'] as String? ?? '').toLowerCase().trim();
    final type = (data['type'] as String? ?? '').toLowerCase();
    final hid = (data['hearingDocId'] as String?)?.trim() ?? '';

    // Real court hearing rows (with hearing doc link) — repair title, do not delete.
    if (hid.isNotEmpty &&
        (type == 'hearing_activity' || type == 'hearing_activity_update')) {
      return false;
    }

    if (clientCourtEmailSpamNotification(data)) return true;

    if (_isWrongClientCourtNoticeTitle(title)) return true;

    // hearing_activity noise without a linked hearing doc.
    if ((type == 'hearing_activity' || type == 'hearing_activity_update') &&
        hid.isEmpty) {
      return true;
    }

    if (type == 'hearing_activity' || type == 'hearing_activity_update') {
      return false;
    }
    if (hid.isNotEmpty) return false;

    return title.contains('court email (review)') ||
        title.contains('hearing / court date detected') ||
        type == 'court_email_ingest' ||
        (type.startsWith('court_') && !type.contains('hearing'));
  }

  static bool _clientHearingTitleNeedsRepair(
    String title,
    Map<String, dynamic> hearingData,
  ) {
    final t = title.toLowerCase().trim();
    final expected = clientInboxTitleFromHearing(hearingData).toLowerCase();
    if (t != expected) return true;
    return t == 'new court notice' ||
        (t.startsWith('new court notice') && !t.contains('court hearings'));
  }

  Future<void> _writeClientHearingNotificationPayload(
    String uid,
    String hearingDocId,
    Map<String, dynamic> d, {
    required bool docExists,
    required bool wasRead,
  }) async {
    final nid = 'hearing_inapp_${hearingDocId}_$uid';
    final caseMaps = await HearingCalendarFields.loadCaseMapsForHearing(d);
    final prepared = HearingCalendarFields.prepareForNotificationDisplay(
      d,
      caseMaps: caseMaps,
    );
    var body = inboxBodyFromHearing(prepared);
    if (body.trim().isEmpty) body = inboxSummaryFromHearing(prepared);
    if (body.trim().isEmpty) {
      body =
          'Court hearing notice for ${(prepared['caseNo'] as String?)?.trim().isNotEmpty == true ? (prepared['caseNo'] as String).trim() : 'your case'}.';
    }

    final payload = <String, dynamic>{
      'userId': uid,
      'clientId': uid,
      'type': 'hearing_activity',
      'title': clientInboxTitleFromHearing(prepared),
      'summary': clientSummaryFromNotificationMap({
        ...prepared,
        'summary': inboxSummaryFromHearing(prepared),
      }),
      'message': body,
      'hearingDocId': hearingDocId,
      ...HearingNotificationFormatter.copyHearingFieldsForNotification(
        prepared,
        caseMaps: caseMaps,
      ),
      if ((d['caseId'] as String?)?.trim().isNotEmpty == true)
        'caseId': (d['caseId'] as String).trim(),
    };
    if (wasRead) {
      payload['isRead'] = true;
    } else if (!docExists) {
      payload['isRead'] = false;
      payload['createdAt'] = Timestamp.now();
    }

    await _db.collection('notifications').doc(nid).set(
      payload,
      SetOptions(merge: true),
    );
  }

  /// Deletes wrong email-ingest / "New court notice" spam (not real court hearings).
  Future<int> purgeClientCourtEmailNotices(String uid) async {
    var deleted = 0;
    try {
      final seen = <String>{};
      final toDelete = <DocumentReference<Map<String, dynamic>>>[];
      final snaps = await Future.wait([
        _db.collection('notifications').where('userId', isEqualTo: uid).limit(400).get(),
        _db.collection('notifications').where('clientId', isEqualTo: uid).limit(400).get(),
      ]);
      for (final snap in snaps) {
        for (final doc in snap.docs) {
          if (!seen.add(doc.id)) continue;
          if (!shouldRemoveClientNotification(doc.data())) continue;
          toDelete.add(doc.reference);
        }
      }
      for (var i = 0; i < toDelete.length; i += 450) {
        final batch = _db.batch();
        final chunk = toDelete.skip(i).take(450);
        for (final ref in chunk) {
          batch.delete(ref);
          deleted++;
        }
        await batch.commit();
      }
    } catch (e) {
      if (kDebugMode) _fanoutLog('purgeClientCourtEmailNotices: $e');
    }
    return deleted;
  }

  @Deprecated('Use purgeClientCourtEmailNotices')
  Future<void> removeClientCourtEmailNotices(String uid) async {
    await purgeClientCourtEmailNotices(uid);
  }

  /// Writes/updates the client hearing row directly (stable doc id, attorney-style body).
  Future<void> ensureClientHearingNotification(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    bool trustClientNameMatch = false,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !doc.exists) return;
    final d = doc.data();
    if (d == null) return;

    if (!trustClientNameMatch && !await hearingInvolvesClientUser(uid, d)) {
      return;
    }

    final nid = 'hearing_inapp_${doc.id}_$uid';
    final existing = await _db.collection('notifications').doc(nid).get();
    final wasRead =
        existing.exists && _notificationWasRead(existing.data());

    if (existing.exists) {
      final ex = existing.data() ?? {};
      if (shouldRemoveClientNotification(ex) ||
          !clientHearingInboxType((ex['type'] as String? ?? '').toLowerCase())) {
        try {
          await existing.reference.delete();
        } catch (_) {}
      } else {
        final exTitle = (ex['title'] as String?)?.trim() ?? '';
        if (!_clientHearingTitleNeedsRepair(exTitle, d)) {
          return;
        }
        // Fall through to rewrite title/body (e.g. old "New court notice" rows).
      }
    }

    try {
      await _writeClientHearingNotificationPayload(
        uid,
        doc.id,
        d,
        docExists: existing.exists,
        wasRead: wasRead,
      );
      final caseId = await _caseIdForClientOnHearing(uid, d);
      await _linkHearingToClients(
        doc.reference,
        {uid},
        caseId: caseId,
        firmMaySetCaseId: caseId != null,
      );
    } catch (e) {
      if (kDebugMode) _fanoutLog('ensureClientHearingNotification: $e');
    }
  }

  /// Server backfill when client cannot read imported `hearings` rows directly.
  Future<void> _syncClientHearingsViaCloudFunction() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final fn = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable(
        'syncClientHearingInbox',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
      );
      final result = await fn.call();
      if (kDebugMode) {
        _fanoutLog('syncClientHearingInbox CF: ${result.data}');
      }
      _refreshInboxStreamsForUser(uid);
    } on FirebaseFunctionsException catch (e) {
      // not-found = function not deployed; client-side sync still runs.
      if (kDebugMode &&
          e.code != 'not-found' &&
          e.code != 'unavailable' &&
          e.code != 'deadline-exceeded') {
        _fanoutLog(
          'syncClientHearingInbox CF (${e.code}): ${e.message ?? e}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        _fanoutLog('syncClientHearingInbox CF failed: $e');
      }
    }
  }

  /// Client app: find hearings by profile name and create in-app notification rows.
  Future<void> syncClientHearingNotifications({bool force = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (!force) {
      final last = _lastClientSyncAt[uid];
      if (last != null &&
          DateTime.now().difference(last) < _clientSyncMinInterval) {
        return;
      }
    }
    _lastClientSyncAt[uid] = DateTime.now();

    try {
      final roleSnap = await _db.collection('users').doc(uid).get();
      final ud = roleSnap.data();
      if (ud == null) return;
      if ((ud['role'] as String?)?.toLowerCase() != 'client') return;

      await purgeClientCourtEmailNotices(uid);
      await _syncClientHearingsViaCloudFunction();

      final seenHearingIds = <String>{};

      await _syncClientHearingsFromNotificationRefs(uid, seenHearingIds);

      try {
        final owned = await _db
            .collection('hearings')
            .where('ownerClientId', isEqualTo: uid)
            .limit(40)
            .get();
        for (final doc in owned.docs) {
          if (seenHearingIds.add(doc.id)) {
            await ensureClientHearingNotification(
              doc,
              trustClientNameMatch: true,
            );
          }
        }
      } catch (e) {
        if (kDebugMode) _fanoutLog('syncClientHearings ownerClientId: $e');
      }

      // Hearings already linked to this client (Cloud Functions / staff fan-out).
      try {
        final linked = await _db
            .collection('hearings')
            .where('involvedClientIds', arrayContains: uid)
            .limit(40)
            .get();
        for (final doc in linked.docs) {
          if (seenHearingIds.add(doc.id)) {
            await ensureClientHearingNotification(
              doc,
              trustClientNameMatch: true,
            );
          }
        }
      } catch (e) {
        if (kDebugMode) {
          _fanoutLog('syncClientHearings involvedClientIds: $e');
        }
      }

      try {
        final matched = await _db
            .collection('hearings')
            .where('matchedClientIds', arrayContains: uid)
            .limit(40)
            .get();
        for (final doc in matched.docs) {
          if (seenHearingIds.add(doc.id)) {
            await ensureClientHearingNotification(
              doc,
              trustClientNameMatch: true,
            );
          }
        }
      } catch (e) {
        if (kDebugMode) _fanoutLog('syncClientHearings matchedClientIds: $e');
      }

      // Firestore-secure: only query clientName values copied from the profile (not "Last, First").
      for (final nm in _clientNameFirestoreQueryVariants(ud)) {
        try {
          final q = await _db
              .collection('hearings')
              .where('clientName', isEqualTo: nm)
              .limit(40)
              .get();
          for (final doc in q.docs) {
            if (seenHearingIds.add(doc.id)) {
              await ensureClientHearingNotification(
                doc,
                trustClientNameMatch: true,
              );
            }
          }
        } catch (e) {
          if (kDebugMode) {
            _fanoutLog('syncClientHearings clientName=$nm: $e');
          }
        }
      }

      // Hearings linked to this client's cases (caseId + case number).
      try {
        final cases = await _db
            .collection('cases')
            .where('clientId', isEqualTo: uid)
            .limit(30)
            .get();
        for (final c in cases.docs) {
          try {
            final byCaseId = await _db
                .collection('hearings')
                .where('caseId', isEqualTo: c.id)
                .limit(30)
                .get();
            for (final h in byCaseId.docs) {
              if (seenHearingIds.add(h.id)) {
                await _linkHearingToClients(
                  h.reference,
                  {uid},
                  caseId: c.id,
                  firmMaySetCaseId: true,
                );
                await ensureClientHearingNotification(
                  h,
                  trustClientNameMatch: true,
                );
              }
            }
          } catch (_) {}

          final m = c.data();
          for (final field in [
            'caseNumber',
            'caseNo',
            'docketNumber',
            'criminalCaseNo',
          ]) {
            final cn = (m[field] as String?)?.trim() ?? '';
            if (cn.isEmpty) continue;
            try {
              final hq = await _db
                  .collection('hearings')
                  .where('caseNo', isEqualTo: cn)
                  .limit(15)
                  .get();
              for (final h in hq.docs) {
                if (seenHearingIds.add(h.id)) {
                  await ensureClientHearingNotification(
                    h,
                    trustClientNameMatch: true,
                  );
                }
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        if (kDebugMode) _fanoutLog('syncClientHearings by case: $e');
      }

      // Backfill: notifications already written by Cloud Functions / staff.
      for (final type in _inboxHearingNotificationTypes) {
        try {
          final q = await _db
              .collection('notifications')
              .where('userId', isEqualTo: uid)
              .where('type', isEqualTo: type)
              .limit(50)
              .get();
          for (final n in q.docs) {
            final hid = _hearingIdFromNotificationDoc(n.id, n.data());
            if (hid == null || !seenHearingIds.add(hid)) continue;
            final hDoc = await _db.collection('hearings').doc(hid).get();
            if (hDoc.exists) {
              await ensureClientHearingNotification(hDoc);
            }
          }
        } catch (_) {}
      }

      await _normalizeClientHearingNotificationRows(uid);
    } catch (e) {
      if (kDebugMode) {
        _fanoutLog(
          'HearingNotificationFanout.syncClientHearingNotifications: $e',
        );
      }
    }
    _refreshInboxStreamsForUser(uid);
  }

  /// Pull hearing docs referenced on any notification row for this client (get-by-id).
  Future<void> _syncClientHearingsFromNotificationRefs(
    String uid,
    Set<String> seenHearingIds,
  ) async {
    try {
      final seenNotifIds = <String>{};
      final snaps = await Future.wait([
        _db.collection('notifications').where('userId', isEqualTo: uid).limit(300).get(),
        _db.collection('notifications').where('clientId', isEqualTo: uid).limit(300).get(),
      ]);
      for (final snap in snaps) {
        for (final n in snap.docs) {
          if (!seenNotifIds.add(n.id)) continue;
          final hid = _hearingIdFromNotificationDoc(n.id, n.data());
          if (hid == null || !seenHearingIds.add(hid)) continue;
          try {
            final hDoc = await _db.collection('hearings').doc(hid).get();
            if (hDoc.exists) {
              await ensureClientHearingNotification(
                hDoc,
                trustClientNameMatch: true,
              );
            }
          } catch (e) {
            if (kDebugMode) {
              _fanoutLog('syncClientHearingsFromNotificationRefs $hid: $e');
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        _fanoutLog('_syncClientHearingsFromNotificationRefs: $e');
      }
    }
  }

  /// Fixes titles and removes wrong spam; re-links rows to real hearing docs.
  Future<void> _normalizeClientHearingNotificationRows(String uid) async {
    try {
      final snaps = await Future.wait([
        _db.collection('notifications').where('userId', isEqualTo: uid).limit(400).get(),
        _db.collection('notifications').where('clientId', isEqualTo: uid).limit(400).get(),
      ]);
      final seen = <String>{};
      for (final snap in snaps) {
        for (final doc in snap.docs) {
          if (!seen.add(doc.id)) continue;
          final data = doc.data();
          if (shouldRemoveClientNotification(data)) {
            try {
              await doc.reference.delete();
            } catch (_) {}
            continue;
          }
          final type = (data['type'] as String? ?? '').toLowerCase();
          if (!clientHearingInboxType(type)) continue;
          final hid = _hearingIdFromNotificationDoc(doc.id, data);
          if (hid == null) continue;
          try {
            final hDoc = await _db.collection('hearings').doc(hid).get();
            if (hDoc.exists) {
              await ensureClientHearingNotification(
                hDoc,
                trustClientNameMatch: true,
              );
              continue;
            }
          } catch (_) {}
          await _writeClientHearingNotificationPayload(
            uid,
            hid,
            {
              'caseNo': data['caseNo'],
              'clientName': data['clientName'],
              'courtBranch': data['courtBranch'],
              'fullText': data['message'],
            },
            docExists: true,
            wasRead: _notificationWasRead(data),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) _fanoutLog('_normalizeClientHearingNotificationRows: $e');
    }
  }

  /// Fan out in-app notifications for one hearing document.
  Future<void> processDocumentIfNeeded(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    bool clientScoped = false,
    bool ignoreProcessedDigest = false,
  }) async {
    if (!doc.exists || doc.id.isEmpty) return;
    final digest = _fanoutDigest(doc);
    final d = doc.data();
    if (d == null) return;

    if (!clientScoped) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || !await _canRunFirmWideFanout(uid)) return;
    }

    String digestKey = digest;
    String? clientScopedUid;
    if (clientScoped) {
      clientScopedUid = FirebaseAuth.instance.currentUser?.uid;
      if (clientScopedUid == null) return;
      digestKey = '${digest}_client_$clientScopedUid';
      final nid = 'hearing_inapp_${doc.id}_$clientScopedUid';
      final existing = await _db.collection('notifications').doc(nid).get();
      if (existing.exists) {
        final data = existing.data() ?? {};
        final currentTitle = (data['title'] as String?)?.trim() ?? '';
        final needsTitleFix = _clientHearingTitleNeedsRepair(currentTitle, d);
        final wrongType = !clientHearingInboxType(
          (data['type'] as String? ?? '').toLowerCase(),
        );
        if (!needsTitleFix &&
            !wrongType &&
            await _alreadyProcessed(digestKey)) {
          return;
        }
      } else if (await _alreadyProcessed(digestKey)) {
        /* notification row missing — create it */
      }
    }
    final skipInAppWrites = !clientScoped &&
        !ignoreProcessedDigest &&
        await _alreadyProcessed(digestKey);

    final recipients = <String>{};
    var resolved = await _resolveCase(d);

    if (clientScoped) {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      if (!await hearingInvolvesClientUser(uid, d)) return;
      recipients.add(uid);
    } else {
      recipients.addAll(_extraUidsFromHearing(d));
      resolved ??= await _resolveCaseByListenerAttorney(d);

      if (resolved != null) {
        final caseSnap = await _db.collection('cases').doc(resolved.id).get();
        if (caseSnap.exists) {
          recipients.addAll(await _recipientsForCase(caseSnap));
        }
      }

      await _addClientsByNameFromHearing(recipients, d);

      if (recipients.isEmpty) {
        await _addRecipientsForUnmatchedImport(recipients, d);
      }

      if (isDisplayableHearingRow(d)) {
        await _addAllActiveStaff(recipients);
      }
    }

    if (recipients.isEmpty) {
      if (kDebugMode) {
        _fanoutLog(
          'HearingNotificationFanout: no recipients for ${doc.id} (add caseNumber on case or notifyUserIds)',
        );
      }
      return;
    }

    final recipientList = recipients.toList();

    final caseMaps = await HearingCalendarFields.loadCaseMapsForHearing(d);
    if (resolved != null) {
      final rid = resolved.id;
      if (caseMaps.every((c) => (c['id'] as String?) != rid)) {
        caseMaps.add({
          'id': rid,
          'caseTitle': resolved.title,
          if ((d['caseNo'] as String?)?.trim().isNotEmpty == true)
            'caseNo': (d['caseNo'] as String?)!.trim(),
        });
      }
    }
    final prepared = HearingCalendarFields.prepareForNotificationDisplay(
      d,
      caseMaps: caseMaps,
    );
    final caseLabel = _caseLabelForDisplay(prepared, caseMaps: caseMaps);
    final caseId = resolved?.id ?? (d['caseId'] as String?)?.trim() ?? '';

    final title = clientScoped
        ? clientInboxTitleFromHearing(prepared)
        : _buildTitle(prepared, caseLabel);
    final resolvedForBody = resolved ?? (id: doc.id, title: caseLabel);
    final body = _buildBody(d, resolvedForBody);
    final summary = _buildSummary(d, caseLabel);

    final type = 'hearing_activity';

    if (skipInAppWrites) {
      await HearingSmsAlertService.instance.sendAlertsForHearing(
        hearingDocId: doc.id,
        hearingData: d,
        recipientUserIds: recipientList,
        title: title,
        body: body,
        summary: summary,
        caseLabel: caseLabel,
      );
      return;
    }

    final clientRecipientUids = await _clientUidsAmong(recipients);

    final existingByUid =
        <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final uid in recipients) {
      final nid = 'hearing_inapp_${doc.id}_$uid';
      try {
        existingByUid[uid] =
            await _db.collection('notifications').doc(nid).get();
      } catch (_) {}
    }

    Map<String, dynamic> payloadFor(String uid) {
      final isClientRecipient = clientRecipientUids.contains(uid);
      final rowTitle =
          isClientRecipient ? clientInboxTitleFromHearing(d) : title;
      final existing = existingByUid[uid];
      final docExists = existing?.exists == true;
      final wasRead = docExists && _notificationWasRead(existing?.data());

      final payload = <String, dynamic>{
        'userId': uid,
        if (isClientRecipient) 'clientId': uid,
        'type': type,
        'title': rowTitle,
        'summary': summary,
        'message': body,
        if (caseId.isNotEmpty) 'caseId': caseId,
        'hearingDocId': doc.id,
        ...HearingNotificationFormatter.copyHearingFieldsForNotification(
          prepared,
          caseMaps: caseMaps,
        ),
      };
      _applyResolvedCaseTitleOnPayload(payload, prepared);
      if (wasRead) {
        payload['isRead'] = true;
      } else if (!docExists) {
        payload['isRead'] = false;
        payload['createdAt'] = Timestamp.now();
      }
      return payload;
    }

    var wroteAny = false;
    for (var i = 0; i < recipientList.length; i += 400) {
      final chunk = recipientList.skip(i).take(400);
      final batch = _db.batch();
      for (final uid in chunk) {
        final nid = 'hearing_inapp_${doc.id}_$uid';
        batch.set(
          _db.collection('notifications').doc(nid),
          payloadFor(uid),
          SetOptions(merge: true),
        );
      }
      try {
        await batch.commit();
        wroteAny = true;
      } catch (e) {
        if (_isPermissionDenied(e)) {
          if (kDebugMode) {
            _fanoutLog(
              'HearingNotificationFanout: batch permission-denied; '
              'will still attempt PhilSMS.',
            );
          }
        } else {
          if (kDebugMode) {
            _fanoutLog('HearingNotificationFanout batch commit failed: $e');
          }
          for (final uid in chunk) {
            try {
              final nid = 'hearing_inapp_${doc.id}_$uid';
              await _db
                  .collection('notifications')
                  .doc(nid)
                  .set(payloadFor(uid), SetOptions(merge: true));
              wroteAny = true;
            } catch (inner) {
              if (_isPermissionDenied(inner)) continue;
              if (kDebugMode) {
                _fanoutLog(
                  'HearingNotificationFanout write failed for $uid: $inner',
                );
              }
            }
          }
        }
      }
    }
    if (wroteAny) {
      await _markProcessed(digestKey);
    } else if (kDebugMode) {
      _fanoutLog(
        'HearingNotificationFanout: in-app writes failed for ${doc.id}; '
        'still attempting PhilSMS.',
      );
    }

    await HearingSmsAlertService.instance.sendAlertsForHearing(
      hearingDocId: doc.id,
      hearingData: d,
      recipientUserIds: recipientList,
      title: title,
      body: body,
      summary: summary,
      caseLabel: caseLabel,
    );

    if (!wroteAny) return;

    if (!clientScoped) {
      try {
        await doc.reference.update({
          'clientFanoutComplete': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        /* Sender-only updates on some rows — prefs dedupe still applies */
      }
      final involved = await _resolveClientUidsFromHearingName(d);
      final allClients = <String>{...involved, ...clientRecipientUids};
      if (allClients.isNotEmpty) {
        await _linkHearingToClients(
          doc.reference,
          allClients,
          caseId: caseId,
          firmMaySetCaseId: true,
        );
      }
    } else {
      final scopedUid = clientScopedUid;
      if (scopedUid == null) return;
      await _linkHearingToClients(
        doc.reference,
        {scopedUid},
        caseId: caseId,
      );
    }
  }

  static String? _hearingIdFromNotificationDoc(
    String docId,
    Map<String, dynamic> data,
  ) {
    final hid = (data['hearingDocId'] as String?)?.trim();
    if (hid != null && hid.isNotEmpty) return hid;
    const prefix = 'hearing_inapp_';
    if (!docId.startsWith(prefix)) return null;
    final rest = docId.substring(prefix.length);
    if (rest.startsWith('upd_')) {
      final inner = rest.substring(4);
      final lastUs = inner.lastIndexOf('_');
      if (lastUs > 0) return inner.substring(0, lastUs);
    } else {
      final lastUs = rest.lastIndexOf('_');
      if (lastUs > 0) return rest.substring(0, lastUs);
    }
    return null;
  }

  static DateTime _sortTimeForHearing(Map<String, dynamic> hd) {
    return (hd['createdAt'] as Timestamp?)?.toDate() ??
        (hd['clientFanoutComplete'] as Timestamp?)?.toDate() ??
        (hd['updatedAt'] as Timestamp?)?.toDate() ??
        DateTime.now();
  }

  /// Shared inbox rows for reminders screen + bell (must stay in sync).
  List<HearingInboxRow> buildInboxRowsFromSnapshots(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> notifDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> hearingDocs, {
    bool allNotificationTypes = false,
    bool hearingsOnly = false,
    Set<String> readHearingIds = const {},
  }) {
    final coveredHearingIds = <String>{};
    final rows = <HearingInboxRow>[];
    final hearingById = <String, Map<String, dynamic>>{
      for (final d in hearingDocs) d.id: d.data(),
    };
    final hearingPool =
        hearingDocs.map((d) => d.data()).toList(growable: false);

    for (final doc in notifDocs) {
      var data = Map<String, dynamic>.from(doc.data());
      if (hearingsOnly && clientCourtEmailSpamNotification(data)) continue;
      final type = data['type'] as String? ?? '';
      if (!allNotificationTypes) {
        if (hearingsOnly) {
          if (!clientHearingInboxType(type)) continue;
        } else if (!hearingOrAppointmentBellType(type)) {
          continue;
        }
      }
      final hid = _hearingIdFromNotificationDoc(doc.id, data);
      if (hid != null) coveredHearingIds.add(hid);

      if (hid != null && hearingById.containsKey(hid)) {
        final hd = Map<String, dynamic>.from(hearingById[hid]!);
        final siblings = HearingCalendarFields.siblingSourcesByCaseNo(
          hd,
          hearingPool,
        );
        final prepared = HearingCalendarFields.prepareForNotificationDisplay(
          hd,
          extraSources: siblings,
        );
        final caseLabel = _caseLabelForDisplay(prepared);
        data = {
          ...data,
          ...HearingNotificationFormatter.copyHearingFieldsForNotification(
            prepared,
          ),
          'hearingDocId': hid,
          'title': _buildTitle(prepared, caseLabel),
          'summary': _buildSummary(prepared, caseLabel),
        };
      } else {
        final caseLabel = _caseLabelForDisplay(data);
        final storedCaption = (data['caseTitle'] as String?)?.trim() ?? '';
        if (storedCaption.isNotEmpty &&
            !HearingCalendarFields.isLowQualityCaseTitle(storedCaption)) {
          data = Map<String, dynamic>.from(data);
          data['title'] = _buildTitle(data, caseLabel);
          data['summary'] = _buildSummary(data, caseLabel);
        }
      }

      if (hearingsOnly && clientHearingInboxType(type)) {
        data = Map<String, dynamic>.from(data);
        data['title'] = clientInboxTitleFromHearing(data);
        data['summary'] = clientSummaryFromNotificationMap(data);
        data['hearingDocId'] ??= hid;
        final msg = (data['message'] as String?)?.trim() ?? '';
        if (msg.isEmpty && hid != null) {
          data['message'] =
              'Court order for case ${(data['caseNo'] as String?)?.trim() ?? hid}. '
              'Tap to read the full notice.';
        }
      }

      final ts = (data['createdAt'] as Timestamp?)?.toDate();
      rows.add(
        HearingInboxRow(
          rowKey: doc.id,
          notificationDocId: doc.id,
          data: data,
          sortTime: ts ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }

    for (final hDoc in hearingDocs) {
      if (coveredHearingIds.contains(hDoc.id)) continue;
      final hd = hDoc.data();
      if (!isDisplayableHearingRow(hd)) continue;

      final siblings = HearingCalendarFields.siblingSourcesByCaseNo(
        hd,
        hearingPool,
      );
      final prepared = HearingCalendarFields.prepareForNotificationDisplay(
        hd,
        extraSources: siblings,
      );
      final ts = _sortTimeForHearing(hd);
      rows.add(
        HearingInboxRow(
          rowKey: 'hearing_${hDoc.id}',
          notificationDocId: null,
          data: {
            'type': 'hearing_activity',
            'title': inboxTitleFromHearing(prepared),
            'summary': inboxSummaryFromHearing(prepared),
            'message': inboxBodyFromHearing(prepared),
            'hearingDocId': hDoc.id,
            ...HearingNotificationFormatter.copyHearingFieldsForNotification(
              prepared,
            ),
            'createdAt': Timestamp.fromDate(ts),
            'isRead': readHearingIds.contains(hDoc.id),
          },
          sortTime: ts,
        ),
      );
    }

    rows.sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return rows;
  }

  /// Bell badge: unread inbox rows (same source as reminders list).
  int countInboxBellFromSnapshots(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> notifDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> hearingDocs, {
    bool allNotificationTypes = false,
    bool hearingsOnly = false,
    Set<String> readHearingIds = const {},
  }) {
    return buildInboxRowsFromSnapshots(
      notifDocs,
      hearingDocs,
      allNotificationTypes: allNotificationTypes,
      hearingsOnly: hearingsOnly,
      readHearingIds: readHearingIds,
    ).where((r) => r.isUnread).length;
  }

  /// Marks one reminders/bell row read (Firestore notification and/or hearing-only).
  Future<void> markInboxRowAsRead({
    required String userId,
    String? notificationDocId,
    Map<String, dynamic>? rowData,
  }) async {
    if (notificationDocId != null && notificationDocId.isNotEmpty) {
      try {
        await _db.collection('notifications').doc(notificationDocId).update({
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        if (kDebugMode) _fanoutLog('markInboxRowAsRead notification: $e');
      }
      return;
    }

    final data = rowData ?? {};
    final hearingDocId = (data['hearingDocId'] as String?)?.trim();
    if (hearingDocId == null || hearingDocId.isEmpty) return;

    await _addReadHearingId(userId, hearingDocId);

    final nid = 'hearing_inapp_${hearingDocId}_$userId';
    try {
      await _db.collection('notifications').doc(nid).set({
        'userId': userId,
        'type': data['type'] ?? 'hearing_activity',
        'title': data['title'] ?? 'Court hearing / order',
        if (data['summary'] != null) 'summary': data['summary'],
        if (data['message'] != null) 'message': data['message'],
        'hearingDocId': hearingDocId,
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
        'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
        if (data['caseNo'] != null) 'caseNo': data['caseNo'],
        if (data['clientName'] != null) 'clientName': data['clientName'],
        if (data['courtBranch'] != null) 'courtBranch': data['courtBranch'],
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) _fanoutLog('markInboxRowAsRead hearing notif: $e');
    }

    _refreshInboxStreamsForUser(userId);
  }

  /// Marks every unread inbox row read (matches reminders list + bell).
  Future<void> markAllInboxRowsRead(
    String userId, {
    bool allNotificationTypes = false,
    bool includeGlobalHearingsFallback = true,
    bool hearingsOnly = false,
  }) async {
    try {
      final notifs = await _db
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .limit(200)
          .get();

      final batch = _db.batch();
      var pending = 0;
      for (final doc in notifs.docs) {
        final type = doc.data()['type'] as String? ?? '';
        if (!allNotificationTypes) {
          if (hearingsOnly) {
            if (!clientHearingInboxType(type)) continue;
          } else if (!hearingOrAppointmentBellType(type)) {
            continue;
          }
        }
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
        pending++;
      }
      if (pending > 0) await batch.commit();

      if (includeGlobalHearingsFallback) {
        final hearings = await _hearingsSnapshotForInbox();
        if (hearings == null) return;

        final readIds =
            _readHearingIdsMem[userId] ??
            await _getReadHearingIdsFromPrefs(userId);
        _readHearingIdsMem[userId] = readIds;
        final covered = <String>{};
        for (final doc in notifs.docs) {
          final hid = _hearingIdFromNotificationDoc(doc.id, doc.data());
          if (hid != null) covered.add(hid);
        }

        for (final hDoc in hearings.docs) {
          if (covered.contains(hDoc.id)) continue;
          final hd = hDoc.data();
          if (!isDisplayableHearingRow(hd)) continue;
          readIds.add(hDoc.id);
          final ts = _sortTimeForHearing(hd);
          final nid = 'hearing_inapp_${hDoc.id}_$userId';
          await _db.collection('notifications').doc(nid).set({
            'userId': userId,
            'type': 'hearing_activity',
            'title': inboxTitleFromHearing(hd),
            'summary': inboxSummaryFromHearing(hd),
            'message': inboxBodyFromHearing(hd),
            'hearingDocId': hDoc.id,
            'isRead': true,
            'readAt': FieldValue.serverTimestamp(),
            'createdAt': Timestamp.fromDate(ts),
            if (hd['caseNo'] != null) 'caseNo': hd['caseNo'],
            if (hd['clientName'] != null) 'clientName': hd['clientName'],
            if (hd['courtBranch'] != null) 'courtBranch': hd['courtBranch'],
          }, SetOptions(merge: true));
        }

        final prefs = await SharedPreferences.getInstance();
        final key = _inboxReadHearingsKey(userId);
        final list = readIds.toList();
        final trimmed = list.length > _maxReadHearingIds
            ? list.sublist(0, _maxReadHearingIds)
            : list;
        await prefs.setStringList(key, trimmed);
      }
    } catch (e) {
      if (kDebugMode) _fanoutLog('markAllInboxRowsRead: $e');
    }
    _refreshInboxStreamsForUser(userId);
  }

  Future<int> countInboxBellItems(
    String userId, {
    bool allNotificationTypes = false,
  }) async {
    final notifDocs = await _notificationDocsForInbox(userId);
    final hearings = await _canUseGlobalHearingsInbox(userId)
        ? await _hearingsSnapshotForInbox(forUserId: userId)
        : null;
    await _ensureReadHearingIdsLoaded(userId);
    final readHearingIds = _readHearingIdsMem[userId] ?? const {};
    return countInboxBellFromSnapshots(
      notifDocs,
      hearings?.docs ?? const [],
      allNotificationTypes: allNotificationTypes,
      readHearingIds: readHearingIds,
    );
  }

  /// Real-time bell count — derived from the same inbox rows as the reminders list.
  Stream<int> watchInboxBellCount(
    String userId, {
    bool allNotificationTypes = false,
    bool includeGlobalHearingsFallback = true,
    bool hearingsOnly = false,
  }) {
    return _inboxBundle(
      userId,
      allNotificationTypes: allNotificationTypes,
      includeGlobalHearingsFallback: includeGlobalHearingsFallback,
      hearingsOnly: hearingsOnly,
    ).countStream;
  }

  static int _countClientHearingUnreadFromSnapshots(
    QuerySnapshot<Map<String, dynamic>>? userIdSnap,
    QuerySnapshot<Map<String, dynamic>>? clientIdSnap,
  ) {
    final seen = <String>{};
    var n = 0;
    for (final snap in [userIdSnap, clientIdSnap]) {
      if (snap == null) continue;
      for (final doc in snap.docs) {
        if (!seen.add(doc.id)) continue;
        final data = doc.data();
        if (data['isRead'] == true) continue;
        if (clientCourtEmailSpamNotification(data)) continue;
        final type = (data['type'] as String? ?? '').toLowerCase();
        if (!clientHearingInboxType(type)) continue;
        n++;
      }
    }
    return n;
  }

  static int _countClientOtherAlertsFromSnapshots(
    QuerySnapshot<Map<String, dynamic>>? userIdSnap,
    QuerySnapshot<Map<String, dynamic>>? clientIdSnap,
  ) {
    final seen = <String>{};
    var n = 0;
    for (final snap in [userIdSnap, clientIdSnap]) {
      if (snap == null) continue;
      for (final doc in snap.docs) {
        if (!seen.add(doc.id)) continue;
        if (doc.data()['isRead'] == true) continue;
        final type = (doc.data()['type'] as String? ?? '').toLowerCase();
        if (_isCourtEmailSpamType(type)) continue;
        if (clientCourtEmailSpamNotification(doc.data())) continue;
        if (hearingOrAppointmentBellType(type)) continue;
        n++;
      }
    }
    return n;
  }

  /// One-shot badge count (hearings + other alerts) after sync.
  Future<int> countClientNotificationBadge(String userId) async {
    final snaps = await Future.wait([
      _db.collection('notifications').where('userId', isEqualTo: userId).limit(300).get(),
      _db.collection('notifications').where('clientId', isEqualTo: userId).limit(300).get(),
    ]);
    return _countClientHearingUnreadFromSnapshots(snaps[0], snaps[1]) +
        _countClientOtherAlertsFromSnapshots(snaps[0], snaps[1]);
  }

  /// Real-time unread court-hearing notifications for the client bell.
  Stream<int> watchClientHearingUnreadCount(String userId) {
    Stream<QuerySnapshot<Map<String, dynamic>>> userIdStream;
    try {
      userIdStream = _db
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .limit(300)
          .snapshots();
    } catch (_) {
      userIdStream = const Stream.empty();
    }

    Stream<QuerySnapshot<Map<String, dynamic>>> clientIdStream;
    try {
      clientIdStream = _db
          .collection('notifications')
          .where('clientId', isEqualTo: userId)
          .limit(300)
          .snapshots();
    } catch (_) {
      clientIdStream = const Stream.empty();
    }

    return Stream<int>.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? lastUserIdSnap;
      QuerySnapshot<Map<String, dynamic>>? lastClientIdSnap;

      void recompute() {
        if (controller.isClosed) return;
        controller.add(
          _countClientHearingUnreadFromSnapshots(lastUserIdSnap, lastClientIdSnap),
        );
      }

      recompute();

      late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> subU;
      late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> subC;

      subU = userIdStream.listen(
        (snap) {
          lastUserIdSnap = snap;
          recompute();
        },
        onError: (_) {
          lastUserIdSnap = null;
          recompute();
        },
      );
      subC = clientIdStream.listen(
        (snap) {
          lastClientIdSnap = snap;
          recompute();
        },
        onError: (_) {
          lastClientIdSnap = null;
          recompute();
        },
      );

      controller.onCancel = () async {
        await subU.cancel();
        await subC.cancel();
      };
    });
  }

  /// Client dashboard bell: unread hearing rows + other non-hearing alerts.
  Stream<int> watchClientNotificationBadgeCount(String userId) {
    final hearingStream = watchClientHearingUnreadCount(userId);
    final otherStream = watchOtherAlertsUnreadCount(userId);

    return Stream<int>.multi((controller) {
      var hearing = 0;
      var other = 0;

      void emit() {
        if (!controller.isClosed) controller.add(hearing + other);
      }

      emit();

      late final StreamSubscription<int> subH;
      late final StreamSubscription<int> subO;

      subH = hearingStream.listen(
        (v) {
          hearing = v;
          emit();
        },
        onError: (_) {
          hearing = 0;
          emit();
        },
      );
      subO = otherStream.listen(
        (v) {
          other = v;
          emit();
        },
        onError: (_) {
          other = 0;
          emit();
        },
      );

      controller.onCancel = () async {
        await subH.cancel();
        await subO.cancel();
      };
    });
  }

  static bool _isCourtEmailSpamType(String type) {
    final t = type.toLowerCase();
    return t == 'court_email_ingest' || t.startsWith('court_');
  }

  /// Unread general alerts (excludes court-email spam and hearing/appointment rows).
  Stream<int> watchOtherAlertsUnreadCount(String userId) {
    Stream<QuerySnapshot<Map<String, dynamic>>> userIdStream;
    try {
      userIdStream = _db
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .limit(200)
          .snapshots();
    } catch (_) {
      userIdStream = const Stream.empty();
    }

    Stream<QuerySnapshot<Map<String, dynamic>>> clientIdStream;
    try {
      clientIdStream = _db
          .collection('notifications')
          .where('clientId', isEqualTo: userId)
          .limit(200)
          .snapshots();
    } catch (_) {
      clientIdStream = const Stream.empty();
    }

    return Stream<int>.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? lastUserIdSnap;
      QuerySnapshot<Map<String, dynamic>>? lastClientIdSnap;

      void recompute() {
        if (controller.isClosed) return;
        final seen = <String>{};
        var n = 0;
        for (final snap in [lastUserIdSnap, lastClientIdSnap]) {
          if (snap == null) continue;
          for (final doc in snap.docs) {
            if (!seen.add(doc.id)) continue;
            if (doc.data()['isRead'] == true) continue;
            final type = (doc.data()['type'] as String? ?? '').toLowerCase();
            if (_isCourtEmailSpamType(type)) continue;
            if (clientCourtEmailSpamNotification(doc.data())) continue;
            if (hearingOrAppointmentBellType(type)) continue;
            n++;
          }
        }
        controller.add(n);
      }

      late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> subU;
      late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> subC;

      subU = userIdStream.listen(
        (snap) {
          lastUserIdSnap = snap;
          recompute();
        },
        onError: (_) {
          lastUserIdSnap = null;
          recompute();
        },
      );
      subC = clientIdStream.listen(
        (snap) {
          lastClientIdSnap = snap;
          recompute();
        },
        onError: (_) {
          lastClientIdSnap = null;
          recompute();
        },
      );

      controller.onCancel = () async {
        await subU.cancel();
        await subC.cancel();
      };
    });
  }

  /// Staff bell badge: hearings/appointments + other unread alerts (matches notifications screen).
  Stream<int> watchStaffNotificationBadgeCount(String userId) {
    final hearingStream = watchInboxBellCount(userId);
    final otherStream = watchOtherAlertsUnreadCount(userId);

    int safeCount(Object? value) {
      if (value is int) return value;
      if (value is num) return value.round();
      return 0;
    }

    return Stream<int>.multi((controller) {
      var hearing = 0;
      var other = 0;

      int coerceCount(Object? value) {
        if (value is int) return value;
        if (value is num) return value.round();
        return 0;
      }

      void emit() {
        if (!controller.isClosed) {
          controller.add(safeCount(hearing) + safeCount(other));
        }
      }

      emit();

      late final StreamSubscription<int> subHearing;
      late final StreamSubscription<int> subOther;

      subHearing = hearingStream.listen(
        (v) {
          hearing = coerceCount(v);
          emit();
        },
        onError: (_) {
          hearing = 0;
          emit();
        },
      );
      subOther = otherStream.listen(
        (v) {
          other = coerceCount(v);
          emit();
        },
        onError: (_) {
          other = 0;
          emit();
        },
      );

      controller.onCancel = () async {
        await subHearing.cancel();
        await subOther.cancel();
      };
    });
  }

  /// One-shot load for reminders screen (shows data even before snapshot listeners fire).
  Future<List<HearingInboxRow>> fetchInboxRowsOnce(
    String userId, {
    bool allNotificationTypes = false,
    bool includeGlobalHearingsFallback = true,
    bool hearingsOnly = false,
  }) async {
    await _ensureReadHearingIdsLoaded(userId);
    final notifDocs = await _notificationDocsForInbox(
      userId,
      hearingsOnly: hearingsOnly,
    );
    final hearings = includeGlobalHearingsFallback &&
            await _canUseGlobalHearingsInbox(userId)
        ? await _hearingsSnapshotForInbox(forUserId: userId)
        : null;

    final rows = buildInboxRowsFromSnapshots(
      notifDocs,
      hearings?.docs ?? const [],
      allNotificationTypes: allNotificationTypes,
      hearingsOnly: hearingsOnly,
      readHearingIds: _readHearingIdsMem[userId] ?? const {},
    );

    _inboxBundle(
      userId,
      allNotificationTypes: allNotificationTypes,
      includeGlobalHearingsFallback: includeGlobalHearingsFallback,
      hearingsOnly: hearingsOnly,
    ).seedRows(rows, hearingsSnapshot: hearings);

    return rows;
  }

  /// Client reminders: hearing rows from `notifications` only (no global `hearings` scan).
  Future<List<HearingInboxRow>> fetchClientHearingInboxRowsOnce(
    String userId, {
    bool runSync = false,
  }) async {
    if (runSync) {
      await syncClientHearingNotifications();
    }
    await _ensureReadHearingIdsLoaded(userId);
    final notifDocs = await _notificationDocsForInbox(userId, hearingsOnly: true);
    final rows = buildInboxRowsFromSnapshots(
      notifDocs,
      const [],
      hearingsOnly: true,
      readHearingIds: _readHearingIdsMem[userId] ?? const {},
    );
    _inboxBundle(
      userId,
      includeGlobalHearingsFallback: false,
      hearingsOnly: true,
    ).seedRows(rows, hearingsSnapshot: null);
    _refreshInboxStreamsForUser(userId);
    return rows;
  }

  /// Client hearing inbox stream (notifications collection only).
  Stream<List<HearingInboxRow>> watchClientHearingInboxRows(String userId) {
    return watchInboxRows(
      userId,
      includeGlobalHearingsFallback: false,
      hearingsOnly: true,
    );
  }

  /// Reminders list stream — same source as [watchInboxBellCount].
  Stream<List<HearingInboxRow>> watchInboxRows(
    String userId, {
    bool allNotificationTypes = false,
    bool includeGlobalHearingsFallback = true,
    bool hearingsOnly = false,
  }) {
    final bundle = _inboxBundle(
      userId,
      allNotificationTypes: allNotificationTypes,
      includeGlobalHearingsFallback: includeGlobalHearingsFallback,
      hearingsOnly: hearingsOnly,
    );
    return Stream<List<HearingInboxRow>>.multi((controller) {
      final cached = bundle.lastRows;
      if (cached != null) {
        controller.add(cached);
      }

      late final StreamSubscription<List<HearingInboxRow>> sub;
      sub = bundle.rowsStream.listen(
        controller.add,
        onError: (Object e) {
          if (_isPermissionDenied(e)) return;
          if (!controller.isClosed) controller.add(const []);
        },
        onDone: controller.close,
      );
      controller.onCancel = () => sub.cancel();
    });
  }

  /// Writes one hearing inbox row for a single staff user (skips digest / full fan-out).
  Future<void> ensureStaffHearingNotificationForUser(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String staffUid,
  ) async {
    if (!doc.exists || staffUid.isEmpty) return;
    final d = doc.data();
    if (d == null || !isDisplayableHearingRow(d)) return;

    final nid = 'hearing_inapp_${doc.id}_$staffUid';
    DocumentSnapshot<Map<String, dynamic>>? existing;
    try {
      existing = await _db.collection('notifications').doc(nid).get();
    } catch (_) {}

    final resolved = await _resolveCase(d);
    final caseMaps = await HearingCalendarFields.loadCaseMapsForHearing(d);
    if (resolved != null) {
      final rid = resolved.id;
      if (caseMaps.every((c) => (c['id'] as String?) != rid)) {
        caseMaps.add({
          'id': rid,
          'caseTitle': resolved.title,
          if ((d['caseNo'] as String?)?.trim().isNotEmpty == true)
            'caseNo': (d['caseNo'] as String?)!.trim(),
        });
      }
    }
    final prepared = HearingCalendarFields.prepareForNotificationDisplay(
      d,
      caseMaps: caseMaps,
    );
    final caseLabel = _caseLabelForDisplay(prepared, caseMaps: caseMaps);
    final caseId = resolved?.id ?? (d['caseId'] as String?)?.trim() ?? '';
    final title = _buildTitle(prepared, caseLabel);
    final resolvedForBody = resolved ?? (id: doc.id, title: caseLabel);
    final body = _buildBody(prepared, resolvedForBody);
    final summary = _buildSummary(prepared, caseLabel);
    final docExists = existing?.exists == true;
    final wasRead =
        docExists && _notificationWasRead(existing?.data());

    final payload = <String, dynamic>{
      'userId': staffUid,
      'type': 'hearing_activity',
      'title': title,
      'summary': summary,
      'message': body,
      if (caseId.isNotEmpty) 'caseId': caseId,
      'hearingDocId': doc.id,
      ...HearingNotificationFormatter.copyHearingFieldsForNotification(
        prepared,
        caseMaps: caseMaps,
      ),
    };
    _applyResolvedCaseTitleOnPayload(payload, prepared);
    if (wasRead) {
      payload['isRead'] = true;
    } else if (!docExists) {
      payload['isRead'] = false;
      payload['createdAt'] = Timestamp.now();
    }

    try {
      await _db
          .collection('notifications')
          .doc(nid)
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      if (_isPermissionDenied(e)) return;
      if (kDebugMode) {
        _fanoutLog('ensureStaffHearingNotificationForUser: $e');
      }
    }
  }

  bool _isPermissionDenied(Object e) {
    if (e is FirebaseException) {
      return e.code == 'permission-denied';
    }
    return e.toString().contains('permission-denied');
  }

  /// Waits until Firebase Auth matches [userId] (web often attaches listeners too early).
  Future<bool> _waitForInboxAuth(String userId) async {
    if (userId.isEmpty) return false;
    if (FirebaseAuth.instance.currentUser?.uid == userId) return true;
    try {
      await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u?.uid == userId)
          .timeout(const Duration(seconds: 20));
      return FirebaseAuth.instance.currentUser?.uid == userId;
    } catch (_) {
      return false;
    }
  }

  /// Whether this account may run `hearings.limit()` inbox queries (matches [isFirmUser] rules).
  Future<bool> _canUseGlobalHearingsInbox(String uid) async {
    if (uid.isEmpty) return false;
    if (await _isStaffAccount(uid)) return true;
    try {
      final u = await _db.collection('users').doc(uid).get();
      if (!u.exists) return false;
      final role = (u.data()?['role'] as String?)?.toLowerCase().trim() ?? '';
      return role == 'attorney' || role == 'admin';
    } catch (_) {
      return false;
    }
  }

  void _listenFirestore<T>(
    Stream<T> stream,
    void Function(T event) onData, {
    String? debugLabel,
  }) {
    stream.listen(
      onData,
      onError: (Object e) {
        if (kDebugMode && debugLabel != null) {
          _fanoutLog('$debugLabel: $e');
        }
      },
      cancelOnError: true,
    );
  }

  /// Only firm roles may fan out hearing notifications to multiple recipients.
  Future<bool> _canRunFirmWideFanout(String uid) async {
    try {
      if (await _isStaffAccount(uid)) return true;
      final u = await _db.collection('users').doc(uid).get();
      final role = (u.data()?['role'] as String?)?.toLowerCase().trim() ?? '';
      return role == 'attorney' || role == 'admin';
    } catch (_) {
      return false;
    }
  }

  /// Backfill court hearing notifications for the signed-in staff user.
  Future<void> syncStaffHearingNotifications({bool force = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      if (!await _isStaffAccount(uid)) return;

      if (!await _canUseGlobalHearingsInbox(uid)) return;

      final snap = await _db.collection('hearings').limit(100).get();

      for (final doc in snap.docs) {
        if (!isDisplayableHearingRow(doc.data())) continue;
        await ensureStaffHearingNotificationForUser(doc, uid);
        if (force) {
          await processDocumentIfNeeded(doc, ignoreProcessedDigest: true);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        _fanoutLog('HearingNotificationFanout.syncStaffHearingNotifications: $e');
      }
    }
  }

  /// One-shot scan (e.g. when opening Appointment Reminders) so new `hearings` are
  /// fan-out even if the real-time listener missed the first write.
  Future<void> syncRecentHearingsForInbox() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      if (!await _canUseGlobalHearingsInbox(uid)) return;

      final snap = await _hearingsSnapshotForInbox(forUserId: uid);
      if (snap == null) return;
      for (final doc in snap.docs) {
        await processDocumentIfNeeded(doc);
      }
    } catch (e) {
      if (kDebugMode) {
        _fanoutLog('HearingNotificationFanout.syncRecentHearingsForInbox: $e');
      }
    }
  }
}

/// Shared Firestore listeners for reminders list + dashboard bell (same unread rows).
class _InboxStreamBundle {
  _InboxStreamBundle({
    required this.userId,
    required this.allNotificationTypes,
    required this.includeGlobalHearingsFallback,
    required this.hearingsOnly,
    required this.emitRows,
    required this.attachListeners,
  }) {
    _rowsController = StreamController<List<HearingInboxRow>>.broadcast(
      onListen: _onRowsListen,
    );
    countStream = _rowsController.stream.map(
      (rows) => rows.where((r) => r.isUnread).length,
    );
    attachListeners(
      userId,
      allNotificationTypes,
      includeGlobalHearingsFallback,
      hearingsOnly,
      (notifDocs, hearings) {
        unawaited(_deliver(notifDocs, hearings));
      },
    );
  }

  final String userId;
  final bool allNotificationTypes;
  final bool includeGlobalHearingsFallback;
  final bool hearingsOnly;
  final Future<void> Function(
    String userId,
    bool allNotificationTypes,
    bool hearingsOnly,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> notifDocs,
    QuerySnapshot<Map<String, dynamic>>? hearings,
    void Function(List<HearingInboxRow>) deliver,
  )
  emitRows;
  final void Function(
    String userId,
    bool allNotificationTypes,
    bool includeGlobalHearingsFallback,
    bool hearingsOnly,
    void Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> notifDocs,
      QuerySnapshot<Map<String, dynamic>>? hearings,
    )
    onData,
  )
  attachListeners;

  late final StreamController<List<HearingInboxRow>> _rowsController;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _lastNotifDocs;
  QuerySnapshot<Map<String, dynamic>>? _lastHearings;
  List<HearingInboxRow>? _lastRows;

  List<HearingInboxRow>? get lastRows => _lastRows;

  Stream<List<HearingInboxRow>> get rowsStream => _rowsController.stream;
  late final Stream<int> countStream;

  void _onRowsListen() {
    if (_lastRows != null && !_rowsController.isClosed) {
      scheduleMicrotask(() {
        if (!_rowsController.isClosed) _rowsController.add(_lastRows!);
      });
      return;
    }
    if (_lastNotifDocs != null) {
      unawaited(_deliver(_lastNotifDocs!, _lastHearings));
    }
  }

  Future<void> _deliver(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> notifDocs,
    QuerySnapshot<Map<String, dynamic>>? hearings,
  ) async {
    _lastNotifDocs = notifDocs;
    if (hearings != null) _lastHearings = hearings;
    if (_rowsController.isClosed) return;
    await emitRows(
      userId,
      allNotificationTypes,
      hearingsOnly,
      notifDocs,
      _lastHearings,
      (rows) {
        _lastRows = rows;
        _cacheBellCount(userId, rows);
        if (!_rowsController.isClosed) _rowsController.add(rows);
      },
    );
  }

  Future<void> emit() async {
    if (_lastNotifDocs == null) return;
    await _deliver(_lastNotifDocs!, _lastHearings);
  }

  void seedRows(
    List<HearingInboxRow> rows, {
    QuerySnapshot<Map<String, dynamic>>? hearingsSnapshot,
  }) {
    _lastRows = rows;
    _cacheBellCount(userId, rows);
    if (hearingsSnapshot != null) _lastHearings = hearingsSnapshot;
    if (!_rowsController.isClosed) _rowsController.add(rows);
  }
}

bool _hearingTypeForBell(String type) {
  final t = type.toLowerCase();
  // Court-email ingest alerts belong in the general inbox, not hearing reminders.
  if (t == 'court_email_ingest' || t.startsWith('court_')) return false;
  return t.contains('hearing') ||
      t == 'appointment_scheduled' ||
      t == 'appointment_3day_reminder' ||
      t == 'appointment_sameday_reminder';
}

/// Used by attorney UI to count rows that should light the reminders bell.
bool hearingOrAppointmentBellType(String type) => _hearingTypeForBell(type);

/// Client notifications: court hearings/orders only (not firm-wide appointment reminders).
bool clientHearingInboxType(String type) {
  final t = type.toLowerCase();
  if (t == 'court_email_ingest' || t.startsWith('court_')) return false;
  return t.contains('hearing');
}

/// Email-ingest spam shown as "New court notice" — not real court hearing orders.
bool clientCourtEmailSpamNotification(Map<String, dynamic> data) {
  final type = (data['type'] as String? ?? '').toLowerCase();
  final hid = (data['hearingDocId'] as String?)?.trim() ?? '';
  final title = (data['title'] as String? ?? '').toLowerCase().trim();

  // Linked `hearings/{id}` row — keep and repair title in UI (not email-queue spam).
  if (hid.isNotEmpty &&
      (type == 'hearing_activity' || type == 'hearing_activity_update')) {
    return false;
  }

  if (HearingNotificationFanoutService._isWrongClientCourtNoticeTitle(title)) {
    return true;
  }

  if (type == 'court_email_ingest') return true;
  if (type.startsWith('court_') && !type.contains('hearing')) return true;

  // Email queue rows typed as hearing_activity but not linked to a hearing doc.
  if ((type == 'hearing_activity' || type == 'hearing_activity_update') &&
      hid.isEmpty) {
    return true;
  }

  if (hid.isEmpty &&
      (title.contains('court email') ||
          title.contains('hearing / court date detected'))) {
    return true;
  }

  if (!title.contains('court hearing') &&
      !title.contains('court order') &&
      !title.contains('court hearings') &&
      !title.contains('hearing scheduled') &&
      !title.contains('hearing updated') &&
      !title.contains('hearing message')) {
    if (title.contains('supa update') ||
        title.contains('prisma') ||
        title.contains('roboflow') ||
        title.contains('ollama')) {
      return true;
    }
  }
  if (title.contains('court email (review)') ||
      title.contains('hearing / court date detected')) {
    return true;
  }
  return false;
}

/// One row in Hearing & Appointment Reminders (from `notifications` or `hearings`).
class HearingInboxRow {
  HearingInboxRow({
    required this.rowKey,
    required this.notificationDocId,
    required this.data,
    required this.sortTime,
  });

  final String rowKey;
  final String? notificationDocId;
  final Map<String, dynamic> data;
  final DateTime sortTime;

  bool get isUnread => data['isRead'] != true;

  bool get isHearingSource {
    final type = (data['type'] as String? ?? '').toLowerCase();
    final title = (data['title'] as String? ?? '').toLowerCase();
    return type.contains('hearing') ||
        title.contains('new notice court hearings') ||
        title.contains('court hearing') ||
        title.contains('court order') ||
        (data['hearingDocId'] as String?)?.isNotEmpty == true;
  }
}
