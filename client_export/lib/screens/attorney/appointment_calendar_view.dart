import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/appointment_model.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../services/auth_service.dart';
import '../../services/hearing_calendar_fields.dart';
import '../../services/hearing_calendar_sync_service.dart';
import '../../services/staff_service.dart';
import '../../widgets/common/hearing_calendar_event_body.dart';
import '../../widgets/common/hearing_notification_detail_panel.dart';

import 'appointment_scheduler_form.dart';

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
    final caseNo = (hearingEvent!['caseNo'] as String?)?.trim();
    if (caseNo != null && caseNo.isNotEmpty) return caseNo;
    final client = (hearingEvent!['clientName'] as String?)?.trim();
    if (client != null && client.isNotEmpty) return client;
    final caseTitle = (hearingEvent!['caseTitle'] as String?)?.trim();
    if (caseTitle != null && caseTitle.isNotEmpty) return caseTitle;
    final t = hearingEvent!['title'];
    if (t is String && t.trim().isNotEmpty) {
      return t.trim().replaceFirst(RegExp(r'^\[AI\]\s*'), '');
    }
    return 'Hearing';
  }

  /// Short label for month grid cells (client name first).
  String calendarCellLabel() {
    if (appointment != null) return '';
    final client = (hearingEvent!['clientName'] as String?)?.trim();
    if (client != null && client.isNotEmpty) return client;
    final caseNo = (hearingEvent!['caseNo'] as String?)?.trim();
    if (caseNo != null && caseNo.isNotEmpty) return caseNo;
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

  const AppointmentCalendarView({
    super.key,
    this.initialAppointments,
    this.sharedAppointmentsStream,
    this.embedded = false,
  });

  @override
  State<AppointmentCalendarView> createState() =>
      _AppointmentCalendarViewState();
}

class _AppointmentCalendarViewState extends State<AppointmentCalendarView> {
  final EnhancedAppointmentService _appointmentService =
      EnhancedAppointmentService();
  final AuthService _authService = AuthService();
  final StaffService _staffService = StaffService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DateTime _viewDate = DateTime.now();
  String _viewMode = 'month'; // 'month' or 'week'
  List<AppointmentModel> _appointments = [];

  /// Hearings/deadlines/meetings from `calendar_events` (manual + AI-synced hearings).
  List<Map<String, dynamic>> _calendarEvents = [];

  /// Live projection from `hearings` (ensures marks show even if sync write lags).
  List<Map<String, dynamic>> _hearingOverlay = [];
  StreamSubscription<List<Map<String, dynamic>>>? _calendarEventsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _hearingOverlaySub;
  StreamSubscription<List<AppointmentModel>>? _appointmentsSub;
  String? _attachedAttorneyId;
  bool _ownsAppointmentsStream = false;
  Timer? _syncAttachTimer;

  final Map<String, String> _clientNameCache =
      <String, String>{}; // Cache for client full names
  final Map<String, String> _clientEmailCache =
      <String, String>{}; // Cache for client emails
  bool _didAutoFocusHearingMonth = false;

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
    _bindAppointments();
    _subscribeCalendarEvents();

    final user = _authService.currentUser;
    if (user != null) {
      _attachedAttorneyId = user.uid;
      _subscribeHearingOverlay();
      unawaited(_loadHearingsFromFirestoreFallback(user.uid));
      _syncAttachTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        HearingCalendarSyncService.instance.attachForAttorney(user.uid);
      });
    }
  }

  @override
  void didUpdateWidget(AppointmentCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sharedAppointmentsStream != widget.sharedAppointmentsStream ||
        oldWidget.initialAppointments != widget.initialAppointments) {
      final seed = widget.initialAppointments;
      if (seed != null && seed.isNotEmpty) {
        _appointments = List<AppointmentModel>.from(seed);
      }
      _bindAppointments();
    }
  }

  /// One-shot load so calendar cells populate even if the live overlay stream errors.
  Future<void> _loadHearingsFromFirestoreFallback(String attorneyId) async {
    try {
      final casesSnap = await _firestore
          .collection('cases')
          .where('attorneyId', isEqualTo: attorneyId)
          .get();
      final caseMaps = casesSnap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();

      final hearingsSnap =
          await _firestore.collection('hearings').limit(500).get();
      final rows = HearingCalendarSyncService.instance.projectHearingsFromDocs(
        attorneyId,
        caseMaps,
        hearingsSnap.docs,
      );
      if (!mounted || rows.isEmpty) return;
      setState(() {
        _hearingOverlay = rows;
        _maybeFocusFirstHearingMonth(rows);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _syncAttachTimer?.cancel();
    _calendarEventsSub?.cancel();
    _hearingOverlaySub?.cancel();
    if (_ownsAppointmentsStream) {
      _appointmentsSub?.cancel();
    }
    final aid = _attachedAttorneyId;
    if (aid != null) {
      HearingCalendarSyncService.instance.detachForAttorney(aid);
    }
    super.dispose();
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
    final user = _authService.currentUser;
    if (user == null) return;
    _calendarEventsSub?.cancel();
    _calendarEventsSub = _staffService.getCalendarEvents(user.uid).listen((
      events,
    ) {
      if (mounted) {
        setState(
          () => _calendarEvents = _mergeCalendarEventsFromServer(events),
        );
      }
    });
  }

  void _subscribeHearingOverlay() {
    final user = _authService.currentUser;
    if (user == null) return;
    _hearingOverlaySub?.cancel();
    _hearingOverlaySub = HearingCalendarSyncService.instance
        .watchHearingEntriesForAttorney(user.uid)
        .listen(
      (rows) {
        if (mounted) {
          setState(() {
            _hearingOverlay = rows;
            _maybeFocusFirstHearingMonth(rows);
          });
        }
      },
      onError: (_) {},
    );
  }

  /// Months with Firestore `hearings` not shown in the current calendar view.
  List<DateTime> _hearingMonthsOutsideView() {
    final seen = <String>{};
    final out = <DateTime>[];
    for (final ev in _hearingOverlay) {
      final d = _dateTimeFromField(ev['eventDate']);
      if (d == null) continue;
      if (d.year == _viewDate.year && d.month == _viewDate.month) continue;
      final key = '${d.year}-${d.month}';
      if (seen.add(key)) {
        out.add(DateTime(d.year, d.month));
      }
    }
    out.sort((a, b) {
      final c = a.year.compareTo(b.year);
      return c != 0 ? c : a.month.compareTo(b.month);
    });
    return out;
  }

  Widget _buildHearingsOutsideMonthBanner() {
    final months = _hearingMonthsOutsideView();
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
                  setState(() {
                    _viewDate = DateTime(m.year, m.month);
                  });
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

  /// If Firestore hearings are in another month (e.g. April), open that month once.
  void _maybeFocusFirstHearingMonth(List<Map<String, dynamic>> rows) {
    if (_didAutoFocusHearingMonth || rows.isEmpty) return;
    final dates = <DateTime>[];
    for (final row in rows) {
      final d = _dateTimeFromField(row['eventDate']);
      if (d != null) dates.add(d);
    }
    if (dates.isEmpty) return;
    dates.sort();
    final hasInViewMonth = dates.any(
      (d) => d.year == _viewDate.year && d.month == _viewDate.month,
    );
    if (hasInViewMonth) return;
    _didAutoFocusHearingMonth = true;
    final first = dates.first;
    _viewDate = DateTime(first.year, first.month);
  }

  AppointmentModel? _appointmentFromCalendarEvent(Map<String, dynamic> ev) {
    var id = (ev['appointmentId'] as String?)?.trim() ?? '';
    if (id.isEmpty) {
      final docId = (ev['id'] as String?)?.trim() ?? '';
      if (docId.startsWith('appt_')) {
        id = docId.substring(5);
      }
    }
    if (id.isEmpty) return null;

    final eventDate = _dateTimeFromField(ev['eventDate']);
    if (eventDate == null) return null;

    return AppointmentModel(
      id: id,
      clientId: (ev['clientId'] as String?) ?? '',
      clientName: (ev['clientName'] as String?) ?? 'Client',
      attorneyId: ev['assignedTo'] as String?,
      caseId: ev['caseId'] as String?,
      caseTitle: ev['caseTitle'] as String?,
      appointmentDateTime: eventDate,
      appointmentType: (ev['appointmentType'] as String?) ?? 'meeting_office',
      notes: ev['notes'] as String?,
      status: 'upcoming',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  List<_AttorneyCalendarEntry> _getEntriesForDate(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final out = <_AttorneyCalendarEntry>[];
    final syncedHearingIds = <String>{};
    final appointmentIds = <String>{};

    for (final apt in _appointments) {
      if (apt.appointmentType == 'hearing_court') {
        continue; // shown as manual calendar hearing after mirror
      }
      final aptDate = DateTime(
        apt.appointmentDateTime.year,
        apt.appointmentDateTime.month,
        apt.appointmentDateTime.day,
      );
      if (aptDate == day) {
        out.add(_AttorneyCalendarEntry.fromAppointment(apt));
        if (apt.id.isNotEmpty) appointmentIds.add(apt.id);
      }
    }

    void addHearing(Map<String, dynamic> ev) {
      final eventDate = _dateTimeFromField(ev['eventDate']);
      if (eventDate == null) return;
      final evDay = DateTime(eventDate.year, eventDate.month, eventDate.day);
      if (evDay != day) return;
      final hid = (ev['hearingDocId'] as String?)?.trim() ?? '';
      if (hid.isNotEmpty) {
        if (syncedHearingIds.contains(hid)) return;
        syncedHearingIds.add(hid);
      }
      out.add(_AttorneyCalendarEntry.fromHearing(ev));
    }

    // Overlay uses live `hearingDate` — prefer it over stale `calendar_events` rows.
    for (final ev in _hearingOverlay) {
      addHearing(ev);
    }
    for (final ev in _calendarEvents) {
      if (isFirestoreSyncedHearingCalendarRow(ev)) continue;
      if (ev['eventType'] == 'hearing') {
        final hid = (ev['hearingDocId'] as String?)?.trim() ?? '';
        if (hid.isNotEmpty) continue;
      }
      addHearing(ev);
    }

    out.sort((a, b) => a.startTime.compareTo(b.startTime));
    return out;
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
        final merged = _mergeAppointmentsFromStream(appointments);
        setState(() => _appointments = merged);
        _loadClientNames(merged);
      });
      return;
    }

    final user = _authService.currentUser;
    if (user == null) return;

    _ownsAppointmentsStream = true;
    _appointmentsSub = _appointmentService
        .getAttorneyAppointments(user.uid)
        .listen((appointments) {
      if (!mounted) return;
      final merged = _mergeAppointmentsFromStream(appointments);
      setState(() => _appointments = merged);
      _loadClientNames(merged);
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

    // Fetch client names in parallel for better performance
    final futures = uncachedClientIds.map((clientId) async {
      try {
        final clientDoc = await _firestore
            .collection('users')
            .doc(clientId)
            .get();

        if (clientDoc.exists) {
          final clientData = clientDoc.data()!;
          // Try multiple possible field names for full name
          // Priority: fullName > full_name > name
          final fullName =
              clientData['fullName'] as String? ??
              clientData['full_name'] as String? ??
              '';
          final name = clientData['name'] as String? ?? '';
          final email = clientData['email'] as String? ?? '';

          // Build display name: prefer fullName, fallback to name
          // Never use email - always get from profile
          String displayName = '';
          if (fullName.isNotEmpty && fullName.trim().isNotEmpty) {
            displayName = fullName.trim();
          } else if (name.isNotEmpty && name.trim().isNotEmpty) {
            displayName = name.trim();
          }

          // Return both name and email
          return {
            'clientId': clientId,
            'displayName': displayName.isNotEmpty && !displayName.contains('@')
                ? displayName
                : '',
            'email': email.isNotEmpty ? email : '',
          };
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Error loading client name for $clientId: $e');
        // Return empty for failed requests
      }
      return null;
    }).toList();

    // Wait for all requests to complete
    final results = await Future.wait(futures);

    // Update cache with all results at once
    if (mounted) {
      try {
        setState(() {
          final nameCache = _getClientNameCache();
          final emailCache = _getClientEmailCache();
          for (final result in results) {
            if (result != null) {
              final clientId = result['clientId'];
              if (clientId != null) {
                // Cache name if available
                final displayName = result['displayName'];
                if (displayName != null) {
                  // Only cache valid names (not emails)
                  final displayNameStr = displayName.toString();
                  if (displayNameStr.isNotEmpty &&
                      !_isEmailAddress(displayNameStr)) {
                    nameCache[clientId.toString()] = displayNameStr;
                  }
                }

                // Cache email if available
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
        });
      } catch (e) {
        if (kDebugMode) debugPrint('Error updating client caches: $e');
      }
    }
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
    unawaited(_loadClientNames([apt]));
  }

  /// Best-effort Firestore refresh after create (calendar already has [apt]).
  Future<void> _refreshAppointmentFromFirestore(AppointmentModel apt) async {
    if (apt.id.isEmpty) return;
    try {
      final doc =
          await _firestore.collection('appointments').doc(apt.id).get();
      if (!doc.exists || !mounted) return;
      _mergeAppointmentIntoState(AppointmentModel.fromFirestore(doc));
    } catch (e) {
      if (kDebugMode) debugPrint('refreshAppointmentFromFirestore: $e');
    }
  }

  Future<AppointmentModel?> _fetchLatestAppointmentForDay(DateTime day) async {
    final user = _authService.currentUser;
    if (user == null) return null;
    try {
      final snap = await _firestore
          .collection('appointments')
          .where('attorneyId', isEqualTo: user.uid)
          .get();
      AppointmentModel? best;
      for (final doc in snap.docs) {
        final apt = AppointmentModel.fromFirestore(doc);
        if (_calendarDay(apt.appointmentDateTime) != _calendarDay(day)) continue;
        if (best == null ||
            apt.createdAt.isAfter(best.createdAt)) {
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
      }
    });
  }

  /// Manual court hearings from Add Appointment also show in the day list.
  Future<void> _mirrorHearingCourtToCalendarEvent(AppointmentModel apt) async {
    final attorneyId = apt.attorneyId ?? _authService.currentUser?.uid;
    if (attorneyId == null || attorneyId.isEmpty) return;

    String? caseNo;
    if (apt.caseId != null && apt.caseId!.trim().isNotEmpty) {
      try {
        final caseSnap =
            await _firestore.collection('cases').doc(apt.caseId).get();
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
      MaterialPageRoute(
        builder: (context) => const AppointmentSchedulerForm(),
      ),
    );
    if (result == true) {
      _bindAppointments();
    }
  }

  Widget _buildCalendarBody({required bool isMobile}) {
    return Column(
      children: [
        if (widget.embedded && isMobile)
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
                      onPressed: _openNewAppointment,
                      tooltip: 'New Appointment',
                    ),
                  ],
                ),
              ),
            ),
          ),
        _buildCalendarHeader(isMobile: isMobile),
        _buildWeekdayRow(isMobile: isMobile),
        _buildHearingsOutsideMonthBanner(),
        Expanded(
          child: (isMobile || _viewMode == 'month')
              ? _buildMonthView()
              : _buildWeekView(),
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
            onPressed: _openNewAppointment,
            tooltip: 'New Appointment',
          ),
        ],
      ),
      body: calendarBody,
    );
  }

  Widget _buildCalendarHeader({required bool isMobile}) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      color: calendarBlue,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: () {
              setState(() {
                _viewDate = _viewMode == 'month' || isMobile
                    ? DateTime(_viewDate.year, _viewDate.month - 1)
                    : _viewDate.subtract(const Duration(days: 7));
              });
            },
          ),
          Flexible(
            child: Text(
              _viewMode == 'month' || isMobile
                  ? DateFormat('MMMM yyyy').format(_viewDate)
                  : 'Week of ${DateFormat('MMM dd').format(_viewDate)}',
              style: TextStyle(
                fontSize: isMobile ? 18 : 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Row(
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
                  DateFormat('yyyy').format(_viewDate),
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
                  setState(() {
                    _viewDate = _viewMode == 'month' || isMobile
                        ? DateTime(_viewDate.year, _viewDate.month + 1)
                        : _viewDate.add(const Duration(days: 7));
                  });
                },
              ),
            ],
          ),
          if (!isMobile)
            TextButton(
              onPressed: () {
                setState(() {
                  _viewDate = DateTime.now();
                });
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

  Widget _buildMonthView() {
    final firstDayOfMonth = DateTime(_viewDate.year, _viewDate.month, 1);
    final lastDayOfMonth = DateTime(_viewDate.year, _viewDate.month + 1, 0);
    final firstDayWeekday = firstDayOfMonth.weekday;
    final daysInMonth = lastDayOfMonth.day;

    // Get all days to display (including previous/next month days)
    final List<DateTime> days = [];
    // Previous month days
    for (int i = firstDayWeekday - 1; i > 0; i--) {
      days.add(firstDayOfMonth.subtract(Duration(days: i)));
    }
    // Current month days
    for (int i = 1; i <= daysInMonth; i++) {
      days.add(DateTime(_viewDate.year, _viewDate.month, i));
    }
    // Next month days to fill the grid
    final remainingDays = 42 - days.length; // 6 weeks * 7 days
    for (int i = 1; i <= remainingDays; i++) {
      days.add(DateTime(_viewDate.year, _viewDate.month + 1, i));
    }

    // Adjust cell size for web vs mobile – on web we use a more compact grid
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 200;
    final gridPadding = EdgeInsets.all(isWeb ? 8 : 16);
    final spacing = isWeb ? 4.0 : 8.0;
    // Slightly taller cells so hearing title + AI SCHD fit (reference-style grid).
    final aspectRatio = isWeb ? 0.82 : 1.05;

    return GridView.builder(
      padding: gridPadding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
      ),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final isCurrentMonth = day.month == _viewDate.month;
        final isToday =
            day.year == DateTime.now().year &&
            day.month == DateTime.now().month &&
            day.day == DateTime.now().day;
        final dayEntries = _getEntriesForDate(day);

        return _buildDayCell(day, isCurrentMonth, isToday, dayEntries);
      },
    );
  }

  Widget _buildWeekView() {
    final startOfWeek = _viewDate.subtract(
      Duration(days: _viewDate.weekday - 1),
    );
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
          // Day Header - tappable if has items
          InkWell(
            onTap: dayEntries.isNotEmpty
                ? () => _showEntriesForDate(day, dayEntries)
                : () async {
                    final created = await _createAppointmentForDate(day);
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
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Appointments + calendar events
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(4),
              itemCount: dayEntries.length,
              itemBuilder: (context, index) {
                return _buildCalendarEntrySlot(dayEntries[index]);
              },
            ),
          ),
          // Add button
          InkWell(
            onTap: () async {
              final created = await _createAppointmentForDate(day);
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

  Widget _buildDayCell(
    DateTime day,
    bool isCurrentMonth,
    bool isToday,
    List<_AttorneyCalendarEntry> entries,
  ) {
    return Container(
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
          // Date number - tappable if has items
          InkWell(
            onTap: entries.isNotEmpty
                ? () => _showEntriesForDate(day, entries)
                : () async {
                    final created = await _createAppointmentForDate(day);
                    if (created != null && mounted) {
                      await _openDayDialogAfterAppointmentAdded(
                        day,
                        created: created,
                      );
                    }
                  },
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 12,
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
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: calendarBlue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${entries.length}',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Appointments + hearings — show up to 3
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: entries.length > 3 ? 3 : entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return InkWell(
                  onTap: () => _showEntryDetails(entry),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _getEntryColor(entry),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                DateFormat('hh:mm a').format(entry.startTime),
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (entry.isAiScheduled)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: calendarGold,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  'AI',
                                  style: TextStyle(
                                    fontSize: 6,
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              )
                          ],
                        ),
                        Text(
                          entry.appointment != null
                              ? _getClientDisplayName(entry.appointment!)
                              : entry.calendarCellLabel().isNotEmpty
                                  ? entry.calendarCellLabel()
                                  : entry.hearingTitle(),
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (entries.length > 3)
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                '+${entries.length - 3} more',
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
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
                    _getClientDisplayName(apt),
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
    } else if (entry.hearingEvent != null) {
      _showHearingEventDetails(entry.hearingEvent!);
    }
  }

  /// Show all items (appointments + court/automation events) for a date
  void _showEntriesForDate(
    DateTime date,
    List<_AttorneyCalendarEntry> entries,
  ) {
    // Must live outside [StatefulBuilder]'s builder — that builder re-runs on
    // every setState and would otherwise reset the list to [entries].
    var dayEntries = List<_AttorneyCalendarEntry>.from(entries);

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Container(
          width: MediaQuery.of(dialogContext).size.width > 600
              ? 500
              : double.infinity,
          padding: const EdgeInsets.all(24),
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final apptN =
                  dayEntries.where((e) => e.appointment != null).length;
              final calN = dayEntries.length - apptN;
              final aiN = dayEntries.where((e) => e.isAiScheduled).length;

              return Column(
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
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${dayEntries.length} scheduled item${dayEntries.length != 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
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
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: dayEntries.length,
                  itemBuilder: (context, index) {
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _getClientDisplayName(apt),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getAppointmentColor(
                                          apt,
                                        ).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _getAppointmentColor(apt),
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        _getAppointmentTypeLabel(
                                          apt.appointmentType,
                                        ),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _getAppointmentColor(apt),
                                          fontWeight: FontWeight.bold,
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
                                      ).format(apt.appointmentDateTime),
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
                                            color: Colors.grey[700],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry.hearingTitle(),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (entry.isAiScheduled)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: calendarGold,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _aiSchedLabel,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
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
                                    child: Text(
                                      entry.hearingTypeLabel(),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: hearingEventColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const SizedBox(height: 8),
                              HearingCalendarEventBody(
                                data: ev,
                                dense: true,
                                maxLines: 7,
                              ),
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
                onPressed: () async {
                  final created = await _createAppointmentForDate(date);
                  if (created == null || !context.mounted) return;
                  final showDay = _calendarDay(created.appointmentDateTime);
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
                ),
              ),
            ],
          );
            },
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
        final snap =
            await _firestore.collection('hearings').doc(hearingDocId).get();
        if (snap.exists && snap.data() != null) {
          final hd = snap.data()!;
          final caseMaps = <Map<String, dynamic>>[];
          final caseId = (hd['caseId'] as String?)?.trim() ?? '';
          if (caseId.isNotEmpty) {
            final caseSnap =
                await _firestore.collection('cases').doc(caseId).get();
            if (caseSnap.exists && caseSnap.data() != null) {
              caseMaps.add({'id': caseSnap.id, ...caseSnap.data()!});
            }
          }
          final cn = (hd['caseNo'] as String?)?.trim() ?? '';
          final siblings = _hearingOverlay
              .where(
                (o) =>
                    cn.isNotEmpty &&
                    (o['caseNo'] as String?)?.trim() == cn,
              )
              .toList();
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
                  siblingRows: _hearingOverlay,
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
