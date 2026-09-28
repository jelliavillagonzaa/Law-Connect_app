import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/staff_service.dart';
import '../../services/staff_auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/hearing_calendar_fields.dart';
import '../../services/hearing_calendar_sync_service.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../services/notary_service.dart';
import '../../models/appointment_model.dart';
import '../../models/case_model.dart';
import '../../models/user_model.dart';
import '../../utils/calendar_perf.dart';
import '../../utils/calendar_hearing_nav.dart';
import '../../utils/calendar_live_hearing_map.dart';
import '../../widgets/common/hearing_calendar_event_body.dart';
import '../../widgets/common/hearing_notification_detail_panel.dart';
import '../../widgets/common/calendar_month_grid.dart';
import '../../widgets/common/stable_merged_listenable_builder.dart';
import '../attorney/appointment_calendar_view.dart';
import '../attorney/attorney_notary_request_detail_screen.dart';

class StaffCalendarScreen extends StatefulWidget {
  /// Pre-filled from dashboard so the grid shows instantly on first open.
  final List<AppointmentModel>? initialAppointments;

  /// Reuse dashboard Firestore stream (avoids duplicate listeners / lag).
  final Stream<List<AppointmentModel>>? sharedAppointmentsStream;

  /// Known from dashboard — avoids async gap before calendar_events subscribes.
  final String? assignedAttorneyId;

  /// When true, renders without [Scaffold] (used inside [StaffDashboard] tabs).
  final bool embedded;

  const StaffCalendarScreen({
    super.key,
    this.initialAppointments,
    this.sharedAppointmentsStream,
    this.assignedAttorneyId,
    this.embedded = false,
  });

  @override
  State<StaffCalendarScreen> createState() => _StaffCalendarScreenState();
}

class _StaffCalendarScreenState extends State<StaffCalendarScreen> {
  static final Map<String, List<Map<String, dynamic>>>
  _calendarEventsCacheByAttorney = <String, List<Map<String, dynamic>>>{};

  final StaffService _staffService = StaffService();
  final StaffAuthService _staffAuthService = StaffAuthService();
  final NotificationService _notificationService = NotificationService();
  final EnhancedAppointmentService _appointmentService =
      EnhancedAppointmentService();
  final NotaryService _notaryService = NotaryService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _assignedAttorneyId;
  late final ValueNotifier<DateTime> _viewDateNotifier = ValueNotifier(
    DateTime.now(),
  );
  DateTime get _viewDate => _viewDateNotifier.value;
  String _viewMode = 'month'; // 'month' or 'week'
  List<Map<String, dynamic>> _calendarEvents = [];
  List<AppointmentModel> _appointments = [];
  List<CaseModel> _attorneyCases = [];

  Timer? _dataUiDebounce;
  Map<String, List<Map<String, dynamic>>> _eventsByDayKey = {};
  List<Map<String, dynamic>>? _pendingCalendarEvents;
  List<AppointmentModel>? _pendingAppointments;
  List<Map<String, dynamic>>? _pendingLiveHearings;
  String _lastCalendarFingerprint = '';
  String _lastAppointmentsFingerprint = '';
  String _lastLiveHearingsFingerprint = '';
  String _lastEventsIndexFingerprint = '';
  int _eventsRevision = 0;
  final ValueNotifier<int> _eventsRevisionNotifier = ValueNotifier(0);
  List<Map<String, dynamic>> _cachedHearingNavEvents = [];
  List<Map<String, dynamic>> _liveHearingRows = [];
  Timer? _entriesIndexDebounce;
  final ValueNotifier<int> _hearingNavRevision = ValueNotifier(0);
  bool _flushDataImmediately = true;
  bool _entriesIndexFlushImmediately = true;
  bool _ownsAppointmentsStream = false;
  bool _didRevealHearingMonth = false;
  final Set<String> _seenHearingDocIds = {};
  bool _followNewHearings = false;
  Timer? _armFollowTimer;

  // Stream subscriptions
  StreamSubscription<List<CaseModel>>? _casesSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _eventsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _liveHearingsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _notificationsSubscription;
  StreamSubscription<List<AppointmentModel>>? _appointmentsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _notaryCalendarSub;
  List<Map<String, dynamic>> _notaryCalendarRows = [];

  // Calendar color theme (match attorney calendar)
  static const Color calendarBlue = Color.fromARGB(255, 46, 109, 192);
  static const Color calendarGold = Color(0xFFF4C10F);
  static const Color sundayRed = Color(0xFFE53935);
  static const Color hearingEventColor = Color(0xFF5E35B1);
  static const Color primaryRed = calendarBlue;

  Timer? _reminderPeriodicTimer;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialAppointments;
    if (seed != null && seed.isNotEmpty) {
      _appointments = List<AppointmentModel>.from(seed);
    }
    final presetAttorneyId = widget.assignedAttorneyId?.trim();
    if (presetAttorneyId != null && presetAttorneyId.isNotEmpty) {
      _assignedAttorneyId = presetAttorneyId;
      _bootstrapCalendarData();
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          _notificationService.initialize();
          _checkHearingNotifications();
        }
      });
    } else {
      _loadAttorneyId();
    }
  }

  void _bootstrapCalendarData() {
    _hydrateCalendarEventsFromCache();
    _hydrateLiveHearingsFromCache();
    _paintGridFromCachedData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bindAppointments();
      _loadCalendarEvents();
      _loadAttorneyCases();
      _scheduleBackgroundHearingSync();
      Future<void>.delayed(
        Duration(milliseconds: kIsWeb ? 80 : CalendarPerf.hearingStreamDeferMs),
        () {
          if (!mounted) return;
          _subscribeLiveHearings();
          _subscribeNotaryCalendar();
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

  void _scheduleBackgroundHearingSync() {
    final aid = _assignedAttorneyId?.trim() ?? '';
    if (aid.isEmpty) return;
    Future<void>.delayed(
      Duration(
        milliseconds: kIsWeb ? 200 : CalendarPerf.attachSyncDeferMs,
      ),
      () {
        if (!mounted) return;
        HearingCalendarSyncService.instance.attachForAttorney(aid);
      },
    );
  }

  List<Map<String, dynamic>> _gridCalendarEvents() {
    final merged = CalendarLiveHearingMap.mergeIntoCalendarEvents(
      _calendarEvents,
      _liveHearingRows,
    );
    if (_notaryCalendarRows.isEmpty) return merged;
    return [...merged, ..._notaryCalendarRows];
  }

  void _hydrateCalendarEventsFromCache() {
    final aid = _assignedAttorneyId?.trim() ?? '';
    if (aid.isEmpty) return;
    final cached = _calendarEventsCacheByAttorney[aid];
    if (cached == null || cached.isEmpty) return;
    _calendarEvents = List<Map<String, dynamic>>.from(cached);
    _lastCalendarFingerprint = _calendarEventsFingerprint(_calendarEvents);
    _seedSeenHearings(_calendarEvents);
  }

  void _hydrateLiveHearingsFromCache() {
    final aid = HearingCalendarSyncService.overlayKey(_assignedAttorneyId ?? '');
    final cached = HearingCalendarSyncService.instance.peekHearingNavRows(aid);
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
    _scheduleEventsIndexRebuild();
    _hearingNavRevision.value++;
  }

  void _scheduleEventsIndexRebuild({bool immediate = false}) {
    _entriesIndexDebounce?.cancel();
    if (immediate) _entriesIndexFlushImmediately = true;
    final ms = _entriesIndexFlushImmediately
        ? 0
        : CalendarPerf.entriesIndexDebounceMs;
    _entriesIndexDebounce = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      unawaited(_rebuildEventsIndexAsync());
      _entriesIndexFlushImmediately = false;
    });
  }

  String _eventsIndexFingerprint() =>
      '${_appointmentsFingerprint(_appointments)}|${_calendarEventsFingerprint(_calendarEvents)}|${_calendarEventsFingerprint(_liveHearingRows)}|${_calendarEventsFingerprint(_notaryCalendarRows)}';

  Future<void> _rebuildEventsIndexAsync() async {
    final fp = _eventsIndexFingerprint();
    if (fp == _lastEventsIndexFingerprint && _eventsByDayKey.isNotEmpty) {
      return;
    }

    final appointments = List<AppointmentModel>.from(_appointments);
    final calendarEvents = _gridCalendarEvents();

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final buckets = <String, List<Map<String, dynamic>>>{};
    final hearingIdsByDay = <String, Set<String>>{};
    final appointmentIdsByDay = <String, Set<String>>{};

    void addEvent(
      Map<String, dynamic> ev, {
      bool allowAppointment = false,
    }) {
      final type = (ev['eventType'] as String?)?.trim().toLowerCase() ?? '';
      if (!allowAppointment && type == 'appointment') return;
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
      final aptId = (ev['appointmentId'] as String?)?.trim() ?? '';
      if (aptId.isNotEmpty) {
        final seen = appointmentIdsByDay.putIfAbsent(key, () => <String>{});
        if (seen.contains(aptId)) return;
        seen.add(aptId);
      }
      buckets.putIfAbsent(key, () => []).add(Map<String, dynamic>.from(ev));
    }

    for (var i = 0; i < calendarEvents.length; i++) {
      if (i > 0 && i % 50 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
      }
      addEvent(calendarEvents[i]);
    }
    for (final apt in appointments) {
      if (apt.appointmentType == 'hearing_court') continue;
      if (!apt.appearsOnAttorneyCalendar) continue;
      addEvent(_appointmentAsEvent(apt), allowAppointment: true);
    }

    for (final key in buckets.keys.toList()) {
      final list = buckets[key]!
        ..sort((a, b) {
          final ad = _dateTimeFromField(a['eventDate']);
          final bd = _dateTimeFromField(b['eventDate']);
          if (ad == null || bd == null) return 0;
          return ad.compareTo(bd);
        });
      buckets[key] = _collapseSameCaseOnDay(list);
    }

    if (!mounted) return;
    _lastEventsIndexFingerprint = fp;
    _eventsByDayKey = buckets;
    _eventsRevision++;
    _eventsRevisionNotifier.value++;
  }

  void _rebuildEventsIndex() {
    unawaited(_rebuildEventsIndexAsync());
  }

  /// Repeated imports of one case on the same day stay a single card.
  List<Map<String, dynamic>> _collapseSameCaseOnDay(
    List<Map<String, dynamic>> list,
  ) {
    final out = <String, Map<String, dynamic>>{};
    final order = <String>[];
    for (final ev in list) {
      final cn = HearingCalendarFields.asDisplayString(ev['caseNo'])
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      final id = HearingCalendarFields.asDisplayString(
        ev['hearingDocId'] ?? ev['id'],
      );
      final key = id.isNotEmpty ? 'id:$id' : (cn.isNotEmpty ? 'case:$cn' : 'x:${ev.hashCode}');
      final prev = out[key];
      if (prev == null) {
        order.add(key);
        out[key] = ev;
        continue;
      }
      final prevTitle = HearingCalendarFields.asDisplayString(prev['caseTitle']);
      final nextTitle = HearingCalendarFields.asDisplayString(ev['caseTitle']);
      if (nextTitle.length > prevTitle.length) out[key] = ev;
    }
    return [for (final k in order) out[k]!];
  }

  void _subscribeNotaryCalendar() {
    final aid = _assignedAttorneyId?.trim() ?? '';
    if (aid.isEmpty) return;
    _notaryCalendarSub?.cancel();
    _notaryCalendarSub = _notaryService.watchNotaryCalendarRows(aid).listen(
      (rows) {
        if (!mounted) return;
        _notaryCalendarRows = rows;
        _scheduleEventsIndexRebuild();
        _hearingNavRevision.value++;
      },
      onError: (_) {},
    );
  }

  void _subscribeLiveHearings() {
    final aid = HearingCalendarSyncService.overlayKey(_assignedAttorneyId ?? '');

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
      onError: (e) {
        debugPrint('[StaffCalendar] live hearings: $e');
      },
    );
  }

  Future<void> _loadAutomatedHearings() async {
    final aid = HearingCalendarSyncService.overlayKey(_assignedAttorneyId ?? '');
    if (!mounted) return;
    try {
      var rows = await HearingCalendarSyncService.instance
          .fetchAutomatedCalendarRows(aid);
      final inbox = await HearingCalendarSyncService.instance
          .fetchRowsFromHearingNotifications(aid);
      rows = CalendarLiveHearingMap.mergeHearingRows(rows, inbox);
      if (!mounted || rows.isEmpty) return;
      _applyAutomatedHearingRows(rows);
    } catch (e) {
      debugPrint('[StaffCalendar] automated hearings failed: $e');
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
    _lastEventsIndexFingerprint = '';
    _rebuildHearingNavCache();
    _hearingNavRevision.value++;
    if (!_followNewHearingMonth(_liveHearingRows)) {
      _maybeRevealHearingMonth();
    }
    unawaited(_rebuildEventsIndexAsync());
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

  void _maybeRevealHearingMonth() {
    if (_didRevealHearingMonth || _liveHearingRows.isEmpty) return;
    final view = _viewDateNotifier.value;
    final inView = _liveHearingRows.any((ev) {
      final d = ev['eventDate'];
      return d is DateTime && d.year == view.year && d.month == view.month;
    });
    if (inView) {
      _didRevealHearingMonth = true;
      return;
    }
    final hasApptInView = _appointments.any((a) {
      final d = a.appointmentDateTime;
      return d.year == view.year && d.month == view.month;
    });
    if (hasApptInView) {
      _didRevealHearingMonth = true;
      return;
    }
    DateTime? pick;
    for (final ev in _liveHearingRows) {
      final d = ev['eventDate'];
      if (d is! DateTime) continue;
      if (pick == null || d.isAfter(pick)) pick = d;
    }
    if (pick == null) return;
    _didRevealHearingMonth = true;
    _viewDateNotifier.value = DateTime(pick.year, pick.month);
  }

  @override
  void didUpdateWidget(StaffCalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sharedAppointmentsStream != widget.sharedAppointmentsStream ||
        oldWidget.initialAppointments != widget.initialAppointments) {
      final seed = widget.initialAppointments;
      if (seed != null && seed.isNotEmpty) {
        _appointments = List<AppointmentModel>.from(seed);
      }
      _bindAppointments();
    }
    final newAid = widget.assignedAttorneyId?.trim() ?? '';
    if (newAid.isNotEmpty && newAid != _assignedAttorneyId) {
      _assignedAttorneyId = newAid;
      _bootstrapCalendarData();
    }
  }

  @override
  void dispose() {
    _reminderPeriodicTimer?.cancel();
    _armFollowTimer?.cancel();
    _dataUiDebounce?.cancel();
    _entriesIndexDebounce?.cancel();
    _hearingNavRevision.dispose();
    _eventsRevisionNotifier.dispose();
    _viewDateNotifier.dispose();
    _casesSubscription?.cancel();
    _eventsSubscription?.cancel();
    _liveHearingsSub?.cancel();
    _notaryCalendarSub?.cancel();
    _notificationsSubscription?.cancel();
    if (_ownsAppointmentsStream) {
      _appointmentsSubscription?.cancel();
    }
    super.dispose();
  }

  Future<void> _loadAttorneyId() async {
    if (!mounted) return;

    final staff = await _staffAuthService.getCurrentStaff();
    if (!mounted) return;

    if (staff != null) {
      final attorneyId = staff.assignedAttorneyId;
      _assignedAttorneyId = attorneyId;
      _bootstrapCalendarData();
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          _notificationService.initialize();
          _checkHearingNotifications();
        }
      });
    } else {
      _bootstrapCalendarData();
    }
  }

  void _loadAttorneyCases() {
    if (_assignedAttorneyId == null) return;

    _casesSubscription?.cancel();
    _casesSubscription = _staffService
        .getAttorneyCases(_assignedAttorneyId!)
        .listen((cases) {
          if (mounted) _attorneyCases = cases;
        });
  }

  void _loadCalendarEvents() {
    if (_assignedAttorneyId == null) return;
    final aid = _assignedAttorneyId?.trim() ?? '';
    if (aid.isNotEmpty) {
      final cached = _calendarEventsCacheByAttorney[aid];
      if (cached != null && cached.isNotEmpty) {
        _calendarEvents = List<Map<String, dynamic>>.from(cached);
        _lastCalendarFingerprint = _calendarEventsFingerprint(_calendarEvents);
        _rebuildHearingNavCache();
        _scheduleEventsIndexRebuild();
      }
    }

    _eventsSubscription?.cancel();
    _eventsSubscription = _staffService
        .getCalendarEvents(_assignedAttorneyId!)
        .listen((events) {
          _pendingCalendarEvents = events;
          _scheduleDataUiFlush();
        });
  }

  String _dayKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

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
      if (rows.isNotEmpty) {
        final merged = CalendarLiveHearingMap.mergeHearingRows(
          _liveHearingRows,
          rows,
        );
        final fp = CalendarPerf.eventsFingerprint(merged);
        if (fp != _lastLiveHearingsFingerprint) {
          _liveHearingRows = merged;
          _lastLiveHearingsFingerprint = fp;
          hearingsChanged = true;
          if (!_followNewHearingMonth(_liveHearingRows)) {
            _maybeRevealHearingMonth();
          }
        }
      }
    }

    if (pendingCalendar != null) {
      final fp = _calendarEventsFingerprint(pendingCalendar);
      if (fp != _lastCalendarFingerprint) {
        _calendarEvents = pendingCalendar;
        final aid = _assignedAttorneyId?.trim() ?? '';
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
      final aid = _assignedAttorneyId?.trim() ?? '';
      if (aid.isNotEmpty) {
        unawaited(
          _appointmentService.syncOccupiedTimeSlotsIfNeeded(aid, _appointments),
        );
      }
    }

    void commitUi() {
      if (!calendarChanged && !appointmentsChanged && !hearingsChanged) {
        return;
      }
      _rebuildHearingNavCache();
      _scheduleEventsIndexRebuild();
      _hearingNavRevision.value++;
    }

    if (pendingCalendar != null && pendingAppointments != null) {
      Future.microtask(() {
        applyAppointmentsNow();
        if (!appointmentsChanged || !mounted) return;
        _rebuildHearingNavCache();
        _scheduleEventsIndexRebuild();
        _hearingNavRevision.value++;
      });
      if (calendarChanged) commitUi();
      return;
    }

    applyAppointmentsNow();
    commitUi();
  }

  void _rebuildHearingNavCache() {
    _cachedHearingNavEvents = _gridCalendarEvents()
        .where(CalendarHearingNav.isHearingRow)
        .toList();
  }

  /// Same client appointments the attorney sees, so the calendars are identical.
  void _bindAppointments() {
    if (_ownsAppointmentsStream) {
      _appointmentsSubscription?.cancel();
      _appointmentsSubscription = null;
    }

    final shared = widget.sharedAppointmentsStream;
    if (shared != null) {
      _ownsAppointmentsStream = false;
      _appointmentsSubscription = shared.listen(
        (appointments) {
          if (!mounted) return;
          _pendingAppointments = appointments;
          _scheduleDataUiFlush();
        },
        onError: (e) {
          debugPrint('Staff calendar appointments stream: $e');
        },
      );
      return;
    }

    final aid = _assignedAttorneyId?.trim() ?? '';
    if (aid.isEmpty) return;

    _ownsAppointmentsStream = true;
    _appointmentsSubscription = _appointmentService
        .getAttorneyAppointments(aid)
        .listen(
          (appointments) {
            if (!mounted) return;
            _pendingAppointments = appointments;
            _scheduleDataUiFlush();
          },
          onError: (e) {
            debugPrint('Staff calendar appointments stream: $e');
          },
        );
  }

  /// Adapts an attorney client appointment into the calendar event shape used
  /// by the day cells / dialogs (rendered as a non-hearing blue chip).
  Map<String, dynamic> _appointmentAsEvent(AppointmentModel a) {
    final title = a.clientName.trim().isNotEmpty
        ? a.clientName.trim()
        : (a.caseTitle?.trim().isNotEmpty == true
              ? a.caseTitle!.trim()
              : 'Appointment');
    return <String, dynamic>{
      'id': 'appt_${a.id}',
      'appointmentId': a.id,
      'eventType': 'appointment',
      'eventDate': a.appointmentDateTime,
      'title': title,
      'description': a.notes,
      'clientName': a.clientName,
      'caseTitle': a.caseTitle,
      'appointmentType': a.appointmentType,
      'status': a.status,
      'source': 'attorney_appointment',
    };
  }

  /// Hearing rows from `calendar_events` for the cross-month navigation banner.
  List<Map<String, dynamic>> _allHearingNavEvents() => _cachedHearingNavEvents;

  List<DateTime> _hearingMonthsOutsideView(DateTime viewDate) {
    return CalendarHearingNav.monthsOutsideView(
      hearingRows: _allHearingNavEvents(),
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
              'Scheduled court hearings on file appear in another month — View:',
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

  bool _isHearingCalendarEvent(Map<String, dynamic> ev) {
    if (NotaryService.isNotaryCalendarRow(ev)) return false;
    if ((ev['hearingDocId'] as String?)?.trim().isNotEmpty == true) {
      return true;
    }
    return isAiSyncedCalendarEvent(ev);
  }

  String _hearingDisplayTitle(Map<String, dynamic> ev) {
    final caseNo = (ev['caseNo'] as String?)?.trim();
    if (caseNo != null && caseNo.isNotEmpty) return caseNo;
    final client = (ev['clientName'] as String?)?.trim();
    if (client != null && client.isNotEmpty) return client;
    final caseTitle = (ev['caseTitle'] as String?)?.trim();
    if (caseTitle != null && caseTitle.isNotEmpty) return caseTitle;
    final t = (ev['title'] as String?)?.trim();
    if (t != null && t.isNotEmpty) {
      return t.replaceFirst(RegExp(r'^\[AI\]\s*'), '');
    }
    return 'Hearing';
  }

  void _checkHearingNotifications() {
    if (_assignedAttorneyId == null) return;

    _notificationsSubscription?.cancel();
    _notificationsSubscription = _staffService
        .getUpcomingHearingNotifications(_assignedAttorneyId!)
        .listen((notifications) {
          if (!mounted) return;

          for (var notification in notifications) {
            final notificationDate =
                notification['notificationDate'] as DateTime?;
            if (notificationDate != null) {
              final now = DateTime.now();
              if (notificationDate.year == now.year &&
                  notificationDate.month == now.month &&
                  notificationDate.day == now.day) {
                _sendHearingNotification(notification);
              }
            }
          }
        });
  }

  Future<void> _sendHearingNotification(
    Map<String, dynamic> notification,
  ) async {
    if (!mounted) return;

    final hearingDate = notification['hearingDate'] as DateTime?;
    final title = notification['title'] as String? ?? 'Upcoming Hearing';
    final notificationId = notification['id'] as String?;

    if (hearingDate != null && notificationId != null) {
      final daysUntil = hearingDate.difference(DateTime.now()).inDays;
      final hearingDateStr = DateFormat(
        'EEEE, MMMM dd, yyyy • hh:mm a',
      ).format(hearingDate);

      if (mounted) {
        await _notificationService.showAlert(
          title: '🔔 Hearing Reminder',
          message: '$title\nDate: $hearingDateStr\n($daysUntil days remaining)',
        );
      }

      if (mounted) {
        await _staffService.markNotificationAsSent(notificationId);
      }
    }
  }

  List<Map<String, dynamic>> _getEventsForDate(DateTime date) {
    return _eventsByDayKey[_dayKey(
          DateTime(date.year, date.month, date.day),
        )] ??
        const [];
  }

  Color _eventChipColor(Map<String, dynamic> event) {
    if (NotaryService.isNotaryCalendarRow(event)) {
      return const Color(0xFF00897B);
    }
    if (_isHearingCalendarEvent(event)) return hearingEventColor;
    if ((event['eventType'] as String?) == 'appointment') {
      switch (event['status'] as String? ?? 'scheduled') {
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
    return _getEventTypeColor(event['eventType'] as String?);
  }

  String _eventGridLabel(Map<String, dynamic> event) {
    if (_isHearingCalendarEvent(event)) {
      return _hearingDisplayTitle(event);
    }
    final client = (event['clientName'] as String?)?.trim();
    if (client != null && client.isNotEmpty) return client;
    return (event['title'] as String?)?.trim().isNotEmpty == true
        ? event['title'] as String
        : 'Event';
  }

  Widget _buildCompactDayEvent(Map<String, dynamic> event) {
    final when = _dateTimeFromField(event['eventDate']);
    final isHearing = _isHearingCalendarEvent(event);
    final label = isHearing
        ? _hearingDisplayTitle(event)
        : (event['title'] as String?) ?? 'Event';
    return InkWell(
      onTap: () => Future.microtask(() => _showEventDetails(event)),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: _eventChipColor(event),
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
                    when != null ? DateFormat('hh:mm a').format(when) : '',
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
                if (isAiSyncedCalendarEvent(event))
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
    List<Map<String, dynamic>> events, {
    required double bodyHeight,
  }) {
    if (events.isEmpty) return const SizedBox.shrink();
    final layout = CalendarPerf.layoutDayCellEntries(
      bodyHeight: bodyHeight,
      totalEntries: events.length,
    );
    if (layout.shown <= 0) {
      if (!layout.showMore) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          '+${events.length} more',
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
              child: _buildCompactDayEvent(events[i]),
            ),
          ),
        if (layout.showMore)
          SizedBox(
            height: CalendarPerf.monthCellMoreRowHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '+${events.length - layout.shown} more',
                  style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Map<String, dynamic>> _hearingSiblingsForCase(String caseNo) {
    final cn = caseNo.trim();
    if (cn.isEmpty) return const [];
    return _calendarEvents
        .where((o) => (o['caseNo'] as String?)?.trim() == cn)
        .toList();
  }

  Color _getEventTypeColor(String? type) {
    switch (type) {
      case 'deadline':
        return Colors.red;
      case 'hearing':
        return Colors.blue;
      case 'filing':
        return Colors.orange;
      case 'meeting':
        return Colors.green;
      case 'reminder':
        return Colors.purple;
      case 'appointment':
        return calendarBlue;
      case 'notary':
        return const Color(0xFF00897B);
      default:
        return calendarBlue;
    }
  }

  Widget _buildCalendarBody({required bool isMobile}) {
    return Column(
      children: [
        if (widget.embedded && isMobile && kIsWeb)
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
                      onPressed: () => _showAddEventDialog(),
                      tooltip: 'New Event',
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
                builder: (context, _) =>
                    _buildHearingsOutsideMonthBanner(_viewDateNotifier.value),
              ),
              Expanded(
                child: RepaintBoundary(
                  child: StableMergedListenableBuilder(
                    listenables: [_viewDateNotifier, _eventsRevisionNotifier],
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
    if (_assignedAttorneyId == null) {
      if (widget.embedded) {
        return const ColoredBox(
          color: Colors.white,
          child: Center(child: Text('No attorney assigned')),
        );
      }
      return Scaffold(
        appBar: AppBar(
          backgroundColor: calendarBlue,
          title: const Text(
            'Calendar',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: const Center(child: Text('No attorney assigned')),
      );
    }

    final calendar = AppointmentCalendarView(
      embedded: widget.embedded,
      attorneyId: _assignedAttorneyId,
      initialAppointments: widget.initialAppointments ?? _appointments,
      sharedAppointmentsStream: widget.sharedAppointmentsStream,
      showTopAddButton: false,
      padHeaderForStatusBar: !kIsWeb,
      actingAsStaff: true,
      onAddPressed: () {
        unawaited(_showAddEventDialog());
      },
      onAddForDate: _showAddEventDialogForDate,
    );

    if (widget.embedded) {
      return calendar;
    }
    return calendar;
  }

  Widget _buildCalendarHeader({
    required bool isMobile,
    required DateTime viewDate,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      color: calendarBlue,
      child: Row(
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
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 10 : 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: calendarGold,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  DateFormat('yyyy').format(viewDate),
                  style: TextStyle(
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
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
          // Match attorney calendar: only Sunday column in red.
          final isSunday = index == 0;
          return Expanded(
            child: Center(
              child: Text(
                labels[index],
                style: TextStyle(
                  fontSize: 12,
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
          key: ValueKey('staff-month-${viewDate.year}-${viewDate.month}'),
          viewDate: viewDate,
          isCompact: isCompact,
          cellBuilder: (context, day, isCurrentMonth, isToday) {
            return _buildDayCell(
              day,
              isCurrentMonth,
              isToday,
              _getEventsForDate(day),
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
    final dayEvents = _getEventsForDate(day);

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
          InkWell(
            onTap: dayEvents.isNotEmpty
                ? () => Future.microtask(
                    () => _showEventsForDate(day, dayEvents),
                  )
                : () => _showAddEventDialogForDate(day),
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
                      if (dayEvents.isNotEmpty) ...[
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
                            '${dayEvents.length}',
                            style: const TextStyle(
                              fontSize: 8,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
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
                itemCount: dayEvents.length,
                itemBuilder: (context, index) =>
                    _buildTimeSlotEvent(dayEvents[index]),
              ),
            ),
          ),
          InkWell(
            onTap: () => _showAddEventDialogForDate(day),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.add, size: 20, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(
    DateTime day,
    bool isCurrentMonth,
    bool isToday,
    List<Map<String, dynamic>> events, {
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
            onTap: events.isNotEmpty
                ? () => Future.microtask(
                    () => _showEventsForDate(day, events),
                  )
                : () => _showAddEventDialogForDate(day),
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
                  if (events.isNotEmpty) ...[
                    const SizedBox(width: 2),
                    Flexible(
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
                          '${events.length}',
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
                  ],
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
                            events,
                            bodyHeight: monthCellBodyHeight,
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
                                events,
                                bodyHeight: bodyHeight,
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

  Widget _buildTimeSlotEvent(Map<String, dynamic> event) {
    final when = _dateTimeFromField(event['eventDate']);
    return InkWell(
      onTap: () => Future.microtask(() => _showEventDetails(event)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _eventChipColor(event),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (when != null)
              Text(
                DateFormat('hh:mm a').format(when),
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            Text(
              _eventGridLabel(event),
              style: const TextStyle(fontSize: 12, color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showEventsForDate(DateTime date, List<Map<String, dynamic>> events) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width > 600
              ? 500
              : double.infinity,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('MMMM dd, yyyy').format(date),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final aiN = events.where(isAiSyncedCalendarEvent).length;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${events.length} scheduled item${events.length != 1 ? 's' : ''}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${events.length} calendar event${events.length != 1 ? 's' : ''}'
                        '${aiN > 0 ? ' ($aiN AI)' : ''}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    final isHearing = _isHearingCalendarEvent(event);
                    final when = _dateTimeFromField(event['eventDate']);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: isHearing
                          ? hearingEventColor.withOpacity(0.06)
                          : null,
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          if (isHearing) {
                            _showHearingEventDetails(event);
                          } else {
                            _showEventDetails(event);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      isHearing
                                          ? _hearingDisplayTitle(event)
                                          : (event['title'] ?? 'Event'),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (isAiSyncedCalendarEvent(event))
                                    const Padding(
                                      padding: EdgeInsets.only(left: 8),
                                      child: HearingAiSchedBadge(),
                                    ),
                                  if (isHearing) ...[
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: hearingEventColor.withOpacity(
                                          0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: hearingEventColor,
                                          width: 1,
                                        ),
                                      ),
                                      child: const Text(
                                        'Hearing',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: hearingEventColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ] else
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getEventTypeColor(
                                          event['eventType'],
                                        ).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _getEventTypeColor(
                                            event['eventType'],
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        event['eventType'] ?? 'event',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _getEventTypeColor(
                                            event['eventType'],
                                          ),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (when != null) ...[
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
                                      DateFormat('hh:mm a').format(when),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (isHearing) ...[
                                const SizedBox(height: 8),
                                HearingCalendarEventBody(
                                  data: event,
                                  dense: true,
                                  maxLines: 7,
                                ),
                              ] else if (event['description'] != null &&
                                  event['description']
                                      .toString()
                                      .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  event['description'],
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showAddEventDialogForDate(date);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Event'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: calendarBlue,
                  foregroundColor: Colors.white,
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
        /* keep calendar snapshot */
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
                      color: calendarGold.withValues(alpha: 0.35),
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

  void _showEventDetails(Map<String, dynamic> event) {
    if (NotaryService.isNotaryCalendarRow(event)) {
      final id = (event['notaryRequestId'] as String?)?.trim() ?? '';
      if (id.isEmpty) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AttorneyNotaryRequestDetailScreen(
            requestId: id,
            actingAsStaff: true,
          ),
        ),
      );
      return;
    }
    if (_isHearingCalendarEvent(event)) {
      _showHearingEventDetails(event);
      return;
    }
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
                        event['title'] ?? 'Event',
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _getEventTypeColor(
                      event['eventType'],
                    ).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _getEventTypeColor(event['eventType']),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    event['eventType'] ?? 'event',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _getEventTypeColor(event['eventType']),
                    ),
                  ),
                ),
                if (_dateTimeFromField(event['eventDate']) != null) ...[
                  const SizedBox(height: 24),
                  _buildDetailRow(
                    icon: Icons.calendar_today,
                    label: 'Date',
                    value: DateFormat(
                      'EEEE, MMMM dd, yyyy',
                    ).format(_dateTimeFromField(event['eventDate'])!),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    icon: Icons.access_time,
                    label: 'Time',
                    value: DateFormat(
                      'hh:mm a',
                    ).format(_dateTimeFromField(event['eventDate'])!),
                  ),
                ],
                if (event['description'] != null &&
                    event['description'].toString().isNotEmpty) ...[
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
                              'Description',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              event['description'],
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
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAddEventDialogForDate(DateTime date) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime? selectedDate = date;
    TimeOfDay? selectedTime = TimeOfDay.now();
    String? eventType;
    String? selectedCaseId;
    String? selectedClientId; // Single client from dropdown
    bool notifyClient = false;
    bool notifyAttorney = false; // To notify the assigned attorney

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          // Helper to safely update state - defer setState to avoid gesture conflicts
          void safeSetState(VoidCallback fn) {
            // Use Future.delayed to defer to next event loop iteration
            Future.delayed(Duration.zero, () {
              if (context.mounted) {
                setState(fn);
              }
            });
          }

          return AlertDialog(
            title: const Text('Add Calendar Event'),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            content: SizedBox(
              width: MediaQuery.of(context).size.width > 600
                  ? 500
                  : double.infinity,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Event Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'deadline',
                          child: Text('Deadline'),
                        ),
                        DropdownMenuItem(
                          value: 'hearing',
                          child: Text('Hearing'),
                        ),
                        DropdownMenuItem(
                          value: 'filing',
                          child: Text('Filing'),
                        ),
                        DropdownMenuItem(
                          value: 'meeting',
                          child: Text('Meeting'),
                        ),
                        DropdownMenuItem(
                          value: 'reminder',
                          child: Text('Reminder'),
                        ),
                      ],
                      onChanged: (value) {
                        safeSetState(() {
                          eventType = value;
                          if (value != 'hearing') {
                            selectedCaseId = null;
                            selectedClientId = null;
                          }
                        });
                      },
                    ),
                    if (eventType == 'hearing') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Select Case (Optional)',
                          border: OutlineInputBorder(),
                          helperText: 'Link hearing to a case',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('No Case Selected'),
                          ),
                          ..._attorneyCases.map(
                            (caseModel) => DropdownMenuItem(
                              value: caseModel.id,
                              child: Text(caseModel.caseTitle),
                            ),
                          ),
                        ],
                        value: selectedCaseId,
                        onChanged: (value) {
                          safeSetState(() {
                            selectedCaseId = value;
                            if (value != null) {
                              try {
                                final selectedCase = _attorneyCases.firstWhere(
                                  (c) => c.id == value,
                                );
                                selectedClientId = selectedCase.clientId;
                              } catch (e) {
                                selectedClientId = null;
                              }
                            } else {
                              selectedClientId = null;
                            }
                          });
                        },
                      ),
                      if (selectedCaseId != null) ...[
                        const SizedBox(height: 8),
                        StreamBuilder<DocumentSnapshot>(
                          stream: _firestore
                              .collection('users')
                              .doc(selectedClientId)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data!.exists) {
                              final data =
                                  snapshot.data!.data() as Map<String, dynamic>;
                              final client = UserModel.fromFirestore(
                                data,
                                selectedClientId!,
                              );
                              return Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.person,
                                      size: 16,
                                      color: Colors.blue,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Client: ${client.name}',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    ListTile(
                      title: Text(
                        selectedDate == null
                            ? 'Select Date'
                            : DateFormat('MMM dd, yyyy').format(selectedDate!),
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (date != null) {
                          safeSetState(() {
                            selectedDate = date;
                          });
                        }
                      },
                    ),
                    ListTile(
                      title: Text(
                        selectedTime == null
                            ? 'Select Time'
                            : selectedTime!.format(context),
                      ),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: selectedTime ?? TimeOfDay.now(),
                        );
                        if (time != null) {
                          safeSetState(() {
                            selectedTime = time;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    // Select Client (Optional) dropdown
                    const Text(
                      'Select Client (Optional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _loadClientsWithDetails(_assignedAttorneyId),
                      builder: (context, snapshot) {
                        final clients = snapshot.data ?? [];
                        return DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            hintText: 'Select a client *',
                            border: OutlineInputBorder(),
                          ),
                          value: selectedClientId,
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('No Client Selected'),
                            ),
                            ...clients.map(
                              (client) => DropdownMenuItem(
                                value: client['id'] as String,
                                child: Text(
                                  client['name'] as String? ?? 'Client',
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            safeSetState(() {
                              selectedClientId = value;
                              // If client is cleared and Client checkbox is checked, uncheck it
                              if (value == null && notifyClient) {
                                notifyClient = false;
                              }
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    // Send Reminders To section
                    const Text(
                      'Send Reminders To',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Staff always notified (current user)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Staff (You) - Always notified',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(),
                          // Client checkbox - only enabled if a client is selected
                          CheckboxListTile(
                            title: const Text('Client'),
                            value: notifyClient,
                            onChanged: selectedClientId != null
                                ? (value) {
                                    safeSetState(() {
                                      notifyClient = value ?? true;
                                    });
                                  }
                                : null,
                            activeColor: Colors.blue,
                            contentPadding: EdgeInsets.zero,
                            subtitle: selectedClientId == null
                                ? const Text(
                                    'Select a client first',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  )
                                : notifyClient
                                ? FutureBuilder<DocumentSnapshot>(
                                    future: _firestore
                                        .collection('users')
                                        .doc(selectedClientId)
                                        .get(),
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData &&
                                          snapshot.data!.exists) {
                                        final data =
                                            snapshot.data!.data()
                                                as Map<String, dynamic>;
                                        final clientName =
                                            data['name'] ??
                                            data['fullName'] ??
                                            'Client';
                                        return Text(
                                          'Will remind: $clientName',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.blue,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  )
                                : null,
                          ),
                          // Attorney checkbox (to notify the assigned attorney)
                          CheckboxListTile(
                            title: const Text('Attorney'),
                            value: notifyAttorney,
                            onChanged: (value) {
                              safeSetState(() {
                                notifyAttorney = value ?? true;
                              });
                            },
                            activeColor: Colors.blue,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (titleController.text.isEmpty ||
                      selectedDate == null ||
                      selectedTime == null ||
                      eventType == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please fill all required fields'),
                      ),
                    );
                    return;
                  }

                  final eventDateTime = DateTime(
                    selectedDate!.year,
                    selectedDate!.month,
                    selectedDate!.day,
                    selectedTime!.hour,
                    selectedTime!.minute,
                  );

                  // If notifyClient is checked, use the selectedClientId from the dropdown
                  final clientIdsToRemind =
                      notifyClient && selectedClientId != null
                      ? [selectedClientId!]
                      : <String>[];

                  final shouldSendNow = true; // Always send immediately

                  final result = await _staffService.createCalendarEvent(
                    eventType: eventType!,
                    eventDate: eventDateTime,
                    title: titleController.text,
                    description: descriptionController.text.isEmpty
                        ? null
                        : descriptionController.text,
                    caseId: selectedCaseId,
                    assignedTo: _assignedAttorneyId,
                    clientId: selectedClientId,
                    remindAttorney:
                        notifyAttorney, // Based on checkbox selection
                    remindClient: notifyClient,
                    selectedClientIds: clientIdsToRemind,
                    sendNow: shouldSendNow,
                    notifyStaff:
                        true, // Staff (current user) is always notified
                  );

                  if (result['success'] == true && eventType == 'hearing') {
                    final daysUntil = eventDateTime
                        .difference(DateTime.now())
                        .inDays;
                    if (daysUntil >= 2) {
                      final notificationDate = eventDateTime.subtract(
                        const Duration(days: 2),
                      );
                      final notificationDateStr = DateFormat(
                        'EEEE, MMMM dd, yyyy',
                      ).format(notificationDate);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Hearing scheduled! Notification will be sent on $notificationDateStr (2 days before)',
                          ),
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  }

                  if (result['success'] == true) {
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Event created successfully'),
                        ),
                      );
                      _loadCalendarEvents();
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result['message'] ?? 'Failed to create event',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddEventDialog() async {
    await _showAddEventDialogForDate(DateTime.now());
  }

  Future<List<Map<String, dynamic>>> _loadClientsWithDetails(
    String? attorneyId,
  ) async {
    if (attorneyId == null) return [];

    try {
      final casesSnapshot = await _firestore
          .collection('cases')
          .where('attorneyId', isEqualTo: attorneyId)
          .get();

      final clientIds = <String>{};
      for (var doc in casesSnapshot.docs) {
        final data = doc.data();
        final clientId = data['clientId'] as String?;
        if (clientId != null && clientId.trim().isNotEmpty) {
          clientIds.add(clientId);
        }
      }

      if (clientIds.isEmpty) return [];

      final clients = <Map<String, dynamic>>[];
      for (var clientId in clientIds) {
        if (clientId.trim().isEmpty) continue;
        try {
          final clientDoc = await _firestore
              .collection('users')
              .doc(clientId)
              .get();
          if (clientDoc.exists) {
            final clientData = clientDoc.data()!;
            final clientName =
                clientData['name'] ?? clientData['fullName'] ?? 'Client';
            clients.add({'id': clientId, 'name': clientName});
          }
        } catch (e) {
          print('Error loading client $clientId: $e');
        }
      }

      clients.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String),
      );

      return clients;
    } catch (e) {
      print('Error loading clients: $e');
      return [];
    }
  }
}
