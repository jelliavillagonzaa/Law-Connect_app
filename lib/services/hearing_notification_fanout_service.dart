import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/hearing_notification_formatter.dart';
import '../utils/out_of_system_notice.dart';
import 'hearing_calendar_fields.dart';
import 'fcm_service.dart';
import 'hearing_sms_alert_service.dart';
import 'staff_application_service.dart';
import 'firestore_mirror_helper.dart';

/// Inbox / fan-out must not spam the console when switching attorney tabs.
void _fanoutLog(String message) {}

/// Top-level (not on the singleton) so Flutter web hot reload does not leave the map undefined.
final Map<String, _InboxStreamBundle> _hearingInboxBundles =
    <String, _InboxStreamBundle>{};

/// In-memory read-hearing ids (avoids awaiting SharedPreferences on every emit).
final Map<String, Set<String>> _readHearingIdsMem = <String, Set<String>>{};

/// Last bell badge count — shown instantly before Firestore catches up.
final Map<String, int> _bellCountMem = <String, int>{};
final Map<String, ValueNotifier<int>> _bellCountNotifiers =
    <String, ValueNotifier<int>>{};
final Map<String, DateTime> _inboxFreshUntil = <String, DateTime>{};
final Map<String, DateTime> _attorneyInboxAckAt = <String, DateTime>{};
final Set<String> _spamPurgedUids = <String>{};
const String _bellCountPrefsPrefix = 'inbox_bell_count_v2_';
const String _attorneyInboxAckPrefsPrefix = 'attorney_inbox_ack_ms_';

int _unreadBellCount(List<HearingInboxRow> rows) {
  return rows
      .where(
        (r) =>
            r.isUnread &&
            !HearingCalendarFields.isNonCourtHearingSpam(r.data),
      )
      .length;
}

void _setBellCount(String userId, int n) {
  if (userId.isEmpty) return;
  _bellCountMem[userId] = n;
  final vn = _bellCountNotifiers[userId];
  if (vn != null && vn.value != n) vn.value = n;
  unawaited(() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_bellCountPrefsPrefix$userId', n);
    } catch (_) {}
  }());
}

void _cacheBellCount(String userId, List<HearingInboxRow> rows) {
  if (userId.isEmpty) return;
  _setBellCount(userId, _unreadBellCount(rows));
}

void _markInboxFresh(String userId) {
  if (userId.isEmpty) return;
  _inboxFreshUntil[userId] =
      DateTime.now().add(const Duration(seconds: 25));
}

Future<void> _loadBellCountFromPrefs(String userId) async {
  if (userId.isEmpty || _bellCountMem.containsKey(userId)) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    _bellCountMem[userId] = prefs.getInt('$_bellCountPrefsPrefix$userId') ?? 0;
    final vn = _bellCountNotifiers[userId];
    if (vn != null && vn.value != _bellCountMem[userId]) {
      vn.value = _bellCountMem[userId]!;
    }
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

  /// Throttle firm inbox backfill (opening Reminders used to fan out 20+ hearings every time).
  static final Map<String, DateTime> _lastInboxSyncAt = <String, DateTime>{};
  static const _inboxSyncMinInterval = Duration(minutes: 1);
  static final Set<String> _inboxSyncInFlight = <String>{};
  static final Set<String> _sessionWarmInboxKeys = <String>{};
  static final Map<String, Timer> _inboxRefreshDebounceByUser =
      <String, Timer>{};

  /// Bump when matching logic changes so older hearings can fan out again (doc IDs are stable; merge avoids dup spam).
  static const _prefsKey = 'hearing_inapp_fanout_ids_v9';
  final Set<String> _webClientPublishedHearingIds = <String>{};
  static const _inboxReadHearingsKeyPrefix = 'inbox_read_hearing_ids_v1_';
  static const _maxIds = 1500;
  static const _maxReadHearingIds = 500;

  /// Always merged into the reminders inbox (not only the recent-200 cap).
  static const _inboxHearingNotificationTypes = [
    'hearing_activity',
  ];

  static const _inboxAppointmentNotificationTypes = [
    'appointment_scheduled',
    'appointment_3day_reminder',
    'appointment_sameday_reminder',
    'appointment_request',
    'case_request',
    'task_assigned',
    'task_completed',
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
  Future<void> prepareBellCount(String userId) async {
    await _loadBellCountFromPrefs(userId);
  }

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
      return _unreadBellCount(rows);
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
    final warmKey = _inboxStreamCacheKey(
      userId,
      allNotificationTypes,
      includeGlobalHearingsFallback: includeGlobalHearingsFallback,
      hearingsOnly: hearingsOnly,
    );
    if (_sessionWarmInboxKeys.contains(warmKey)) return;
    _sessionWarmInboxKeys.add(warmKey);
    unawaited(_loadBellCountFromPrefs(userId));
    unawaited(_ensureReadHearingIdsLoaded(userId));
    // Web: no live inbox listeners on dashboard — they caused permission-denied loops + UI freeze.
    if (kIsWeb) return;
    _inboxBundle(
      userId,
      allNotificationTypes: allNotificationTypes,
      includeGlobalHearingsFallback: includeGlobalHearingsFallback,
      hearingsOnly: hearingsOnly,
    ).ensureListenersAttached();
  }

  /// Live badge count for the reminders bell.
  ValueNotifier<int> inboxBellCountListenable(String userId) {
    return _bellCountNotifiers.putIfAbsent(
      userId,
      () => ValueNotifier<int>(_bellCountMem[userId] ?? 0),
    );
  }

  /// Instant read-hearing ids (empty until prefs load).
  Set<String> peekReadHearingIds(String userId) {
    return Set<String>.from(_readHearingIdsMem[userId] ?? const {});
  }

  /// True when a fetch just finished — Reminders can paint without another round-trip.
  bool isAttorneyInboxFresh(String userId) {
    final until = _inboxFreshUntil[userId];
    return until != null && DateTime.now().isBefore(until);
  }

  HearingInboxRow _rowWithReadFlag(
    HearingInboxRow row,
    Set<String> readIds, {
    String? userId,
  }) {
    if (!row.isUnread) return row;
    final hid = (row.data['hearingDocId'] as String?)?.trim() ?? '';
    final acked =
        userId != null && _attorneyRowIsAcked(userId, row.sortTime);
    if (acked ||
        readIds.contains(row.rowKey) ||
        (hid.isNotEmpty && readIds.contains(hid)) ||
        (row.notificationDocId != null &&
            row.notificationDocId!.isNotEmpty &&
            readIds.contains(row.notificationDocId))) {
      return HearingInboxRow(
        rowKey: row.rowKey,
        notificationDocId: row.notificationDocId,
        data: {...row.data, 'isRead': true},
        sortTime: row.sortTime,
      );
    }
    return row;
  }

  bool _attorneyRowIsAcked(String userId, DateTime sortTime) {
    final ack = _attorneyInboxAckAt[userId];
    if (ack == null) return false;
    return !sortTime.isAfter(ack);
  }

  bool attorneyInboxTreatsAsRead(String userId, DateTime sortTime) {
    return _attorneyRowIsAcked(userId, sortTime);
  }

  /// Attorney Reminders and dashboard bell use this exact unread number.
  void setAttorneyBellCount(String userId, int n) {
    _setBellCount(userId, n < 0 ? 0 : n);
  }

  Future<void> loadAttorneyInboxAck(String userId) async {
    if (userId.isEmpty || _attorneyInboxAckAt.containsKey(userId)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt('$_attorneyInboxAckPrefsPrefix$userId');
      if (ms != null && ms > 0) {
        _attorneyInboxAckAt[userId] =
            DateTime.fromMillisecondsSinceEpoch(ms);
        return;
      }
    } catch (_) {}
    try {
      final doc = await _db
          .collection('notifications')
          .doc('attorney_inbox_ack_$userId')
          .get()
          .timeout(const Duration(seconds: 3));
      final raw = doc.data()?['ackAt'];
      if (raw is Timestamp) {
        _attorneyInboxAckAt[userId] = raw.toDate();
      }
    } catch (_) {}
  }

  Future<void> saveAttorneyInboxAck(String userId) async {
    if (userId.isEmpty) return;
    final at = DateTime.now().add(const Duration(seconds: 2));
    _attorneyInboxAckAt[userId] = at;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        '$_attorneyInboxAckPrefsPrefix$userId',
        at.millisecondsSinceEpoch,
      );
    } catch (_) {}
    try {
      await HybridDatastore.set(
        collection: 'notifications',
        id: 'attorney_inbox_ack_$userId',
        data: {
          'userId': userId,
          'type': 'attorney_inbox_ack',
          'isRead': true,
          'ackAt': Timestamp.fromDate(at),
          'createdAt': FieldValue.serverTimestamp(),
        },
        options: SetOptions(merge: true),
      );
    } catch (_) {}
  }

  /// Publish attorney inbox rows so the dashboard bell matches Reminders.
  void publishAttorneyInbox(String userId, List<HearingInboxRow> rows) {
    if (userId.isEmpty) return;
    final readIds = _readHearingIdsMem[userId] ?? const <String>{};
    final clean = rows
        .where((r) => !HearingCalendarFields.isNonCourtHearingSpam(r.data))
        .where((r) {
          final type = (r.data['type'] as String? ?? '').toLowerCase();
          return type != 'attorney_inbox_ack';
        })
        .map((r) => _rowWithReadFlag(r, readIds, userId: userId))
        .toList(growable: false);
    _inboxBundle(userId).seedRows(clean, attachListeners: false);
    _cacheBellCount(userId, clean);
    _markInboxFresh(userId);
  }

  int _unreadNotificationBellCount(List<HearingInboxRow> rows) {
    return rows.where((r) {
      if (!r.isUnread) return false;
      if (isHearingRecordUpdateNotification(r.data)) return false;
      if (HearingCalendarFields.isNonCourtHearingSpam(r.data)) return false;
      final type = (r.data['type'] as String? ?? '').toLowerCase();
      if (type == 'court_email_ingest') return false;
      if (r.notificationDocId == null || r.notificationDocId!.isEmpty) {
        return false;
      }
      return hearingOrAppointmentBellType(type) || type.contains('hearing');
    }).length;
  }

  int _countAttorneyBellFromNotifDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var n = 0;
    for (final doc in docs) {
      final data = doc.data();
      if (data['isRead'] == true) continue;
      final type = (data['type'] as String? ?? '').toLowerCase();
      if (type == 'attorney_inbox_ack' || type == 'attorney_read_keys') {
        continue;
      }
      if (isHearingRecordUpdateNotification(data)) continue;
      if (HearingCalendarFields.isNonCourtHearingSpam(data)) continue;
      if (type == 'court_email_ingest') continue;
      if (type.startsWith('court_') && !type.contains('hearing')) continue;
      if (hearingOrAppointmentBellType(type) || type.contains('hearing')) {
        n++;
      }
    }
    return n;
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _attorneyBellSub;
  String? _attorneyBellUid;
  final Map<String, ValueNotifier<int>> _attorneyUnreadNotifBell =
      <String, ValueNotifier<int>>{};

  /// Unread `notifications` count for the attorney bell (not live hearings).
  ValueNotifier<int> attorneyUnreadNotificationBellListenable(String userId) {
    return _attorneyUnreadNotifBell.putIfAbsent(
      userId,
      () => ValueNotifier<int>(0),
    );
  }

  void _setAttorneyUnreadNotifBell(String userId, int n) {
    if (userId.isEmpty) return;
    final v = n < 0 ? 0 : n;
    final vn = attorneyUnreadNotificationBellListenable(userId);
    if (vn.value != v) vn.value = v;
  }

  /// One Firestore listener per attorney. Badge = unread notification docs only.
  void attachAttorneyBellWatcher(String userId) {
    if (userId.isEmpty) return;
    if (_attorneyBellUid == userId && _attorneyBellSub != null) return;
    unawaited(_attorneyBellSub?.cancel());
    _attorneyBellUid = userId;
    _attorneyBellSub = null;

    void apply(QuerySnapshot<Map<String, dynamic>> snap) {
      _setAttorneyUnreadNotifBell(
        userId,
        _countAttorneyBellFromNotifDocs(snap.docs),
      );
    }

    Query<Map<String, dynamic>> unreadQuery() => _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .limit(99);

    Query<Map<String, dynamic>> fallbackQuery() => _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .limit(120);

    _attorneyBellSub = unreadQuery().snapshots().listen(
      apply,
      onError: (_) {
        unawaited(_attorneyBellSub?.cancel());
        _attorneyBellSub = fallbackQuery().snapshots().listen(
          apply,
          onError: (_) {
            unawaited(refreshAttorneyBellFromNotifications(userId));
          },
        );
        unawaited(refreshAttorneyBellFromNotifications(userId));
      },
    );
    unawaited(refreshAttorneyBellFromNotifications(userId));
  }

  Future<int> refreshAttorneyBellFromNotifications(String userId) async {
    if (userId.isEmpty) return 0;
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _db
            .collection('notifications')
            .where('userId', isEqualTo: userId)
            .where('isRead', isEqualTo: false)
            .limit(99)
            .get()
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        snap = await _db
            .collection('notifications')
            .where('userId', isEqualTo: userId)
            .limit(120)
            .get()
            .timeout(const Duration(seconds: 8));
      }
      final n = _countAttorneyBellFromNotifDocs(snap.docs);
      _setAttorneyUnreadNotifBell(userId, n);
      return n;
    } catch (_) {
      return attorneyUnreadNotificationBellListenable(userId).value;
    }
  }

  void _markCachedInboxRead(
    String userId, {
    String? rowKey,
    String? notificationDocId,
    String? hearingDocId,
    bool all = false,
  }) {
    if (userId.isEmpty) return;
    var patchedAny = false;
    for (final bundle in _hearingInboxBundles.values) {
      if (bundle.userId != userId) continue;
      final rows = bundle.lastRows;
      if (rows == null) continue;
      var changed = false;
      final next = <HearingInboxRow>[];
      for (final r in rows) {
        final hid = (r.data['hearingDocId'] as String?)?.trim() ?? '';
        final match = all ||
            (rowKey != null && rowKey.isNotEmpty && r.rowKey == rowKey) ||
            (notificationDocId != null &&
                notificationDocId.isNotEmpty &&
                r.notificationDocId == notificationDocId) ||
            (hearingDocId != null &&
                hearingDocId.isNotEmpty &&
                (hid == hearingDocId || r.rowKey == 'hearing_$hearingDocId'));
        if (match && r.isUnread) {
          changed = true;
          next.add(
            HearingInboxRow(
              rowKey: r.rowKey,
              notificationDocId: r.notificationDocId,
              data: {...r.data, 'isRead': true},
              sortTime: r.sortTime,
            ),
          );
        } else {
          next.add(r);
        }
      }
      if (changed) {
        patchedAny = true;
        bundle.seedRows(next, attachListeners: false);
      }
    }
    if (all) {
      _setBellCount(userId, 0);
    } else if (!patchedAny) {
      final n = _bellCountMem[userId] ?? 0;
      _setBellCount(userId, n > 0 ? n - 1 : 0);
    }
  }

  /// One-shot badge refresh — unread `notifications` only (not every hearings doc).
  Future<int> refreshInboxBellCountOnce(
    String userId, {
    bool includeGlobalHearingsFallback = true,
    bool hearingsOnly = false,
  }) async {
    attachAttorneyBellWatcher(userId);
    return refreshAttorneyBellFromNotifications(userId);
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

  void _scheduleInboxRefreshForUser(String userId) {
    if (userId.isEmpty) return;
    _inboxRefreshDebounceByUser[userId]?.cancel();
    _inboxRefreshDebounceByUser[userId] = Timer(
      const Duration(milliseconds: 450),
      () {
        _inboxRefreshDebounceByUser.remove(userId);
        _refreshInboxStreamsForUser(userId);
      },
    );
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
    unawaited(() async {
      if (!await _waitForInboxAuth(userId)) {
        StreamSubscription<User?>? authWait;
        authWait = FirebaseAuth.instance.authStateChanges().listen((user) {
          if (user?.uid != userId) return;
          authWait?.cancel();
          unawaited(_startInboxListenersAfterAuth(
            userId,
            allNotificationTypes,
            includeGlobalHearingsFallback,
            hearingsOnly,
            onData,
          ));
        });
        return;
      }

      await _startInboxListenersAfterAuth(
        userId,
        allNotificationTypes,
        includeGlobalHearingsFallback,
        hearingsOnly,
        onData,
      );
    }());
  }

  Future<void> _startInboxListenersAfterAuth(
    String userId,
    bool allNotificationTypes,
    bool includeGlobalHearingsFallback,
    bool hearingsOnly,
    void Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> notifDocs,
      QuerySnapshot<Map<String, dynamic>>? hearings,
    )
    onData,
  ) async {
    if (kIsWeb) {
      await _startInboxListenersWeb(
        userId: userId,
        includeGlobalHearingsFallback: includeGlobalHearingsFallback,
        hearingsOnly: hearingsOnly,
        onData: onData,
      );
      return;
    }

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
      refreshDebounce = Timer(const Duration(milliseconds: 900), () {
        unawaited(refreshNotifDocs(allowGlobalHearings: allowGlobalHearings));
      });
    }

    try {
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
    } catch (e) {
      if (kDebugMode) _fanoutLog('inbox listeners: $e');
      await refreshNotifDocs(allowGlobalHearings: false);
    }
  }

  /// Web: one hearings fetch + notifications stream only (no `hearings.snapshots()` loop).
  Future<void> _startInboxListenersWeb({
    required String userId,
    required bool includeGlobalHearingsFallback,
    required bool hearingsOnly,
    required void Function(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> notifDocs,
      QuerySnapshot<Map<String, dynamic>>? hearings,
    )
    onData,
  }) async {
    QuerySnapshot<Map<String, dynamic>>? cachedHearings;
    Timer? refreshDebounce;
    var refreshGen = 0;

    Future<void> emitInbox({bool reloadHearings = false}) async {
      final gen = ++refreshGen;
      try {
        final allowHearings = includeGlobalHearingsFallback &&
            await _canUseGlobalHearingsInbox(userId);
        if (reloadHearings && allowHearings) {
          cachedHearings = await _hearingsSnapshotForInbox(forUserId: userId);
        }
        final notifs = await _notificationDocsForInbox(
          userId,
          hearingsOnly: hearingsOnly,
        );
        if (gen != refreshGen) return;
        onData(notifs, allowHearings ? cachedHearings : null);
      } catch (e) {
        if (kDebugMode) _fanoutLog('inbox web emit: $e');
        if (gen != refreshGen) return;
        onData(const [], cachedHearings);
      }
    }

    await emitInbox(reloadHearings: true);

    _listenFirestore(
      _userNotificationsInboxStream(userId),
      (_) {
        refreshDebounce?.cancel();
        refreshDebounce = Timer(const Duration(milliseconds: 400), () {
          unawaited(emitInbox(reloadHearings: false));
        });
      },
      debugLabel: 'inbox web notifications',
    );
  }

  String _inboxReadHearingsKey(String userId) =>
      '$_inboxReadHearingsKeyPrefix$userId';

  Future<Set<String>> _getReadHearingIdsFromPrefs(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_inboxReadHearingsKey(userId)) ?? []).toSet();
  }

  Future<void> _addReadHearingId(String userId, String hearingDocId) async {
    await _addReadHearingIds(userId, [hearingDocId]);
  }

  /// One prefs write — parallel [_addReadHearingId] calls were overwriting each other.
  Future<void> _addReadHearingIds(String userId, Iterable<String> ids) async {
    final incoming = ids.map((id) => id.trim()).where((id) => id.isNotEmpty);
    if (incoming.isEmpty) return;

    final mem = _readHearingIdsMem.putIfAbsent(userId, () => <String>{});
    mem.addAll(incoming);

    final prefs = await SharedPreferences.getInstance();
    final key = _inboxReadHearingsKey(userId);
    final seen = <String>{};
    final merged = <String>[];
    for (final id in [...incoming, ...(prefs.getStringList(key) ?? const [])]) {
      if (seen.add(id)) merged.add(id);
    }
    final trimmed = merged.length > _maxReadHearingIds
        ? merged.sublist(0, _maxReadHearingIds)
        : merged;
    await prefs.setStringList(key, trimmed);
  }

  /// Persist attorney hearing rows as read in Firestore so Mark read survives reopen.
  Future<void> _writeAttorneyHearingReadReceipts(
    String userId,
    List<HearingInboxRow> rows,
  ) async {
    var written = 0;
    for (final row in rows) {
      if (written >= 40) break;
      final hid = (row.data['hearingDocId'] as String?)?.trim() ?? '';
      if (hid.isEmpty) continue;
      final nid = (row.notificationDocId?.trim().isNotEmpty == true)
          ? row.notificationDocId!.trim()
          : 'hearing_inapp_${hid}_$userId';
      try {
        await HybridDatastore.set(
          collection: 'notifications',
          id: nid,
          data: {
            'userId': userId,
            'type': row.data['type'] ?? 'hearing_activity',
            'title': row.data['title'] ?? 'Court hearing / order',
            if (row.data['summary'] != null) 'summary': row.data['summary'],
            if (row.data['message'] != null) 'message': row.data['message'],
            'hearingDocId': hid,
            'isRead': true,
            'readAt': FieldValue.serverTimestamp(),
            'createdAt': row.data['createdAt'] ?? FieldValue.serverTimestamp(),
            if (row.data['caseNo'] != null) 'caseNo': row.data['caseNo'],
            if (row.data['clientName'] != null)
              'clientName': row.data['clientName'],
          },
          options: SetOptions(merge: true),
        );
        written++;
      } catch (_) {}
    }
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

  /// Last significant digit group in a court docket string (e.g. `3545`).
  static String? docketDigits(String raw) {
    final matches = RegExp(r'\d{2,}')
        .allMatches(raw.trim())
        .map((m) => m.group(0)!)
        .toList();
    if (matches.isEmpty) return null;
    return matches.last;
  }

  static bool fieldMatchesCaseReference(String? fieldValue, String caseNo) =>
      _fieldMatchesCaseReference(fieldValue, caseNo);

  static bool caseMapMatchesHearing(
    Map<String, dynamic> caseMap,
    String caseNo,
    Map<String, dynamic> hearing,
  ) =>
      _caseMapMatchesHearing(caseMap, caseNo, hearing);

  static bool _fieldMatchesCaseReference(String? fieldValue, String caseNo) {
    if (fieldValue == null) return false;
    final v = fieldValue.trim();
    if (v.isEmpty) return false;
    if (v == caseNo) return true;
    final nv = _normalizeCaseRefWhitespace(caseNo);
    if (_normalizeCaseRefWhitespace(v).toLowerCase() == nv.toLowerCase()) {
      return true;
    }
    if (_textContainsCaseReference(v, nv)) return true;
    final dockA = docketDigits(v);
    final dockB = docketDigits(caseNo);
    if (dockA != null && dockB != null && dockA == dockB) {
      return true;
    }
    final av = _alnumLower(v);
    final an = _alnumLower(caseNo);
    // Full normalized equality only — avoid `3545` matching unrelated captions.
    return an.length >= 8 && av == an;
  }

  /// Firestore equality variants for court docket strings (OCR / import formats).
  static List<String> caseNumberQueryVariants(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return const [];
    final out = <String>{t, t.toUpperCase(), t.toLowerCase()};
    final collapsed = t.replaceAll(RegExp(r'\s+'), '');
    if (collapsed.isNotEmpty) out.add(collapsed);
    const prefixes = [
      'spec. case No.',
      'spec. case No',
      'Special Case No.',
      'Special Case No',
      'Civil Case No.',
      'Civil Case No',
      'CRM. No.',
      'Criminal Case No.',
      'Case No.',
      'Case No',
    ];
    var remainder = t;
    for (final p in prefixes) {
      if (remainder.length > p.length &&
          remainder.toLowerCase().startsWith(p.toLowerCase())) {
        remainder = remainder.substring(p.length).trim();
        if (remainder.isNotEmpty) out.add(remainder);
      }
    }
    final nums = RegExp(r'\d{2,}')
        .allMatches(t)
        .map((m) => m.group(0)!)
        .where((n) => n.length >= 2)
        .toSet();
    for (final n in nums) {
      out.add(n);
      for (final prefix in [
        'Case No. $n',
        'Case No $n',
        'spec. case No. $n',
        'spec. case No $n',
        'Special Case No. $n',
        'Civil Case No. $n',
        'CRM. No. $n',
        'Criminal Case No. $n',
      ]) {
        out.add(prefix);
      }
    }
    return out.where((e) => e.isNotEmpty).toList();
  }

  static List<String> _caseNumberQueryVariants(String raw) =>
      caseNumberQueryVariants(raw);

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
      return attorneyCaseMaps.any(
        (c) => _caseMapMatchesHearing(c, caseNo, hearing),
      );
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      unawaited(purgeCourtEmailIngestNotices(uid));
    }
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
    // Web: Cloud Functions + inbox `hearings.limit(100)` fallback — avoid a 500-doc listener that freezes the UI.
    if (kIsWeb) return;

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

    unawaited(syncClientHearingNotifications());

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

  static List<String> _significantNameWords(String raw) {
    const skip = {
      'and',
      'the',
      'sps',
      'heirs',
      'namely',
      'vs',
      'versus',
    };
    return _normalizeCaseRefWhitespace(raw)
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where((w) => w.length >= 3 && !skip.contains(w))
        .toList();
  }

  static bool _partyMatchesStoredName(String stored, String party) {
    if (_namesMatchForClient(stored, party)) return true;
    final storedNorm = _normalizeCaseRefWhitespace(stored);
    final partyNorm = _normalizeCaseRefWhitespace(party);
    if (storedNorm.toLowerCase() == partyNorm.toLowerCase()) return true;
    final storedWords = _significantNameWords(stored);
    final partyWords = _significantNameWords(party);
    if (partyWords.length >= 2 &&
        partyWords.every((w) => storedNorm.toLowerCase().contains(w))) {
      return true;
    }
    if (storedWords.length >= 2 &&
        storedWords.every((w) => partyNorm.toLowerCase().contains(w))) {
      return true;
    }
    if (partyWords.length >= 2 &&
        storedWords.length >= 2 &&
        partyWords.first == storedWords.first &&
        partyWords.last == storedWords.last) {
      return true;
    }
    return false;
  }

  static bool _namesPartialMatchForClient(
    String stored,
    String hearingClientName,
  ) {
    if (_partyMatchesStoredName(stored, hearingClientName)) return true;
    for (final party in HearingCalendarFields.splitHearingPartyNames(
      hearingClientName,
    )) {
      if (_partyMatchesStoredName(stored, party)) return true;
    }
    return false;
  }

  static String _hearingClientNameBlob(Map<String, dynamic> d) {
    final parts = <String>[];
    void add(String? s) {
      final t = s?.trim() ?? '';
      if (t.isEmpty) return;
      if (parts.any((e) => e.toLowerCase() == t.toLowerCase())) return;
      parts.add(t);
    }

    add(d['clientName'] as String?);
    for (final key in ['involvedPartyNames', 'involvedParties']) {
      final raw = d[key];
      if (raw is List) {
        for (final e in raw) {
          add(e?.toString());
        }
      }
    }
    return parts.join(', ');
  }

  /// Resolve client user IDs from [d]['clientName'] (each party, not the whole blob).
  Future<Set<String>> _resolveClientUidsFromHearingName(
    Map<String, dynamic> d,
  ) async {
    final clientName = _hearingClientNameBlob(d);
    if (clientName.isEmpty) return {};

    final matched = <String>{};
    final parties = HearingCalendarFields.splitHearingPartyNames(clientName);
    final queryNames = parties.isEmpty ? [clientName] : parties;

    for (final party in queryNames.take(12)) {
      final nameKeys = _clientNameMatchVariants(party);
      for (final field in ['fullName', 'name', 'displayName']) {
        for (final nm in nameKeys.take(6)) {
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
    }

    try {
      final cq = await _db
          .collection('users')
          .where('role', isEqualTo: 'client')
          .limit(250)
          .get();
      for (final u in cq.docs) {
        if (matched.contains(u.id)) continue;
        if (hearingDocMatchesClientProfile(d, u.data())) {
          matched.add(u.id);
        }
      }
    } catch (_) {}

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

  static const _devicePushPrefsKey = 'hearing_device_push_ids_v1';
  final Set<String> _devicePushQueued = <String>{};

  /// The server skips a second import of the same case, so the row can show
  /// with no phone push. Queue FCM when no notification was written.
  Future<void> queueDevicePushIfMissing(
    String hearingId,
    Map<String, dynamic> hearingData,
  ) async {
    final id = hearingId.trim();
    if (id.isEmpty || !isDisplayableHearingRow(hearingData)) return;
    if (!_devicePushQueued.add(id)) return;

    final created = hearingData['createdAt'] is Timestamp
        ? (hearingData['createdAt'] as Timestamp).toDate()
        : DateTime.tryParse('${hearingData['createdAt'] ?? ''}');
    final age = created == null
        ? const Duration(hours: 1)
        : DateTime.now().difference(created);
    if (age > const Duration(hours: 12)) return;
    if (age < const Duration(seconds: 70)) {
      _devicePushQueued.remove(id);
      unawaited(
        Future<void>.delayed(const Duration(seconds: 70) - age, () {
          return queueDevicePushIfMissing(id, hearingData);
        }),
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final sent = prefs.getStringList(_devicePushPrefsKey) ?? <String>[];
      if (sent.contains(id)) return;

      final existing = await _db
          .collection('notifications')
          .where('hearingDocId', isEqualTo: id)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        sent.insert(0, id);
        await prefs.setStringList(
          _devicePushPrefsKey,
          sent.length > 200 ? sent.sublist(0, 200) : sent,
        );
        return;
      }

      final caseNo = HearingCalendarFields.asDisplayString(hearingData['caseNo']);
      final title = caseNo.isNotEmpty
          ? 'Court hearing / order — $caseNo'
          : 'Court hearing / order';
      final body = HearingCalendarFields.pushHearingContext(hearingData);
      final fcm = FCMService();
      final ids = <String>{};
      for (final role in const ['attorney', 'staff']) {
        try {
          final q = await _db
              .collection('users')
              .where('role', isEqualTo: role)
              .limit(40)
              .get();
          for (final doc in q.docs) {
            if (doc.data()['isActive'] == false) continue;
            ids.add(doc.id);
          }
        } catch (_) {}
      }
      for (final uid in ids) {
        await fcm.sendNotificationToUser(
          userId: uid,
          title: title,
          body: body.isEmpty ? title : body,
          data: {
            'type': 'hearing_activity',
            'hearingDocId': id,
            'caseNo': caseNo,
          },
        );
      }
      sent.insert(0, id);
      await prefs.setStringList(
        _devicePushPrefsKey,
        sent.length > 200 ? sent.sublist(0, 200) : sent,
      );
    } catch (e) {
      _devicePushQueued.remove(id);
      if (kDebugMode) {
        _fanoutLog('HearingNotificationFanout device push $id: $e');
      }
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
    if (HearingCalendarFields.isNonCourtHearingSpam(d)) return false;
    final source = '${d['source'] ?? ''}'.toLowerCase();
    final activity = '${d['activityType'] ?? ''}'.trim().toLowerCase();
    if (source == 'n8n' || activity == 'court_import') return true;
    final cn = HearingCalendarFields.asDisplayString(d['caseNo']);
    final ft = HearingCalendarFields.asDisplayString(d['fullText']);
    final msg = HearingCalendarFields.asDisplayString(d['message']);
    final summary = HearingCalendarFields.asDisplayString(d['summary']);
    final caseId = HearingCalendarFields.asDisplayString(d['caseId']);
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

    if (FirebaseAuth.instance.currentUser?.uid != userId) {
      try {
        final ok = await _waitForInboxAuth(userId)
            .timeout(const Duration(seconds: 2), onTimeout: () => false);
        if (!ok) return docs;
      } catch (_) {
        return docs;
      }
    }

    void addDocs(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> add) {
      for (final d in add) {
        final data = d.data();
        if (hearingsOnly) {
          final type = (data['type'] as String? ?? '').toLowerCase();
          if (type == 'court_email_ingest') continue;
          if (type.startsWith('court_') && !type.contains('hearing')) continue;
          final queue =
              ((data['queueDocId'] ?? data['queuedDocId']) as String? ?? '')
                  .toLowerCase();
          if (queue.contains('imap')) continue;
        } else if (clientCourtEmailSpamNotification(data)) {
          continue;
        }
        if (seen.add(d.id)) docs.add(d);
      }
    }

    Future<void> takeQuery(Query<Map<String, dynamic>> query) async {
      try {
        QuerySnapshot<Map<String, dynamic>> snap;
        try {
          snap = await query
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 1));
          if (snap.docs.isEmpty) {
            snap = await query.get().timeout(const Duration(seconds: 1));
          }
        } catch (_) {
          snap = await query.get().timeout(const Duration(seconds: 1));
        }
        addDocs(snap.docs);
      } catch (e) {
        if (kDebugMode) _fanoutLog('inbox notifications query: $e');
      }
    }

    Future<void> take(String field) {
      return takeQuery(
        _db
            .collection('notifications')
            .where(field, isEqualTo: userId)
            .limit(30),
      );
    }

    Future<void> takeTyped(String field, String type) {
      return takeQuery(
        _db
            .collection('notifications')
            .where(field, isEqualTo: userId)
            .where('type', isEqualTo: type)
            .limit(30),
      );
    }

    // Client hearings inbox: one query at a time (concurrent Firestore ANRs Android).
    if (hearingsOnly) {
      await take('userId');
      bool hasHearing() => docs.any((d) {
        final type = (d.data()['type'] as String? ?? '').toLowerCase();
        return clientHearingInboxType(type);
      });
      if (!hasHearing()) {
        await takeTyped('userId', 'hearing_activity');
      }
      if (!hasHearing() && !kIsWeb) {
        await take('clientId');
      }
      return docs;
    }

    try {
      await Future.wait<void>([
        take('userId'),
        if (!kIsWeb) take('clientId'),
      ]).timeout(const Duration(seconds: 1), onTimeout: () => <void>[]);
    } catch (e) {
      if (kDebugMode) _fanoutLog('inbox notifications wait: $e');
    }

    if (kIsWeb) {
      return docs;
    }

    // Extra per-type queries only when the broad query likely missed rows.
    if (docs.length < 60) {
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
                .limit(40)
                .get()
                .timeout(const Duration(seconds: 4));
          } catch (e) {
            if (kDebugMode) _fanoutLog('inbox notifications type=$type: $e');
            return null;
          }
        }),
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () => const <QuerySnapshot<Map<String, dynamic>>?>[],
      );
      for (final snap in typeSnaps) {
        if (snap != null) addDocs(snap.docs);
      }
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
      if (_isPermissionDenied(e)) return null;
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
    final hearingClient = _hearingClientNameBlob(hearingData);
    if (hearingClient.isEmpty) return false;
    for (final field in ['fullName', 'name', 'displayName']) {
      final stored = (userData[field] as String?)?.trim() ?? '';
      if (stored.isNotEmpty &&
          _namesPartialMatchForClient(stored, hearingClient)) {
        return true;
      }
    }
    final first = (userData['firstName'] as String?)?.trim() ?? '';
    final last = (userData['lastName'] as String?)?.trim() ?? '';
    if (first.isNotEmpty &&
        last.isNotEmpty &&
        _namesPartialMatchForClient('$first $last', hearingClient)) {
      return true;
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
    if (isHearingRecordUpdateNotification(data)) return true;

    final title = (data['title'] as String? ?? '').toLowerCase().trim();
    final type = (data['type'] as String? ?? '').toLowerCase();
    final hid = (data['hearingDocId'] as String?)?.trim() ?? '';

    // Real court hearing rows (with hearing doc link) — repair title, do not delete.
    if (hid.isNotEmpty && type == 'hearing_activity') {
      return false;
    }

    if (clientCourtEmailSpamNotification(data)) return true;

    if (_isWrongClientCourtNoticeTitle(title)) return true;

    // hearing_activity noise without a linked hearing doc.
    if (type == 'hearing_activity' && hid.isEmpty) {
      return true;
    }

    if (type == 'hearing_activity') {
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

    await HybridDatastore.set(
      collection: 'notifications',
      id: nid,
      data: payload,
      options: SetOptions(merge: true),
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

  /// Same as [purgeClientCourtEmailNotices] — works for client, staff, and attorney.
  Future<int> purgeCourtEmailIngestNotices(String uid) =>
      purgeClientCourtEmailNotices(uid);

  /// Deletes BlastTV / voucher / "[AI] Hearing (eating)" junk from inbox sources.
  Future<int> purgeNonCourtHearingSpam(String uid) async {
    if (uid.isEmpty) return 0;
    if (_spamPurgedUids.contains(uid)) return 0;
    _spamPurgedUids.add(uid);
    var deleted = 0;

    try {
      Future<QuerySnapshot<Map<String, dynamic>>?> safeGet(
        Future<QuerySnapshot<Map<String, dynamic>>> future,
      ) {
        return future
            .then<QuerySnapshot<Map<String, dynamic>>?>((s) => s)
            .catchError((_) => null);
      }

      final snaps = await Future.wait([
        safeGet(
          _db
              .collection('notifications')
              .where('userId', isEqualTo: uid)
              .limit(80)
              .get(),
        ),
        safeGet(
          _db
              .collection('calendar_events')
              .where('assignedTo', isEqualTo: uid)
              .limit(40)
              .get(),
        ),
        safeGet(
          _db
              .collection('hearing_notifications')
              .where('attorneyId', isEqualTo: uid)
              .limit(40)
              .get(),
        ),
        safeGet(
          _db
              .collection('activity_logs')
              .where('userId', isEqualTo: uid)
              .limit(80)
              .get(),
        ),
        safeGet(
          _db
              .collection('hearings')
              .where('attorneyUid', isEqualTo: uid)
              .limit(40)
              .get(),
        ),
      ]);
      final refs = <DocumentReference<Map<String, dynamic>>>[];
      for (final snap in snaps) {
        if (snap == null) continue;
        for (final doc in snap.docs) {
          final data = doc.data();
          final junk = doc.reference.parent.id == 'activity_logs'
              ? HearingCalendarFields.isJunkWorkLog(data)
              : HearingCalendarFields.isNonCourtHearingSpam(data);
          if (junk) {
            refs.add(doc.reference);
          }
        }
      }
      for (var i = 0; i < refs.length; i += 400) {
        final batch = _db.batch();
        final chunk = refs.skip(i).take(400);
        for (final ref in chunk) {
          batch.delete(ref);
          deleted++;
        }
        await batch.commit();
      }
    } catch (e) {
      if (kDebugMode) _fanoutLog('purgeNonCourtHearingSpam: $e');
      _spamPurgedUids.remove(uid);
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

  Future<void> _ensureClientHearingsLimited(
    Iterable<DocumentSnapshot<Map<String, dynamic>>> docs,
    Set<String> seenHearingIds, {
    Future<void> Function(DocumentSnapshot<Map<String, dynamic>> doc)? before,
  }) async {
    final pending = <Future<void>>[];
    for (final doc in docs) {
      if (!seenHearingIds.add(doc.id)) continue;
      pending.add(() async {
        if (before != null) await before(doc);
        await ensureClientHearingNotification(
          doc,
          trustClientNameMatch: true,
        );
      }());
      if (pending.length >= 4) {
        await Future.wait(pending);
        pending.clear();
      }
    }
    if (pending.isNotEmpty) await Future.wait(pending);
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
        options: HttpsCallableOptions(timeout: const Duration(seconds: 8)),
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

      unawaited(purgeClientCourtEmailNotices(uid));
      unawaited(_syncClientHearingsViaCloudFunction());

      final seenHearingIds = <String>{};

      await _syncClientHearingsFromNotificationRefs(uid, seenHearingIds);

      try {
        final linkedSnaps = await Future.wait([
          _db
              .collection('hearings')
              .where('ownerClientId', isEqualTo: uid)
              .limit(40)
              .get(),
          _db
              .collection('hearings')
              .where('involvedClientIds', arrayContains: uid)
              .limit(40)
              .get(),
          _db
              .collection('hearings')
              .where('matchedClientIds', arrayContains: uid)
              .limit(40)
              .get(),
        ]);
        await _ensureClientHearingsLimited(
          linkedSnaps.expand((s) => s.docs),
          seenHearingIds,
        );
      } catch (e) {
        if (kDebugMode) _fanoutLog('syncClientHearings linked: $e');
      }

      // Firestore-secure: only query clientName values copied from the profile.
      for (final nm in _clientNameFirestoreQueryVariants(ud).take(3)) {
        try {
          final q = await _db
              .collection('hearings')
              .where('clientName', isEqualTo: nm)
              .limit(20)
              .get();
          await _ensureClientHearingsLimited(q.docs, seenHearingIds);
        } catch (e) {
          if (kDebugMode) {
            _fanoutLog('syncClientHearings clientName=$nm: $e');
          }
        }
      }

      try {
        final cases = await _db
            .collection('cases')
            .where('clientId', isEqualTo: uid)
            .limit(15)
            .get();
        for (final c in cases.docs) {
          try {
            final byCaseId = await _db
                .collection('hearings')
                .where('caseId', isEqualTo: c.id)
                .limit(20)
                .get();
            await _ensureClientHearingsLimited(
              byCaseId.docs,
              seenHearingIds,
              before: (h) => _linkHearingToClients(
                h.reference,
                {uid},
                caseId: c.id,
                firmMaySetCaseId: true,
              ),
            );
          } catch (_) {}

          final m = c.data();
          for (final field in ['caseNumber', 'caseNo']) {
            final cn = (m[field] as String?)?.trim() ?? '';
            if (cn.isEmpty) continue;
            try {
              final hq = await _db
                  .collection('hearings')
                  .where('caseNo', isEqualTo: cn)
                  .limit(10)
                  .get();
              await _ensureClientHearingsLimited(hq.docs, seenHearingIds);
            } catch (_) {}
          }
        }
      } catch (e) {
        if (kDebugMode) _fanoutLog('syncClientHearings by case: $e');
      }

      unawaited(_normalizeClientHearingNotificationRows(uid));
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
        _db
            .collection('notifications')
            .where('userId', isEqualTo: uid)
            .limit(80)
            .get(),
        _db
            .collection('notifications')
            .where('clientId', isEqualTo: uid)
            .limit(80)
            .get(),
      ]);
      final pending = <Future<void>>[];
      for (final snap in snaps) {
        for (final n in snap.docs) {
          if (!seenNotifIds.add(n.id)) continue;
          final data = n.data();
          final hid = _hearingIdFromNotificationDoc(n.id, data);
          if (hid == null || !seenHearingIds.add(hid)) continue;
          final type = (data['type'] as String? ?? '').toLowerCase();
          final caseNo = (data['caseNo'] as String?)?.trim() ?? '';
          final title = (data['title'] as String?)?.trim() ?? '';
          if (clientHearingInboxType(type) &&
              caseNo.isNotEmpty &&
              title.isNotEmpty &&
              !_clientHearingTitleNeedsRepair(title, data)) {
            continue;
          }
          pending.add(() async {
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
          }());
          if (pending.length >= 4) {
            await Future.wait(pending);
            pending.clear();
          }
        }
      }
      if (pending.isNotEmpty) await Future.wait(pending);
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

  /// Writes in-app rows for every registered client named on these hearings.
  Future<void> publishMatchedClientInboxForHearings(
    Iterable<DocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    var n = 0;
    for (final doc in docs) {
      if (n >= 25) break;
      if (!doc.exists) continue;
      await _publishMatchedClientInbox(doc);
      n++;
    }
  }

  Future<void> _publishMatchedClientInbox(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (!doc.exists || doc.id.isEmpty) return;
    if (!_webClientPublishedHearingIds.add(doc.id)) return;
    final d = doc.data();
    if (d == null) {
      _webClientPublishedHearingIds.remove(doc.id);
      return;
    }
    if (HearingCalendarFields.isNonCourtHearingSpam(d) ||
        !isDisplayableHearingRow(d)) {
      return;
    }

    try {
      final uids = await _resolveClientUidsFromHearingName(d);
      if (uids.isEmpty) return;
      for (final uid in uids) {
        try {
          final nid = 'hearing_inapp_${doc.id}_$uid';
          final existing = await _db.collection('notifications').doc(nid).get();
          await _writeClientHearingNotificationPayload(
            uid,
            doc.id,
            d,
            docExists: existing.exists,
            wasRead: existing.exists && _notificationWasRead(existing.data()),
          );
        } catch (e) {
          if (kDebugMode) {
            _fanoutLog('_publishMatchedClientInbox $uid: $e');
          }
        }
      }
      await _linkHearingToClients(
        doc.reference,
        uids,
        firmMaySetCaseId: true,
      );
      final parties = HearingCalendarFields.splitHearingPartyNames(
        _hearingClientNameBlob(d),
      );
      if (parties.isNotEmpty) {
        try {
          await doc.reference.set(
            {'involvedPartyNames': FieldValue.arrayUnion(parties)},
            SetOptions(merge: true),
          );
        } catch (_) {}
      }
    } catch (e) {
      _webClientPublishedHearingIds.remove(doc.id);
      if (kDebugMode) _fanoutLog('_publishMatchedClientInbox: $e');
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
    if (HearingCalendarFields.isNonCourtHearingSpam(d)) return;

    // Web firm inbox: skip the heavy fan-out, but still write client inbox
    // rows and send SMS. Push is already sent by the Cloud Function.
    if (kIsWeb && !clientScoped) {
      await _publishMatchedClientInbox(doc);
      unawaited(
        HearingSmsAlertService.instance.sendAlertsForHearing(
          hearingDocId: doc.id,
          hearingData: d,
          recipientUserIds: const [],
        ),
      );
      return;
    }

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
      final chunk = recipientList.skip(i).take(400).toList();
      final docs = <String, Map<String, dynamic>>{
        for (final uid in chunk)
          'hearing_inapp_${doc.id}_$uid': payloadFor(uid),
      };
      try {
        final result = await HybridDatastore.setManyMerge(
          collection: 'notifications',
          docs: docs,
        );
        if (result.isSuccess) {
          wroteAny = true;
        } else if (_isPermissionDenied(result.firestoreError ?? '')) {
          if (kDebugMode) {
            _fanoutLog(
              'HearingNotificationFanout: batch permission-denied; '
              'will still attempt PhilSMS.',
            );
          }
        } else {
          if (kDebugMode) {
            _fanoutLog(
              'HearingNotificationFanout batch write failed: '
              '${result.failureMessage}',
            );
          }
          for (final uid in chunk) {
            try {
              final nid = 'hearing_inapp_${doc.id}_$uid';
              final single = await HybridDatastore.set(
                collection: 'notifications',
                id: nid,
                data: payloadFor(uid),
                options: SetOptions(merge: true),
              );
              if (single.isSuccess) wroteAny = true;
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
      } catch (e) {
        if (_isPermissionDenied(e)) {
          if (kDebugMode) {
            _fanoutLog(
              'HearingNotificationFanout: batch permission-denied; '
              'will still attempt PhilSMS.',
            );
          }
        } else if (kDebugMode) {
          _fanoutLog('HearingNotificationFanout batch write failed: $e');
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

    unawaited(
      HearingSmsAlertService.instance.sendAlertsForHearing(
        hearingDocId: doc.id,
        hearingData: d,
        recipientUserIds: recipientList,
        title: title,
        body: body,
        summary: summary,
        caseLabel: caseLabel,
      ),
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
      if (isHearingRecordUpdateNotification(data)) continue;
      if (hearingsOnly) {
        // Keep real hearing rows even when hearingDocId is missing.
        // The old spam rule emptied the client bell.
        if (isOutOfSystemPumpedNotice(data)) continue;
        final rawType = (data['type'] as String? ?? '').toLowerCase();
        if (rawType == 'court_email_ingest') continue;
        if (rawType.startsWith('court_') && !rawType.contains('hearing')) {
          continue;
        }
        final queue =
            ((data['queueDocId'] ?? data['queuedDocId']) as String? ?? '')
                .toLowerCase();
        if (queue.contains('imap')) continue;
      } else if (HearingCalendarFields.isNonCourtHearingSpam(data)) {
        continue;
      }
      final type = data['type'] as String? ?? '';
      if (!allNotificationTypes) {
        if (hearingsOnly) {
          if (!clientHearingInboxType(type)) continue;
        } else if (!hearingOrAppointmentBellType(type)) {
          continue;
        }
      }
      final hid = _hearingIdFromNotificationDoc(doc.id, data);

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

      if (hearingsOnly &&
          clientHearingInboxType(type) &&
          type.toLowerCase().contains('hearing')) {
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
      if (hid != null) coveredHearingIds.add(hid);
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
    String? inboxRowKey,
    Map<String, dynamic>? rowData,
  }) async {
    final data = rowData ?? {};
    final hearingDocId = (data['hearingDocId'] as String?)?.trim();
    final key = (inboxRowKey ?? notificationDocId)?.trim();
    if (key != null && key.isNotEmpty) {
      unawaited(_addReadHearingId(userId, key));
    }
    if (hearingDocId != null && hearingDocId.isNotEmpty) {
      unawaited(_addReadHearingId(userId, hearingDocId));
    }
    _markCachedInboxRead(
      userId,
      rowKey: key,
      notificationDocId: notificationDocId,
      hearingDocId: hearingDocId,
    );

    if (notificationDocId != null && notificationDocId.isNotEmpty) {
      final readPatch = <String, dynamic>{
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      };
      final result = await HybridDatastore.update(
        collection: 'notifications',
        id: notificationDocId,
        patch: readPatch,
      );
      if (!result.isSuccess && kDebugMode) {
        _fanoutLog(
          'markInboxRowAsRead notification: ${result.failureMessage}',
        );
      }
      if (hearingDocId == null || hearingDocId.isEmpty) return;
    }

    if (hearingDocId == null || hearingDocId.isEmpty) return;

    await _addReadHearingId(userId, hearingDocId);

    final nid = 'hearing_inapp_${hearingDocId}_$userId';
    try {
      final readPayload = <String, dynamic>{
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
      };
      await HybridDatastore.set(
        collection: 'notifications',
        id: nid,
        data: readPayload,
        options: SetOptions(merge: true),
      );
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
    _markCachedInboxRead(userId, all: true);
    final cached = peekInboxRows(
      userId,
      allNotificationTypes: allNotificationTypes,
      includeGlobalHearingsFallback: includeGlobalHearingsFallback,
      hearingsOnly: hearingsOnly,
    );
    var source = cached;
    if (source == null || source.isEmpty) {
      for (final bundle in _hearingInboxBundles.values) {
        if (bundle.userId != userId) continue;
        final rows = bundle.lastRows;
        if (rows != null && rows.isNotEmpty) {
          source = rows;
          break;
        }
      }
    }
    if (source != null) {
      final persist = <String>{};
      for (final row in source) {
        persist.add(row.rowKey);
        final hid = (row.data['hearingDocId'] as String?)?.trim() ?? '';
        if (hid.isNotEmpty) persist.add(hid);
        final nid = row.notificationDocId?.trim() ?? '';
        if (nid.isNotEmpty) persist.add(nid);
      }
      await _addReadHearingIds(userId, persist);
      if (includeGlobalHearingsFallback && !hearingsOnly) {
        await _writeAttorneyHearingReadReceipts(userId, source);
      }
    }

    if (includeGlobalHearingsFallback && !hearingsOnly) {
      await saveAttorneyInboxAck(userId);
    }

    try {
      final notifSnaps = <QuerySnapshot<Map<String, dynamic>>>[];
      try {
        notifSnaps.add(
          await _db
              .collection('notifications')
              .where('userId', isEqualTo: userId)
              .where('isRead', isEqualTo: false)
              .limit(200)
              .get(),
        );
      } catch (_) {}
      if (includeGlobalHearingsFallback && !hearingsOnly) {
        try {
          notifSnaps.add(
            await _db
                .collection('notifications')
                .where('attorneyId', isEqualTo: userId)
                .where('isRead', isEqualTo: false)
                .limit(200)
                .get(),
          );
        } catch (_) {
          try {
            notifSnaps.add(
              await _db
                  .collection('notifications')
                  .where('attorneyId', isEqualTo: userId)
                  .limit(200)
                  .get(),
            );
          } catch (_) {}
        }
      }

      final batch = _db.batch();
      var pending = 0;
      final seen = <String>{};
      final markedDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final snap in notifSnaps) {
        for (final doc in snap.docs) {
          if (!seen.add(doc.id)) continue;
          if (doc.data()['isRead'] == true) continue;
          final type = doc.data()['type'] as String? ?? '';
          if (type == 'attorney_inbox_ack') continue;
          if (!allNotificationTypes) {
            if (hearingsOnly) {
              if (!clientHearingInboxType(type)) continue;
            } else if (!hearingOrAppointmentBellType(type) &&
                !type.contains('hearing')) {
              continue;
            }
          }
          batch.update(doc.reference, {
            'isRead': true,
            'readAt': FieldValue.serverTimestamp(),
          });
          markedDocs.add(doc);
          pending++;
        }
      }
      if (pending > 0) await batch.commit();

      if (includeGlobalHearingsFallback && !kIsWeb) {
        final hearings = await _hearingsSnapshotForInbox();
        if (hearings == null) {
          if (includeGlobalHearingsFallback && !hearingsOnly) {
            _setBellCount(userId, 0);
          }
          return;
        }

        final readIds =
            _readHearingIdsMem[userId] ??
            await _getReadHearingIdsFromPrefs(userId);
        _readHearingIdsMem[userId] = readIds;
        final covered = <String>{};
        for (final doc in markedDocs) {
          final hid = _hearingIdFromNotificationDoc(doc.id, doc.data());
          if (hid != null) covered.add(hid);
        }

        for (final hDoc in hearings.docs) {
          if (covered.contains(hDoc.id)) continue;
          final hd = hDoc.data();
          if (!isDisplayableHearingRow(hd)) continue;
          readIds.add(hDoc.id);
        }

        final prefs = await SharedPreferences.getInstance();
        final key = _inboxReadHearingsKey(userId);
        final list = readIds.toList();
        final trimmed = list.length > _maxReadHearingIds
            ? list.sublist(0, _maxReadHearingIds)
            : list;
        await prefs.setStringList(key, trimmed);
      } else if (includeGlobalHearingsFallback && kIsWeb) {
        final hearings = await _hearingsSnapshotForInbox(forUserId: userId);
        final readIds =
            _readHearingIdsMem[userId] ??
            await _getReadHearingIdsFromPrefs(userId);
        for (final hDoc in hearings?.docs ?? const []) {
          if (isDisplayableHearingRow(hDoc.data())) readIds.add(hDoc.id);
        }
        _readHearingIdsMem[userId] = readIds;
        final prefs = await SharedPreferences.getInstance();
        final list = readIds.toList();
        final trimmed = list.length > _maxReadHearingIds
            ? list.sublist(0, _maxReadHearingIds)
            : list;
        await prefs.setStringList(_inboxReadHearingsKey(userId), trimmed);
      }
    } catch (e) {
      if (kDebugMode) _fanoutLog('markAllInboxRowsRead: $e');
    }
    if (includeGlobalHearingsFallback && !hearingsOnly) {
      _setBellCount(userId, 0);
    } else {
      _scheduleInboxRefreshForUser(userId);
    }
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
        if (isHearingRecordUpdateNotification(doc.data())) continue;
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

  /// Attorney Reminders: own notifications + firm hearings + legacy
  /// `hearing_notifications`. Does not use the client email-spam filter
  /// (that filter hid real attorney hearing/appointment rows).
  Future<List<HearingInboxRow>> fetchAttorneyInboxRowsOnce(
    String userId, {
    bool attachListeners = false,
    bool fetchGlobalHearings = true,
    bool reuseCachedHearings = false,
  }) async {
    if (userId.isEmpty) return const [];
    if (reuseCachedHearings && isAttorneyInboxFresh(userId)) {
      final cached = peekInboxRows(
        userId,
        includeGlobalHearingsFallback: true,
      );
      if (cached != null) return cached;
    }
    await loadAttorneyInboxAck(userId);
    await _ensureReadHearingIdsLoaded(userId);
    final bundle = _inboxBundle(
      userId,
      includeGlobalHearingsFallback: true,
    );

    final notifFuture = _attorneyNotificationDocs(userId);

    final Future<QuerySnapshot<Map<String, dynamic>>?> hearingsFuture;
    if (fetchGlobalHearings) {
      hearingsFuture = _db
          .collection('hearings')
          .orderBy('createdAt', descending: true)
          .limit(80)
          .get()
          .timeout(const Duration(seconds: 4))
          .then<QuerySnapshot<Map<String, dynamic>>?>((s) => s)
          .catchError((_) => _db
              .collection('hearings')
              .limit(80)
              .get()
              .timeout(const Duration(seconds: 4))
              .then<QuerySnapshot<Map<String, dynamic>>?>((s) => s)
              .catchError((_) => null));
    } else if (reuseCachedHearings) {
      hearingsFuture = Future.value(bundle.lastHearingsSnapshot);
    } else {
      hearingsFuture = Future.value(null);
    }

    final legacyFuture = _db
        .collection('hearing_notifications')
        .where('attorneyId', isEqualTo: userId)
        .limit(40)
        .get()
        .then<QuerySnapshot<Map<String, dynamic>>?>((s) => s)
        .catchError((_) => null);

    List<QueryDocumentSnapshot<Map<String, dynamic>>> notifDocs =
        const [];
    QuerySnapshot<Map<String, dynamic>>? hearings;
    QuerySnapshot<Map<String, dynamic>>? legacy;
    try {
      final packed = await Future.wait<Object?>([
        notifFuture,
        hearingsFuture,
        legacyFuture,
      ]).timeout(const Duration(seconds: 5));
      notifDocs = (packed[0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>?) ??
          const [];
      hearings = packed[1] as QuerySnapshot<Map<String, dynamic>>?;
      legacy = packed[2] as QuerySnapshot<Map<String, dynamic>>?;
    } catch (_) {}

    final rows = buildInboxRowsFromSnapshots(
      notifDocs,
      hearings?.docs ?? const [],
      allNotificationTypes: true,
      readHearingIds: _readHearingIdsMem[userId] ?? const {},
    );

    final keys = rows.map((r) => r.rowKey).toSet();
    if (legacy != null) {
      for (final doc in legacy.docs) {
        final row = _rowFromHearingNotificationDoc(doc);
        if (row != null && keys.add(row.rowKey)) {
          rows.add(row);
        }
      }
    }
    rows.sort((a, b) => b.sortTime.compareTo(a.sortTime));
    final readIds = _readHearingIdsMem[userId] ?? const <String>{};
    final flagged = rows
        .map((r) => _rowWithReadFlag(r, readIds, userId: userId))
        .toList();

    bundle.seedRows(
      flagged,
      hearingsSnapshot: hearings,
      attachListeners: attachListeners && !kIsWeb,
    );
    _cacheBellCount(userId, flagged);
    _markInboxFresh(userId);
    return flagged;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _attorneyNotificationDocs(String userId) async {
    try {
      final seen = <String>{};
      final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      Future<void> take(Query<Map<String, dynamic>> q) async {
        try {
          QuerySnapshot<Map<String, dynamic>> snap;
          try {
            snap = await q
                .limit(40)
                .get(const GetOptions(source: Source.cache))
                .timeout(const Duration(milliseconds: 500));
            if (snap.docs.isEmpty) {
              snap = await q
                  .limit(40)
                  .get()
                  .timeout(const Duration(seconds: 1));
            }
          } catch (_) {
            return;
          }
          for (final doc in snap.docs) {
            if (!seen.add(doc.id)) continue;
            final data = doc.data();
            final type = (data['type'] as String? ?? '').toLowerCase();
            if (type == 'attorney_inbox_ack' ||
                type == 'attorney_read_keys') {
              continue;
            }
            if (type == 'court_email_ingest') continue;
            if (type.startsWith('court_') && !type.contains('hearing')) {
              continue;
            }
            docs.add(doc);
          }
        } catch (_) {}
      }

      await take(
        _db.collection('notifications').where('userId', isEqualTo: userId),
      );
      await take(
        _db.collection('notifications').where('attorneyId', isEqualTo: userId),
      );
      return docs;
    } catch (e) {
      if (kDebugMode) _fanoutLog('attorney notifications: $e');
      return const [];
    }
  }

  HearingInboxRow? _rowFromHearingNotificationDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (HearingCalendarFields.isNonCourtHearingSpam(data)) return null;
    final title = (data['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return null;
    final created = (data['createdAt'] as Timestamp?)?.toDate() ??
        (data['notificationDate'] as Timestamp?)?.toDate() ??
        (data['hearingDate'] as Timestamp?)?.toDate() ??
        DateTime.now();
    final desc = (data['description'] as String?)?.trim() ?? '';
    final eventType = (data['eventType'] as String?)?.trim().toLowerCase() ??
        'hearing';
    return HearingInboxRow(
      rowKey: 'hn_${doc.id}',
      notificationDocId: null,
      data: {
        'type': eventType.contains('hearing') ? 'hearing' : eventType,
        'title': title,
        'message': desc,
        'summary': desc,
        'isRead': data['status'] == 'sent',
        'createdAt': Timestamp.fromDate(created),
        if (data['caseId'] != null) 'caseId': data['caseId'],
      },
      sortTime: created,
    );
  }

  HearingInboxRow? _rowFromCalendarEventDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required Set<String> readHearingIds,
  }) {
    final data = doc.data();
    if (HearingCalendarFields.isNonCourtHearingSpam(data)) return null;
    final title = (data['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return null;
    DateTime when = DateTime.now();
    final rawWhen = data['eventDate'] ?? data['createdAt'];
    if (rawWhen is Timestamp) {
      when = rawWhen.toDate();
    } else if (rawWhen is DateTime) {
      when = rawWhen;
    }
    final desc = (data['description'] as String?)?.trim() ?? '';
    final hid = (data['hearingDocId'] as String?)?.trim() ?? '';
    return HearingInboxRow(
      rowKey: 'cal_${doc.id}',
      notificationDocId: null,
      data: {
        'type': 'calendar_reminder',
        'title': title,
        'message': desc,
        'summary': desc,
        'isRead': hid.isNotEmpty && readHearingIds.contains(hid),
        'createdAt': Timestamp.fromDate(when),
        if (hid.isNotEmpty) 'hearingDocId': hid,
      },
      sortTime: when,
    );
  }

  /// One-shot load for reminders screen (shows data even before snapshot listeners fire).
  Future<List<HearingInboxRow>> fetchInboxRowsOnce(
    String userId, {
    bool allNotificationTypes = false,
    bool includeGlobalHearingsFallback = true,
    bool hearingsOnly = false,
    bool attachListeners = false,
    bool fetchGlobalHearings = true,
    bool reuseCachedHearings = false,
  }) async {
    if (includeGlobalHearingsFallback && !hearingsOnly) {
      return fetchAttorneyInboxRowsOnce(
        userId,
        attachListeners: attachListeners,
        fetchGlobalHearings: fetchGlobalHearings,
        reuseCachedHearings: reuseCachedHearings,
      );
    }

    await _ensureReadHearingIdsLoaded(userId);
    final bundle = _inboxBundle(
      userId,
      allNotificationTypes: allNotificationTypes,
      includeGlobalHearingsFallback: includeGlobalHearingsFallback,
      hearingsOnly: hearingsOnly,
    );

    final notifDocs = await _notificationDocsForInbox(
      userId,
      hearingsOnly: hearingsOnly,
    );
    await Future<void>.delayed(Duration.zero);

    QuerySnapshot<Map<String, dynamic>>? hearings;
    if (includeGlobalHearingsFallback &&
        await _canUseGlobalHearingsInbox(userId)) {
      if (fetchGlobalHearings) {
        hearings = await _hearingsSnapshotForInbox(forUserId: userId);
      } else if (reuseCachedHearings) {
        hearings = bundle.lastHearingsSnapshot;
      }
    }

    final rows = buildInboxRowsFromSnapshots(
      notifDocs,
      hearings?.docs ?? const [],
      allNotificationTypes: allNotificationTypes,
      hearingsOnly: hearingsOnly,
      readHearingIds: _readHearingIdsMem[userId] ?? const {},
    );

    bundle.seedRows(
      rows,
      hearingsSnapshot: hearings,
      attachListeners: attachListeners && !kIsWeb,
    );

    return rows;
  }

  /// Client reminders: hearing rows from `notifications` only (no global `hearings` scan).
  Future<List<HearingInboxRow>> fetchClientHearingInboxRowsOnce(
    String userId, {
    bool runSync = false,
    bool forceSync = false,
  }) async {
    if (runSync) {
      // Inbox paint must not wait on Cloud Function / name-scan backfill.
      unawaited(syncClientHearingNotifications(force: forceSync));
    }
    unawaited(_ensureReadHearingIdsLoaded(userId));
    List<QueryDocumentSnapshot<Map<String, dynamic>>> notifDocs = const [];
    try {
      notifDocs = await _notificationDocsForInbox(userId, hearingsOnly: true);
    } catch (_) {
      notifDocs = const [];
    }
    final rows = buildInboxRowsFromSnapshots(
      notifDocs,
      const [],
      hearingsOnly: true,
      readHearingIds: _readHearingIdsMem[userId] ?? const {},
    );
    final existing = peekInboxRows(
      userId,
      includeGlobalHearingsFallback: false,
      hearingsOnly: true,
    );
    final toStore = rows.isNotEmpty
        ? rows
        : (existing != null && existing.isNotEmpty ? existing : rows);
    _inboxBundle(
      userId,
      includeGlobalHearingsFallback: false,
      hearingsOnly: true,
    ).seedRows(toStore, hearingsSnapshot: null, attachListeners: false);
    return toStore;
  }

  /// Staff inbox: lightweight notifications query; optional capped hearings scan.
  Future<List<HearingInboxRow>> fetchStaffInboxLight(
    String userId, {
    bool includeGlobalHearings = false,
    int notificationLimit = 60,
    int hearingsLimit = 50,
  }) async {
    if (userId.isEmpty) return const [];

    final readIdsFuture = _ensureReadHearingIdsLoaded(userId);
    final authOk = FirebaseAuth.instance.currentUser?.uid == userId
        ? true
        : await _waitForInboxAuth(userId);
    if (!authOk) {
      await readIdsFuture;
      return peekInboxRows(userId) ?? const [];
    }

    final notifFuture = _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .limit(notificationLimit)
        .get();

    Future<QuerySnapshot<Map<String, dynamic>>?>? hearingsFuture;
    if (includeGlobalHearings && hearingsLimit > 0) {
      hearingsFuture = _db
          .collection('hearings')
          .limit(hearingsLimit)
          .get()
          .then<QuerySnapshot<Map<String, dynamic>>?>((s) => s)
          .catchError((_) => null);
    }

    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
    try {
      final snap = await notifFuture;
      docs = snap.docs;
    } catch (_) {
      await readIdsFuture;
      return peekInboxRows(userId) ?? const [];
    }

    final hearings =
        hearingsFuture != null ? await hearingsFuture : null;
    await readIdsFuture;

    // Yield so the UI can paint between network and heavy row building.
    await Future<void>.delayed(Duration.zero);

    final rows = buildInboxRowsFromSnapshots(
      docs,
      hearings?.docs ?? const [],
      readHearingIds: _readHearingIdsMem[userId] ?? const {},
    );

    _inboxBundle(userId).seedRows(
      rows,
      hearingsSnapshot: hearings,
      attachListeners: false,
    );
    _cacheBellCount(userId, rows);
    return rows;
  }

  /// Read-hearing ids for staff global hearing rows (lightweight).
  Future<Set<String>> staffReadHearingIds(String userId) async {
    await _ensureReadHearingIdsLoaded(userId);
    return Set<String>.from(_readHearingIdsMem[userId] ?? const {});
  }

  /// Extra global hearings for staff inbox — no notification re-fetch, no sibling merge.
  Future<List<HearingInboxRow>> fetchStaffExtraHearingRows(
    String userId, {
    Set<String> coveredHearingIds = const {},
    int hearingsLimit = 25,
  }) async {
    if (userId.isEmpty || hearingsLimit <= 0) return const [];

    final readFuture = _ensureReadHearingIdsLoaded(userId);
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _db.collection('hearings').limit(hearingsLimit).get();
    } catch (_) {
      await readFuture;
      return const [];
    }
    await readFuture;
    await Future<void>.delayed(Duration.zero);

    final readIds = _readHearingIdsMem[userId] ?? const {};
    return buildGlobalHearingRowsLight(
      snap.docs,
      coveredHearingIds: coveredHearingIds,
      readHearingIds: readIds,
    );
  }

  /// Lightweight hearing rows (single doc each — skips pool-wide sibling merge).
  static List<HearingInboxRow> buildGlobalHearingRowsLight(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> hearingDocs, {
    Set<String> coveredHearingIds = const {},
    Set<String> readHearingIds = const {},
  }) {
    final rows = <HearingInboxRow>[];
    for (final hDoc in hearingDocs) {
      if (coveredHearingIds.contains(hDoc.id)) continue;
      final hd = hDoc.data();
      if (!isDisplayableHearingRow(hd)) continue;

      final caseNo = (hd['caseNo'] as String?)?.trim() ?? '';
      final ts = _sortTimeForHearing(hd);
      final summary = (hd['summary'] as String?)?.trim() ??
          (hd['activityType'] as String?)?.trim() ??
          '';

      rows.add(
        HearingInboxRow(
          rowKey: 'hearing_${hDoc.id}',
          notificationDocId: null,
          data: {
            'type': 'hearing_activity',
            'title': caseNo.isNotEmpty
                ? 'Court hearing — $caseNo'
                : 'Court hearing / order',
            'summary': summary,
            'message': '',
            'hearingDocId': hDoc.id,
            if (caseNo.isNotEmpty) 'caseNo': caseNo,
            if (hd['clientName'] != null) 'clientName': hd['clientName'],
            if (hd['courtBranch'] != null) 'courtBranch': hd['courtBranch'],
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
      final result = await HybridDatastore.set(
        collection: 'notifications',
        id: nid,
        data: payload,
        options: SetOptions(merge: true),
      );
      if (!result.isSuccess) {
        if (_isPermissionDenied(result.firestoreError ?? '')) return;
        if (kDebugMode) {
          _fanoutLog(
            'ensureStaffHearingNotificationForUser: ${result.failureMessage}',
          );
        }
      }
    } catch (e) {
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
    for (var i = 0; i < 24; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (FirebaseAuth.instance.currentUser?.uid == userId) return true;
    }
    try {
      await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u?.uid == userId)
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    return FirebaseAuth.instance.currentUser?.uid == userId;
  }

  /// Whether this account may run `hearings.limit()` inbox queries (matches [isFirmUser] rules).
  Future<bool> _canUseGlobalHearingsInbox(String uid) async {
    if (uid.isEmpty) return false;
    if (await _isStaffAccount(uid)) return true;
    try {
      final u = await _db.collection('users').doc(uid).get();
      if (!u.exists) return false;
      final role = (u.data()?['role'] as String?)?.toLowerCase().trim() ?? '';
      return role == 'attorney' ||
          role == 'admin' ||
          role.contains('attorney');
    } catch (_) {
      return true;
    }
  }

  void _listenFirestore<T>(
    Stream<T> stream,
    void Function(T event) onData, {
    String? debugLabel,
  }) {
    stream
        .handleError((Object e, StackTrace _) {
          if (kDebugMode && debugLabel != null) {
            _fanoutLog('$debugLabel: $e');
          }
        })
        .listen(onData, cancelOnError: true);
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
  Future<int> syncStaffHearingNotifications({
    bool force = false,
    int maxDocs = 8,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 0;
    try {
      if (!await _isStaffAccount(uid)) return 0;
      if (!await _canUseGlobalHearingsInbox(uid)) return 0;

      final snap = await _db
          .collection('hearings')
          .limit(maxDocs * 4)
          .get();

      var synced = 0;
      for (final doc in snap.docs) {
        if (!isDisplayableHearingRow(doc.data())) continue;
        await ensureStaffHearingNotificationForUser(doc, uid);
        synced++;
        if (synced >= maxDocs) break;
        await Future<void>.delayed(Duration.zero);
      }
      return synced;
    } catch (e) {
      if (kDebugMode) {
        _fanoutLog('HearingNotificationFanout.syncStaffHearingNotifications: $e');
      }
      return 0;
    }
  }

  /// One-shot scan (e.g. when opening Appointment Reminders) so new `hearings` are
  /// fan-out even if the real-time listener missed the first write.
  Future<void> syncRecentHearingsForInbox({
    bool force = false,
    int maxDocs = 15,
  }) async {
    if (kIsWeb) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_inboxSyncInFlight.contains(uid)) return;
    if (!force) {
      final last = _lastInboxSyncAt[uid];
      if (last != null &&
          DateTime.now().difference(last) < _inboxSyncMinInterval) {
        return;
      }
    }
    _inboxSyncInFlight.add(uid);
    try {
      if (!await _canUseGlobalHearingsInbox(uid)) return;

      final snap = await _hearingsSnapshotForInbox(forUserId: uid);
      if (snap == null) return;
      var processed = 0;
      for (final doc in snap.docs) {
        if (!isDisplayableHearingRow(doc.data())) continue;
        await processDocumentIfNeeded(doc);
        processed++;
        if (processed >= maxDocs) break;
        await Future<void>.delayed(Duration.zero);
      }
      _lastInboxSyncAt[uid] = DateTime.now();
      _refreshInboxStreamsForUser(uid);
    } catch (e) {
      if (kDebugMode) {
        _fanoutLog('HearingNotificationFanout.syncRecentHearingsForInbox: $e');
      }
    } finally {
      _inboxSyncInFlight.remove(uid);
    }
  }
}

bool _inboxRowsListEqual(List<HearingInboxRow>? a, List<HearingInboxRow> b) {
  if (a == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].rowKey != b[i].rowKey) return false;
    if (a[i].isUnread != b[i].isUnread) return false;
  }
  return true;
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
    _attachListeners = () {
      if (_listenersAttached) return;
      _listenersAttached = true;
      attachListeners(
        userId,
        allNotificationTypes,
        includeGlobalHearingsFallback,
        hearingsOnly,
        (notifDocs, hearings) {
          unawaited(_deliver(notifDocs, hearings));
        },
      );
    };
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
  late final void Function() _attachListeners;
  bool _listenersAttached = false;

  void ensureListenersAttached() => _attachListeners();

  late final StreamController<List<HearingInboxRow>> _rowsController;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _lastNotifDocs;
  QuerySnapshot<Map<String, dynamic>>? _lastHearings;
  List<HearingInboxRow>? _lastRows;

  List<HearingInboxRow>? get lastRows => _lastRows;

  QuerySnapshot<Map<String, dynamic>>? get lastHearingsSnapshot =>
      _lastHearings;

  Stream<List<HearingInboxRow>> get rowsStream => _rowsController.stream;
  late final Stream<int> countStream;

  void _onRowsListen() {
    if (!kIsWeb) _attachListeners();
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
        if (_inboxRowsListEqual(_lastRows, rows)) return;
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
    bool attachListeners = false,
  }) {
    _lastRows = rows;
    _cacheBellCount(userId, rows);
    _markInboxFresh(userId);
    if (hearingsSnapshot != null) _lastHearings = hearingsSnapshot;
    if (!_rowsController.isClosed) _rowsController.add(rows);
    if (attachListeners) _attachListeners();
  }
}

bool _hearingTypeForBell(String type) {
  final t = type.toLowerCase();
  // Court-email ingest alerts belong in the general inbox, not hearing reminders.
  if (t == 'court_email_ingest' || t.startsWith('court_')) return false;
  // Extra "record updated" rows — hearing already lives in `hearings`.
  if (t == 'hearing_activity_update') return false;
  return t.contains('hearing') ||
      t.contains('notary') ||
      t.contains('appointment') ||
      t.contains('reminder') ||
      t.contains('deadline') ||
      t == 'appointment_scheduled' ||
      t == 'appointment_3day_reminder' ||
      t == 'appointment_sameday_reminder' ||
      t == 'appointment_accepted' ||
      t == 'appointment_request' ||
      t == 'calendar_reminder' ||
      t == 'case_request' ||
      t == 'task_assigned' ||
      t == 'task_completed';
}

/// Extra "Hearing record updated" inbox rows. The hearing already lives in `hearings`.
bool isHearingRecordUpdateNotification(Map<String, dynamic> data) {
  final type = HearingCalendarFields.asDisplayString(data['type']).toLowerCase();
  if (type == 'hearing_activity_update') return true;
  final title = HearingCalendarFields.asDisplayString(data['title']).toLowerCase();
  return title.startsWith('hearing record updated');
}

/// Used by attorney UI to count rows that should light the reminders bell.
bool hearingOrAppointmentBellType(String type) => _hearingTypeForBell(type);

/// Client notifications: court hearings/orders plus staff calendar reminders.
bool clientHearingInboxType(String type) {
  final t = type.toLowerCase();
  if (t == 'court_email_ingest' || t.startsWith('court_')) return false;
  if (t == 'hearing_activity_update') return false;
  return t.contains('hearing') || t == 'calendar_reminder';
}

/// Email-ingest spam shown as "New court notice" — not real court hearing orders.
bool clientCourtEmailSpamNotification(Map<String, dynamic> data) {
  if (isOutOfSystemPumpedNotice(data)) return true;
  if (isHearingRecordUpdateNotification(data)) return true;

  final type = HearingCalendarFields.asDisplayString(data['type']).toLowerCase();
  final hid = HearingCalendarFields.asDisplayString(data['hearingDocId']);
  final title = HearingCalendarFields.asDisplayString(data['title']).toLowerCase();
  final queueDocId = HearingCalendarFields.asDisplayString(
    data['queueDocId'] ?? data['queuedDocId'],
  ).toLowerCase();

  if (queueDocId.contains('imap')) return true;

  // Linked `hearings/{id}` row — keep and repair title in UI (not email-queue spam).
  if (hid.isNotEmpty && type == 'hearing_activity') {
    return false;
  }

  if (HearingNotificationFanoutService._isWrongClientCourtNoticeTitle(title)) {
    return true;
  }

  if (type == 'court_email_ingest') return true;
  if (type.startsWith('court_') && !type.contains('hearing')) return true;

  // Email queue rows typed as hearing_activity but not linked to a hearing doc.
  if (type == 'hearing_activity' && hid.isEmpty) {
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
