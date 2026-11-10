import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kIsWeb, ValueListenable;
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../controllers/auth_controller.dart';
import '../../services/case_service.dart';
import '../../services/auth_service.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../models/case_model.dart';
import '../../models/user_model.dart';
import '../../models/appointment_model.dart';
import '../../widgets/common/case_card.dart';
import '../../widgets/case/case_status_filter_button.dart';
import '../../utils/case_status_filter.dart';
import '../../widgets/common/lazy_indexed_stack.dart';
import '../../widgets/common/nav_unread_dot.dart';
import '../../widgets/attorney/attorney_thin_nav_rail.dart';
import '../../widgets/attorney/attorney_ui_theme.dart';
import '../../widgets/attorney/attorney_top_bar.dart';
import '../../theme/app_theme.dart';
import '../case/case_detail_page.dart';
import '../chat/chat_list_page.dart';
import '../auth/login_page.dart';
import '../../screens/client/help_center_screen.dart';
import '../../help/attorney_help_catalog.dart';
import '../../screens/attorney/appointment_calendar_view.dart';
import '../../screens/billing/billing_management_screen.dart'
    show openPaymentHistoryScreen;

import '../../widgets/attorney/reminders_bell_button.dart';
import '../../pages/attorney/attorney_profile_page.dart';
import '../../services/chat_service.dart';
import '../../services/hearing_calendar_sync_service.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../../services/hearing_calendar_fields.dart';
import '../../services/staff_service.dart';
import '../../services/attorney_inbox_read_store.dart';
import '../../services/fcm_service.dart';
import '../../services/calendar_session_cleanup.dart';
import '../../screens/attorney/attorney_case_requests_screen.dart';
import '../../screens/attorney/attorney_create_case_screen.dart';
import '../../screens/attorney/attorney_client_chat_screen.dart';
import '../../screens/attorney/attorney_tasks_screen.dart';
import '../../screens/attorney/attorney_create_task_screen.dart';
import '../../widgets/attorney/upcoming_appointment_tile.dart';
import '../../widgets/attorney/attorney_modern_dashboard_view.dart';

class AttorneyDashboard extends StatefulWidget {
  const AttorneyDashboard({super.key});

  @override
  State<AttorneyDashboard> createState() => _AttorneyDashboardState();
}

class _AttorneyDashboardState extends State<AttorneyDashboard> {
  final GlobalKey<LazyIndexedStackState> _mobileTabStackKey =
      GlobalKey<LazyIndexedStackState>();
  final GlobalKey<LazyIndexedStackState> _desktopTabStackKey =
      GlobalKey<LazyIndexedStackState>();
  final CaseService _caseService = CaseService();
  final AuthService _authService = AuthService();
  final EnhancedAppointmentService _appointmentService =
      EnhancedAppointmentService();
  final ChatService _chatService = ChatService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  AuthController? _authController;

  UserModel? _currentUser;
  String _activeItem = 'dashboard';
  int _selectedBottomNavIndex = 0;
  bool _isAvailable = true;
  final TextEditingController _desktopSearchController = TextEditingController();
  final ValueNotifier<String> _headerSearchQuery = ValueNotifier('');
  final ValueNotifier<String> _casesStatusFilter =
      ValueNotifier(CaseStatusFilter.all);
  final ValueNotifier<bool> _closedCasesFolder = ValueNotifier(false);

  StreamSubscription<List<CaseModel>>? _casesSub;
  StreamSubscription<List<AppointmentModel>>? _appointmentsSub;
  StreamSubscription<int>? _unreadCountSub;
  Stream<List<AppointmentModel>>? _sharedAppointmentsStream;
  Stream<List<CaseModel>>? _sharedCasesStream;
  bool _dashboardStreamsAttached = false;
  Timer? _dashboardDebounce;
  Timer? _calendarPrewarmTimer;
  bool _hearingSyncAttached = false;
  Map<String, dynamic> _stats = {};
  List<CaseModel> _myCases = [];
  // Pending appointment requests from clients (status == 'pending')
  List<AppointmentModel> _allAppointments = [];
  List<AppointmentModel> _pendingRequests = [];
  // Upcoming confirmed/scheduled appointments
  List<AppointmentModel> _upcomingAppointments = [];
  List<Map<String, dynamic>> _liveHearingRows = [];
  StreamSubscription<List<Map<String, dynamic>>>? _liveHearingsSub;
  final Map<String, String> _upcomingClientNames = {};
  final Map<String, String> _upcomingClientEmails = {};
  int _unreadCount = 0;

  Object get _dashboardTabRevision {
    try {
      return Object.hash(
        _stats['totalCases'],
        _stats['activeCases'],
        _stats['completedCases'],
        _stats['pendingCases'],
        _stats['upcomingAppointments'],
      );
    } catch (_) {
      return 'dashboard';
    }
  }

  /// Header shows the user's name unless it is the generic placeholder "attorney".
  String? get _headerTitle {
    final name = (_currentUser?.fullName ?? _currentUser?.name ?? '').trim();
    if (name.isEmpty || name.toLowerCase() == 'attorney') {
      return null;
    }
    return name;
  }

  @override
  void initState() {
    super.initState();
    try {
      _authController = Get.find<AuthController>();
    } catch (e) {
      // AuthController not found, will use AuthService
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadUserData());
      _loadDashboardData();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;

      unawaited(AttorneyInboxReadStore.instance.ensureLoaded(uid));
      unawaited(HearingNotificationFanoutService.instance
          .refreshAttorneyBellFromNotifications(uid));
      unawaited(FCMService().initialize().catchError((_) {}));
      unawaited(FCMService().saveTokenForUser(uid).catchError((_) {}));
      if (kIsWeb) {
        Timer(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          _attachUnreadWatcher();
        });
      } else {
        Timer(const Duration(seconds: 6), () {
          if (!mounted) return;
          _attachUnreadWatcher();
        });
      }
    });
  }

  /// Schedules a late calendar_events backfill. Display uses live hearings.
  void _ensureHearingCalendarSync() {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid.trim();
    if (uid == null || uid.isEmpty || _hearingSyncAttached) return;
    _hearingSyncAttached = true;
    HearingCalendarSyncService.instance.attachForAttorney(uid);
  }

  @override
  void dispose() {
    _desktopSearchController.dispose();
    _headerSearchQuery.dispose();
    _casesStatusFilter.dispose();
    _closedCasesFolder.dispose();
    _casesSub?.cancel();
    _appointmentsSub?.cancel();
    _liveHearingsSub?.cancel();
    _unreadCountSub?.cancel();
    _dashboardDebounce?.cancel();
    _calendarPrewarmTimer?.cancel();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      HearingCalendarSyncService.instance.detachForAttorney(uid);
    }
    CalendarSessionCleanup.onLogout();
    super.dispose();
  }

  /// Every mobile tab: scrollable immediately (even while loading / empty).
  Widget _mobileTabShell({required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildAttorneyTopBar({EdgeInsetsGeometry? padding}) {
    return AttorneyTopBar(
      notification: _buildRemindersBellIcon(lightSurface: true),
      padding: padding ?? const EdgeInsets.fromLTRB(24, 20, 24, 8),
      findHits: _headerSearchHits,
      onQueryChanged: (query) => _headerSearchQuery.value = query.trim(),
      onSubmitted: _onHeaderSearchSubmitted,
    );
  }

  String _safeText(Object? value) {
    if (value == null) return '';
    final text = '$value';
    if (text == 'null' || text == 'undefined') return '';
    return text;
  }

  List<AttorneySearchHit> _headerSearchHits(String raw) {
    try {
      final q = _safeText(raw).trim().toLowerCase();
      if (q.isEmpty) return const [];

      final hits = <AttorneySearchHit>[];

      for (final c in _myCases) {
        final title = _safeText(c.caseTitle);
        final type = _safeText(c.caseType);
        final description = _safeText(c.caseDescription);
        final hay = '$title $type $description'.toLowerCase();
        if (!hay.contains(q) && !caseTitleMatchesSearch(c, raw)) continue;
        hits.add(
          AttorneySearchHit(
            title: title,
            subtitle: 'Case · $type',
            icon: Icons.folder_outlined,
            onTap: () {
              Get.to(() => CaseDetailPage(caseId: c.id));
            },
          ),
        );
        if (hits.length >= 8) return hits;
      }

      for (final a in _allAppointments) {
        final clientName = _safeText(a.clientName);
        final caseTitle = _safeText(a.caseTitle);
        final notes = _safeText(a.notes);
        final status = _safeText(a.status).toLowerCase();
        final hay = '$clientName $caseTitle $notes $status';
        if (!hay.contains(q)) continue;
        final pending = status == 'pending';
        hits.add(
          AttorneySearchHit(
            title: clientName.isNotEmpty ? clientName : 'Appointment',
            subtitle: pending
                ? 'Pending appointment'
                : DateFormat('MMM d, y · h:mm a').format(a.appointmentDateTime),
            icon: pending ? Icons.pending_outlined : Icons.event_outlined,
            onTap: () => _handleItemSelected(pending ? 'pending' : 'calendar'),
          ),
        );
        if (hits.length >= 8) return hits;
      }

      return hits;
    } catch (_) {
      return const [];
    }
  }

  void _onHeaderSearchSubmitted(String query) {
    _headerSearchQuery.value = query.trim();
    if (query.trim().isEmpty) return;
    final hasCase = _myCases.any((c) => caseTitleMatchesSearch(c, query));
    final hasClosed = _myCases.any(
      (c) =>
          CaseStatusFilter.isCompleted(c.status) &&
          caseTitleMatchesSearch(c, query),
    );
    if (hasClosed && !hasCase) {
      _handleItemSelected('closed_cases');
      return;
    }
    _handleItemSelected(hasCase ? 'cases' : 'calendar');
  }

  Widget _buildRemindersBellIcon({bool lightSurface = false}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Icon(
        Icons.notifications_active,
        color: lightSurface
            ? AttorneyUi.primary
            : Colors.white.withValues(alpha: 0.8),
      );
    }

    return RemindersBellButton(
      key: ValueKey<String>('attorney_bell_${user.uid}'),
      userId: user.uid,
      lightSurface: lightSurface,
    );
  }

  void _attachUnreadWatcher() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _unreadCountSub?.cancel();
    _unreadCountSub = _chatService.watchUnreadCount(uid).listen(
      _applyUnreadCount,
      onError: (_) {},
    );
  }

  Future<void> _loadUnreadCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final count = await _chatService.getUnreadCount(user.uid);
      _applyUnreadCount(count);
    } catch (_) {}
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      DocumentSnapshot<Map<String, dynamic>> userDoc;
      try {
        userDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(milliseconds: 800));
        if (!userDoc.exists) {
          userDoc = await _firestore
              .collection('users')
              .doc(user.uid)
              .get()
              .timeout(const Duration(seconds: 1));
        }
      } catch (_) {
        return;
      }
      if (userDoc.exists && mounted) {
        final userData = userDoc.data()!;
        setState(() {
          _currentUser = UserModel.fromFirestore(userData, user.uid);
          _isAvailable = _currentUser?.isAvailable ?? true;
        });
      }
    } catch (_) {
      // Non-critical; avoid console noise on tab switches.
    }
  }

  Future<void> _loadDashboardData() async {
    if (_dashboardStreamsAttached) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    _dashboardStreamsAttached = true;
    _attachDashboardStreams(user.uid);
  }

  void _attachDashboardStreams(String uid) {
    try {
      final casesStream = _sharedCasesStream ??=
          _caseService.getCasesForUser(uid, 'attorney');
      _sharedAppointmentsStream ??= _appointmentService.getAttorneyAppointments(
        uid,
      );
      final appointmentsStream = _sharedAppointmentsStream!;

      unawaited(_casesSub?.cancel());
      _casesSub = casesStream.listen(
        (cases) {
          if (!mounted) return;
          _myCases = cases;
          _stats = _computeStats();
          _scheduleDashboardRebuild();
        },
        onError: (_) {},
      );

      unawaited(_appointmentsSub?.cancel());
      _appointmentsSub = appointmentsStream.listen(
        (appointments) {
          if (!mounted) return;
          try {
            _allAppointments = appointments;
            _pendingRequests = appointments
                .where((apt) => apt.status.toLowerCase() == 'pending')
                .toList();
            _upcomingAppointments = _selectUpcomingAppointments(appointments);
            _stats = _computeStats();
          } catch (_) {
            _allAppointments = appointments;
            _upcomingAppointments = const [];
            _pendingRequests = const [];
            _stats = _computeStats();
          }
          _scheduleDashboardRebuild();
        },
        onError: (_) {},
      );

      _subscribeLiveHearingsForDashboard(uid);
    } catch (_) {
      // Streams will retry via Firestore; keep UI responsive.
    }
  }

  void _subscribeLiveHearingsForDashboard(String uid) {
    final aid = HearingCalendarSyncService.overlayKey(uid);
    final cached = HearingCalendarSyncService.instance.peekHearingNavRows(aid);
    if (cached != null && cached.isNotEmpty) {
      _liveHearingRows = List<Map<String, dynamic>>.from(cached);
      _upcomingAppointments = _selectUpcomingAppointments(_allAppointments);
    }
    _liveHearingsSub?.cancel();
    _liveHearingsSub = StaffService().watchLiveHearingsForGrid(aid).listen(
      (rows) {
        if (!mounted) return;
        _liveHearingRows = rows;
        _upcomingAppointments = _selectUpcomingAppointments(_allAppointments);
        _stats = _computeStats();
        _scheduleDashboardRebuild();
      },
      onError: (_) {},
    );
  }

  /// One accepted/scheduled booking per date+time. Pending requests and
  /// leftover request rows never appear here.
  List<AppointmentModel> _selectUpcomingAppointments(
    List<AppointmentModel>? appointments,
  ) {
    try {
      final source = appointments ?? const <AppointmentModel>[];
      final now = DateTime.now();
      final convertedRequestIds = <String>{};
      for (final apt in source) {
        final requestId = apt.requestId?.trim() ?? '';
        if (requestId.isNotEmpty) convertedRequestIds.add(requestId);
      }

      final visible = <AppointmentModel>[];
      for (final apt in source) {
        final status = apt.status.toLowerCase().trim();
        if (status == 'pending' ||
            status == 'declined' ||
            status == 'cancelled' ||
            status == 'accepted' ||
            status == 'completed') {
          continue;
        }
        final occupies = status == 'upcoming' ||
            status == 'confirmed' ||
            status == 'scheduled' ||
            status == 'rescheduled';
        if (!occupies) continue;
        if (!apt.appointmentDateTime.isAfter(now)) continue;
        if (convertedRequestIds.contains(apt.id)) continue;
        visible.add(apt);
      }

      for (final h in _liveHearingRows) {
        final dt = h['eventDate'];
        DateTime? when;
        if (dt is DateTime) {
          when = dt;
        } else if (dt is Timestamp) {
          when = dt.toDate();
        }
        if (when == null || !when.isAfter(now)) continue;

        final hid = HearingCalendarFields.asDisplayString(h['hearingDocId']).isNotEmpty
            ? HearingCalendarFields.asDisplayString(h['hearingDocId'])
            : HearingCalendarFields.asDisplayString(h['id']);
        final caseNo = HearingCalendarFields.asDisplayString(h['caseNo']);
        final clientName = HearingCalendarFields.asDisplayString(h['clientName']);
        final caseTitle = HearingCalendarFields.asDisplayString(h['caseTitle']);
        final title = HearingCalendarFields.asDisplayString(h['title']);
        final courtBranch = HearingCalendarFields.asDisplayString(h['courtBranch']);
        final location = HearingCalendarFields.asDisplayString(h['location']);
        final venue = courtBranch.isNotEmpty ? courtBranch : location;

        String displayName = clientName;
        if (displayName.isEmpty) {
          if (caseNo.isNotEmpty && !HearingCalendarFields.isPlaceholderCaseNo(caseNo)) {
            displayName = caseNo;
          } else if (caseTitle.isNotEmpty) {
            displayName = caseTitle;
          } else {
            displayName = title.isNotEmpty ? title : 'Court Hearing';
          }
        }

        visible.add(
          AppointmentModel(
            id: hid.isNotEmpty ? 'hearing_$hid' : 'hearing_${h.hashCode}',
            clientId: HearingCalendarFields.asDisplayString(h['clientId']),
            clientName: displayName,
            caseId: HearingCalendarFields.asDisplayString(h['caseId']),
            caseTitle: caseTitle.isNotEmpty
                ? caseTitle
                : (caseNo.isNotEmpty ? caseNo : (title.isNotEmpty ? title : 'Court Hearing')),
            appointmentDateTime: when,
            appointmentType: 'hearing_court',
            notes: venue.isNotEmpty ? 'Location: $venue' : null,
            status: 'confirmed',
            createdAt: h['createdAt'] is DateTime
                ? h['createdAt'] as DateTime
                : (h['createdAt'] is Timestamp
                    ? (h['createdAt'] as Timestamp).toDate()
                    : when),
            updatedAt: h['updatedAt'] is DateTime
                ? h['updatedAt'] as DateTime
                : (h['updatedAt'] is Timestamp
                    ? (h['updatedAt'] as Timestamp).toDate()
                    : when),
          ),
        );
      }

      visible.sort((a, b) {
        final rank = _upcomingKeepRank(b) - _upcomingKeepRank(a);
        if (rank != 0) return rank;
        final dateCmp = a.appointmentDateTime.compareTo(b.appointmentDateTime);
        if (dateCmp != 0) return dateCmp;
        final aCreated = a.updatedAt ?? a.createdAt;
        final bCreated = b.updatedAt ?? b.createdAt;
        return bCreated.compareTo(aCreated);
      });

      // Deduplicate identical bookings without dropping distinct cases/hearings.
      final byMinute = <String, AppointmentModel>{};
      for (final apt in visible) {
        final t = apt.appointmentDateTime;
        final cid = apt.caseId?.trim() ?? '';
        final ctitle = apt.caseTitle?.trim() ?? '';
        final caseKey = cid.isNotEmpty ? cid : (ctitle.isNotEmpty ? ctitle : apt.id);
        final key = '${t.year}-${t.month}-${t.day}-${t.hour}-${t.minute}_$caseKey';
        byMinute.putIfAbsent(key, () => apt);
      }

      final upcoming = byMinute.values.toList()
        ..sort((a, b) {
          final dateCmp = a.appointmentDateTime.compareTo(b.appointmentDateTime);
          if (dateCmp != 0) return dateCmp;
          final aCreated = a.updatedAt ?? a.createdAt;
          final bCreated = b.updatedAt ?? b.createdAt;
          return bCreated.compareTo(aCreated);
        });
      return upcoming.take(5).toList();
    } catch (_) {
      return const <AppointmentModel>[];
    }
  }

  int _upcomingKeepRank(AppointmentModel apt) {
    switch (apt.status.toLowerCase().trim()) {
      case 'confirmed':
        return 4;
      case 'scheduled':
        return 3;
      case 'upcoming':
        return 2;
      case 'rescheduled':
        return 1;
      default:
        return 0;
    }
  }

  bool _looksLikeEmail(String? value) {
    final text = (value ?? '').trim();
    return text.contains('@') && text.contains('.');
  }

  bool _isGenericClientLabel(String? value) {
    final text = (value ?? '').trim().toLowerCase();
    return text.isEmpty ||
        text == 'client' ||
        text == 'user' ||
        text == 'someone';
  }

  String _upcomingClientName(AppointmentModel apt) {
    try {
      final id = apt.clientId.trim();
      final emailKey = _looksLikeEmail(apt.clientName)
          ? apt.clientName.trim().toLowerCase()
          : (_upcomingClientEmails[id] ?? '').toLowerCase();
      final cached = _upcomingClientNames[id] ??
          (emailKey.isNotEmpty ? _upcomingClientNames[emailKey] : null) ??
          '';
      if (cached.isNotEmpty &&
          !_looksLikeEmail(cached) &&
          !_isGenericClientLabel(cached)) {
        return cached;
      }
      final stored = apt.clientName.trim();
      if (stored.isNotEmpty &&
          !_looksLikeEmail(stored) &&
          !_isGenericClientLabel(stored)) {
        return stored;
      }
      return '';
    } catch (_) {
      final stored = apt.clientName.trim();
      if (stored.isNotEmpty &&
          !_looksLikeEmail(stored) &&
          !_isGenericClientLabel(stored)) {
        return stored;
      }
      return '';
    }
  }

  String _upcomingClientEmail(AppointmentModel apt) {
    try {
      final cached = _upcomingClientEmails[apt.clientId.trim()] ?? '';
      if (cached.isNotEmpty) return cached;
      final stored = apt.clientName.trim();
      if (_looksLikeEmail(stored)) return stored;
      return '';
    } catch (_) {
      final stored = apt.clientName.trim();
      return _looksLikeEmail(stored) ? stored : '';
    }
  }

  String _displayNameFromUserData(Map<String, dynamic> data) {
    final resolved = UserModel.resolveDisplayName(data).trim();
    if (resolved.isNotEmpty &&
        !_looksLikeEmail(resolved) &&
        !_isGenericClientLabel(resolved)) {
      return resolved;
    }
    return '';
  }

  Future<Map<String, String>?> _loadClientProfile({
    required String clientId,
    String? emailHint,
  }) async {
    Map<String, dynamic>? data;
    if (clientId.isNotEmpty) {
      final doc = await _firestore.collection('users').doc(clientId).get();
      if (doc.exists) data = doc.data();
    }
    if (data == null && emailHint != null && _looksLikeEmail(emailHint)) {
      final snap = await _firestore
          .collection('users')
          .where('email', isEqualTo: emailHint.trim())
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) data = snap.docs.first.data();
    }
    if (data == null) return null;
    return {
      'name': _displayNameFromUserData(data),
      'email': (data['email'] as String?)?.trim() ?? '',
    };
  }

  Future<void> _hydrateUpcomingClientProfiles(
    List<AppointmentModel>? appointments,
  ) async {
    final source = appointments ?? const <AppointmentModel>[];
    if (source.isEmpty) return;

    var changed = false;
    for (final apt in source) {
      try {
        final clientId = apt.clientId.trim();
        final emailHint = _looksLikeEmail(apt.clientName)
            ? apt.clientName.trim()
            : (_upcomingClientEmails[clientId] ?? '');
        final existingName = clientId.isEmpty
            ? ''
            : (_upcomingClientNames[clientId] ?? '');
        if (existingName.isNotEmpty &&
            !_looksLikeEmail(existingName) &&
            !_isGenericClientLabel(existingName) &&
            (clientId.isEmpty || _upcomingClientEmails.containsKey(clientId))) {
          continue;
        }

        final profile = await _loadClientProfile(
          clientId: clientId,
          emailHint: emailHint.isNotEmpty ? emailHint : null,
        );
        if (profile == null) continue;
        final cacheKey = clientId.isNotEmpty ? clientId : (profile['email'] ?? '');
        if (cacheKey.isEmpty) continue;

        final name = profile['name'] ?? '';
        final email = profile['email'] ?? '';
        void store(String key, String field, Map<String, String> cache) {
          if (key.isEmpty || field.isEmpty) return;
          cache[key] = field;
          cache[key.toLowerCase()] = field;
        }

        if (name.isNotEmpty) {
          store(cacheKey, name, _upcomingClientNames);
          store(clientId, name, _upcomingClientNames);
          store(email, name, _upcomingClientNames);
          changed = true;
        }
        if (email.isNotEmpty) {
          store(cacheKey, email, _upcomingClientEmails);
          store(clientId, email, _upcomingClientEmails);
          changed = true;
        }
      } catch (_) {}
    }
    if (changed && mounted) {
      _scheduleDashboardRebuild();
    }
  }

  void _scheduleDashboardRebuild() {
    _dashboardDebounce?.cancel();
    _dashboardDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      try {
        _upcomingAppointments = _selectUpcomingAppointments(_allAppointments);
        _stats = _computeStats();
      } catch (_) {}
      setState(() {});
    });
  }

  void _applyUnreadCount(int count) {
    if (!mounted || _unreadCount == count) return;
    setState(() => _unreadCount = count);
  }

  Map<String, dynamic> _computeStats() {
    try {
      final totalCases = _myCases.length;
      final activeCases = _myCases
          .where((c) => !CaseStatusFilter.isCompleted(c.status))
          .length;
      final completedCases = _myCases
          .where((c) => CaseStatusFilter.isCompleted(c.status))
          .length;
      return {
        'totalCases': totalCases,
        'activeCases': activeCases,
        'completedCases': completedCases,
        'pendingCases': _pendingRequests.length,
        'upcomingAppointments': _upcomingAppointments.length,
      };
    } catch (_) {
      return {
        'totalCases': 0,
        'activeCases': 0,
        'completedCases': 0,
        'pendingCases': 0,
        'upcomingAppointments': 0,
      };
    }
  }

  Future<void> _toggleAvailability() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final newAvailability = !_isAvailable;

    // If turning OFF (going offline), automatically log out
    if (!newAvailability) {
      // Show confirmation dialog before logging out
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Go Offline?',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Going offline will automatically log you out. Are you sure?',
            style: TextStyle(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Go Offline & Logout',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

      if (confirm != true) {
        // User cancelled, don't change availability
        return;
      }

      // Update availability to false and then logout
      try {
        await _firestore.collection('users').doc(user.uid).update({
          'isAvailable': false,
        });
      } catch (e) {
        // Even if update fails, proceed with logout
        if (kDebugMode) debugPrint('Failed to update availability: $e');
      }

      // Automatically log out
      await _handleLogout();
      return;
    }

    // If turning ON (going online), just update availability
    try {
      await _firestore.collection('users').doc(user.uid).update({
        'isAvailable': newAvailability,
      });
      if (mounted) {
        setState(() => _isAvailable = newAvailability);
        Get.snackbar(
          'Success',
          'You are now available',
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to update availability: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  void _openHelpCenter() {
    Get.to(
      () => const HelpCenterScreen(
        articles: attorneyHelpArticles,
        intro:
            'Answers come from the attorney guide: cases, appointments, tasks, billing, and messages.',
        hint: 'Example: How do I accept an appointment?',
      ),
    );
  }

  Future<void> _handleLogout() async {
    try {
      if (_authController != null) {
        await _authController!.logout();
      } else {
        await _authService.logout();
      }
      Get.offAll(() => const LoginPage());
    } catch (e) {
      Get.offAll(() => const LoginPage());
    }
  }

  void _handleItemSelected(String item, {String? caseFilter}) {
    if (item == 'cases') {
      _closedCasesFolder.value = false;
      _casesStatusFilter.value = caseFilter ?? CaseStatusFilter.all;
    } else if (item == 'closed_cases') {
      _closedCasesFolder.value = true;
      _casesStatusFilter.value = CaseStatusFilter.completed;
    }
    switch (item) {
      case 'create_case':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AttorneyCreateCaseScreen(),
          ),
        ).then((created) {
          if (created == true && mounted) {
            setState(() => _activeItem = 'dashboard');
            _loadDashboardData();
          }
        }).catchError((error) {
          if (mounted && kDebugMode) {
            debugPrint('Navigation error: $error');
          }
        });
        return;
      case 'messages':
        setState(() => _activeItem = 'messages');
        unawaited(_loadUnreadCount());
        return;
      case 'payment_history':
        openPaymentHistoryScreen(
          context,
          attorneyId: _currentUser?.id,
          recorderRole: 'attorney',
          recorderName:
              _currentUser?.fullName ?? _currentUser?.name ?? 'Attorney',
        );
        return;
    }

    int? bottomIndex;
    switch (item) {
      case 'cases':
        bottomIndex = 1;
        break;
      case 'closed_cases':
        bottomIndex = 1;
        break;
      case 'case_requests':
        bottomIndex = 2;
        break;
      case 'calendar':
        bottomIndex = 3;
        break;
      case 'messages':
        bottomIndex = 4;
        break;
    }

    setState(() {
      _activeItem = item;
      if (bottomIndex != null) {
        _selectedBottomNavIndex = bottomIndex;
      }
    });
    if (item == 'calendar') _ensureHearingCalendarSync();
  }

  int _desktopTabIndex() {
    switch (_activeItem) {
      case 'cases':
      case 'closed_cases':
        return 1;
      case 'case_requests':
        return 2;
      case 'tasks':
        return 3;
      case 'messages':
        return 4;
      case 'calendar':
        return 5;
      case 'settings':
        return 6;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      // Match modern light clean background
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: !isDesktop
          ? AppBar(
              automaticallyImplyLeading: false,
              title: Text(
                _headerTitle ?? '',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
              backgroundColor: const Color(0xFF07152B),
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    tooltip: 'Help Center',
                    iconSize: 20,
                    icon: const Icon(Icons.help_outline_rounded, color: Colors.white),
                    onPressed: _openHelpCenter,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: _buildRemindersBellIcon(),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 8, left: 2, right: 12),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AttorneyProfilePage(),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.60),
                          width: 1.5,
                        ),
                      ),
                      child: ClipOval(
                        child: _currentUser?.photoUrl != null &&
                                _currentUser!.photoUrl!.trim().isNotEmpty
                            ? Image.network(
                                _currentUser!.photoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              )
                            : const Icon(
                                Icons.person_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Thin Navigation Rail - Desktop only (Web optimized)
          if (isDesktop)
            AttorneyThinNavRail(
              activeItem: _activeItem,
              onItemSelected: _handleItemSelected,
              onLogout: _handleLogout,
              isAvailable: _isAvailable,
              onAvailabilityChanged: (value) => _toggleAvailability(),
              messageUnreadCount: _unreadCount,
              pendingRequestsCount: _pendingRequests.length,
            ),

          // Main Content
          Expanded(
            child: Column(
              children: [
                // Desktop Header with Search, Help, Reminders Bell & Avatar (Web)
                if (isDesktop)
                  Container(
                    height: 68,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(
                          color: Color(0xFFE2E8F0),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left: Search input field (or Page Title + Search)
                        Row(
                          children: [
                            if (_activeItem != 'dashboard' &&
                                _headerTitle != null &&
                                _headerTitle!.isNotEmpty) ...[
                              Text(
                                _headerTitle!,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 20),
                            ],
                            SizedBox(
                              width: 360,
                              height: 40,
                              child: TextField(
                                controller: _desktopSearchController,
                                onSubmitted: _onHeaderSearchSubmitted,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF0F172A),
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      'Search cases, clients, or case numbers...',
                                  hintStyle: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 19,
                                    color: Color(0xFF94A3B8),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF1F5F9),
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF1E6BFF),
                                      width: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Right: Help, Bell, User Profile
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Help Center',
                              icon: const Icon(
                                Icons.help_outline_rounded,
                                color: Color(0xFF64748B),
                                size: 22,
                              ),
                              onPressed: _openHelpCenter,
                            ),
                            const SizedBox(width: 6),
                            _buildRemindersBellIcon(lightSurface: true),
                            const SizedBox(width: 14),
                            InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AttorneyProfilePage(),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFCBD5E1),
                                    width: 1.5,
                                  ),
                                ),
                                child: ClipOval(
                                  child: _currentUser?.photoUrl != null &&
                                          _currentUser!.photoUrl!.trim().isNotEmpty
                                      ? Image.network(
                                          _currentUser!.photoUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                            Icons.person_rounded,
                                            color: Color(0xFF64748B),
                                            size: 22,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.person_rounded,
                                          color: Color(0xFF64748B),
                                          size: 22,
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                // Content Area (dashboard + views)
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ],
      ),
      // Drawer removed on mobile – navigation handled by bottom nav
      drawer: null,
      // Bottom Navigation - Mobile only (iPhone-style floating frosted glass capsule dock)
      bottomNavigationBar: !isDesktop ? _buildIphoneFloatingNavBar() : null,
    );
  }

  Widget _buildContent() {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    final attorneyId =
        _currentUser?.id ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (!isDesktop) {
      return LazyIndexedStack(
        key: _mobileTabStackKey,
        index: _selectedBottomNavIndex,
        activeTabRevision: _selectedBottomNavIndex == 0
            ? _dashboardTabRevision
            : _selectedBottomNavIndex == 1
                ? 'attorney_cases_tab_v4'
                : _selectedBottomNavIndex == 3
                    ? 'attorney_calendar_overlay_v8'
                    : 'mobile_tab_${_selectedBottomNavIndex}_$attorneyId',
        builders: [
          () => _buildDashboardView(),
          () => _buildCasesView(isMobile: true),
          () => AttorneyCaseRequestsScreen(
            embedded: true,
            attorneyId: attorneyId,
          ),
          () => AppointmentCalendarView(
            embedded: true,
            initialAppointments: _allAppointments,
            sharedAppointmentsStream: _sharedAppointmentsStream,
          ),
          () => const ChatListPage(),
        ],
      );
    }

    return LazyIndexedStack(
      key: _desktopTabStackKey,
      index: _desktopTabIndex(),
      activeTabRevision: _desktopTabIndex() == 0
          ? _dashboardTabRevision
          : _desktopTabIndex() == 1
              ? 'attorney_cases_tab_v4'
              : _desktopTabIndex() == 5
                  ? 'attorney_calendar_overlay_v8'
                  : 'desktop_tab_${_desktopTabIndex()}_$attorneyId',
      builders: [
        () => _buildDashboardView(),
        () => _buildCasesView(isMobile: false),
        () => AttorneyCaseRequestsScreen(
          embedded: true,
          attorneyId: attorneyId,
        ),
        () => AttorneyTasksScreen(
          embedded: true,
          attorneyId: attorneyId,
        ),
        () => const ChatListPage(),
        () => AppointmentCalendarView(
          embedded: true,
          initialAppointments: _allAppointments,
          sharedAppointmentsStream: _sharedAppointmentsStream,
        ),
        () => const AttorneyProfilePage(embedded: true),
      ],
    );
  }

  Widget _buildDashboardView() {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    return AttorneyModernDashboardView(
      key: const ValueKey('attorney_modern_dashboard_view'),
      stats: _stats,
      myCases: _myCases,
      allAppointments: _allAppointments,
      pendingRequests: _pendingRequests,
      upcomingAppointments: _upcomingAppointments,
      currentUser: _currentUser,
      isDesktop: isDesktop,
      onCreateCase: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AttorneyCreateCaseScreen(),
          ),
        ).then((created) {
          if (created == true && mounted) {
            setState(() {
              _activeItem = 'dashboard';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Case created successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            _loadDashboardData();
          }
        }).catchError((error) {
          if (mounted && kDebugMode) {
            debugPrint('Navigation error: $error');
          }
        });
      },
      onViewAllTasks: () {
        if (isDesktop) {
          setState(() {
            _activeItem = 'tasks';
          });
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AttorneyTasksScreen(),
            ),
          );
        }
      },
      onPaymentHistory: () => _handleItemSelected('payment_history'),
      onViewCalendar: () {
        setState(() {
          if (isDesktop) {
            _activeItem = 'calendar';
          } else {
            _selectedBottomNavIndex = 4;
            _activeItem = 'calendar';
          }
        });
        _ensureHearingCalendarSync();
      },
      onNavigate: (item, {caseFilter}) =>
          _handleItemSelected(item, caseFilter: caseFilter),
      onCaseTap: (caseModel) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CaseDetailPage(
              caseId: caseModel.id,
            ),
          ),
        );
      },
      onAppointmentTap: (apt) {
        _handleItemSelected('calendar');
      },
    );
  }

  List<Widget> _dashboardBody({required bool isDesktop}) {
    return [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              onTap: () {
                Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const AttorneyCreateCaseScreen(),
                      ),
                    )
                    .then((created) {
                      if (created == true && mounted) {
                        setState(() {
                          _activeItem = 'dashboard';
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Case created successfully!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        _loadDashboardData();
                      }
                    })
                    .catchError((error) {
                      if (mounted) {
                        if (kDebugMode) {
                          debugPrint('Navigation error: $error');
                        }
                      }
                    });
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.add_circle_outline,
                        color: Colors.grey[700],
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Create Case',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Create a new case for a client',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey[400],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Quick Actions Section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick Actions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1C1C1C),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AttorneyCreateTaskScreen(),
                          ),
                        );
                        if (result == true && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Task created successfully!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.add_task, size: 20),
                      label: const Text('Create Task'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.royalBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final isDesktop =
                            MediaQuery.of(context).size.width >= 800;
                        if (isDesktop) {
                          // Desktop: Switch view within the same screen
                          setState(() {
                            _activeItem = 'tasks';
                          });
                        } else {
                          // Mobile: Navigate to tasks screen
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AttorneyTasksScreen(),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.task_outlined, size: 20),
                      label: const Text('View All Tasks'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.royalBlue,
                        side: const BorderSide(color: AppTheme.royalBlue),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Bottom section: upcoming appointments
          _buildUpcomingAppointmentsSection(),
    ];
  }

  Widget _buildUpcomingAppointmentsSection() {
    final upcoming = _selectUpcomingAppointments(_allAppointments);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FF),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                color: AppTheme.royalBlue,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Upcoming Appointments',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1C1C1C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (upcoming.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No upcoming appointments',
                style: TextStyle(fontSize: 14, color: const Color(0xFF6D6D6D)),
              ),
            )
          else
            ...upcoming.take(5).map(
              (appointment) => UpcomingAppointmentTile(
                key: ValueKey('upcoming_${appointment.id}'),
                appointment: appointment,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCasesView({required bool isMobile}) {
    final uid =
        _currentUser?.id ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return _AttorneyCasesTab(
      key: const ValueKey('attorney_cases_tab_v4'),
      attorneyId: uid,
      isMobile: isMobile,
      fallbackCases: _myCases,
      caseService: _caseService,
      mobileTabShell: _mobileTabShell,
      headerSearch: _headerSearchQuery,
      statusFilter: _casesStatusFilter,
      closedFolder: _closedCasesFolder,
    );
  }


  String _activeItemForBottomNavIndex(int index) {
    switch (index) {
      case 1:
        return 'cases';
      case 2:
        return 'case_requests';
      case 3:
        return 'calendar';
      case 4:
        return 'messages';
      default:
        return 'dashboard';
    }
  }

  Widget _buildIphoneFloatingNavBar() {
    final navItems = [
      (
        icon: Icons.grid_view_rounded,
        unselectedIcon: Icons.grid_view_outlined,
        label: 'Dashboard',
        badge: 0,
      ),
      (
        icon: Icons.folder_rounded,
        unselectedIcon: Icons.folder_outlined,
        label: 'Cases',
        badge: 0,
      ),
      (
        icon: Icons.move_to_inbox_rounded,
        unselectedIcon: Icons.inbox_outlined,
        label: 'Requests',
        badge: 0,
      ),
      (
        icon: Icons.calendar_month_rounded,
        unselectedIcon: Icons.calendar_today_outlined,
        label: 'Calendar',
        badge: 0,
      ),
      (
        icon: Icons.chat_bubble_rounded,
        unselectedIcon: Icons.chat_bubble_outline_rounded,
        label: 'Messages',
        badge: _unreadCount,
      ),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 66,
              decoration: BoxDecoration(
                color: const Color(0xFF07152B).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF07152B).withValues(alpha: 0.50),
                    blurRadius: 26,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Row(
                children: List.generate(navItems.length, (index) {
                  final item = navItems[index];
                  final isSelected = _selectedBottomNavIndex == index;

                  return Expanded(
                    child: _AttorneyIphoneNavButton(
                      isSelected: isSelected,
                      icon: item.icon,
                      unselectedIcon: item.unselectedIcon,
                      label: item.label,
                      badge: item.badge,
                      onTap: () {
                        if (_selectedBottomNavIndex == index) return;
                        setState(() {
                          _selectedBottomNavIndex = index;
                          _activeItem = _activeItemForBottomNavIndex(index);
                        });
                        if (index == 1) {
                          _closedCasesFolder.value = false;
                          _casesStatusFilter.value = CaseStatusFilter.all;
                        }
                        if (index == 3) _ensureHearingCalendarSync();
                        if (index == 4) unawaited(_loadUnreadCount());
                      },
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }


}

/// Matches case title/type against search text (supports partial + multi-word).
bool caseTitleMatchesSearch(CaseModel caseModel, String rawQuery) {
  final query = '$rawQuery'.trim().toLowerCase();
  if (query.isEmpty || query == 'null' || query == 'undefined') return true;

  String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(' vs. ', ' vs ')
      .replaceAll(' v. ', ' vs ')
      .trim();

  final haystack = normalize('${caseModel.caseTitle} ${caseModel.caseType}');
  final normalizedQuery = normalize(query);

  if (haystack.contains(normalizedQuery)) return true;

  final words = normalizedQuery.split(' ').where((w) => w.length >= 2);
  if (words.isEmpty) return haystack.contains(normalizedQuery);
  return words.every(haystack.contains);
}

/// Self-contained Cases tab — search state lives here so [LazyIndexedStack]
/// cache does not block filter updates.
class _AttorneyCasesTab extends StatefulWidget {
  const _AttorneyCasesTab({
    super.key,
    required this.attorneyId,
    required this.isMobile,
    required this.fallbackCases,
    required this.caseService,
    required this.mobileTabShell,
    required this.headerSearch,
    required this.statusFilter,
    required this.closedFolder,
  });

  final String attorneyId;
  final bool isMobile;
  final List<CaseModel> fallbackCases;
  final CaseService caseService;
  final Widget Function({required Widget child}) mobileTabShell;
  final ValueListenable<String> headerSearch;
  final ValueNotifier<String> statusFilter;
  final ValueNotifier<bool> closedFolder;

  @override
  State<_AttorneyCasesTab> createState() => _AttorneyCasesTabState();
}

class _AttorneyCasesTabState extends State<_AttorneyCasesTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = CaseStatusFilter.all;
  bool _closedFolder = false;
  late Stream<List<CaseModel>> _casesStream;

  @override
  void initState() {
    super.initState();
    _casesStream =
        widget.caseService.getCasesForUser(widget.attorneyId, 'attorney');
    widget.headerSearch.addListener(_applyHeaderSearch);
    widget.statusFilter.addListener(_applyStatusFilter);
    widget.closedFolder.addListener(_applyClosedFolder);
    _statusFilter = widget.statusFilter.value;
    _closedFolder = widget.closedFolder.value;
    final q = widget.headerSearch.value;
    _searchQuery = q;
    if (q.isNotEmpty) {
      _searchController.text = q;
    }
  }

  @override
  void didUpdateWidget(_AttorneyCasesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.headerSearch != widget.headerSearch) {
      oldWidget.headerSearch.removeListener(_applyHeaderSearch);
      widget.headerSearch.addListener(_applyHeaderSearch);
      _applyHeaderSearch();
    }
    if (oldWidget.statusFilter != widget.statusFilter) {
      oldWidget.statusFilter.removeListener(_applyStatusFilter);
      widget.statusFilter.addListener(_applyStatusFilter);
      _applyStatusFilter();
    }
    if (oldWidget.closedFolder != widget.closedFolder) {
      oldWidget.closedFolder.removeListener(_applyClosedFolder);
      widget.closedFolder.addListener(_applyClosedFolder);
      _applyClosedFolder();
    }
    if (oldWidget.attorneyId != widget.attorneyId) {
      _casesStream =
          widget.caseService.getCasesForUser(widget.attorneyId, 'attorney');
    }
  }

  void _applyHeaderSearch() {
    final q = widget.headerSearch.value;
    if (!mounted) return;
    if (q == _searchQuery && _searchController.text == q) return;
    setState(() {
      _searchQuery = q;
      if (_searchController.text != q) {
        _searchController.value = TextEditingValue(
          text: q,
          selection: TextSelection.collapsed(offset: q.length),
        );
      }
    });
  }

  void _applyStatusFilter() {
    final next = widget.statusFilter.value;
    if (!mounted) return;
    if (next == _statusFilter) return;
    setState(() => _statusFilter = next);
  }

  void _applyClosedFolder() {
    final next = widget.closedFolder.value;
    if (!mounted) return;
    if (next == _closedFolder) return;
    setState(() => _closedFolder = next);
  }

  @override
  void dispose() {
    widget.headerSearch.removeListener(_applyHeaderSearch);
    widget.statusFilter.removeListener(_applyStatusFilter);
    widget.closedFolder.removeListener(_applyClosedFolder);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  InputDecoration _searchDecoration() {
    return InputDecoration(
      hintText: _closedFolder
          ? 'Search closed cases...'
          : 'Search cases by title...',
      prefixIcon: const Icon(Icons.search),
      suffixIcon: _searchQuery.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearSearch,
              tooltip: 'Clear search',
            )
          : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      filled: true,
      fillColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CaseModel>>(
      stream: _casesStream,
      builder: (context, snapshot) {
        final cases = snapshot.data ?? List<CaseModel>.from(widget.fallbackCases);

        if (snapshot.hasError && cases.isEmpty) {
          return widget.mobileTabShell(
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red),
                    SizedBox(height: 16),
                    Text(
                      'Could not load cases',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final filter = _closedFolder
            ? CaseStatusFilter.completed
            : _statusFilter;
        final filteredCases = cases
            .where((c) => CaseStatusFilter.matches(c, filter))
            .where((c) => caseTitleMatchesSearch(c, _searchQuery))
            .toList();

        String emptyMessage() {
          if (_searchQuery.trim().isNotEmpty) {
            return 'No cases match your search';
          }
          if (_closedFolder) {
            return 'No closed cases';
          }
          if (_statusFilter != CaseStatusFilter.active &&
              _statusFilter != CaseStatusFilter.all) {
            return 'No ${CaseStatusFilter.label(_statusFilter).toLowerCase()} cases';
          }
          return 'No cases yet';
        }

        Widget filterControl({Color? iconColor}) {
          if (_closedFolder) return const SizedBox.shrink();
          return CaseStatusFilterButton(
            selected: _statusFilter,
            iconColor: iconColor ?? AppTheme.royalBlue,
            values: CaseStatusFilter.attorneyMyCaseValues,
            onSelected: (value) {
              widget.statusFilter.value = value;
              setState(() => _statusFilter = value);
            },
          );
        }

        Widget folderLink() {
          return TextButton(
            onPressed: () {
              final nextClosed = !_closedFolder;
              widget.closedFolder.value = nextClosed;
              widget.statusFilter.value = nextClosed
                  ? CaseStatusFilter.completed
                  : CaseStatusFilter.all;
              setState(() {
                _closedFolder = nextClosed;
                _statusFilter = widget.statusFilter.value;
              });
            },
            child: Text(_closedFolder ? 'Cases' : 'Closed cases'),
          );
        }

        if (widget.isMobile) {
          return Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: _searchDecoration(),
                            onChanged: _onSearchChanged,
                            textInputAction: TextInputAction.search,
                          ),
                        ),
                        folderLink(),
                        filterControl(),
                      ],
                    ),
                  ),
                  if (filteredCases.isEmpty)
                    Expanded(
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.35,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    emptyMessage(),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  if (!_closedFolder) ...[
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const AttorneyCreateCaseScreen(),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('Create New Case'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.royalBlue,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredCases.length,
                        itemBuilder: (context, index) {
                          final caseModel = filteredCases[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: CaseCard(
                              caseModel: caseModel,
                              onTap: () {
                                Get.to(
                                  () => CaseDetailPage(caseId: caseModel.id),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
              if (!_closedFolder)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.extended(
                    heroTag: 'attorney_cases_mobile_create_fab',
                    backgroundColor: AppTheme.royalBlue,
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Case'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const AttorneyCreateCaseScreen(),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: _searchDecoration(),
                      onChanged: _onSearchChanged,
                      textInputAction: TextInputAction.search,
                    ),
                  ),
                  const SizedBox(width: 8),
                  filterControl(),
                ],
              ),
            ),
            if (filteredCases.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.folder_open, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        emptyMessage(),
                        style: const TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 158,
                    ),
                    itemCount: filteredCases.length,
                    itemBuilder: (context, index) {
                      final caseModel = filteredCases[index];
                      return CaseCard(
                        caseModel: caseModel,
                        onTap: () {
                          Get.to(() => CaseDetailPage(caseId: caseModel.id));
                        },
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NavBarItem extends StatefulWidget {
  final String title;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.title,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_NavBarItem> createState() => _NavBarItemState();
}

class _NavBarItemState extends State<_NavBarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppTheme.sidebarActive
                : (_isHovered
                      ? AppTheme.sidebarActive.withOpacity(0.6)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: widget.isActive
                    ? AppTheme.sidebarActiveText
                    : (_isHovered
                          ? AppTheme.sidebarActiveText.withOpacity(0.7)
                          : AppTheme.mutedText),
              ),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: widget.isActive
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: widget.isActive
                      ? AppTheme.sidebarActiveText
                      : (_isHovered
                            ? AppTheme.sidebarActiveText.withOpacity(0.8)
                            : AppTheme.mutedText),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttorneyIphoneNavButton extends StatefulWidget {
  final bool isSelected;
  final IconData icon;
  final IconData unselectedIcon;
  final String label;
  final int badge;
  final VoidCallback onTap;

  const _AttorneyIphoneNavButton({
    required this.isSelected,
    required this.icon,
    required this.unselectedIcon,
    required this.label,
    required this.badge,
    required this.onTap,
  });

  @override
  State<_AttorneyIphoneNavButton> createState() =>
      _AttorneyIphoneNavButtonState();
}

class _AttorneyIphoneNavButtonState extends State<_AttorneyIphoneNavButton> {
  bool _isDown = false;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF38BDF8); // Electric cyan-blue
    final inactiveColor = Colors.white.withValues(alpha: 0.60);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isDown = true),
      onTapUp: (_) {
        setState(() => _isDown = false);
        unawaited(HapticFeedback.lightImpact());
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isDown = false),
      child: AnimatedScale(
        scale: _isDown ? 0.88 : (widget.isSelected ? 1.04 : 1.0),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? const Color(0xFF1E6BFF).withValues(alpha: 0.24)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.isSelected
                  ? const Color(0xFF38BDF8).withValues(alpha: 0.35)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      widget.isSelected ? widget.icon : widget.unselectedIcon,
                      key: ValueKey<bool>(widget.isSelected),
                      size: 21,
                      color: widget.isSelected ? activeColor : inactiveColor,
                    ),
                  ),
                  if (widget.badge > 0)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4.5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF07152B),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  const Color(0xFFEF4444).withValues(alpha: 0.4),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          widget.badge > 99 ? '99+' : '${widget.badge}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 10,
                  fontWeight:
                      widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: widget.isSelected ? activeColor : inactiveColor,
                  letterSpacing: 0.1,
                ),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

