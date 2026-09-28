import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/appointment_model.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../services/auth_service.dart';
import '../../services/hearing_calendar_fields.dart';
import '../../services/hearing_calendar_sync_service.dart';
import '../../services/staff_service.dart';
import '../../services/notary_service.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../../utils/calendar_perf.dart';
import '../../utils/calendar_hearing_nav.dart';
import '../../utils/calendar_live_hearing_map.dart';
import '../../utils/firestore_query_get.dart';
import '../../widgets/common/hearing_calendar_event_body.dart';
import '../../widgets/common/hearing_notification_detail_panel.dart';
import '../../widgets/common/calendar_month_grid.dart';
import '../../widgets/common/stable_merged_listenable_builder.dart';

import 'appointment_scheduler_form.dart';
import 'attorney_notary_request_detail_screen.dart';

/// Single cell in the unified attorney calendar: client appointment OR Firestore hearing/deadline.
class _AttorneyCalendarEntry {
  _AttorneyCalendarEntry._({this.appointment, this.hearingEvent})
    : assert(
        (appointment != null) ^ (hearingEvent != null),
        'Exactly one of appointment or hearingEvent',
      );

  factory _AttorneyCalendarEntry.fromAppointment(AppointmentModel a) =>
      _AttorneyCalendarEntry._(appointment: a);

  factory _AttorneyCalendarEntry.fromHearing(Map<String, dynamic> m) =>
      _AttorneyCalendarEntry._(hearingEvent: Map<String, dynamic>.from(m));

  final AppointmentModel? appointment;
  final Map<String, dynamic>? hearingEvent;

  bool get isHearing => hearingEvent != null;

  /// Auto-placed: court email, legal assistant, or hearings → calendar sync.
  bool get isAiScheduled {
    if (hearingEvent == null) return false;
    return isAiSyncedCalendarEvent(hearingEvent!);
  }

  String involvedPartiesLabel() {
    if (hearingEvent == null) return '';
    final raw = hearingEvent!['involvedParties'];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .join(' · ');
    }
    return '';
  }

  DateTime get startTime {
    if (appointment != null) return appointment!.appointmentDateTime;
    final dt = hearingEvent!['eventDate'];
    if (dt is DateTime) return dt;
    if (dt is Timestamp) return dt.toDate();
    return DateTime.now();
  }

  String hearingTitle() {
    final caseNo = HearingCalendarFields.asDisplayString(hearingEvent!['caseNo']);
    if (caseNo.isNotEmpty) return caseNo;
    final client =
        HearingCalendarFields.asDisplayString(hearingEvent!['clientName']);
    if (client.isNotEmpty) return client;
    final caseTitle =
        HearingCalendarFields.asDisplayString(hearingEvent!['caseTitle']);
    if (caseTitle.isNotEmpty) return caseTitle;
    final t = HearingCalendarFields.asDisplayString(hearingEvent!['title']);
    if (t.isNotEmpty) {
      return t.replaceFirst(RegExp(r'^\[AI\]\s*'), '');
    }
    return 'Hearing';
  }

  /// Short label for month grid cells (client name first — matches legacy UI).
  String calendarCellLabel() {
    if (appointment != null) return '';
    final client =
        HearingCalendarFields.asDisplayString(hearingEvent!['clientName']);
    if (client.isNotEmpty) return client;
    final caseNo = HearingCalendarFields.asDisplayString(hearingEvent!['caseNo']);
    if (caseNo.isNotEmpty) return caseNo;
    final title = hearingTitle();
    return title.replaceFirst(RegExp(r'^\[AI\]\s*'), '');
  }

  String hearingTypeLabel() {
    final et = hearingEvent!['eventType'];
    if (et is String && et.isNotEmpty) {
      return et[0].toUpperCase() + et.substring(1);
    }
    return 'Event';
  }
}

class AppointmentCalendarView extends StatefulWidget {
  /// Pre-filled from dashboard so the grid shows instantly on first open.
  final List<AppointmentModel>? initialAppointments;

  /// Reuse dashboard Firestore stream (avoids duplicate listeners / lag).
  final Stream<List<AppointmentModel>>? sharedAppointmentsStream;

  /// When true, no nested [Scaffold] — required inside [AttorneyDashboard] tabs.
  final bool embedded;

  /// Staff calendar: view this attorney’s grid (same UI as attorney).
  final String? attorneyId;

  /// Staff calendar: + opens add-event instead of the attorney scheduler.
  final VoidCallback? onAddPressed;

  /// Staff calendar: empty-day tap opens add-event for that date.
  final Future<void> Function(DateTime day)? onAddForDate;

  /// Top-right + on the embedded mobile header. Staff app hides this.
  final bool showTopAddButton;

  /// Push the month row below the device status bar. Staff app only.
  final bool padHeaderForStatusBar;

  /// Staff calendar: open notary details with staff actions and full request info.
  final bool actingAsStaff;

  const AppointmentCalendarView({
    super.key,
    this.initialAppointments,
    this.sharedAppointmentsStream,
    this.embedded = false,
    this.attorneyId,
    this.onAddPressed,
    this.onAddForDate,
    this.showTopAddButton = true,
    this.padHeaderForStatusBar = false,
    this.actingAsStaff = false,
  });

  @override
  State<AppointmentCalendarView> createState() =>
      _AppointmentCalendarViewState();
}

class _AppointmentCalendarViewState extends State<AppointmentCalendarView> {
  static final Map<String, List<Map<String, dynamic>>>
  _calendarEventsCacheByAttorney = <String, List<Map<String, dynamic>>>{};

  final EnhancedAppointmentService _appointmentService =
      EnhancedAppointmentService();
  final AuthService _authService = AuthService();
  final StaffService _staffService = StaffService();
  final NotaryService _notaryService = NotaryService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late final ValueNotifier<DateTime> _viewDateNotifier = ValueNotifier(
    DateTime.now(),
  );
  DateTime get _viewDate => _viewDateNotifier.value;
  String _viewMode = 'month'; // 'month' or 'week'
  List<AppointmentModel> _appointments = [];

  /// Hearings/deadlines/meetings from `calendar_events` (manual + AI-synced hearings).
  List<Map<String, dynamic>> _calendarEvents = [];

  StreamSubscription<List<Map<String, dynamic>>>? _calendarEventsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _liveHearingsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _notaryCalendarSub;
  StreamSubscription<List<AppointmentModel>>? _appointmentsSub;
  bool _ownsAppointmentsStream = false;
  Timer? _dataUiDebounce;

  /// Precomputed day → entries map so the month grid does not rescan all data 42× per frame.
  Map<String, List<_AttorneyCalendarEntry>> _entriesByDayKey = {};
  List<Map<String, dynamic>>? _pendingCalendarEvents;
  List<AppointmentModel>? _pendingAppointments;
  List<Map<String, dynamic>>? _pendingLiveHearings;
  String _lastCalendarFingerprint = '';
  String _lastAppointmentsFingerprint = '';
  String _lastLiveHearingsFingerprint = '';
  String _lastEntriesIndexFingerprint = '';
  int _entriesRevision = 0;
  final ValueNotifier<int> _entriesRevisionNotifier = ValueNotifier(0);
  List<Map<String, dynamic>> _cachedHearingNavEvents = [];
  List<Map<String, dynamic>> _liveHearingRows = [];
  List<Map<String, dynamic>> _notaryCalendarRows = [];
  int _entriesIndexGen = 0;
  bool _didRevealHearingMonth = false;
  final Set<String> _seenHearingDocIds = {};
  bool _followNewHearings = false;
  Timer? _armFollowTimer;
  bool _notaryCalendarReady = false;
  Timer? _entriesIndexDebounce;
  Timer? _clientNamesDebounce;
  final ValueNotifier<int> _hearingNavRevision = ValueNotifier(0);
  bool _flushDataImmediately = true;
  bool _entriesIndexFlushImmediately = true;

  final Map<String, String> _clientNameCache =
      <String, String>{}; // Cache for client full names
  final Map<String, String> _clientEmailCache =
      <String, String>{}; // Cache for client emails

  // Calendar color theme (match reference UI: blue + gold, Sunday red)
  static const Color calendarBlue = Color.fromARGB(255, 46, 109, 192);
  static const Color calendarGold = Color(0xFFF4C10F);
  static const Color sundayRed = Color(0xFFE53935);
  // Accent color for appointment pills (reuse calendar blue by default)
  static const Color primaryRed = calendarBlue;

  /// Court / automation calendar events (distinct from client appointments).
  static const Color hearingEventColor = Color(0xFF5E35B1);

  /// Shown on auto-placed calendar events (email ingest, hearings sync, legal assistant).
  static const String _aiSchedLabel = 'AI SCHD';

  Widget _aiSchedBadge({required bool compact}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 2 : 6,
        vertical: compact ? 1 : 3,
      ),
      decoration: BoxDecoration(
        color: calendarGold,
        borderRadius: BorderRadius.circular(compact ? 3 : 6),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          _aiSchedLabel,
          maxLines: 1,
          style: TextStyle(
            fontSize: compact ? 6.5 : 10,
            height: 1,
            color: Colors.black87,
            fontWeight: FontWeight.w800,
            letterSpacing: compact ? -0.25 : 0,
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final seed = widget.initialAppointments;
    if (seed != null && seed.isNotEmpty) {
      _appointments = List<AppointmentModel>.from(seed);
    }
    _hydrateCalendarEventsFromCache();
    _hydrateLiveHearingsFromCache();
    _paintGridFromCachedData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bindAppointments();
      _subscribeCalendarEvents();
      _subscribeNotaryCalendar();
      Future<void>.delayed(
        const Duration(milliseconds: CalendarPerf.hearingStreamDeferMs),
        () {
          if (!mounted) return;
          _subscribeLiveHearings();
        },
      );
      Future<void>.delayed(
        Duration(milliseconds: kIsWeb ? 200 : 2000),
        () {
          if (mounted) unawaited(_loadAutomatedHearings());
        },
      );
    });
  }

  List<Map<String, dynamic>> get _effectiveHearingRows => _liveHearingRows;

  List<Map<String, dynamic>> _gridCalendarEvents() {
    final merged = CalendarLiveHearingMap.mergeIntoCalendarEvents(
      _calendarEvents,
      _effectiveHearingRows,
    );
    if (_notaryCalendarRows.isEmpty) return merged;
    return [...merged, ..._notaryCalendarRows];
  }

  void _hydrateCalendarEventsFromCache() {
    final uid = _calendarAttorneyId();
    if (uid.isEmpty) return;
    final cached = _calendarEventsCacheByAttorney[uid];
    if (cached == null || cached.isEmpty) return;
    _calendarEvents = List<Map<String, dynamic>>.from(cached);
    _lastCalendarFingerprint = _calendarEventsFingerprint(_calendarEvents);
    _seedSeenHearings(_calendarEvents);
  }

  void _hydrateLiveHearingsFromCache() {
    final uid = _calendarAttorneyId();
    if (uid.isEmpty) return;
    final cached = HearingCalendarSyncService.instance.peekHearingNavRows(uid);
    if (cached == null || cached.isEmpty) return;
    _liveHearingRows = List<Map<String, dynamic>>.from(cached);
    _lastLiveHearingsFingerprint = CalendarPerf.eventsFingerprint(_liveHearingRows);
    _seedSeenHearings(_liveHearingRows);
  }

  void _paintGridFromCachedData() {
    if (_calendarEvents.isEmpty &&
        _liveHearingRows.isEmpty &&
        _appointments.isEmpty) {
      return;
    }
    _rebuildHearingNavCache();
    _scheduleEntriesIndexRebuild();
    _hearingNavRevision.value++;
  }

  void _scheduleEntriesIndexRebuild({bool immediate = false}) {
    _entriesIndexDebounce?.cancel();
    if (immediate) _entriesIndexFlushImmediately = true;
    final ms = _entriesIndexFlushImmediately
        ? 0
        : CalendarPerf.entriesIndexDebounceMs;
    _entriesIndexDebounce = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      unawaited(_rebuildEntriesIndexAsync());
      _entriesIndexFlushImmediately = false;
    });
  }

  String _entriesIndexFingerprint() =>
      '${_appointmentsFingerprint(_appointments)}|${_calendarEventsFingerprint(_calendarEvents)}|${_calendarEventsFingerprint(_liveHearingRows)}|${_calendarEventsFingerprint(_notaryCalendarRows)}';

  Future<void> _rebuildEntriesIndexAsync() async {
    final gen = ++_entriesIndexGen;
    final fp = _entriesIndexFingerprint();
    if (fp == _lastEntriesIndexFingerprint && _entriesByDayKey.isNotEmpty) {
      return;
    }

    final appointments = List<AppointmentModel>.from(_appointments);
    final calendarEvents = _gridCalendarEvents();

    await Future<void>.delayed(Duration.zero);
    if (!mounted || gen != _entriesIndexGen) return;

    final buckets = <String, List<_AttorneyCalendarEntry>>{};
    final hearingIdsByDay = <String, Set<String>>{};

    for (final apt in appointments) {
      if (apt.appointmentType == 'hearing_court') continue;
      if (!apt.appearsOnAttorneyCalendar) continue;
      final d = apt.appointmentDateTime;
      final key = _dayKey(DateTime(d.year, d.month, d.day));
      buckets
          .putIfAbsent(key, () => [])
          .add(_AttorneyCalendarEntry.fromAppointment(apt));
    }

    void addHearing(Map<String, dynamic> ev) {
      final type = (ev['eventType'] as String?)?.trim().toLowerCase() ?? '';
      if (type == 'appointment') return;
      final eventDate = _dateTimeFromField(ev['eventDate']);
      if (eventDate == null) return;
      final day = DateTime(eventDate.year, eventDate.month, eventDate.day);
      final key = _dayKey(day);
      final hid = (ev['hearingDocId'] as String?)?.trim() ?? '';
      if (hid.isNotEmpty) {
        final seen = hearingIdsByDay.putIfAbsent(key, () => <String>{});
        if (seen.contains(hid)) return;
        seen.add(hid);
      }
      buckets
          .putIfAbsent(key, () => [])
          .add(_AttorneyCalendarEntry.fromHearing(ev));
    }

    for (var i = 0; i < calendarEvents.length; i++) {
      if (i > 0 && i % 50 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
      }
      addHearing(calendarEvents[i]);
    }

    if (!mounted || gen != _entriesIndexGen) return;

    for (final key in buckets.keys.toList()) {
      buckets[key] = _dedupeCalendarEntriesForDay(buckets[key]!);
    }

    if (!mounted || gen != _entriesIndexGen) return;
    _lastEntriesIndexFingerprint = fp;
    _entriesByDayKey = buckets;
    _entriesRevision++;
    _entriesRevisionNotifier.value++;
  }

  void _rebuildEntriesIndex() {
    unawaited(_rebuildEntriesIndexAsync());
  }

  void _scheduleDeferredClientNamesLoad() {
    _clientNamesDebounce?.cancel();
    _clientNamesDebounce = Timer(
      const Duration(milliseconds: CalendarPerf.clientNamesLoadDeferMs),
      () {
        if (!mounted || _appointments.isEmpty) return;
        unawaited(_loadClientNames(_appointments));
      },
    );
  }

  @override
  void didUpdateWidget(AppointmentCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sharedAppointmentsStream != widget.sharedAppointmentsStream ||
        oldWidget.attorneyId != widget.attorneyId) {
      final seed = widget.initialAppointments;
      if (seed != null && seed.isNotEmpty) {
        _appointments = List<AppointmentModel>.from(seed);
      }
      _hydrateCalendarEventsFromCache();
      _hydrateLiveHearingsFromCache();
      _bindAppointments();
      _subscribeCalendarEvents();
      _subscribeLiveHearings();
      _subscribeNotaryCalendar();
    }
  }

  @override
  void dispose() {
    _dataUiDebounce?.cancel();
    _entriesIndexDebounce?.cancel();
    _clientNamesDebounce?.cancel();
    _armFollowTimer?.cancel();
    _hearingNavRevision.dispose();
    _entriesRevisionNotifier.dispose();
    _viewDateNotifier.dispose();
    _calendarEventsSub?.cancel();
    _liveHearingsSub?.cancel();
    _notaryCalendarSub?.cancel();
    if (_ownsAppointmentsStream) {
      _appointmentsSub?.cancel();
    }
    super.dispose();
  }

  void _subscribeNotaryCalendar() {
    final aid = _calendarAttorneyId();
    if (aid.isEmpty) {
      _notaryCalendarReady = true;
      return;
    }
    _notaryCalendarSub?.cancel();
    _notaryCalendarSub = _notaryService.watchNotaryCalendarRows(aid).listen(
      (rows) {
        if (!mounted) return;
        _notaryCalendarRows = rows;
        _notaryCalendarReady = true;
        _scheduleEntriesIndexRebuild(immediate: true);
        _hearingNavRevision.value++;
        _maybeRevealHearingMonth();
      },
      onError: (_) {
        if (!mounted) return;
        _notaryCalendarReady = true;
        _maybeRevealHearingMonth();
      },
    );
  }

  void _subscribeLiveHearings() {
    final aid = HearingCalendarSyncService.overlayKey(_calendarAttorneyId());

    _liveHearingsSub?.cancel();
    _liveHearingsSub = _staffService.watchLiveHearingsForGrid(aid).listen(
      (rows) {
        if (rows.isNotEmpty) {
          _applyAutomatedHearingRows(rows);
          return;
        }
        _pendingLiveHearings = rows;
        _scheduleDataUiFlush();
      },
      onError: (_) {},
    );
  }

  String _calendarAttorneyId() {
    final override = widget.attorneyId?.trim() ?? '';
    if (override.isNotEmpty) return override;
    final fromService = _authService.currentUser?.uid.trim() ?? '';
    if (fromService.isNotEmpty) return fromService;
    return FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  }

  void _handleAddPressed() {
    final custom = widget.onAddPressed;
    if (custom != null) {
      custom();
      return;
    }
    unawaited(_openNewAppointment());
  }

  Future<AppointmentModel?> _handleAddForDate(DateTime day) async {
    final custom = widget.onAddForDate;
    if (custom != null) {
      await custom(day);
      return null;
    }
    return _createAppointmentForDate(day);
  }

  Map<String, dynamic>? _rowFromHearingData(
    String docId,
    Map<String, dynamic> data,
  ) {
    try {
      return _rowFromHearingDataImpl(docId, data);
    } catch (e) {
      debugPrint('[Calendar] skip hearing $docId: $e');
      return null;
    }
  }

  Map<String, dynamic>? _rowFromHearingDataImpl(
    String docId,
    Map<String, dynamic> data,
  ) {
    final aid = _calendarAttorneyId();
    final mapped = CalendarLiveHearingMap.fromHearingDoc(
      data,
      docId,
      aid,
      fallbackToCreatedAt: true,
    );
    if (mapped != null) return mapped;
    final caseNo = HearingCalendarFields.asDisplayString(data['caseNo']).isNotEmpty
        ? HearingCalendarFields.asDisplayString(data['caseNo'])
        : HearingCalendarFields.asDisplayString(data['caseNumber']);
    if (!HearingNotificationFanoutService.isDisplayableHearingRow(data) &&
        caseNo.isEmpty &&
        (data['hearingDate'] == null)) {
      return null;
    }
    final when = CalendarLiveHearingMap.parseHearingWhen(data) ??
        (data['createdAt'] is Timestamp
            ? (data['createdAt'] as Timestamp).toDate()
            : data['updatedAt'] is Timestamp
                ? (data['updatedAt'] as Timestamp).toDate()
                : DateTime.now());
    return CalendarLiveHearingMap.gridRow(
      docId: docId,
      attorneyId: aid,
      when: when,
      caseNo: caseNo,
      clientName: HearingCalendarFields.asDisplayString(data['clientName']),
      caseTitle: HearingCalendarFields.asDisplayString(data['caseTitle']),
      courtBranch: HearingCalendarFields.asDisplayString(data['courtBranch']),
      hearingTime: HearingCalendarFields.asDisplayString(data['hearingTime']),
    );
  }

  /// Newest hearing/order rows — attorneyUid is not required.
  Future<List<Map<String, dynamic>>> _fetchHearingsForCalendar() async {
    final aid = HearingCalendarSyncService.overlayKey(_calendarAttorneyId());
    try {
      final query = _firestore
          .collection('hearings')
          .orderBy('createdAt', descending: true)
          .limit(150);
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await FirestoreQueryGet.hearings(query);
      } catch (e) {
        debugPrint('[Calendar] hearings fetch failed: $e');
        return const [];
      }
      final rows = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final row = _rowFromHearingData(doc.id, doc.data());
        if (row != null) rows.add(row);
      }
      return rows;
    } catch (e) {
      debugPrint('[Calendar] hearings fetch failed: $e');
      return const [];
    }
  }

  /// Fallback when the live overlay missed n8n / court-import hearings.
  Future<void> _loadAutomatedHearings() async {
    if (!mounted) return;
    try {
      var rows = await HearingCalendarSyncService.instance
          .fetchAutomatedCalendarRows(
            HearingCalendarSyncService.overlayKey(_calendarAttorneyId()),
          );
      final inbox = await HearingCalendarSyncService.instance
          .fetchRowsFromHearingNotifications(
            HearingCalendarSyncService.overlayKey(_calendarAttorneyId()),
          );
      rows = CalendarLiveHearingMap.mergeHearingRows(rows, inbox);
      if (rows.isEmpty) {
        rows = await _fetchHearingsForCalendar();
      }
      if (!mounted || rows.isEmpty) return;
      _applyAutomatedHearingRows(rows);
    } catch (e) {
      debugPrint('[Calendar] automated hearings failed: $e');
    }
  }

  void _applyAutomatedHearingRows(List<Map<String, dynamic>> rows) {
    if (!mounted || rows.isEmpty) return;
    final merged = CalendarLiveHearingMap.mergeHearingRows(
      _liveHearingRows,
      rows,
    );
    final fp = CalendarPerf.eventsFingerprint(merged);
    _jumpToInboxHearingMonth(rows);
    if (fp == _lastLiveHearingsFingerprint && _liveHearingRows.isNotEmpty) {
      return;
    }
    _liveHearingRows = merged;
    _lastLiveHearingsFingerprint = fp;
    _lastEntriesIndexFingerprint = '';
    _rebuildHearingNavCache();
    _hearingNavRevision.value++;
    if (!_followNewHearingMonth(_liveHearingRows)) {
      _maybeRevealHearingMonth();
    }
    unawaited(_rebuildEntriesIndexAsync());
  }

  void _jumpToInboxHearingMonth(List<Map<String, dynamic>> rows) {
    DateTime? when;
    for (final r in rows) {
      if (r['fromInbox'] != true) continue;
      final d = _dateTimeFromField(r['eventDate']);
      if (d == null) continue;
      if (when == null || d.isAfter(when)) when = d;
    }
    if (when == null) return;
    final view = _viewDateNotifier.value;
    if (when.year == view.year && when.month == view.month) return;
    _viewDateNotifier.value = DateTime(when.year, when.month);
  }

  void _seedSeenHearings(List<Map<String, dynamic>> rows) {
    CalendarHearingNav.collectHearingIds(rows, _seenHearingDocIds);
  }

  void _scheduleFollowArm() {
    if (_followNewHearings) return;
    _armFollowTimer?.cancel();
    _armFollowTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      _followNewHearings = true;
    });
  }

  /// Jumps to a hearing that arrived after the calendar finished its first load.
  bool _followNewHearingMonth(List<Map<String, dynamic>> rows) {
    if (!_followNewHearings) {
      _seedSeenHearings(rows);
      _scheduleFollowArm();
      return false;
    }
    final when = CalendarHearingNav.newestUnseenHearingDate(
      rows,
      _seenHearingDocIds,
      parseDate: _dateTimeFromField,
    );
    if (when == null) return false;
    final view = _viewDateNotifier.value;
    if (when.year == view.year && when.month == view.month) return true;
    _viewDateNotifier.value = DateTime(when.year, when.month);
    return true;
  }

  bool _eventDateInView(dynamic raw, DateTime view) {
    final d = raw is DateTime ? raw : _dateTimeFromField(raw);
    return d != null && d.year == view.year && d.month == view.month;
  }

  /// Do not jump away from a month that already has hearings or notary.
  void _maybeRevealHearingMonth() {
    if (_didRevealHearingMonth || !_notaryCalendarReady) return;
    if (_liveHearingRows.isEmpty && _notaryCalendarRows.isEmpty) return;
    final view = _viewDateNotifier.value;
    final inView = _liveHearingRows.any(
          (ev) => _eventDateInView(ev['eventDate'], view),
        ) ||
        _notaryCalendarRows.any(
          (ev) => _eventDateInView(ev['eventDate'], view),
        );
    if (inView) {
      _didRevealHearingMonth = true;
      return;
    }
    DateTime? pick;
    void consider(dynamic raw) {
      final d = raw is DateTime ? raw : _dateTimeFromField(raw);
      if (d == null) return;
      if (pick == null || d.isAfter(pick!)) pick = d;
    }

    for (final ev in _liveHearingRows) {
      consider(ev['eventDate']);
    }
    for (final ev in _notaryCalendarRows) {
      consider(ev['eventDate']);
    }
    final jumpTo = pick;
    if (jumpTo == null) return;
    _didRevealHearingMonth = true;
    _viewDateNotifier.value = DateTime(jumpTo.year, jumpTo.month);
  }

  void _scheduleCalendarEventsUi(List<Map<String, dynamic>> events) {
    _pendingCalendarEvents = events;
    _scheduleDataUiFlush();
  }

  String _calendarEventsFingerprint(List<Map<String, dynamic>> events) =>
      CalendarPerf.eventsFingerprint(events);

  String _appointmentsFingerprint(List<AppointmentModel> apps) =>
      CalendarPerf.appointmentsFingerprint(apps);

  void _scheduleDataUiFlush() {
    _dataUiDebounce?.cancel();
    final ms = _flushDataImmediately
        ? CalendarPerf.openingCoalesceMs
        : CalendarPerf.dataDebounceMs;
    _dataUiDebounce = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      _applyPendingDataUi();
      if (_flushDataImmediately) _flushDataImmediately = false;
    });
  }

  void _applyPendingDataUi() {
    if (!mounted) return;
    final pendingCalendar = _pendingCalendarEvents;
    final pendingAppointments = _pendingAppointments;
    _pendingCalendarEvents = null;
    _pendingAppointments = null;

    var calendarChanged = false;
    var appointmentsChanged = false;
    var hearingsChanged = false;

    if (_pendingLiveHearings != null) {
      final rows = _pendingLiveHearings!;
      _pendingLiveHearings = null;
      final merged = rows.isEmpty
          ? _liveHearingRows
          : CalendarLiveHearingMap.mergeHearingRows(_liveHearingRows, rows);
      final fp = CalendarPerf.eventsFingerprint(merged);
      if (fp != _lastLiveHearingsFingerprint) {
        _liveHearingRows = merged;
        _lastLiveHearingsFingerprint = fp;
        hearingsChanged = true;
        _followNewHearingMonth(_liveHearingRows);
      }
    }

    if (pendingCalendar != null) {
      final fp = _calendarEventsFingerprint(pendingCalendar);
      if (fp != _lastCalendarFingerprint) {
        _calendarEvents = _mergeCalendarEventsFromServer(pendingCalendar);
        final aid = _calendarAttorneyId();
        if (aid.isNotEmpty) {
          _calendarEventsCacheByAttorney[aid] = List<Map<String, dynamic>>.from(
            _calendarEvents,
          );
        }
        _lastCalendarFingerprint = fp;
        calendarChanged = true;
        _followNewHearingMonth(_calendarEvents);
      }
    }

    void applyAppointmentsNow() {
      if (pendingAppointments == null) return;
      final fp = _appointmentsFingerprint(pendingAppointments);
      if (fp == _lastAppointmentsFingerprint) return;
      _appointments = pendingAppointments;
      _lastAppointmentsFingerprint = fp;
      appointmentsChanged = true;
      _scheduleDeferredClientNamesLoad();
      final uid = _calendarAttorneyId();
      if (uid.isNotEmpty) {
        unawaited(
          _appointmentService.syncOccupiedTimeSlotsIfNeeded(uid, _appointments),
        );
      }
    }

    void commitUi() {
      if (!calendarChanged && !appointmentsChanged && !hearingsChanged) {
        return;
      }
      _rebuildHearingNavCache();
      _scheduleEntriesIndexRebuild();
      _hearingNavRevision.value++;
    }

    if (pendingCalendar != null && pendingAppointments != null) {
      Future.microtask(() {
        applyAppointmentsNow();
        if (!appointmentsChanged || !mounted) return;
        _rebuildHearingNavCache();
        _scheduleEntriesIndexRebuild();
        _hearingNavRevision.value++;
      });
      if (calendarChanged) commitUi();
      return;
    }

    applyAppointmentsNow();
    commitUi();
  }

  String _dayKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

  void _rebuildHearingNavCache() {
    _cachedHearingNavEvents = _gridCalendarEvents()
        .where(CalendarHearingNav.isHearingRow)
        .toList();
  }

  /// Keeps Add Appointment rows visible until Firestore stream includes them.
  List<Map<String, dynamic>> _mergeCalendarEventsFromServer(
    List<Map<String, dynamic>> incoming,
  ) {
    final serverByApptId = <String, Map<String, dynamic>>{};
    for (final e in incoming) {
      final apptId = (e['appointmentId'] as String?)?.trim() ?? '';
      if (apptId.isNotEmpty) serverByApptId[apptId] = e;
    }
    final pending = <Map<String, dynamic>>[];
    for (final local in _calendarEvents) {
      if ((local['source'] as String?) != 'attorney_manual') continue;
      final apptId = (local['appointmentId'] as String?)?.trim() ?? '';
      if (apptId.isEmpty || serverByApptId.containsKey(apptId)) continue;
      pending.add(local);
    }
    return [...incoming, ...pending];
  }

  void _subscribeCalendarEvents() {
    final aid = _calendarAttorneyId();
    if (aid.isEmpty) return;
    final cached = _calendarEventsCacheByAttorney[aid];
    if (cached != null && cached.isNotEmpty) {
      _calendarEvents = List<Map<String, dynamic>>.from(cached);
      _lastCalendarFingerprint = _calendarEventsFingerprint(_calendarEvents);
      _rebuildHearingNavCache();
      _scheduleEntriesIndexRebuild();
    }
    _calendarEventsSub?.cancel();
    _calendarEventsSub = _staffService
        .getCalendarEvents(aid)
        .listen(_scheduleCalendarEventsUi, onError: (_) {});
  }

  List<Map<String, dynamic>> _hearingSiblingsForCase(String caseNo) {
    final cn = caseNo.trim();
    if (cn.isEmpty) return const [];
    return _calendarEvents
        .where(
          (o) => HearingCalendarFields.asDisplayString(o['caseNo']) == cn,
        )
        .toList();
  }

  /// Hearing rows from `calendar_events` for the cross-month navigation banner.
  List<Map<String, dynamic>> _allHearingNavEvents() =>
      _effectiveHearingRows.isNotEmpty
          ? _effectiveHearingRows
          : _cachedHearingNavEvents;

  /// Months with Firestore `hearings` not shown in the current calendar view.
  List<DateTime> _hearingMonthsOutsideView(DateTime viewDate) {
    return CalendarHearingNav.monthsOutsideView(
      hearingRows: [..._allHearingNavEvents(), ..._notaryCalendarRows],
      viewDate: viewDate,
      parseDate: _dateTimeFromField,
    );
  }

  Widget _buildHearingsOutsideMonthBanner(DateTime viewDate) {
    final months = _hearingMonthsOutsideView(viewDate);
    if (months.isEmpty) return const SizedBox.shrink();
    return Material(
      color: calendarGold.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.event_note, size: 18, color: Colors.black87),
            Text(
              'Scheduled dates on file appear in another month — View:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey[900],
              ),
            ),
            ...months.map(
              (m) => TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: calendarBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  _viewDateNotifier.value = DateTime(m.year, m.month);
                },
                child: Text(
                  DateFormat('MMMM yyyy').format(m),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _dateTimeFromField(dynamic raw) {
    if (raw is DateTime) return raw;
    if (raw is Timestamp) return raw.toDate();
    return null;
  }

  DateTime _calendarDay(DateTime d) => DateTime(d.year, d.month, d.day);

  List<_AttorneyCalendarEntry> _getEntriesForDate(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return _entriesByDayKey[_dayKey(day)] ?? const [];
  }

  /// Same case/hearing from overlay + calendar_events can appear twice.
  List<_AttorneyCalendarEntry> _dedupeCalendarEntriesForDay(
    List<_AttorneyCalendarEntry> entries,
  ) {
    final byKey = <String, _AttorneyCalendarEntry>{};
    for (final e in entries) {
      if (e.appointment != null) {
        final id = e.appointment!.id.trim();
        byKey[id.isEmpty ? 'apt:${e.hashCode}' : 'apt:$id'] = e;
        continue;
      }
      final ev = e.hearingEvent!;
      if (NotaryService.isNotaryCalendarRow(ev)) {
        final nid = (ev['notaryRequestId'] as String?)?.trim() ??
            (ev['id'] as String?)?.trim() ??
            '';
        byKey[nid.isNotEmpty ? 'n:$nid' : 'n:${e.hashCode}'] = e;
        continue;
      }
      final hid = HearingCalendarFields.asDisplayString(ev['hearingDocId']);
      final cn = HearingCalendarFields.asDisplayString(ev['caseNo'])
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      final title = e.hearingTitle().trim().toLowerCase();
      final d = e.startTime;
      final dayKey = '${d.year}${d.month}${d.day}';
      // Keep each hearing document. Same-case OCR copies still show if they
      // are separate Firestore rows (October 28 had many of these).
      final key = hid.isNotEmpty
          ? 'h:$hid'
          : (cn.isNotEmpty ? 'case:$cn:$dayKey' : 'c:$title:$dayKey');
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = e;
        continue;
      }
      final prevTitle =
          HearingCalendarFields.asDisplayString(existing.hearingEvent?['caseTitle']);
      final nextTitle =
          HearingCalendarFields.asDisplayString(ev['caseTitle']);
      if (nextTitle.length > prevTitle.length) {
        byKey[key] = e;
      }
    }
    final deduped = byKey.values.toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return deduped;
  }

  void _bindAppointments() {
    if (_ownsAppointmentsStream) {
      _appointmentsSub?.cancel();
      _appointmentsSub = null;
    }

    final shared = widget.sharedAppointmentsStream;
    if (shared != null) {
      _ownsAppointmentsStream = false;
      _appointmentsSub = shared.listen((appointments) {
        if (!mounted) return;
        _pendingAppointments = _mergeAppointmentsFromStream(appointments);
        _scheduleDataUiFlush();
      });
      return;
    }

    final aid = _calendarAttorneyId();
    if (aid.isEmpty) return;

    _ownsAppointmentsStream = true;
    _appointmentsSub = _appointmentService
        .getAttorneyAppointments(aid)
        .listen((appointments) {
          if (!mounted) return;
          _pendingAppointments = _mergeAppointmentsFromStream(appointments);
          _scheduleDataUiFlush();
        });
  }

  /// Keeps just-created rows visible until Firestore snapshot catches up.
  List<AppointmentModel> _mergeAppointmentsFromStream(
    List<AppointmentModel> incoming,
  ) {
    final byId = {for (final a in incoming) a.id: a};
    final merged = List<AppointmentModel>.from(incoming);
    final now = DateTime.now();
    for (final local in _appointments) {
      if (byId.containsKey(local.id)) continue;
      if (now.difference(local.updatedAt) < const Duration(minutes: 3)) {
        merged.add(local);
        byId[local.id] = local;
      }
    }
    merged.sort(
      (a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime),
    );
    return merged;
  }

  /// Get the client name cache (always returns a valid map)
  Map<String, String> _getClientNameCache() {
    return _clientNameCache;
  }

  /// Get the client email cache (always returns a valid map)
  Map<String, String> _getClientEmailCache() {
    try {
      return _clientEmailCache;
    } catch (e) {
      // If cache is somehow undefined, return empty map
      return <String, String>{};
    }
  }

  /// Get client email from cache or profile
  String _getClientEmail(AppointmentModel appointment) {
    if (appointment.clientId.isEmpty) {
      return '';
    }

    try {
      final cache = _getClientEmailCache();
      if (cache.isNotEmpty) {
        final cachedEmail = cache[appointment.clientId];
        if (cachedEmail != null && cachedEmail.isNotEmpty) {
          return cachedEmail;
        }
      }
    } catch (e) {
      // If cache access fails, fall through
      if (kDebugMode) debugPrint('Error accessing email cache: $e');
    }

    // Trigger async fetch if not cached (non-blocking)
    try {
      _loadClientNames([appointment]);
    } catch (e) {
      if (kDebugMode) debugPrint('Error triggering email fetch: $e');
    }

    return '';
  }

  /// Load full client names from client profiles
  Future<void> _loadClientNames(List<AppointmentModel> appointments) async {
    final clientIds = appointments
        .map((apt) => apt.clientId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    // Filter out already cached client IDs - use safe access
    final uncachedClientIds = <String>[];
    for (final id in clientIds) {
      try {
        final cache = _getClientNameCache();
        if (!cache.containsKey(id)) {
          uncachedClientIds.add(id);
        }
      } catch (e) {
        // If cache access fails, include ID to fetch
        uncachedClientIds.add(id);
      }
    }

    if (uncachedClientIds.isEmpty) {
      return; // All names already cached
    }

    final toFetch = uncachedClientIds.take(12).toList();
    final results = <Map<String, dynamic>?>[];
    for (var i = 0; i < toFetch.length; i += 4) {
      final chunk = toFetch.sublist(
        i,
        i + 4 > toFetch.length ? toFetch.length : i + 4,
      );
      final futures = chunk.map((clientId) async {
        try {
          final clientDoc = await _firestore
              .collection('users')
              .doc(clientId)
              .get();

          if (clientDoc.exists) {
            final clientData = clientDoc.data()!;
            final fullName =
                clientData['fullName'] as String? ??
                clientData['full_name'] as String? ??
                '';
            final name = clientData['name'] as String? ?? '';
            final email = clientData['email'] as String? ?? '';

            String displayName = '';
            if (fullName.isNotEmpty && fullName.trim().isNotEmpty) {
              displayName = fullName.trim();
            } else if (name.isNotEmpty && name.trim().isNotEmpty) {
              displayName = name.trim();
            }

            return {
              'clientId': clientId,
              'displayName': displayName.isNotEmpty && !displayName.contains('@')
                  ? displayName
                  : '',
              'email': email.isNotEmpty ? email : '',
            };
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error loading client name for $clientId: $e');
          }
        }
        return null;
      }).toList();
      results.addAll(await Future.wait(futures));
      await Future<void>.delayed(Duration.zero);
    }

    // Update cache silently — names are only needed in detail dialogs, not the grid.
    if (mounted) {
      try {
        final nameCache = _getClientNameCache();
        final emailCache = _getClientEmailCache();
        for (final result in results) {
          if (result != null) {
            final clientId = result['clientId'];
            if (clientId != null) {
              final displayName = result['displayName'];
              if (displayName != null) {
                final displayNameStr = displayName.toString();
                if (displayNameStr.isNotEmpty &&
                    !_isEmailAddress(displayNameStr)) {
                  nameCache[clientId.toString()] = displayNameStr;
                }
              }
              final email = result['email'];
              if (email != null) {
                final emailStr = email.toString();
                if (emailStr.isNotEmpty) {
                  emailCache[clientId.toString()] = emailStr;
                }
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Error updating client caches: $e');
      }
    }
  }

  /// Grid-safe client label — never triggers Firestore from a cell build.
  String _clientLabelForGrid(AppointmentModel appointment) {
    if (appointment.clientId.isEmpty) {
      final storedName = appointment.clientName;
      if (storedName.isNotEmpty && !_isEmailAddress(storedName)) {
        return storedName;
      }
      return 'Client';
    }

    try {
      final cachedName = _getClientNameCache()[appointment.clientId];
      if (cachedName != null &&
          cachedName.isNotEmpty &&
          !_isEmailAddress(cachedName)) {
        return cachedName;
      }
    } catch (_) {}

    final storedName = appointment.clientName;
    if (storedName.isNotEmpty &&
        !_isEmailAddress(storedName) &&
        storedName.length > 2) {
      return storedName;
    }

    return 'Client';
  }

  /// Get the full client name from profile, never show email
  String _getClientDisplayName(AppointmentModel appointment) {
    // Ensure clientId is valid
    if (appointment.clientId.isEmpty) {
      final storedName = appointment.clientName;
      // Never show email addresses - check if it looks like an email
      if (storedName.isNotEmpty && !_isEmailAddress(storedName)) {
        return storedName;
      }
      return 'Client';
    }

    // First, try to get from cache (full name from profile)
    try {
      final cache = _getClientNameCache();
      final cachedName = cache[appointment.clientId];
      if (cachedName != null &&
          cachedName.isNotEmpty &&
          !_isEmailAddress(cachedName)) {
        return cachedName;
      }
    } catch (e) {
      // If cache access fails, fall through
    }

    // Check stored name - only use if it's not an email
    final storedName = appointment.clientName;
    if (storedName.isNotEmpty &&
        !_isEmailAddress(storedName) &&
        storedName.length > 2) {
      // If stored name looks like a real name (not email), use it temporarily
      return storedName;
    }

    // Trigger async fetch for names that might not be loaded yet
    _loadClientNames([appointment]);

    // Return a generic placeholder while loading from profile
    return 'Client';
  }

  /// Check if a string looks like an email address
  bool _isEmailAddress(String text) {
    // Simple email pattern check
    return text.contains('@') &&
        text.contains('.') &&
        text.indexOf('@') < text.lastIndexOf('.') &&
        text.length > 5; // Minimum email length
  }

  Color _getEntryColor(_AttorneyCalendarEntry entry) {
    if (entry.appointment != null) {
      return _getAppointmentColor(entry.appointment!);
    }
    if (entry.hearingEvent != null &&
        NotaryService.isNotaryCalendarRow(entry.hearingEvent!)) {
      return const Color(0xFF00897B);
    }
    return hearingEventColor;
  }

  Color _getAppointmentColor(AppointmentModel appointment) {
    switch (appointment.status) {
      case 'scheduled':
        return primaryRed;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.grey;
      case 'rescheduled':
        return Colors.orange;
      default:
        return primaryRed;
    }
  }

  /// Puts a manual appointment into [_appointments] so the day dialog updates at once.
  void _mergeAppointmentIntoState(AppointmentModel apt) {
    if (!mounted) return;
    setState(() {
      final rest = _appointments.where((a) => a.id != apt.id).toList();
      rest.add(apt);
      rest.sort(
        (a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime),
      );
      _appointments = rest;
    });
    _scheduleEntriesIndexRebuild(immediate: true);
  }

  /// Best-effort Firestore refresh after create (calendar already has [apt]).
  Future<void> _refreshAppointmentFromFirestore(AppointmentModel apt) async {
    if (apt.id.isEmpty) return;
    try {
      final doc = await _firestore.collection('appointments').doc(apt.id).get();
      if (!doc.exists || !mounted) return;
      _mergeAppointmentIntoState(AppointmentModel.fromFirestore(doc));
    } catch (e) {
      if (kDebugMode) debugPrint('refreshAppointmentFromFirestore: $e');
    }
  }

  Future<AppointmentModel?> _fetchLatestAppointmentForDay(DateTime day) async {
    final aid = _calendarAttorneyId();
    if (aid.isEmpty) return null;
    try {
      final snap = await _firestore
          .collection('appointments')
          .where('attorneyId', isEqualTo: aid)
          .get();
      AppointmentModel? best;
      for (final doc in snap.docs) {
        final apt = AppointmentModel.fromFirestore(doc);
        if (_calendarDay(apt.appointmentDateTime) != _calendarDay(day))
          continue;
        if (best == null || apt.createdAt.isAfter(best.createdAt)) {
          best = apt;
        }
      }
      return best;
    } catch (e) {
      if (kDebugMode) debugPrint('_fetchLatestAppointmentForDay: $e');
      return null;
    }
  }

  Future<AppointmentModel?> _coerceCreatedAppointment(
    dynamic result,
    DateTime day,
  ) async {
    if (result is AppointmentModel) {
      if (result.id.isNotEmpty) return result;
      return _fetchLatestAppointmentForDay(day);
    }
    if (result == true) {
      return _fetchLatestAppointmentForDay(day);
    }
    return null;
  }

  /// Opens the manual scheduler for [date]. Returns the saved row when created.
  Future<AppointmentModel?> _createAppointmentForDate(DateTime date) async {
    final day = _calendarDay(date);
    final result = await showDialog<dynamic>(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: AppointmentSchedulerForm(
            initialDate: day,
            initialTime: const TimeOfDay(hour: 9, minute: 0),
            returnCreatedId: true,
          ),
        ),
      ),
    );

    final created = await _coerceCreatedAppointment(result, day);
    AppointmentModel? saved = created;
    if (saved == null || saved.id.isEmpty) {
      saved = await _fetchLatestAppointmentForDay(day);
    }
    if (saved == null || saved.id.isEmpty) return null;

    _mergeAppointmentIntoState(saved);
    unawaited(_refreshAppointmentFromFirestore(saved));
    if (saved.appointmentType == 'hearing_court') {
      await _mirrorHearingCourtToCalendarEvent(saved);
    }
    return saved;
  }

  Map<String, dynamic> _manualHearingRowFromAppointment(
    AppointmentModel apt, {
    String? caseNo,
    String? attorneyId,
  }) {
    final title = (apt.caseTitle?.trim().isNotEmpty == true)
        ? apt.caseTitle!.trim()
        : apt.clientName;
    return {
      'id': 'appt_${apt.id}',
      'eventType': 'hearing',
      'eventDate': apt.appointmentDateTime,
      'title': title,
      'source': 'attorney_manual',
      'clientName': apt.clientName,
      'assignedTo': attorneyId ?? apt.attorneyId,
      if (apt.caseId != null) 'caseId': apt.caseId,
      if (apt.caseTitle != null) 'caseTitle': apt.caseTitle,
      if (caseNo != null && caseNo.isNotEmpty) 'caseNo': caseNo,
      'hearingTime': DateFormat('h:mm a').format(apt.appointmentDateTime),
      'appointmentId': apt.id,
      if (apt.notes != null && apt.notes!.trim().isNotEmpty) 'notes': apt.notes,
    };
  }

  void _mergeManualHearingIntoCalendarState(Map<String, dynamic> manualRow) {
    if (!mounted) return;
    final aptId = manualRow['appointmentId'] as String?;
    setState(() {
      final exists = _calendarEvents.any(
        (e) => (e['appointmentId'] as String?) == aptId,
      );
      if (!exists) {
        _calendarEvents = [..._calendarEvents, manualRow];
        _scheduleEntriesIndexRebuild(immediate: true);
      }
    });
  }

  /// Manual court hearings from Add Appointment also show in the day list.
  Future<void> _mirrorHearingCourtToCalendarEvent(AppointmentModel apt) async {
    final attorneyId = apt.attorneyId ?? _calendarAttorneyId();
    if (attorneyId == null || attorneyId.isEmpty) return;

    String? caseNo;
    if (apt.caseId != null && apt.caseId!.trim().isNotEmpty) {
      try {
        final caseSnap = await _firestore
            .collection('cases')
            .doc(apt.caseId)
            .get();
        caseNo = (caseSnap.data()?['caseNo'] as String?)?.trim();
      } catch (_) {
        /* optional */
      }
    }

    final manualRow = _manualHearingRowFromAppointment(
      apt,
      caseNo: caseNo,
      attorneyId: attorneyId,
    );
    _mergeManualHearingIntoCalendarState(manualRow);

    final title = (apt.caseTitle?.trim().isNotEmpty == true)
        ? apt.caseTitle!.trim()
        : apt.clientName;

    final result = await _staffService.createCalendarEvent(
      eventType: 'hearing',
      eventDate: apt.appointmentDateTime,
      title: title,
      description: apt.notes,
      caseId: apt.caseId,
      assignedTo: attorneyId,
      clientId: apt.clientId.trim().isNotEmpty ? apt.clientId : null,
      createdByRole: 'attorney',
      remindAttorney: false,
      remindClient: false,
      sendNow: false,
      extraFields: {
        'source': 'attorney_manual',
        'clientName': apt.clientName,
        if (apt.caseTitle != null && apt.caseTitle!.trim().isNotEmpty)
          'caseTitle': apt.caseTitle!.trim(),
        if (caseNo != null && caseNo.isNotEmpty) 'caseNo': caseNo,
        'hearingTime': DateFormat('h:mm a').format(apt.appointmentDateTime),
        'appointmentId': apt.id,
      },
    );

    if (result['success'] == true) {
      final eventId = (result['eventId'] as String?)?.trim() ?? '';
      if (eventId.isNotEmpty && mounted) {
        final persisted = Map<String, dynamic>.from(manualRow)
          ..['id'] = eventId;
        setState(() {
          final aptId = apt.id;
          _calendarEvents = [
            ..._calendarEvents.where(
              (e) => (e['appointmentId'] as String?) != aptId,
            ),
            persisted,
          ];
          _scheduleEntriesIndexRebuild(immediate: true);
        });
      }
    } else if (kDebugMode) {
      debugPrint('mirrorHearingCourtToCalendarEvent: ${result['message']}');
    }
  }

  List<_AttorneyCalendarEntry> _entriesForDateWithAppointment(
    DateTime date,
    List<_AttorneyCalendarEntry> base, {
    AppointmentModel? created,
  }) {
    if (created == null) return base;
    final day = _calendarDay(date);
    final aptDay = _calendarDay(created.appointmentDateTime);
    if (aptDay != day) return base;

    final fresh = _getEntriesForDate(day);
    if (created.appointmentType == 'hearing_court') {
      final aptId = created.id.trim();
      if (aptId.isNotEmpty &&
          fresh.any(
            (e) =>
                (e.hearingEvent?['appointmentId'] as String?) == aptId ||
                e.appointment?.id == aptId,
          )) {
        return fresh;
      }
      final manualHearing = _manualHearingRowFromAppointment(created);
      final out = [...fresh, _AttorneyCalendarEntry.fromHearing(manualHearing)];
      out.sort((a, b) => a.startTime.compareTo(b.startTime));
      return out;
    }

    if (fresh.any((e) => e.appointment?.id == created.id)) return fresh;
    final out = [...fresh, _AttorneyCalendarEntry.fromAppointment(created)];
    out.sort((a, b) => a.startTime.compareTo(b.startTime));
    return out;
  }

  Future<void> _openDayDialogAfterAppointmentAdded(
    DateTime date, {
    AppointmentModel? created,
  }) async {
    if (!mounted) return;
    final showDay = created != null
        ? DateTime(
            created.appointmentDateTime.year,
            created.appointmentDateTime.month,
            created.appointmentDateTime.day,
          )
        : DateTime(date.year, date.month, date.day);
    final fresh = _entriesForDateWithAppointment(
      showDay,
      _getEntriesForDate(showDay),
      created: created,
    );
    _showEntriesForDate(showDay, fresh);
  }

  Future<void> _openNewAppointment() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const AppointmentSchedulerForm()),
    );
    if (result == true && mounted) {
      _scheduleEntriesIndexRebuild(immediate: true);
    }
  }

  Widget _buildCalendarBody({required bool isMobile}) {
    return Column(
      children: [
        if (widget.embedded && isMobile && widget.showTopAddButton)
          Material(
            color: calendarBlue,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.white),
                      onPressed: _handleAddPressed,
                      tooltip: widget.onAddPressed != null
                          ? 'New Event'
                          : 'New Appointment',
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: Column(
            children: [
              ValueListenableBuilder<DateTime>(
                valueListenable: _viewDateNotifier,
                builder: (context, viewDate, _) => _buildCalendarHeader(
                  isMobile: isMobile,
                  viewDate: viewDate,
                ),
              ),
              _buildWeekdayRow(isMobile: isMobile),
              StableMergedListenableBuilder(
                listenables: [_viewDateNotifier, _hearingNavRevision],
                builder: (context, _) => _buildHearingsOutsideMonthBanner(
                  _viewDateNotifier.value,
                ),
              ),
              Expanded(
                child: RepaintBoundary(
                  child: StableMergedListenableBuilder(
                    listenables: [
                      _viewDateNotifier,
                      _entriesRevisionNotifier,
                      _hearingNavRevision,
                    ],
                    builder: (context, _) {
                      final viewDate = _viewDateNotifier.value;
                      return (isMobile || _viewMode == 'month')
                          ? _buildMonthView(viewDate)
                          : _buildWeekView(viewDate);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final calendarBody = _buildCalendarBody(isMobile: isMobile);

    if (widget.embedded) {
      return ColoredBox(color: Colors.white, child: calendarBody);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: calendarBlue,
        title: const SizedBox.shrink(),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          if (!isMobile)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ToggleButtons(
                isSelected: [_viewMode == 'month', _viewMode == 'week'],
                onPressed: (index) {
                  setState(() {
                    _viewMode = index == 0 ? 'month' : 'week';
                  });
                },
                borderRadius: BorderRadius.circular(8),
                selectedColor: Colors.white,
                fillColor: Colors.white.withOpacity(0.2),
                color: Colors.white70,
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('Month'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('Week'),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _handleAddPressed,
            tooltip: widget.onAddPressed != null
                ? 'New Event'
                : 'New Appointment',
          ),
        ],
      ),
      body: calendarBody,
    );
  }

  Set<int> _yearsWithSchedules() {
    final years = <int>{};
    for (final key in _entriesByDayKey.keys) {
      final y = int.tryParse(key.split('-').first);
      if (y != null) years.add(y);
    }
    return years;
  }

  List<int> _yearPickerYears() {
    final nowY = DateTime.now().year;
    var minY = nowY - 3;
    var maxY = nowY + 3;
    for (final y in _yearsWithSchedules()) {
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    return [for (var y = minY; y <= maxY; y++) y];
  }

  DateTime _firstScheduleMonthInYear(int year) {
    DateTime? first;
    for (final key in _entriesByDayKey.keys) {
      final parts = key.split('-');
      if (parts.length < 2) continue;
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (y == null || m == null || y != year) continue;
      final month = DateTime(y, m);
      if (first == null || month.isBefore(first)) first = month;
    }
    return first ?? DateTime(year, 1);
  }

  Future<void> _pickCalendarYear(DateTime viewDate) async {
    final years = _yearPickerYears();
    final withSchedules = _yearsWithSchedules();
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Filter by year'),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          content: SizedBox(
            width: 280,
            height: 320,
            child: ListView.builder(
              itemCount: years.length,
              itemBuilder: (context, index) {
                final year = years[index];
                final selected = year == viewDate.year;
                final hasSched = withSchedules.contains(year);
                return ListTile(
                  selected: selected,
                  selectedTileColor: calendarGold.withValues(alpha: 0.35),
                  title: Text(
                    '$year',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: selected || hasSched
                          ? FontWeight.w800
                          : FontWeight.w500,
                      fontSize: 18,
                    ),
                  ),
                  subtitle: hasSched
                      ? const Text(
                          'Has scheduled events',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11),
                        )
                      : null,
                  onTap: () => Navigator.pop(ctx, year),
                );
              },
            ),
          ),
        );
      },
    );
    if (!mounted || picked == null) return;
    _viewDateNotifier.value = _firstScheduleMonthInYear(picked);
  }

  /// Android 15/edge-to-edge often reports [MediaQuery.padding] as 0, so
  /// [SafeArea] leaves the year chip under the status icons. [viewPadding]
  /// is the raw inset and is never consumed.
  double _headerStatusBarInset(BuildContext context) {
    final mq = MediaQuery.of(context);
    final top = mq.viewPadding.top >= mq.padding.top
        ? mq.viewPadding.top
        : mq.padding.top;
    return top > 0 ? top : 32;
  }

  Widget _buildCalendarHeader({
    required bool isMobile,
    required DateTime viewDate,
  }) {
    final extraTop = widget.padHeaderForStatusBar
        ? _headerStatusBarInset(context)
        : 0.0;
    return ColoredBox(
      color: calendarBlue,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isMobile ? 8 : 16,
          extraTop + (isMobile ? 8 : 16),
          isMobile ? 8 : 16,
          isMobile ? 8 : 16,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white),
              onPressed: () {
                _viewDateNotifier.value = _viewMode == 'month' || isMobile
                    ? DateTime(viewDate.year, viewDate.month - 1)
                    : viewDate.subtract(const Duration(days: 7));
              },
            ),
            Expanded(
              child: Text(
                _viewMode == 'month' || isMobile
                    ? DateFormat('MMMM yyyy').format(viewDate)
                    : 'Week of ${DateFormat('MMM dd').format(viewDate)}',
                style: TextStyle(
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Filter by year',
                  child: Material(
                    color: calendarGold,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => unawaited(_pickCalendarYear(viewDate)),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 8 : 12,
                          vertical: isMobile ? 8 : 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat('yyyy').format(viewDate),
                              style: TextStyle(
                                fontSize: isMobile ? 14 : 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              size: 18,
                              color: Colors.black87,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                  onPressed: () {
                    _viewDateNotifier.value = _viewMode == 'month' || isMobile
                        ? DateTime(viewDate.year, viewDate.month + 1)
                        : viewDate.add(const Duration(days: 7));
                  },
                ),
              ],
            ),
            if (!isMobile)
              TextButton(
                onPressed: () {
                  _viewDateNotifier.value = DateTime.now();
                },
                child: const Text('Today'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekdayRow({required bool isMobile}) {
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isMobile ? 8 : 10,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(labels.length, (index) {
          // Reference: only Sunday column in red (not Saturday).
          final isSunday = index == 0;
          return Expanded(
            child: Center(
              child: Text(
                labels[index],
                style: TextStyle(
                  fontSize: 12, // same size for mobile and web
                  fontWeight: FontWeight.w600,
                  color: isSunday ? sundayRed : Colors.grey[700],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMonthView(DateTime viewDate) {
    final isCompact = MediaQuery.sizeOf(context).width > 200;
    return LayoutBuilder(
      builder: (context, constraints) {
        final monthCellBodyHeight = CalendarPerf.monthGridCellBodyHeight(
          gridHeight: constraints.maxHeight,
          isCompact: isCompact,
        );
        return CalendarMonthGrid(
          key: ValueKey('month-${viewDate.year}-${viewDate.month}'),
          viewDate: viewDate,
          isCompact: isCompact,
          cellBuilder: (context, day, isCurrentMonth, isToday) {
            return _buildDayCell(
              day,
              isCurrentMonth,
              isToday,
              _getEntriesForDate(day),
              monthCellBodyHeight: monthCellBodyHeight,
            );
          },
        );
      },
    );
  }

  Widget _buildWeekView(DateTime viewDate) {
    final startOfWeek = viewDate.subtract(Duration(days: viewDate.weekday - 1));
    final weekDays = List.generate(
      7,
      (i) => startOfWeek.add(Duration(days: i)),
    );

    return Row(
      children: weekDays
          .map((day) => Expanded(child: _buildWeekDayColumn(day)))
          .toList(),
    );
  }

  Widget _buildWeekDayColumn(DateTime day) {
    final isToday =
        day.year == DateTime.now().year &&
        day.month == DateTime.now().month &&
        day.day == DateTime.now().day;
    final dayEntries = _getEntriesForDate(day);

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isToday ? calendarBlue : Colors.grey[300]!,
          width: isToday ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Day number = add manual schedule (events stay tappable below).
          InkWell(
            onTap: () async {
              final created = await _handleAddForDate(day);
              if (created != null && mounted) {
                await _openDayDialogAfterAppointmentAdded(
                  day,
                  created: created,
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isToday
                    ? calendarBlue.withOpacity(0.08)
                    : Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    DateFormat('EEE').format(day),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isToday ? calendarBlue : Colors.black87,
                        ),
                      ),
                      if (dayEntries.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: calendarBlue,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${dayEntries.length}',
                            style: const TextStyle(
                              fontSize: 8,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      Icon(Icons.add, size: 12, color: Colors.grey[600]),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ClipRect(
              child: ListView.builder(
                padding: const EdgeInsets.all(4),
                physics: const ClampingScrollPhysics(),
                itemCount: dayEntries.length,
                itemBuilder: (context, index) =>
                    _buildCalendarEntrySlot(dayEntries[index]),
              ),
            ),
          ),
          InkWell(
            onTap: () async {
              final created = await _handleAddForDate(day);
              if (created != null && mounted) {
                await _openDayDialogAfterAppointmentAdded(
                  day,
                  created: created,
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.add, size: 20, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDayEntry(
    _AttorneyCalendarEntry entry, {
    VoidCallback? onOpen,
  }) {
    final label = entry.appointment != null
        ? _clientLabelForGrid(entry.appointment!)
        : entry.calendarCellLabel().isNotEmpty
            ? entry.calendarCellLabel()
            : entry.hearingTitle();
    return InkWell(
      onTap: () => Future.microtask(
        () => onOpen != null ? onOpen() : _showEntryDetails(entry),
      ),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: _getEntryColor(entry),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('hh:mm a').format(entry.startTime),
                    style: const TextStyle(
                      fontSize: 7.5,
                      height: 1,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (entry.isAiScheduled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: calendarGold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Text(
                      'AI',
                      style: TextStyle(
                        fontSize: 5.5,
                        height: 1,
                        color: Colors.black87,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: const TextStyle(
                fontSize: 8,
                height: 1.05,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCellEntryColumn(
    List<_AttorneyCalendarEntry> entries, {
    required double bodyHeight,
    required DateTime day,
  }) {
    void openDay() => _openDayEntries(day, entries.isEmpty ? null : entries.first);
    if (entries.isEmpty) return const SizedBox.shrink();
    final layout = CalendarPerf.layoutDayCellEntries(
      bodyHeight: bodyHeight,
      totalEntries: entries.length,
    );
    if (layout.shown <= 0) {
      if (!layout.showMore) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          '+${entries.length} more',
          style: TextStyle(fontSize: 9, color: Colors.grey[600]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < layout.shown; i++)
          SizedBox(
            height: layout.chipHeight,
            child: ClipRect(
              child: _buildCompactDayEntry(entries[i], onOpen: openDay),
            ),
          ),
        if (layout.showMore)
          SizedBox(
            height: CalendarPerf.monthCellMoreRowHeight,
            child: InkWell(
              onTap: openDay,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '+${entries.length - layout.shown} more',
                    style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDayCell(
    DateTime day,
    bool isCurrentMonth,
    bool isToday,
    List<_AttorneyCalendarEntry> entries, {
    double? monthCellBodyHeight,
  }) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: isToday
            ? calendarBlue.withOpacity(0.08)
            : Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isToday ? calendarBlue : Colors.grey[300]!,
          width: isToday ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () async {
              final created = await _handleAddForDate(day);
              if (created != null && mounted) {
                await _openDayDialogAfterAppointmentAdded(
                  day,
                  created: created,
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
              child: Row(
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                      color: isCurrentMonth
                          ? (isToday
                                ? calendarBlue
                                : (day.weekday == DateTime.sunday
                                      ? sundayRed
                                      : Colors.black87))
                          : Colors.grey[400],
                    ),
                  ),
                  if (entries.isNotEmpty) ...[
                    const SizedBox(width: 2),
                    Flexible(
                      child: GestureDetector(
                        onTap: () => _openDayEntries(day),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: calendarBlue,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${entries.length}',
                            style: const TextStyle(
                              fontSize: 8,
                              height: 1,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(Icons.add, size: 12, color: Colors.grey[500]),
                ],
              ),
            ),
          ),
          Expanded(
            child: monthCellBodyHeight != null
                ? SizedBox(
                    height: monthCellBodyHeight,
                    width: double.infinity,
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
                          child: _buildDayCellEntryColumn(
                            entries,
                            bodyHeight: monthCellBodyHeight,
                            day: day,
                          ),
                        ),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final bodyHeight = constraints.maxHeight;
                      return SizedBox(
                        height: bodyHeight,
                        width: double.infinity,
                        child: ClipRect(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
                              child: _buildDayCellEntryColumn(
                                entries,
                                bodyHeight: bodyHeight,
                                day: day,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarEntrySlot(_AttorneyCalendarEntry entry) {
    final apt = entry.appointment;
    return InkWell(
      onTap: () => _showEntryDetails(entry),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _getEntryColor(entry),
          borderRadius: BorderRadius.circular(6),
        ),
        child: apt != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('hh:mm a').format(entry.startTime),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _clientLabelForGrid(apt),
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          entry.calendarCellLabel().isNotEmpty
                              ? entry.calendarCellLabel()
                              : entry.hearingTitle(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.isAiScheduled) ...[
                        const SizedBox(width: 6),
                        _aiSchedBadge(compact: false),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('hh:mm a').format(entry.startTime),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.95),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (entry.involvedPartiesLabel().isNotEmpty)
                    Text(
                      entry.involvedPartiesLabel(),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.92),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      entry.hearingTypeLabel(),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.9),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
      ),
    );
  }

  void _showEntryDetails(_AttorneyCalendarEntry entry) {
    if (entry.appointment != null) {
      _showAppointmentDetails(entry.appointment!);
      return;
    }
    final ev = entry.hearingEvent;
    if (ev != null && NotaryService.isNotaryCalendarRow(ev)) {
      final id = (ev['notaryRequestId'] as String?)?.trim() ?? '';
      if (id.isEmpty) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AttorneyNotaryRequestDetailScreen(
            requestId: id,
            actingAsStaff: widget.actingAsStaff,
          ),
        ),
      );
      return;
    }
    if (ev != null) {
      _showHearingEventDetails(ev);
    }
  }

  /// Cell shows 3, dialog must list those same 3 — not only the tapped chip.
  void _openDayEntries(DateTime day, [_AttorneyCalendarEntry? tapped]) {
    final all = _getEntriesForDate(day);
    if (all.length > 1) {
      _showEntriesForDate(day, all);
      return;
    }
    if (all.length == 1) {
      _showEntryDetails(all.first);
      return;
    }
    if (tapped != null) _showEntryDetails(tapped);
  }

  /// Show all items (appointments + court/automation events) for a date
  void _showEntriesForDate(
    DateTime date,
    List<_AttorneyCalendarEntry> entries,
  ) {
    if (!mounted) return;
    // Must live outside [StatefulBuilder]'s builder — that builder re-runs on
    // every setState and would otherwise reset the list to [entries].
    var dayEntries = List<_AttorneyCalendarEntry>.from(entries);

    final dialogMaxH = MediaQuery.sizeOf(context).height * 0.88;

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(dialogContext).width > 600
                ? 500
                : MediaQuery.sizeOf(dialogContext).width * 0.94,
            maxHeight: dialogMaxH,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('MMMM dd, yyyy').format(date),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: StatefulBuilder(
                  builder: (context, setDialogState) {
                    final apptN = dayEntries
                        .where((e) => e.appointment != null)
                        .length;
                    final calN = dayEntries.length - apptN;
                    final aiN = dayEntries.where((e) => e.isAiScheduled).length;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${dayEntries.length} scheduled item${dayEntries.length != 1 ? 's' : ''}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                if (apptN > 0 || calN > 0) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      if (apptN > 0)
                                        '$apptN client appointment${apptN != 1 ? 's' : ''}',
                                      if (apptN > 0 && calN > 0) ' · ',
                                      if (calN > 0)
                                        '$calN calendar event${calN != 1 ? 's' : ''}'
                                            '${aiN > 0 ? ' ($aiN AI)' : ''}',
                                    ].join(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                ...List.generate(dayEntries.length, (index) {
                                  final entry = dayEntries[index];
                                  final apt = entry.appointment;
                                  if (apt != null) {
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.pop(dialogContext);
                                          _showAppointmentDetails(apt);
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      _getClientDisplayName(
                                                        apt,
                                                      ),
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          _getAppointmentColor(
                                                            apt,
                                                          ).withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      border: Border.all(
                                                        color:
                                                            _getAppointmentColor(
                                                              apt,
                                                            ),
                                                        width: 1,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      _getAppointmentTypeLabel(
                                                        apt.appointmentType,
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            _getAppointmentColor(
                                                              apt,
                                                            ),
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.access_time,
                                                    size: 16,
                                                    color: Colors.grey[600],
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    DateFormat(
                                                      'hh:mm a',
                                                    ).format(
                                                      apt.appointmentDateTime,
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: Colors.grey[700],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (apt.caseTitle != null) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.folder_outlined,
                                                      size: 16,
                                                      color: Colors.grey[600],
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        'Case: ${apt.caseTitle}',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color:
                                                              Colors.grey[700],
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  final ev = entry.hearingEvent!;
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    color: hearingEventColor.withOpacity(0.06),
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.pop(dialogContext);
                                        _showHearingEventDetails(ev);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    entry.hearingTitle(),
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                if (entry.isAiScheduled)
                                                  Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                          left: 8,
                                                        ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: calendarGold,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      _aiSchedLabel,
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: Colors.black87,
                                                      ),
                                                    ),
                                                  ),
                                                Container(
                                                  margin: const EdgeInsets.only(
                                                    left: 8,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: hearingEventColor
                                                        .withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    border: Border.all(
                                                      color: hearingEventColor,
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    entry.hearingTypeLabel(),
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: hearingEventColor,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            HearingCalendarEventBody(
                                              data: ev,
                                              dense: true,
                                              maxLines: 3,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final created = await _handleAddForDate(date);
                                if (created == null || !context.mounted) {
                                  return;
                                }
                                final showDay = _calendarDay(
                                  created.appointmentDateTime,
                                );
                                final updated = _entriesForDateWithAppointment(
                                  showDay,
                                  _getEntriesForDate(showDay),
                                  created: created,
                                );
                                setDialogState(() => dayEntries = updated);
                                if (mounted) setState(() {});
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Add Appointment'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: calendarBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showHearingEventDetails(Map<String, dynamic> ev) async {
    var display = Map<String, dynamic>.from(ev);
    final hearingDocId = (ev['hearingDocId'] as String?)?.trim() ?? '';
    if (hearingDocId.isNotEmpty) {
      try {
        final snap = await _firestore
            .collection('hearings')
            .doc(hearingDocId)
            .get();
        if (snap.exists && snap.data() != null) {
          final hd = snap.data()!;
          final caseMaps = <Map<String, dynamic>>[];
          final caseId = (hd['caseId'] as String?)?.trim() ?? '';
          if (caseId.isNotEmpty) {
            final caseSnap = await _firestore
                .collection('cases')
                .doc(caseId)
                .get();
            if (caseSnap.exists && caseSnap.data() != null) {
              caseMaps.add({'id': caseSnap.id, ...caseSnap.data()!});
            }
          }
          final cn = (hd['caseNo'] as String?)?.trim() ?? '';
          final siblings = _hearingSiblingsForCase(cn);
          display = await HearingCalendarFields.loadMergedHearingForDisplay(
            hearingDocId: hearingDocId,
            hearingData: hd,
            caseMaps: caseMaps,
            siblingRows: siblings,
          );
          display['hearingDocId'] = hearingDocId;
          display['readOnly'] = true;
          display['eventType'] = 'hearing';
          display['source'] =
              ev['source'] as String? ?? HearingCalendarSyncService.sourceTag;
        }
      } catch (_) {
        /* keep calendar_event snapshot */
      }
    }
    if (!mounted) return;
    _showHearingEventDetailsDialog(display);
  }

  void _showHearingEventDetailsDialog(Map<String, dynamic> ev) {
    final title = hearingCalendarDisplayTitle(ev);
    final isAi = isAiSyncedCalendarEvent(ev);
    final et = ev['eventType'];
    final typeLabel = et is String && et.isNotEmpty
        ? et[0].toUpperCase() + et.substring(1)
        : 'Event';
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width > 600
              ? 500
              : double.infinity,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                if (isAi) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: calendarGold.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: calendarGold, width: 1),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: Colors.black87,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Automated schedule — court hearing record from case file (case number, parties, time, venue).',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: hearingEventColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: hearingEventColor, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.gavel,
                        size: 18,
                        color: hearingEventColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        typeLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: hearingEventColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Court hearing particulars (case file record)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 12),
                HearingNotificationDetailPanel(
                  data: ev,
                  hearingDocId: (ev['hearingDocId'] as String?)?.trim(),
                  calendarOnly: true,
                  siblingRows: _hearingSiblingsForCase(
                    (ev['caseNo'] as String?)?.trim() ?? '',
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Show detailed appointment information
  void _showAppointmentDetails(AppointmentModel appointment) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width > 600
              ? 500
              : double.infinity,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _getClientDisplayName(appointment),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Appointment Type
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _getAppointmentColor(appointment).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _getAppointmentColor(appointment),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getAppointmentTypeIcon(appointment.appointmentType),
                        size: 18,
                        color: _getAppointmentColor(appointment),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getAppointmentTypeLabel(appointment.appointmentType),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _getAppointmentColor(appointment),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Client Email
                Builder(
                  builder: (context) {
                    try {
                      final clientEmail = _getClientEmail(appointment);
                      if (clientEmail.isNotEmpty && clientEmail.contains('@')) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow(
                              icon: Icons.email_outlined,
                              label: 'Email',
                              value: clientEmail,
                            ),
                            const SizedBox(height: 16),
                          ],
                        );
                      }
                    } catch (e) {
                      if (kDebugMode) {
                        debugPrint('Error displaying client email: $e');
                      }
                    }
                    return const SizedBox.shrink();
                  },
                ),
                // Date and Time
                _buildDetailRow(
                  icon: Icons.calendar_today,
                  label: 'Date',
                  value: DateFormat(
                    'EEEE, MMMM dd, yyyy',
                  ).format(appointment.appointmentDateTime),
                ),
                const SizedBox(height: 16),
                _buildDetailRow(
                  icon: Icons.access_time,
                  label: 'Time',
                  value: DateFormat(
                    'hh:mm a',
                  ).format(appointment.appointmentDateTime),
                ),
                const SizedBox(height: 16),
                // Status
                _buildDetailRow(
                  icon: Icons.info_outline,
                  label: 'Status',
                  value: _getStatusLabel(appointment.status),
                  valueColor: _getStatusColor(appointment.status),
                ),
                // Case Information
                if (appointment.caseTitle != null) ...[
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    icon: Icons.folder_outlined,
                    label: 'Case',
                    value: appointment.caseTitle!,
                  ),
                ],
                if (appointment.caseId != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 32),
                    child: Text(
                      'Case ID: ${appointment.caseId}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ),
                ],
                // Notes
                if (appointment.notes != null &&
                    appointment.notes!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.note_outlined,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notes',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              appointment.notes!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: valueColor ?? Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getAppointmentTypeLabel(String type) {
    switch (type) {
      case 'in_office':
      case 'meeting_office':
        return 'Meeting in Office';
      case 'phone_call':
        return 'Phone Call';
      case 'online_meeting':
        return 'Online Meeting';
      case 'hearing':
      case 'hearing_court':
        return 'Hearing in Court';
      case 'consultation':
        return 'Consultation';
      default:
        // Format: convert snake_case to Title Case
        return type
            .replaceAll('_', ' ')
            .split(' ')
            .map((word) {
              return word.isEmpty
                  ? ''
                  : word[0].toUpperCase() + word.substring(1);
            })
            .join(' ');
    }
  }

  IconData _getAppointmentTypeIcon(String type) {
    switch (type) {
      case 'in_office':
      case 'meeting_office':
        return Icons.business;
      case 'phone_call':
        return Icons.phone;
      case 'online_meeting':
        return Icons.video_call;
      case 'hearing':
      case 'hearing_court':
        return Icons.gavel;
      case 'consultation':
        return Icons.meeting_room;
      default:
        return Icons.event;
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'confirmed':
      case 'scheduled':
        return 'Confirmed';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'rescheduled':
        return 'Rescheduled';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
      case 'scheduled':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'rescheduled':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
