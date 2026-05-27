import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'hearing_calendar_fields.dart';
import 'hearing_notification_fanout_service.dart';

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

  /// After Firestore denies calendar sync writes, skip further attempts this session.
  bool _syncWritesBlocked = false;

  static String calendarDocId(String hearingDocId) => 'hearing_cal_$hearingDocId';

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

  /// Start live sync + one-time backfill for an attorney calendar screen.
  void attachForAttorney(String attorneyId) {
    final aid = attorneyId.trim();
    if (aid.isEmpty || _attachedAttorneys.contains(aid)) return;
    _attachedAttorneys.add(aid);

    if (canWriteCalendarSync(aid)) {
      unawaited(syncAllForAttorney(aid));
    }

    StreamSubscription<dynamic>? casesSub;
    StreamSubscription<dynamic>? hearingsSub;
    List<Map<String, dynamic>> caseMaps = [];

    void runSync() {
      if (_syncWritesBlocked || !canWriteCalendarSync(aid)) return;
      unawaited(_syncFromSnapshots(aid, caseMaps));
    }

    casesSub = _db
        .collection('cases')
        .where('attorneyId', isEqualTo: aid)
        .snapshots()
        .listen(
      (snap) {
        caseMaps = snap.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList();
        runSync();
      },
      onError: (_) {},
    );

    hearingsSub = _db.collection('hearings').limit(500).snapshots().listen(
      (_) => runSync(),
      onError: (_) {},
    );

    _subs[aid] = _CombinedSubscription([casesSub, hearingsSub]);
  }

  void detachForAttorney(String attorneyId) {
    final aid = attorneyId.trim();
    _attachedAttorneys.remove(aid);
    _subs.remove(aid)?.cancel();
    _overlaySubs.remove(aid)?.cancel();
    _overlayControllers.remove(aid)?.close();
    _overlayControllers.remove(aid);
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
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadHearingDocsScoped(
    String attorneyId,
    List<Map<String, dynamic>> caseMaps,
  ) async {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final aid = attorneyId.trim();

    Future<void> absorb(Query<Map<String, dynamic>> query) async {
      try {
        final snap = await query.get();
        for (final d in snap.docs) {
          byId[d.id] = d;
        }
      } catch (e) {
        if (_isPermissionDenied(e)) return;
      }
    }

    await absorb(
      _db
          .collection('hearings')
          .where('attorneyUid', isEqualTo: aid)
          .limit(300),
    );

    final caseIds = <String>[];
    for (final c in caseMaps) {
      final id = (c['id'] as String?)?.trim() ?? '';
      if (id.isNotEmpty) caseIds.add(id);
    }
    for (var i = 0; i < caseIds.length; i += 30) {
      final end = i + 30 > caseIds.length ? caseIds.length : i + 30;
      final chunk = caseIds.sublist(i, end);
      await absorb(
        _db
            .collection('hearings')
            .where('caseId', whereIn: chunk)
            .limit(100),
      );
    }

    final caseNos = <String>{};
    for (final c in caseMaps) {
      for (final field in [
        'caseNumber',
        'caseNo',
        'docketNumber',
        'criminalCaseNo',
      ]) {
        final v = (c[field] as String?)?.trim() ?? '';
        if (v.isNotEmpty) caseNos.add(v);
      }
    }
    for (final caseNo in caseNos.take(24)) {
      await absorb(
        _db
            .collection('hearings')
            .where('caseNo', isEqualTo: caseNo)
            .limit(40),
      );
    }

    return byId.values.toList();
  }

  /// Real-time hearing rows for calendar UI (same shape as [getCalendarEvents]).
  Stream<List<Map<String, dynamic>>> watchHearingEntriesForAttorney(
    String attorneyId,
  ) {
    final aid = attorneyId.trim();
    if (aid.isEmpty) return Stream.value(const []);

    final existing = _overlayControllers[aid];
    if (existing != null) return existing.stream;

    final controller =
        StreamController<List<Map<String, dynamic>>>.broadcast();
    _overlayControllers[aid] = controller;
    List<Map<String, dynamic>> caseMaps = [];
    final firmViewer = _isFirmViewerForAttorney(aid);

    QuerySnapshot<Map<String, dynamic>>? lastGlobalHearings;
    QuerySnapshot<Map<String, dynamic>>? lastAttorneyUidHearings;
    List<QueryDocumentSnapshot<Map<String, dynamic>>> scopedDocs = [];
    var scopedReady = false;

    Future<void> emit() async {
      try {
        final merged =
            <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        final attorneyUidSnap = lastAttorneyUidHearings;
        if (attorneyUidSnap != null) {
          for (final d in attorneyUidSnap.docs) {
            merged[d.id] = d;
          }
        }
        for (final d in scopedDocs) {
          merged[d.id] = d;
        }
        final globalSnap = lastGlobalHearings;
        if (!firmViewer && globalSnap != null) {
          for (final d in globalSnap.docs) {
            merged[d.id] = d;
          }
        }

        if (merged.isEmpty) {
          if (firmViewer && !scopedReady) {
            return;
          }
          if (!firmViewer && lastGlobalHearings == null) {
            if (!controller.isClosed) controller.add(const []);
            return;
          }
          if (!controller.isClosed) controller.add(const []);
          return;
        }

        final rows = projectHearingsFromDocs(
          aid,
          caseMaps,
          merged.values.toList(),
        );
        if (!controller.isClosed) controller.add(rows);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('HearingCalendarSync.emit: $e\n$st');
        }
      }
    }

    Future<void> refreshScoped() async {
      scopedDocs = await _loadHearingDocsScoped(aid, caseMaps);
      scopedReady = true;
      await emit();
    }

    void handleOverlayStreamError(Object e, {required bool casesStream}) {
      if (_isPermissionDenied(e)) {
        if (casesStream) {
          caseMaps = [];
        } else if (firmViewer) {
          lastAttorneyUidHearings = null;
        } else {
          lastGlobalHearings = null;
        }
        unawaited(refreshScoped());
        return;
      }
      if (kDebugMode) debugPrint('HearingCalendarSync overlay stream: $e');
    }

    final casesSub = _db
        .collection('cases')
        .where('attorneyId', isEqualTo: aid)
        .snapshots()
        .listen(
      (snap) {
        caseMaps = snap.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList();
        unawaited(refreshScoped());
      },
      onError: (e) => handleOverlayStreamError(e, casesStream: true),
    );

    late final StreamSubscription<dynamic> hearingsSub;
    if (firmViewer) {
      hearingsSub = _db
          .collection('hearings')
          .where('attorneyUid', isEqualTo: aid)
          .limit(300)
          .snapshots()
          .listen(
        (snap) {
          lastAttorneyUidHearings = snap;
          unawaited(emit());
        },
        onError: (e) => handleOverlayStreamError(e, casesStream: false),
      );
      unawaited(refreshScoped());
    } else {
      hearingsSub = _db.collection('hearings').limit(500).snapshots().listen(
        (snap) {
          lastGlobalHearings = snap;
          unawaited(emit());
          if (!_syncWritesBlocked && canWriteCalendarSync(aid)) {
            unawaited(_syncFromSnapshots(aid, caseMaps, hearings: snap.docs));
          }
        },
        onError: (e) => handleOverlayStreamError(e, casesStream: false),
      );
      if (!_syncWritesBlocked && canWriteCalendarSync(aid)) {
        unawaited(syncAllForAttorney(aid));
      }
    }

    _overlaySubs[aid] = _CombinedSubscription([casesSub, hearingsSub]);

    return controller.stream;
  }

  List<Map<String, dynamic>> _projectHearingsForAttorney(
    String attorneyId,
    List<Map<String, dynamic>> caseMaps,
  ) {
    // Populated on next hearings snapshot via emit(); empty until first fire.
    return _lastProjected[attorneyId] ?? const [];
  }

  final Map<String, List<Map<String, dynamic>>> _lastProjected = {};

  /// Calendar overlay: include firm hearings with a schedule + case/client info.
  static bool hearingMatchesAttorneyCalendar(
    Map<String, dynamic> hearing,
    List<Map<String, dynamic>> attorneyCaseMaps,
    String attorneyId,
  ) {
    if (HearingNotificationFanoutService.hearingMatchesAttorneyCases(
      hearing,
      attorneyCaseMaps,
      attorneyId,
    )) {
      return true;
    }

    final aid = attorneyId.trim();
    if (aid.isEmpty) return false;

    final attorneyUid = (hearing['attorneyUid'] as String?)?.trim() ?? '';
    if (attorneyUid == aid) return true;

    final notify = hearing['notifyUserIds'];
    if (notify is List && notify.contains(aid)) return true;

    final caseNo = (hearing['caseNo'] as String?)?.trim() ?? '';
    final clientName = (hearing['clientName'] as String?)?.trim() ?? '';
    final caseTitle = (hearing['caseTitle'] as String?)?.trim() ?? '';
    final hearingDate =
        HearingCalendarFields.hearingFieldAsString(hearing, 'hearingDate');
    final location = (hearing['location'] as String?)?.trim() ?? '';
    final summary = (hearing['summary'] as String?)?.trim() ?? '';

    // Firestore `hearings` rows with explicit schedule (e.g. April 22, 2026 + location).
    if (hearingDate.isNotEmpty &&
        (caseNo.isNotEmpty ||
            clientName.isNotEmpty ||
            caseTitle.isNotEmpty ||
            location.isNotEmpty ||
            summary.isNotEmpty)) {
      return true;
    }

    if (attorneyCaseMaps.isNotEmpty &&
        (caseNo.isNotEmpty ||
            clientName.isNotEmpty ||
            caseTitle.isNotEmpty ||
            hearingDate.isNotEmpty ||
            location.isNotEmpty)) {
      return true;
    }

    try {
      if (HearingCalendarFields.resolveEventDate(hearing) != null &&
          (summary.isNotEmpty ||
              HearingCalendarFields.isCourtImportRow(hearing))) {
        return attorneyCaseMaps.isNotEmpty || attorneyUid == aid;
      }
    } catch (_) {}

    return false;
  }

  static bool isCalendarDisplayableHearingRow(Map<String, dynamic> d) {
    if (HearingNotificationFanoutService.isDisplayableHearingRow(d)) {
      return true;
    }
    return HearingCalendarFields.hearingFieldAsString(d, 'hearingDate')
            .isNotEmpty ||
        HearingCalendarFields.fieldAsDisplayString(d, 'hearingTime')
            .isNotEmpty ||
        (d['location'] as String?)?.trim().isNotEmpty == true ||
        (d['clientName'] as String?)?.trim().isNotEmpty == true ||
        (d['caseNo'] as String?)?.trim().isNotEmpty == true ||
        (d['caseTitle'] as String?)?.trim().isNotEmpty == true ||
        (d['summary'] as String?)?.trim().isNotEmpty == true;
  }

  List<Map<String, dynamic>> projectHearingsFromDocs(
    String attorneyId,
    List<Map<String, dynamic>> caseMaps,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final doc in docs) {
      try {
        final hd = HearingCalendarFields.normalizeHearingDoc(doc.data());
        if (!isCalendarDisplayableHearingRow(hd)) {
          continue;
        }
        if (!hearingMatchesAttorneyCalendar(hd, caseMaps, attorneyId)) {
          continue;
        }
        DateTime? when;
        try {
          when = HearingCalendarFields.resolveEventDate(hd);
          when ??=
              HearingCalendarFields.resolveEventDateFromHearingDateField(hd);
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              'HearingCalendarSync.projectHearingsFromDocs date: $e',
            );
          }
          continue;
        }
        if (when == null) continue;

        final map = HearingCalendarFields.toCalendarOverlayRow(
          raw: hd,
          hearingDocId: doc.id,
          attorneyId: attorneyId,
          when: when,
          caseMaps: caseMaps,
        );
        if (map == null) continue;
        map['source'] = sourceTag;
        out.add(map);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('HearingCalendarSync.projectHearingsFromDocs: $e');
        }
        continue;
      }
    }
    HearingCalendarFields.unifyHearingRecordsForCalendar(out);
    out.sort((a, b) {
      final ad = a['eventDate'];
      final bd = b['eventDate'];
      if (ad is! DateTime || bd is! DateTime) return 0;
      return ad.compareTo(bd);
    });
    return out;
  }

  Future<void> syncAllForAttorney(String attorneyId) async {
    final aid = attorneyId.trim();
    if (aid.isEmpty || !canWriteCalendarSync(aid)) return;

    try {
      final casesSnap = await _db
          .collection('cases')
          .where('attorneyId', isEqualTo: aid)
          .get();
      final caseMaps = casesSnap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();

      final hearingsSnap = await _db.collection('hearings').limit(500).get();
      await _syncFromSnapshots(aid, caseMaps, hearings: hearingsSnap.docs);
    } catch (e) {
      if (kDebugMode) debugPrint('HearingCalendarSync.syncAllForAttorney: $e');
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
          hearings ??
          (await _db.collection('hearings').limit(500).get()).docs;

      for (final doc in docs) {
        try {
          final hd = doc.data();
          if (!isCalendarDisplayableHearingRow(hd)) {
            continue;
          }
          if (!hearingMatchesAttorneyCalendar(hd, caseMaps, attorneyId)) {
            continue;
          }
          final when = HearingCalendarFields.resolveEventDate(hd);
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

    final fields = HearingCalendarFields.fromHearingDoc(hd);
    final eventWhen = fields.eventDate ?? when;
    final resolvedCaseId =
        fields.caseId ?? (hd['caseId'] as String?)?.trim();
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

    final ref = _db.collection('calendar_events').doc(calendarDocId(hearingDocId));
    try {
      final existing = await ref.get();
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
  Future<E> asFuture<E>([E? futureValue]) =>
      _subs.first.asFuture(futureValue);
}
