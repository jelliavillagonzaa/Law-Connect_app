import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'hearing_calendar_fields.dart';
import 'hearing_notification_fanout_service.dart';
import '../utils/calendar_live_hearing_map.dart';
import '../utils/calendar_perf.dart';
import '../utils/firestore_query_get.dart';

/// Mirrors Firestore `hearings` into `calendar_events` so the attorney sees **one**
/// manual calendar. Auto rows use [sourceTag] and show the AI SCHD badge in UI.
class HearingCalendarSyncService {
  HearingCalendarSyncService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  static final HearingCalendarSyncService instance =
      HearingCalendarSyncService();

  final FirebaseFirestore _db;

  /// Same badge bucket as court-email automation in the calendar UI.
  static const String sourceTag = 'hearings_sync';

  final Set<String> _attachedAttorneys = <String>{};
  final Map<String, StreamSubscription<dynamic>> _subs = {};
  final Map<String, Timer> _scopedSyncDebounce = {};
  final Map<String, Timer> _overlayEmitDebounce = {};
  final Map<String, Timer> _overlayScopedDebounce = {};
  final Map<String, List<Map<String, dynamic>>> _hearingNavRowCache = {};
  final Set<String> _automatedOverlayHydrated = <String>{};
  final Map<String, String> _overlayDocFingerprint = {};
  final Map<String, String> _overlayRowFingerprint = {};
  final Map<String, int> _overlayEmitGeneration = {};
  final Map<String, bool> _overlayDebouncedEmitReady = {};
  final Map<String, bool> _overlayScopedDebouncedReady = {};
  final Map<String, Timer> _globalHearingDefer = {};
  final Map<String, Future<void>> _bootstrapInFlight = {};

  static const int _overlayEmitDebounceMs = 560;
  static const int _overlayScopedDebounceMs = 1800;
  static const int _overlayScopedInitialDeferMs =
      CalendarPerf.hearingSupplementDeferMs;
  static const int _globalHearingsOneShotDeferMs =
      CalendarPerf.hearingGlobalOneShotDeferMs;
  static const int _projectionAsyncThreshold =
      CalendarPerf.projectionAsyncThreshold;

  /// After Firestore denies calendar sync writes, skip further attempts this session.
  bool _syncWritesBlocked = false;

  static const int _scopedSyncDebounceMs = 90000;

  static String calendarDocId(String hearingDocId) =>
      'hearing_cal_$hearingDocId';

  /// Firm-wide overlay when a hearing/order has no attorneyUid.
  static const String firmOverlayId = '__firm__';

  static String overlayKey(String attorneyId) {
    final aid = attorneyId.trim();
    return aid.isEmpty ? firmOverlayId : aid;
  }

  /// Only the assigned attorney may write `calendar_events` (staff uses live overlay).
  static bool canWriteCalendarSync(String attorneyId) {
    final uid = FirebaseAuth.instance.currentUser?.uid?.trim();
    final aid = attorneyId.trim();
    return uid != null && uid.isNotEmpty && uid == aid;
  }

  static bool _isPermissionDenied(Object e) {
    if (e is FirebaseException) return e.code == 'permission-denied';
    return e.toString().contains('permission-denied');
  }

  /// Scoped calendar_events backfill — only the attorney's cases/hearings (not 500 rows).
  void _scheduleScopedSync(String attorneyId) {
    final aid = attorneyId.trim();
    if (aid.isEmpty || _syncWritesBlocked || !canWriteCalendarSync(aid)) return;
    _scopedSyncDebounce[aid]?.cancel();
    _scopedSyncDebounce[aid] = Timer(
      const Duration(milliseconds: _scopedSyncDebounceMs),
      () => unawaited(_syncScopedForAttorney(aid)),
    );
  }

  /// Start a late, idle calendar_events backfill. Display uses the live
  /// hearings overlay — running this on tab open remaps large docs and ANRs.
  void attachForAttorney(String attorneyId) {
    final aid = attorneyId.trim();
    if (aid.isEmpty || _attachedAttorneys.contains(aid)) return;
    _attachedAttorneys.add(aid);
    _scheduleScopedSync(aid);
  }

  void detachForAttorney(String attorneyId) {
    final aid = attorneyId.trim();
    _attachedAttorneys.remove(aid);
    _scopedSyncDebounce.remove(aid)?.cancel();
    _overlayEmitDebounce.remove(aid)?.cancel();
    _overlayScopedDebounce.remove(aid)?.cancel();
    _overlayDocFingerprint.remove(aid);
    _overlayRowFingerprint.remove(aid);
    _overlayEmitGeneration.remove(aid);
    _overlayDebouncedEmitReady.remove(aid);
    _overlayScopedDebouncedReady.remove(aid);
    _globalHearingDefer.remove(aid)?.cancel();
    _globalHearingDefer.remove('${aid}_scoped')?.cancel();
    _bootstrapInFlight.remove(aid);
    _subs.remove(aid)?.cancel();
    _overlaySubs.remove(aid)?.cancel();
    _overlayControllers.remove(aid)?.close();
    _overlayControllers.remove(aid);
  }

  /// Call on logout so the next login re-attaches sync and stream listeners.
  void resetForLogout() {
    for (final aid in _attachedAttorneys.toList()) {
      detachForAttorney(aid);
    }
    for (final t in _scopedSyncDebounce.values) {
      t.cancel();
    }
    _scopedSyncDebounce.clear();
    for (final t in _overlayEmitDebounce.values) {
      t.cancel();
    }
    _overlayEmitDebounce.clear();
    for (final t in _overlayScopedDebounce.values) {
      t.cancel();
    }
    _overlayScopedDebounce.clear();
    for (final aid in _overlaySubs.keys.toList()) {
      _overlaySubs.remove(aid)?.cancel();
    }
    for (final c in _overlayControllers.values) {
      if (!c.isClosed) c.close();
    }
    _overlayControllers.clear();
    _hearingNavRowCache.clear();
    _automatedOverlayHydrated.clear();
    _overlayDocFingerprint.clear();
    _overlayRowFingerprint.clear();
    _overlayEmitGeneration.clear();
    _overlayDebouncedEmitReady.clear();
    _overlayScopedDebouncedReady.clear();
    for (final t in _globalHearingDefer.values) {
      t.cancel();
    }
    _globalHearingDefer.clear();
    _bootstrapInFlight.clear();
    _syncWritesBlocked = false;
  }

  final Map<String, StreamController<List<Map<String, dynamic>>>>
  _overlayControllers = {};
  final Map<String, StreamSubscription<dynamic>> _overlaySubs = {};

  /// Staff / paralegal viewing the assigned attorney calendar (not the attorney uid).
  static bool _isFirmViewerForAttorney(String attorneyId) {
    final viewer = FirebaseAuth.instance.currentUser?.uid?.trim() ?? '';
    final aid = attorneyId.trim();
    return viewer.isNotEmpty && aid.isNotEmpty && viewer != aid;
  }

  /// Hearings for hybrid calendar without an unscoped `hearings` collection listen.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _loadHearingDocsScoped(
    String attorneyId,
    List<Map<String, dynamic>> caseMaps,
  ) async {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final aid = attorneyId.trim();

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> runQuery(
      Query<Map<String, dynamic>> query,
    ) async {
      try {
        final snap = await query.get();
        return snap.docs;
      } catch (e) {
        if (_isPermissionDenied(e)) return const [];
        return const [];
      }
    }

    final queries = <Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>>[
      runQuery(
        _db
            .collection('hearings')
            .where('attorneyUid', isEqualTo: aid)
            .limit(300),
      ),
    ];

    final caseIds = <String>[];
    for (final c in caseMaps) {
      final id = (c['id'] as String?)?.trim() ?? '';
      if (id.isNotEmpty) caseIds.add(id);
    }
    for (var i = 0; i < caseIds.length && i < 90; i += 30) {
      final end = i + 30 > caseIds.length ? caseIds.length : i + 30;
      final chunk = caseIds.sublist(i, end);
      queries.add(
        runQuery(
          _db.collection('hearings').where('caseId', whereIn: chunk).limit(100),
        ),
      );
    }

    final caseNoVariants = <String>{};
    for (final c in caseMaps) {
      for (final field in [
        'caseNumber',
        'caseNo',
        'docketNumber',
        'criminalCaseNo',
      ]) {
        final v = (c[field] as String?)?.trim() ?? '';
        if (v.isEmpty) continue;
        caseNoVariants.addAll(
          HearingNotificationFanoutService.caseNumberQueryVariants(v),
        );
      }
    }
    for (final caseNo in caseNoVariants.take(14)) {
      queries.add(
        runQuery(
          _db
              .collection('hearings')
              .where('caseNo', isEqualTo: caseNo)
              .limit(40),
        ),
      );
    }

    final clientNames = <String>{};
    for (final c in caseMaps) {
      for (final field in ['clientName', 'clientFullName', 'caseTitle']) {
        final v = (c[field] as String?)?.trim() ?? '';
        if (v.length >= 4) clientNames.add(v);
      }
    }
    for (final name in clientNames.take(4)) {
      queries.add(
        runQuery(
          _db
              .collection('hearings')
              .where('clientName', isEqualTo: name)
              .limit(40),
        ),
      );
    }

    queries.add(
      runQuery(
        _db
            .collection('hearings')
            .where('notifyUserIds', arrayContains: aid)
            .limit(100),
      ),
    );

    const batchSize = 3;
    for (var i = 0; i < queries.length; i += batchSize) {
      final end = i + batchSize > queries.length ? queries.length : i + batchSize;
      final batches = await Future.wait(queries.sublist(i, end));
      for (final docs in batches) {
        for (final d in docs) {
          byId[d.id] = d;
        }
      }
    }

    return byId.values.toList();
  }

  /// In-memory rows for instant banner/grid on tab revisit (cleared on logout).
  List<Map<String, dynamic>>? peekHearingNavRows(String attorneyId) {
    final aid = attorneyId.trim();
    if (aid.isEmpty) return null;
    return _hearingNavRowCache[aid];
  }

  void invalidateHearingNavCache(String attorneyId) {
    final aid = attorneyId.trim();
    _hearingNavRowCache.remove(aid);
    _automatedOverlayHydrated.remove(aid);
  }

  void rememberOverlayRows(String attorneyId, List<Map<String, dynamic>> rows) {
    final aid = attorneyId.trim();
    if (aid.isEmpty || rows.isEmpty) return;
    final cached = _hearingNavRowCache[aid];
    _hearingNavRowCache[aid] = cached == null || cached.isEmpty
        ? List<Map<String, dynamic>>.from(rows)
        : CalendarLiveHearingMap.mergeHearingRows(cached, rows);
  }

  /// Automated calendar overlay: every non-spam `hearings` row with a date.
  /// n8n writes often omit `attorneyUid` / matching `cases` — still show them.
  Future<List<Map<String, dynamic>>> fetchAutomatedCalendarRows(
    String attorneyId,
  ) async {
    final aid = overlayKey(attorneyId);

    final cached = _hearingNavRowCache[aid];

    try {
      final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

      Future<void> take(Query<Map<String, dynamic>> query) async {
        try {
          final snap = await FirestoreQueryGet.hearings(query);
          for (final doc in snap.docs) {
            byId[doc.id] = doc;
          }
        } catch (e) {
          debugPrint('[HearingCalendar] overlay query failed: $e');
        }
      }

      // Newest + a wide unscoped page so October 28 (and other days) keep
      // every court-order row, not only the last 40 uploads.
      await take(
        _db.collection('hearings').orderBy('createdAt', descending: true).limit(150),
      );
      await take(_db.collection('hearings').limit(200));
      if (aid != firmOverlayId) {
        await take(
          _db.collection('hearings').where('attorneyUid', isEqualTo: aid).limit(300),
        );
      }

      if (byId.isEmpty) {
        return cached ?? const [];
      }

      final out = CalendarLiveHearingMap.mapHearingDocs(byId.values, aid);
      out.sort((a, b) {
        final ad = a['eventDate'];
        final bd = b['eventDate'];
        if (ad is DateTime && bd is DateTime) return ad.compareTo(bd);
        return 0;
      });
      final merged = cached == null || cached.isEmpty
          ? out
          : CalendarLiveHearingMap.mergeHearingRows(cached, out);
      if (merged.isNotEmpty) {
        _hearingNavRowCache[aid] = merged;
      }
      _automatedOverlayHydrated.add(aid);
      debugPrint(
        '[HearingCalendar] automated overlay ${merged.length}/${byId.length}',
      );
      return merged;
    } catch (e) {
      debugPrint('[HearingCalendar] automated overlay failed: $e');
      return cached ?? const [];
    }
  }

  /// Every hearing/order in the user's inbox must land on the calendar,
  /// even when attorneyUid is missing and createdAt queries skip the doc.
  Future<List<Map<String, dynamic>>> fetchRowsFromHearingNotifications(
    String overlayId,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid?.trim() ?? '';
    final aid = overlayKey(overlayId);
    if (uid.isEmpty) return const [];

    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _db
            .collection('notifications')
            .where('userId', isEqualTo: uid)
            .limit(80)
            .get();
      } catch (e) {
        debugPrint('[HearingCalendar] inbox query failed: $e');
        return const [];
      }

      final hearingIds = <String>{};
      final notifByHearing = <String, Map<String, dynamic>>{};
      final standalone = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final data = doc.data();
        final type = '${data['type'] ?? ''}'.toLowerCase();
        final hid = HearingCalendarFields.asDisplayString(data['hearingDocId']);
        final isHearing = type.contains('hearing') || hid.isNotEmpty;
        if (!isHearing) continue;
        if (hid.isNotEmpty) {
          hearingIds.add(hid);
          notifByHearing[hid] = data;
          continue;
        }
        final caseNo = HearingCalendarFields.asDisplayString(data['caseNo']);
        final title = HearingCalendarFields.asDisplayString(data['caseTitle']);
        if (caseNo.isEmpty && title.isEmpty) continue;
        final row = CalendarLiveHearingMap.fromHearingDoc(data, doc.id, aid);
        if (row != null) {
          row['fromInbox'] = true;
          standalone.add(row);
        }
      }

      final rows = <Map<String, dynamic>>[...standalone];
      for (final hid in hearingIds) {
        try {
          final hSnap = await _db.collection('hearings').doc(hid).get();
          final hd = hSnap.exists
              ? Map<String, dynamic>.from(hSnap.data()!)
              : <String, dynamic>{};
          final notif = notifByHearing[hid] ?? const <String, dynamic>{};
          hd['summary'] = HearingCalendarFields.asDisplayString(hd['summary'])
                  .isNotEmpty
              ? hd['summary']
              : notif['summary'] ?? notif['message'];
          hd['message'] = HearingCalendarFields.asDisplayString(hd['message'])
                  .isNotEmpty
              ? hd['message']
              : notif['message'] ?? notif['summary'];
          if (HearingCalendarFields.hearingFieldAsString(hd, 'hearingDate')
              .isEmpty) {
            final fromNotif = HearingCalendarFields.hearingFieldAsString(
              notif,
              'hearingDate',
            );
            if (fromNotif.isNotEmpty) hd['hearingDate'] = fromNotif;
          }
          if (HearingCalendarFields.hearingFieldAsString(hd, 'hearingTime')
              .isEmpty) {
            final fromNotif = HearingCalendarFields.hearingFieldAsString(
              notif,
              'hearingTime',
            );
            if (fromNotif.isNotEmpty) hd['hearingTime'] = fromNotif;
          }
          for (final key in ['caseNo', 'caseTitle', 'clientName', 'courtBranch']) {
            if (HearingCalendarFields.asDisplayString(hd[key]).isEmpty) {
              final v = HearingCalendarFields.asDisplayString(notif[key]);
              if (v.isNotEmpty) hd[key] = v;
            }
          }
          final row = CalendarLiveHearingMap.fromHearingDoc(hd, hid, aid);
          if (row != null) {
            row['fromInbox'] = true;
            rows.add(row);
          }
        } catch (e) {
          debugPrint('[HearingCalendar] inbox hearing $hid: $e');
        }
      }

      if (rows.isNotEmpty) rememberOverlayRows(aid, rows);
      debugPrint('[HearingCalendar] inbox overlay ${rows.length}');
      return rows;
    } catch (e) {
      debugPrint('[HearingCalendar] inbox overlay failed: $e');
      return const [];
    }
  }

  /// Merges global + scoped hearing docs for the attorney calendar overlay.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _loadAllHearingDocsForOverlay(
    String attorneyId,
    List<Map<String, dynamic>> caseMaps,
  ) async {
    final aid = attorneyId.trim();
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    final scoped = await _loadHearingDocsScoped(aid, caseMaps);
    for (final d in scoped) {
      byId[d.id] = d;
    }

    return byId.values.toList();
  }

  /// One-shot scoped hearings for the cross-month banner (no live collection listener).
  Future<List<Map<String, dynamic>>> fetchHearingNavRowsOnce(
    String attorneyId, {
    bool forceRefresh = false,
  }) async {
    final aid = attorneyId.trim();
    if (aid.isEmpty) return const [];

    if (!forceRefresh) {
      final cached = _hearingNavRowCache[aid];
      if (cached != null && cached.isNotEmpty) return cached;
    }

    List<Map<String, dynamic>> caseMaps = [];
    try {
      final snap = await _db
          .collection('cases')
          .where('attorneyId', isEqualTo: aid)
          .get();
      caseMaps = snap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();
    } catch (_) {
      return const [];
    }

    final docs = await _loadAllHearingDocsForOverlay(aid, caseMaps);
    final filtered = _prefilterHearingDocs(docs, aid, caseMaps);
    if (filtered.isEmpty) return const [];
    final rows = projectHearingsFromDocs(aid, caseMaps, filtered);
    _hearingNavRowCache[aid] = rows;
    return rows;
  }

  /// Fast bootstrap: full hearings merge (global + scoped) without blocking the grid.
  Future<void> bootstrapHearingOverlay(String attorneyId) async {
    final aid = attorneyId.trim();
    if (aid.isEmpty) return;

    final cached = _hearingNavRowCache[aid];
    if (cached != null && cached.isNotEmpty) {
      _pushOverlayRows(aid, cached);
      return;
    }

    final inFlight = _bootstrapInFlight[aid];
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final fut = _bootstrapHearingOverlayImpl(aid);
    _bootstrapInFlight[aid] = fut;
    try {
      await fut;
    } finally {
      _bootstrapInFlight.remove(aid);
    }
  }

  Future<void> _bootstrapHearingOverlayImpl(String aid) async {
    final cached = _hearingNavRowCache[aid];
    if (cached != null && cached.isNotEmpty) {
      _pushOverlayRows(aid, cached);
      return;
    }

    List<Map<String, dynamic>> caseMaps = [];
    List<QueryDocumentSnapshot<Map<String, dynamic>>> hearingDocs = [];
    try {
      final results = await Future.wait([
        _db.collection('cases').where('attorneyId', isEqualTo: aid).get(),
        _db
            .collection('hearings')
            .where('attorneyUid', isEqualTo: aid)
            .limit(300)
            .get(),
      ]);
      caseMaps = results[0].docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();
      hearingDocs = results[1].docs;
    } catch (_) {
      return;
    }

    final filtered = _prefilterHearingDocs(hearingDocs, aid, caseMaps);
    if (filtered.isNotEmpty) {
      await _projectDocsChunked(
        attorneyId: aid,
        caseMaps: caseMaps,
        docs: filtered,
      );
    }

    unawaited(_supplementHearingsInBackground(aid, caseMaps));
  }

  /// Scoped + global hearings as lightweight grid rows (no unify / overlay lag).
  Future<List<Map<String, dynamic>>> fetchLightweightGridHearings(
    String attorneyId,
  ) async {
    final aid = attorneyId.trim();
    if (aid.isEmpty) return const [];

    final cached = _hearingNavRowCache[aid];
    if (cached != null && cached.isNotEmpty) {
      return List<Map<String, dynamic>>.from(cached);
    }

    List<Map<String, dynamic>> caseMaps = [];
    try {
      final snap = await _db
          .collection('cases')
          .where('attorneyId', isEqualTo: aid)
          .get();
      caseMaps = snap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();
    } catch (_) {
      caseMaps = const [];
    }

    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final scoped = await _loadHearingDocsScoped(aid, caseMaps);
    for (final d in scoped) {
      byId[d.id] = d;
    }

    final out = <Map<String, dynamic>>[];
    final docs = byId.values.toList();
    for (var i = 0; i < docs.length; i++) {
      if (i > 0 && i % CalendarPerf.hearingProjectionChunkSize == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final row = CalendarLiveHearingMap.fromHearingDoc(
        docs[i].data(),
        docs[i].id,
        aid,
      );
      if (row != null) out.add(row);
    }

    if (out.isNotEmpty) {
      _hearingNavRowCache[aid] = out;
    }
    return out;
  }

  void _pushOverlayRows(String attorneyId, List<Map<String, dynamic>> rows) {
    final controller = _overlayControllers[attorneyId.trim()];
    if (controller == null || controller.isClosed) return;
    Future.microtask(() {
      if (!controller.isClosed) controller.add(rows);
    });
  }

  /// @deprecated Use [bootstrapHearingOverlay]
  Future<void> prefetchHearingOverlay(String attorneyId) =>
      bootstrapHearingOverlay(attorneyId);

  /// Real-time hearing rows for calendar UI (same shape as [getCalendarEvents]).
  Stream<List<Map<String, dynamic>>> watchHearingEntriesForAttorney(
    String attorneyId,
  ) {
    final aid = attorneyId.trim();
    if (aid.isEmpty) return Stream.value(const []);

    final existing = _overlayControllers[aid];
    if (existing != null) return existing.stream;

    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    _overlayControllers[aid] = controller;
    List<Map<String, dynamic>> caseMaps = [];
    List<QueryDocumentSnapshot<Map<String, dynamic>>> scopedDocs = [];
    List<QueryDocumentSnapshot<Map<String, dynamic>>> oneShotGlobalDocs = [];
    QuerySnapshot<Map<String, dynamic>>? lastAttorneyUidHearings;
    var scopedReady = false;
    var oneShotGlobalReady = false;
    var lastCaseCount = 0;

    Future<void> emitProjectedDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ) async {
      if (docs.isEmpty) return;
      final gen = (_overlayEmitGeneration[aid] ?? 0) + 1;
      _overlayEmitGeneration[aid] = gen;

      final filtered = _prefilterHearingDocs(docs, aid, caseMaps);
      if (filtered.isEmpty) return;

      final fp = _fingerprintHearingDocs(filtered);
      if (fp == _overlayDocFingerprint[aid] &&
          (_hearingNavRowCache[aid]?.isNotEmpty ?? false)) {
        return;
      }
      _overlayDocFingerprint[aid] = fp;

      await Future<void>.delayed(Duration.zero);
      if (gen != _overlayEmitGeneration[aid]) return;

      final merged = await _projectDocsChunked(
        attorneyId: aid,
        caseMaps: caseMaps,
        docs: filtered,
      );
      if (gen != _overlayEmitGeneration[aid]) return;

      final rowFp = _overlayRowsFingerprint(merged);
      if (rowFp == _overlayRowFingerprint[aid]) return;
      _overlayRowFingerprint[aid] = rowFp;
    }

    Future<void> emit() async {
      final gen = (_overlayEmitGeneration[aid] ?? 0) + 1;
      _overlayEmitGeneration[aid] = gen;
      try {
        final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        final attorneyUidSnap = lastAttorneyUidHearings;
        if (attorneyUidSnap != null) {
          for (final d in attorneyUidSnap.docs) {
            merged[d.id] = d;
          }
        }
        for (final d in scopedDocs) {
          merged[d.id] = d;
        }
        for (final d in oneShotGlobalDocs) {
          merged[d.id] = d;
        }

        if (merged.isEmpty) {
          if (!scopedReady &&
              lastAttorneyUidHearings == null &&
              !oneShotGlobalReady) {
            return;
          }
          final cached = _hearingNavRowCache[aid];
          if (cached != null && cached.isNotEmpty) return;
          if (gen != _overlayEmitGeneration[aid]) return;
          if (!controller.isClosed) controller.add(const []);
          return;
        }

        final known = _cachedHearingDocIds(aid);
        final filtered = _prefilterHearingDocs(merged.values, aid, caseMaps);
        if (filtered.isEmpty) {
          final cached = _hearingNavRowCache[aid];
          if (cached != null && cached.isNotEmpty) return;
          if (gen != _overlayEmitGeneration[aid]) return;
          if (!controller.isClosed) controller.add(const []);
          return;
        }

        final toProject = known.isEmpty
            ? filtered
            : filtered.where((d) => !known.contains(d.id)).toList();
        if (toProject.isEmpty) return;

        if (gen != _overlayEmitGeneration[aid]) return;
        await emitProjectedDocs(toProject);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('HearingCalendarSync.emit: $e\n$st');
        }
      }
    }

    Future<void> refreshScoped() async {
      final inFlight = _bootstrapInFlight[aid];
      if (inFlight != null) {
        await inFlight;
        if (_hearingNavRowCache[aid]?.isNotEmpty == true) {
          scopedReady = true;
          return;
        }
      }
      scopedDocs = await _loadHearingDocsScoped(aid, caseMaps);
      scopedReady = true;
      await emit();
    }

    Future<void> loadOneShotGlobal() async {
      if (oneShotGlobalReady) return;
      oneShotGlobalReady = true;
      // Unscoped hearings.limit(500) ANRs Android. Overlay uses scoped queries.
      oneShotGlobalDocs = const [];
    }

    void scheduleEmit() {
      _overlayEmitDebounce[aid]?.cancel();
      final immediate = !(_overlayDebouncedEmitReady[aid] ?? false);
      final ms = immediate ? 0 : _overlayEmitDebounceMs;
      _overlayEmitDebounce[aid] = Timer(
        Duration(milliseconds: ms),
        () {
          _overlayDebouncedEmitReady[aid] = true;
          unawaited(emit());
        },
      );
    }

    void scheduleRefreshScoped() {
      _overlayScopedDebounce[aid]?.cancel();
      final immediate = !(_overlayScopedDebouncedReady[aid] ?? false);
      final ms = immediate
          ? _overlayScopedInitialDeferMs
          : _overlayScopedDebounceMs;
      _overlayScopedDebounce[aid] = Timer(
        Duration(milliseconds: ms),
        () {
          _overlayScopedDebouncedReady[aid] = true;
          unawaited(refreshScoped());
        },
      );
    }

    void handleOverlayStreamError(Object e, {required bool casesStream}) {
      if (_isPermissionDenied(e)) {
        if (casesStream) {
          caseMaps = [];
        } else {
          lastAttorneyUidHearings = null;
        }
        scheduleRefreshScoped();
        return;
      }
      if (kDebugMode) debugPrint('HearingCalendarSync overlay stream: $e');
    }

    void onAttorneyUidHearingsSnap(QuerySnapshot<Map<String, dynamic>> snap) {
      final isFirst = lastAttorneyUidHearings == null;
      if (!isFirst &&
          !_snapshotMayAffectAttorney(
            snap,
            aid,
            caseMaps,
            previous: lastAttorneyUidHearings,
          )) {
        lastAttorneyUidHearings = snap;
        return;
      }
      lastAttorneyUidHearings = snap;

      if (isFirst) {
        scheduleEmit();
        return;
      }

      final changed = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.removed) continue;
        final doc = change.doc;
        if (doc is QueryDocumentSnapshot<Map<String, dynamic>>) {
          changed.add(doc);
        }
      }
      if (changed.isEmpty) return;

      _overlayEmitDebounce[aid]?.cancel();
      _overlayEmitDebounce[aid] = Timer(
        Duration(milliseconds: _overlayEmitDebounceMs),
        () => unawaited(emitProjectedDocs(changed)),
      );
    }

    final casesSub = _db
        .collection('cases')
        .where('attorneyId', isEqualTo: aid)
        .snapshots()
        .listen((snap) {
          caseMaps = snap.docs
              .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
              .toList();
          final count = caseMaps.length;
          if (count != lastCaseCount) {
            lastCaseCount = count;
            scheduleRefreshScoped();
          }
        }, onError: (e) => handleOverlayStreamError(e, casesStream: true));

    final attorneyUidHearingsSub = _db
        .collection('hearings')
        .where('attorneyUid', isEqualTo: aid)
        .limit(300)
        .snapshots()
        .listen(
          onAttorneyUidHearingsSnap,
          onError: (e) => handleOverlayStreamError(e, casesStream: false),
        );

    _globalHearingDefer[aid]?.cancel();
    _globalHearingDefer[aid] = Timer(
      const Duration(milliseconds: _globalHearingsOneShotDeferMs),
      () => unawaited(loadOneShotGlobal()),
    );

    _globalHearingDefer['${aid}_scoped']?.cancel();
    _globalHearingDefer['${aid}_scoped'] = Timer(
      const Duration(milliseconds: _overlayScopedInitialDeferMs),
      () {
        if (!controller.isClosed) scheduleRefreshScoped();
      },
    );

    _overlaySubs[aid] = _CombinedSubscription([
      casesSub,
      attorneyUidHearingsSub,
    ]);

    final cached = _hearingNavRowCache[aid];
    if (cached != null && cached.isNotEmpty) {
      Future.microtask(() {
        if (!controller.isClosed) controller.add(cached);
      });
    }

    return controller.stream;
  }

  static String _overlayRowsFingerprint(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '0';
    var hash = rows.length;
    for (var i = 0; i < rows.length; i++) {
      if (i == 0 || i == rows.length - 1 || i % 17 == 0) {
        hash = Object.hash(hash, rows[i]['hearingDocId'], rows[i]['eventDate']);
      }
    }
    return hash.toString();
  }

  static bool _snapshotMayAffectAttorney(
    QuerySnapshot<Map<String, dynamic>> snap,
    String attorneyId,
    List<Map<String, dynamic>> caseMaps, {
    QuerySnapshot<Map<String, dynamic>>? previous,
  }) {
    if (previous == null) return true;
    final changes = snap.docChanges;
    if (changes.isEmpty) return false;
    for (final change in changes) {
      final data = change.doc.data();
      if (data != null &&
          _mightMatchHearingDocForOverlay(data, caseMaps, attorneyId)) {
        return true;
      }
    }
    return false;
  }

  /// Same rules as [_projectOneHearingDoc] — avoids dropping scheduled hearings
  /// (e.g. April 22) that only match via summary / court-import fields.
  static bool _mightMatchHearingDocForOverlay(
    Map<String, dynamic> hd,
    List<Map<String, dynamic>> caseMaps,
    String attorneyId,
  ) {
    if (!isCalendarDisplayableHearingRow(hd)) return false;
    return hearingMatchesAttorneyCalendar(hd, caseMaps, attorneyId);
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _prefilterHearingDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String attorneyId,
    List<Map<String, dynamic>> caseMaps,
  ) {
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in docs) {
      if (_mightMatchHearingDocForOverlay(doc.data(), caseMaps, attorneyId)) {
        out.add(doc);
      }
    }
    return out;
  }

  static String _fingerprintHearingDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (docs.isEmpty) return '0';
    var hash = docs.length;
    for (var i = 0; i < docs.length; i++) {
      if (i == 0 || i == docs.length - 1 || i % 19 == 0) {
        hash = Object.hash(hash, docs[i].id);
      }
    }
    return hash.toString();
  }

  List<Map<String, dynamic>> _projectHearingsForAttorney(
    String attorneyId,
    List<Map<String, dynamic>> caseMaps,
  ) {
    // Populated on next hearings snapshot via emit(); empty until first fire.
    return _lastProjected[attorneyId] ?? const [];
  }

  final Map<String, List<Map<String, dynamic>>> _lastProjected = {};

  /// Court hearing / order: show on every attorney and staff calendar.
  /// attorneyUid is optional — n8n imports and notifications often omit it.
  static bool hearingMatchesAttorneyCalendar(
    Map<String, dynamic> hearing,
    List<Map<String, dynamic>> attorneyCaseMaps,
    String attorneyId,
  ) {
    if (!isCalendarDisplayableHearingRow(hearing)) return false;
    try {
      final when = HearingCalendarFields.resolveEventDate(hearing) ??
          HearingCalendarFields.resolveEventDateFromHearingDateField(hearing) ??
          CalendarLiveHearingMap.parseHearingWhen(hearing);
      if (when != null) return true;
    } catch (_) {}

    if (HearingNotificationFanoutService.hearingMatchesAttorneyCases(
      hearing,
      attorneyCaseMaps,
      attorneyId,
    )) {
      return true;
    }

    final aid = attorneyId.trim();
    if (aid.isEmpty || aid == firmOverlayId) {
      return HearingNotificationFanoutService.isDisplayableHearingRow(hearing);
    }

    final attorneyUid = (hearing['attorneyUid'] as String?)?.trim() ?? '';
    if (attorneyUid == aid) return true;

    final notify = hearing['notifyUserIds'];
    if (notify is List && notify.contains(aid)) return true;

    return false;
  }

  static bool isCalendarDisplayableHearingRow(Map<String, dynamic> d) {
    if (HearingCalendarFields.isNonCourtHearingSpam(d)) return false;
    if (HearingNotificationFanoutService.isDisplayableHearingRow(d)) {
      return true;
    }
    return HearingCalendarFields.hearingFieldAsString(
          d,
          'hearingDate',
        ).isNotEmpty ||
        HearingCalendarFields.fieldAsDisplayString(
          d,
          'hearingTime',
        ).isNotEmpty ||
        HearingCalendarFields.asDisplayString(d['location']).isNotEmpty ||
        HearingCalendarFields.asDisplayString(d['clientName']).isNotEmpty ||
        HearingCalendarFields.asDisplayString(d['caseNo']).isNotEmpty ||
        HearingCalendarFields.asDisplayString(d['caseTitle']).isNotEmpty ||
        HearingCalendarFields.asDisplayString(d['summary']).isNotEmpty;
  }

  List<Map<String, dynamic>> projectHearingsFromDocs(
    String attorneyId,
    List<Map<String, dynamic>> caseMaps,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    bool unify = false,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final row = _projectOneHearingDoc(attorneyId, caseMaps, doc);
      if (row != null) out.add(row);
    }
    return _finalizeProjectedHearings(out, unify: unify);
  }

  /// Yields between chunks so the UI thread stays responsive on calendar open.
  Future<List<Map<String, dynamic>>> projectHearingsFromDocsAsync(
    String attorneyId,
    List<Map<String, dynamic>> caseMaps,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    bool unify = false,
  }) async {
    final out = <Map<String, dynamic>>[];
    final chunk = CalendarPerf.hearingProjectionChunkSize;
    for (var i = 0; i < docs.length; i++) {
      if (i > 0 && i % chunk == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final row = _projectOneHearingDoc(attorneyId, caseMaps, docs[i]);
      if (row != null) out.add(row);
    }
    return _finalizeProjectedHearings(out, unify: unify);
  }

  static Set<String> _cachedHearingDocIds(String attorneyId) {
    final rows = instance._hearingNavRowCache[attorneyId.trim()] ?? const [];
    return rows
        .map((r) => (r['hearingDocId'] as String?)?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static List<Map<String, dynamic>> _mergeProjectedHearingRows(
    List<Map<String, dynamic>> base,
    List<Map<String, dynamic>> incoming,
  ) {
    if (incoming.isEmpty) return base;
    final byId = <String, Map<String, dynamic>>{};
    for (final r in base) {
      final id = (r['hearingDocId'] as String?)?.trim() ?? '';
      if (id.isNotEmpty) byId[id] = r;
    }
    for (final r in incoming) {
      final id = (r['hearingDocId'] as String?)?.trim() ?? '';
      if (id.isNotEmpty) byId[id] = r;
    }
    final merged = byId.values.toList()
      ..sort((a, b) {
        final ad = a['eventDate'];
        final bd = b['eventDate'];
        if (ad is! DateTime || bd is! DateTime) return 0;
        return ad.compareTo(bd);
      });
    return merged;
  }

  /// Projects hearing docs in small chunks and streams rows to the overlay.
  Future<List<Map<String, dynamic>>> _projectDocsChunked({
    required String attorneyId,
    required List<Map<String, dynamic>> caseMaps,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    bool pushEachChunk = true,
  }) async {
    final aid = attorneyId.trim();
    if (docs.isEmpty) {
      return _hearingNavRowCache[aid] ?? const [];
    }

    var merged = List<Map<String, dynamic>>.from(
      _hearingNavRowCache[aid] ?? const [],
    );
    final chunkSize = CalendarPerf.hearingProjectionChunkSize;

    for (var i = 0; i < docs.length; i += chunkSize) {
      final end = i + chunkSize > docs.length ? docs.length : i + chunkSize;
      final slice = docs.sublist(i, end);
      final rows = await projectHearingsFromDocsAsync(
        aid,
        caseMaps,
        slice,
        unify: false,
      );
      merged = _mergeProjectedHearingRows(merged, rows);
      _hearingNavRowCache[aid] = merged;
      _lastProjected[aid] = merged;
      if (pushEachChunk) {
        _pushOverlayRows(aid, merged);
      }
      if (end < docs.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    return merged;
  }

  Future<void> _supplementHearingsInBackground(
    String aid,
    List<Map<String, dynamic>> caseMaps,
  ) async {
    await Future<void>.delayed(
      const Duration(milliseconds: CalendarPerf.hearingSupplementDeferMs),
    );
    if (_bootstrapInFlight.containsKey(aid)) return;

    try {
      final scoped = await _loadHearingDocsScoped(aid, caseMaps);
      final known = _cachedHearingDocIds(aid);
      final fresh = scoped.where((d) => !known.contains(d.id)).toList();
      if (fresh.isEmpty) return;

      final filtered = _prefilterHearingDocs(fresh, aid, caseMaps);
      if (filtered.isEmpty) return;

      await _projectDocsChunked(
        attorneyId: aid,
        caseMaps: caseMaps,
        docs: filtered,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('HearingCalendarSync.supplement: $e');
    }
  }

  Map<String, dynamic>? _projectOneHearingDoc(
    String attorneyId,
    List<Map<String, dynamic>> caseMaps,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    try {
      final hd = HearingCalendarFields.normalizeHearingDoc(doc.data());
      if (!isCalendarDisplayableHearingRow(hd)) {
        return null;
      }
      if (!hearingMatchesAttorneyCalendar(hd, caseMaps, attorneyId)) {
        return null;
      }
      DateTime? when;
      try {
        when = HearingCalendarFields.resolveEventDate(hd);
        when ??= HearingCalendarFields.resolveEventDateFromHearingDateField(hd);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('HearingCalendarSync.projectHearingsFromDocs date: $e');
        }
        return null;
      }
      if (when == null) return null;

      final map = HearingCalendarFields.toCalendarOverlayRow(
        raw: hd,
        hearingDocId: doc.id,
        attorneyId: attorneyId,
        when: when,
        caseMaps: caseMaps,
      );
      if (map == null) return null;
      map['source'] = sourceTag;
      return map;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('HearingCalendarSync.projectHearingsFromDocs: $e');
      }
      return null;
    }
  }

  List<Map<String, dynamic>> _finalizeProjectedHearings(
    List<Map<String, dynamic>> out, {
    bool unify = false,
  }) {
    if (unify && out.isNotEmpty) {
      HearingCalendarFields.unifyHearingRecordsForCalendar(out);
    }
    out.sort((a, b) {
      final ad = a['eventDate'];
      final bd = b['eventDate'];
      if (ad is! DateTime || bd is! DateTime) return 0;
      return ad.compareTo(bd);
    });
    return out;
  }

  Future<void> syncAllForAttorney(String attorneyId) async {
    await _syncScopedForAttorney(attorneyId);
  }

  Future<void> _syncScopedForAttorney(String attorneyId) async {
    final aid = attorneyId.trim();
    if (aid.isEmpty || _syncWritesBlocked || !canWriteCalendarSync(aid)) return;

    try {
      final casesSnap = await _db
          .collection('cases')
          .where('attorneyId', isEqualTo: aid)
          .get();
      final caseMaps = casesSnap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();

      final docs = await _loadHearingDocsScoped(aid, caseMaps);
      await _syncFromSnapshots(aid, caseMaps, hearings: docs);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('HearingCalendarSync._syncScopedForAttorney: $e');
      }
    }
  }

  /// Call after creating/updating a single hearing document.
  Future<void> syncHearingDoc(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid?.trim();
    if (uid == null || uid.isEmpty) return;
    try {
      final snap = await ref.get();
      if (!snap.exists) return;
      final hd = snap.data()!;
      if (!isCalendarDisplayableHearingRow(hd)) {
        return;
      }

      final when = HearingCalendarFields.resolveEventDate(hd);
      if (when == null) return;

      final attorneyIds = await _resolveAttorneyIds(hd);
      for (final aid in attorneyIds) {
        final caseMaps = await _caseMapsForAttorney(aid);
        if (!hearingMatchesAttorneyCalendar(hd, caseMaps, aid)) {
          continue;
        }
        await _upsertCalendarEvent(
          hearingDocId: snap.id,
          hd: hd,
          when: when,
          attorneyId: aid,
        );
      }
    } catch (e) {
      if (_isPermissionDenied(e)) {
        _syncWritesBlocked = true;
        return;
      }
      if (kDebugMode) debugPrint('HearingCalendarSync.syncHearingDoc: $e');
    }
  }

  Future<void> _syncFromSnapshots(
    String attorneyId,
    List<Map<String, dynamic>> caseMaps, {
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? hearings,
  }) async {
    if (_syncWritesBlocked || !canWriteCalendarSync(attorneyId)) return;
    try {
      final docs =
          hearings ?? await _loadHearingDocsScoped(attorneyId, caseMaps);

      for (var i = 0; i < docs.length; i++) {
        final doc = docs[i];
        if (i > 0 && i % 8 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        try {
          final hd = doc.data();
          if (!isCalendarDisplayableHearingRow(hd)) {
            continue;
          }
          if (!hearingMatchesAttorneyCalendar(hd, caseMaps, attorneyId)) {
            continue;
          }
          final when = CalendarLiveHearingMap.parseHearingWhen(hd) ??
              HearingCalendarFields.resolveEventDate(hd);
          if (when == null) continue;
          await _upsertCalendarEvent(
            hearingDocId: doc.id,
            hd: hd,
            when: when,
            attorneyId: attorneyId,
          );
        } catch (e) {
          if (_isPermissionDenied(e)) {
            _syncWritesBlocked = true;
            return;
          }
        }
      }
    } catch (e) {
      if (_isPermissionDenied(e)) {
        _syncWritesBlocked = true;
        return;
      }
      if (kDebugMode) debugPrint('HearingCalendarSync._syncFromSnapshots: $e');
    }
  }

  Future<void> _upsertCalendarEvent({
    required String hearingDocId,
    required Map<String, dynamic> hd,
    required DateTime when,
    required String attorneyId,
  }) async {
    if (!canWriteCalendarSync(attorneyId)) return;
    if (HearingCalendarFields.isNonCourtHearingSpam(hd)) {
      try {
        await _db
            .collection('calendar_events')
            .doc(calendarDocId(hearingDocId))
            .delete();
      } catch (_) {}
      return;
    }

    final ref = _db
        .collection('calendar_events')
        .doc(calendarDocId(hearingDocId));
    try {
      final existing = await ref.get();
      if (existing.exists) {
        final existingMs =
            (existing.data()?['eventDate'] as Timestamp?)
                ?.millisecondsSinceEpoch;
        if (existingMs == when.millisecondsSinceEpoch) {
          return;
        }
      }

      final fields = HearingCalendarFields.fromHearingDoc(hd);
      if (HearingCalendarFields.isNonCourtHearingSpam({
        'title': fields.title,
        'description': fields.description,
        'activityType': fields.hearingPurpose,
      })) {
        await ref.delete();
        return;
      }
      final eventWhen = fields.eventDate ?? when;
      final resolvedCaseId = fields.caseId ?? (hd['caseId'] as String?)?.trim();
      final clientId = resolvedCaseId != null && resolvedCaseId.isNotEmpty
          ? await _clientIdForCase(resolvedCaseId)
          : null;

      final payload = <String, dynamic>{
        'eventType': 'hearing',
        'eventDate': Timestamp.fromDate(eventWhen),
        'assignedTo': attorneyId,
        'source': sourceTag,
        'hearingDocId': hearingDocId,
        'readOnly': true,
        'updatedAt': FieldValue.serverTimestamp(),
        ...fields.toCalendarEventPayload(),
        if (clientId != null && clientId.isNotEmpty) 'clientId': clientId,
      };
      payload['eventDate'] = Timestamp.fromDate(eventWhen);

      if (!existing.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['createdBy'] =
            FirebaseAuth.instance.currentUser?.uid ??
            (hd['senderId'] as String?)?.trim() ??
            (hd['uploadedBy'] as String?)?.trim() ??
            attorneyId;
        payload['createdByRole'] = 'attorney';
        payload['notificationSent'] = false;
        payload['remindAttorney'] = false;
        payload['remindClient'] = false;
        payload['selectedClientIds'] = <String>[];
        payload['notifyStaff'] = false;
      }

      await ref.set(payload, SetOptions(merge: true));
    } catch (e) {
      if (_isPermissionDenied(e)) {
        _syncWritesBlocked = true;
        return;
      }
      rethrow;
    }
  }

  Future<Set<String>> _resolveAttorneyIds(Map<String, dynamic> hd) async {
    final ids = <String>{};

    final attorneyUid = (hd['attorneyUid'] as String?)?.trim();
    if (attorneyUid != null && attorneyUid.isNotEmpty) ids.add(attorneyUid);

    final notify = hd['notifyUserIds'];
    if (notify is List) {
      for (final x in notify) {
        if (x is String && x.trim().length > 8) ids.add(x.trim());
      }
    }

    final caseId = (hd['caseId'] as String?)?.trim() ?? '';
    if (caseId.isNotEmpty) {
      try {
        final c = await _db.collection('cases').doc(caseId).get();
        final aid = (c.data()?['attorneyId'] as String?)?.trim();
        if (aid != null && aid.isNotEmpty) ids.add(aid);
      } catch (_) {}
    }

    if (ids.isEmpty) {
      final caseNo = (hd['caseNo'] as String?)?.trim() ?? '';
      if (caseNo.isNotEmpty) {
        try {
          for (final field in [
            'caseNumber',
            'caseNo',
            'docketNumber',
            'criminalCaseNo',
          ]) {
            final q = await _db
                .collection('cases')
                .where(field, isEqualTo: caseNo)
                .limit(3)
                .get();
            for (final doc in q.docs) {
              final aid = (doc.data()['attorneyId'] as String?)?.trim();
              if (aid != null && aid.isNotEmpty) ids.add(aid);
            }
            if (ids.isNotEmpty) break;
          }
        } catch (_) {}
      }
    }

    return ids;
  }

  Future<List<Map<String, dynamic>>> _caseMapsForAttorney(
    String attorneyId,
  ) async {
    final snap = await _db
        .collection('cases')
        .where('attorneyId', isEqualTo: attorneyId)
        .get();
    return snap.docs
        .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
        .toList();
  }

  Future<String?> _clientIdForCase(String caseId) async {
    try {
      final c = await _db.collection('cases').doc(caseId).get();
      return (c.data()?['clientId'] as String?)?.trim();
    } catch (_) {
      return null;
    }
  }

  @Deprecated('Use HearingCalendarFields.resolveEventDate')
  static DateTime? hearingCalendarDateTime(Map<String, dynamic> hd) =>
      HearingCalendarFields.resolveEventDate(hd);
}

class _CombinedSubscription implements StreamSubscription<dynamic> {
  _CombinedSubscription(this._subs);
  final List<StreamSubscription<dynamic>> _subs;

  @override
  Future<void> cancel() async {
    for (final s in _subs) {
      await s.cancel();
    }
  }

  @override
  void onData(void Function(dynamic data)? handleData) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {
    for (final s in _subs) {
      s.pause(resumeSignal);
    }
  }

  @override
  void resume() {
    for (final s in _subs) {
      s.resume();
    }
  }

  @override
  bool get isPaused => _subs.every((s) => s.isPaused);

  @override
  Future<E> asFuture<E>([E? futureValue]) => _subs.first.asFuture(futureValue);
}
