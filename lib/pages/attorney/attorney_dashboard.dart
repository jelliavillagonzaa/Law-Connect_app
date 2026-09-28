import 'dart:async' show StreamSubscription, Timer, unawaited;

import 'package:flutter/material.dart';
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
import '../../widgets/admin/stat_card.dart';
import '../../theme/app_theme.dart';
import '../case/case_detail_page.dart';
import '../chat/chat_list_page.dart';
import '../auth/login_page.dart';
import '../../screens/attorney/appointment_calendar_view.dart';

import '../../widgets/attorney/reminders_bell_button.dart';
import '../../pages/attorney/attorney_profile_page.dart';
import '../../pages/attorney/confirm_appointment_schedule_page.dart';
import '../../services/chat_service.dart';
import '../../services/hearing_calendar_sync_service.dart';
import '../../services/fcm_service.dart';
import '../../services/calendar_session_cleanup.dart';
import '../../screens/attorney/attorney_case_requests_screen.dart';
import '../../screens/attorney/attorney_create_case_screen.dart';
import '../../screens/attorney/attorney_client_chat_screen.dart';
import '../../screens/attorney/attorney_tasks_screen.dart';
import '../../screens/attorney/attorney_create_task_screen.dart';
import '../../screens/billing/billing_management_screen.dart';
import '../../widgets/attorney/upcoming_appointment_tile.dart';

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
  final ValueNotifier<String> _headerSearchQuery = ValueNotifier('');
  final ValueNotifier<String> _casesStatusFilter =
      ValueNotifier(CaseStatusFilter.active);
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
        _pendingRequests.length,
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

      unawaited(FCMService().initialize().catchError((_) {}));
      unawaited(FCMService().saveTokenForUser(uid).catchError((_) {}));
      if (kIsWeb) {
        Timer(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          _attachUnreadWatcher();
        });
        _calendarPrewarmTimer = Timer(const Duration(seconds: 25), () {
          if (!mounted) return;
          _mobileTabStackKey.currentState?.prewarm(4);
          _desktopTabStackKey.currentState?.prewarm(6);
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
    final uid = FirebaseAuth.instance.currentUser?.uid?.trim();
    if (uid == null || uid.isEmpty || _hearingSyncAttached) return;
    _hearingSyncAttached = true;
    HearingCalendarSyncService.instance.attachForAttorney(uid);
  }

  @override
  void dispose() {
    _headerSearchQuery.dispose();
    _casesStatusFilter.dispose();
    _closedCasesFolder.dispose();
    _casesSub?.cancel();
    _appointmentsSub?.cancel();
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

  Widget _navIconWithBadge(
    IconData icon, {
    int badge = 0,
    Color? color,
    double size = 24,
  }) {
    return navIconWithBadge(
      icon,
      badge: badge,
      color: color,
      iconSize: size,
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

    Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      _attachDashboardStreams(user.uid);
    });
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
    } catch (_) {
      // Streams will retry via Firestore; keep UI responsive.
    }
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

      visible.sort((a, b) {
        final rank = _upcomingKeepRank(b) - _upcomingKeepRank(a);
        if (rank != 0) return rank;
        return a.appointmentDateTime.compareTo(b.appointmentDateTime);
      });

      // Same clock time = same booking. Keep the accepted/confirmed row only.
      final byMinute = <String, AppointmentModel>{};
      for (final apt in visible) {
        final t = apt.appointmentDateTime;
        final key = '${t.year}-${t.month}-${t.day}-${t.hour}-${t.minute}';
        byMinute.putIfAbsent(key, () => apt);
      }

      final upcoming = byMinute.values.toList()
        ..sort(
          (a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime),
        );
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
      final totalCases = _myCases
          .where((c) => !CaseStatusFilter.isCompleted(c.status))
          .length;
      final activeCases = _myCases
          .where((c) => CaseStatusFilter.isInProgress(c.status))
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
      _casesStatusFilter.value = caseFilter ?? CaseStatusFilter.active;
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
      case 'pending':
        bottomIndex = 3;
        break;
      case 'calendar':
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
      case 'pending':
        return 3;
      case 'tasks':
        return 4;
      case 'messages':
        return 5;
      case 'calendar':
        return 6;
      case 'settings':
        return 7;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      // Match attorney settings background color for a cohesive UI
      backgroundColor: const Color.fromARGB(255, 158, 182, 215),
      appBar: !isDesktop
          ? AppBar(
              automaticallyImplyLeading: false,
              title: Text(
                _headerTitle ?? '',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              backgroundColor: AppTheme.royalBlue,
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                _buildRemindersBellIcon(),
                IconButton(
                  icon: const Icon(Icons.person),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AttorneyProfilePage(),
                      ),
                    );
                  },
                  tooltip: 'Profile',
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
            ),

          // Main Content
          Expanded(
            child: Column(
              children: [
                // Desktop Header with Notification Bell (Web)
                if (isDesktop)
                  Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: AppTheme.royalBlue,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _currentUser?.fullName ??
                              _currentUser?.name ??
                              'Attorney',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        _buildRemindersBellIcon(),
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
      // Bottom Navigation - Mobile only
      bottomNavigationBar: !isDesktop
          ? Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      _buildBottomNavItem(Icons.dashboard, 'Dashboard', 0),
                      _buildBottomNavItem(Icons.folder, 'Cases', 1),
                      _buildBottomNavItem(Icons.inbox, 'Requests', 2),
                      _buildBottomNavItem(Icons.pending, 'Pending', 3),
                      _buildBottomNavItem(Icons.calendar_today, 'Calendar', 4),
                      _buildBottomNavItem(
                        Icons.message_outlined,
                        'Messages',
                        5,
                        badge: _unreadCount,
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildContent() {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    if (!isDesktop) {
      return LazyIndexedStack(
        key: _mobileTabStackKey,
        index: _selectedBottomNavIndex,
        activeTabRevision: _selectedBottomNavIndex == 0
            ? _dashboardTabRevision
            : _selectedBottomNavIndex == 1
                ? 'attorney_cases_tab_v4'
                : _selectedBottomNavIndex == 4
                    ? 'attorney_calendar_overlay_v6'
                    : 'mobile_tab_$_selectedBottomNavIndex',
        builders: [
          () => _buildDashboardView(),
          () => _buildCasesView(isMobile: true),
          () => AttorneyCaseRequestsScreen(
            embedded: true,
            attorneyId: FirebaseAuth.instance.currentUser?.uid ?? '',
          ),
          () => _buildPendingCasesView(isMobile: true),
          () => AppointmentCalendarView(
            embedded: true,
            initialAppointments: _allAppointments,
            sharedAppointmentsStream: _sharedAppointmentsStream,
          ),
          () => const ChatListPage(),
        ],
      );
    }

    final attorneyId = FirebaseAuth.instance.currentUser?.uid ?? '';
    return LazyIndexedStack(
      key: _desktopTabStackKey,
      index: _desktopTabIndex(),
      activeTabRevision: _desktopTabIndex() == 0
          ? _dashboardTabRevision
          : _desktopTabIndex() == 1
              ? 'attorney_cases_tab_v4'
              : _desktopTabIndex() == 6
                  ? 'attorney_calendar_overlay_v6'
                  : 'desktop_tab_${_desktopTabIndex()}',
      builders: [
        () => _buildDashboardView(),
        () => _buildCasesView(isMobile: false),
        () => AttorneyCaseRequestsScreen(
          embedded: true,
          attorneyId: attorneyId,
        ),
        () => _buildPendingCasesView(isMobile: false),
        () => const AttorneyTasksScreen(),
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

  void _openBilling() {
    final attorneyId = FirebaseAuth.instance.currentUser?.uid;
    if (attorneyId == null) return;
    Get.to(
      () => BillingManagementScreen(
        attorneyId: attorneyId,
        title: 'Billing & Payments',
        recorderRole: 'attorney',
        recorderName: FirebaseAuth.instance.currentUser?.displayName,
      ),
    );
  }

  Widget _buildDashboardView() {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    final crossAxisCount = isDesktop
        ? (MediaQuery.of(context).size.width > 1200 ? 4 : 3)
        : 2;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 24 : 16,
        vertical: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.royalBlue, AppTheme.deepNavy],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.royalBlue.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.gavel, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Attorney Dashboard',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Manage your cases and appointments',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: isDesktop ? 1.5 : 0.95,
            children: [
              StatCard(
                title: 'Total Cases',
                value: '${_stats['totalCases'] ?? 0}',
                description: 'All assigned cases',
                icon: Icons.folder_outlined,
                iconColor: AppTheme.royalBlue,
                percentageChange: '+3.4%',
                onTap: () => _handleItemSelected(
                  'cases',
                  caseFilter: CaseStatusFilter.active,
                ),
              ),
              StatCard(
                title: 'Active Cases',
                value: '${_stats['activeCases'] ?? 0}',
                description: 'In progress',
                icon: Icons.work_outline,
                iconColor: const Color(0xFF48BB78),
                percentageChange: '+1.2%',
                onTap: () => _handleItemSelected(
                  'cases',
                  caseFilter: CaseStatusFilter.inProgress,
                ),
              ),
              StatCard(
                title: 'Completed Cases',
                value: '${_stats['completedCases'] ?? 0}',
                description: 'Finished cases',
                icon: Icons.check_circle_outline,
                iconColor: const Color(0xFFED8936),
                percentageChange: '+0.8%',
                onTap: () => _handleItemSelected('closed_cases'),
              ),
              StatCard(
                title: 'Pending Requests',
                value: '${_stats['pendingCases'] ?? 0}',
                description: 'Appointment requests',
                icon: Icons.pending_outlined,
                iconColor: const Color(0xFFF56565),
                isPositiveChange: false,
                percentageChange: '-2.1%',
                onTap: () => _handleItemSelected('pending'),
              ),
              StatCard(
                title: 'Upcoming Appointments',
                value: '${_stats['upcomingAppointments'] ?? 0}',
                description: 'Scheduled meetings',
                icon: Icons.calendar_today_outlined,
                iconColor: const Color(0xFF764BA2),
                onTap: () {
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
              ),
            ],
          ),
          const SizedBox(height: 32),
          ..._dashboardBody(isDesktop: isDesktop),
        ],
      ),
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
                    OutlinedButton.icon(
                      onPressed: _openBilling,
                      icon: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 20,
                      ),
                      label: const Text('Billing & Payments'),
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

          // Bottom section: upcoming appointments & pending requests
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildUpcomingAppointmentsSection(),
                    ),
                    const SizedBox(width: 16),
                    Expanded(flex: 1, child: _buildPendingRequestsSection()),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildUpcomingAppointmentsSection(),
                    const SizedBox(height: 16),
                    _buildPendingRequestsSection(),
                  ],
                );
              }
            },
          ),
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

  Widget _buildPendingRequestsSection() {
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
                Icons.pending_actions_outlined,
                color: const Color(0xFFF56565),
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Pending Requests',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1C1C1C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_pendingRequests.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No pending appointment requests',
                style: TextStyle(fontSize: 14, color: const Color(0xFF6D6D6D)),
              ),
            )
          else
            ..._pendingRequests.take(5).map((appointment) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildPendingRequestCard(appointment),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCasesView({required bool isMobile}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Not logged in'));
    }
    return _AttorneyCasesTab(
      key: const ValueKey('attorney_cases_tab_v4'),
      attorneyId: user.uid,
      isMobile: isMobile,
      fallbackCases: _myCases,
      caseService: _caseService,
      mobileTabShell: _mobileTabShell,
      headerSearch: _headerSearchQuery,
      statusFilter: _casesStatusFilter,
      closedFolder: _closedCasesFolder,
    );
  }

  /// Pending appointment requests from clients (status == 'pending')
  Widget _buildPendingCasesView({required bool isMobile}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Not logged in'));
    }

    return StreamBuilder<List<AppointmentModel>>(
      stream: _appointmentService.getAttorneyAppointments(user.uid),
      builder: (context, snapshot) {
        final allAppointments = snapshot.hasData
            ? snapshot.data!
            : List<AppointmentModel>.from(_allAppointments);
        final pending = allAppointments
            .where((apt) => apt.status.toLowerCase() == 'pending')
            .toList();
        if (snapshot.hasError && pending.isEmpty) {
          return _mobileTabShell(
            child: const Center(
              child: Text(
                'Could not load pending requests',
                style: TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        final displayPending = pending.isNotEmpty
            ? pending
            : List<AppointmentModel>.from(_pendingRequests);

        if (displayPending.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pending_actions, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No pending requests',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        if (isMobile) {
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.all(16),
            itemCount: displayPending.length,
            itemBuilder: (context, index) {
              final appointment = displayPending[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildPendingRequestCard(appointment),
              );
            },
          );
        } else {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.all(24),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final appointment in displayPending)
                  SizedBox(
                    width: 320,
                    child: _buildPendingRequestCard(appointment),
                  ),
              ],
            ),
          );
        }
      },
    );
  }

  String _activeItemForBottomNavIndex(int index) {
    switch (index) {
      case 1:
        return 'cases';
      case 2:
        return 'case_requests';
      case 3:
        return 'pending';
      case 4:
        return 'calendar';
      case 5:
        return 'messages';
      default:
        return 'dashboard';
    }
  }

  Widget _buildBottomNavItem(
    IconData icon,
    String label,
    int index, {
    int badge = 0,
  }) {
    final isActive = _selectedBottomNavIndex == index;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_selectedBottomNavIndex == index) return;
            setState(() {
              _selectedBottomNavIndex = index;
              _activeItem = _activeItemForBottomNavIndex(index);
            });
            if (index == 1) {
              _closedCasesFolder.value = false;
              _casesStatusFilter.value = CaseStatusFilter.active;
            }
            if (index == 4) _ensureHearingCalendarSync();
            if (index == 5) unawaited(_loadUnreadCount());
          },
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 64,
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _navIconWithBadge(
                  icon,
                  badge: badge,
                  color: isActive
                      ? AppTheme.royalBlue
                      : const Color(0xFF6D6D6D),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive
                        ? AppTheme.royalBlue
                        : const Color(0xFF6D6D6D),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Card UI for a single pending appointment request
  Widget _buildPendingRequestCard(AppointmentModel appointment) {
    final compact = kIsWeb;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showPendingRequestDetails(appointment),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat(
                            'MMM dd, yyyy – hh:mm a',
                          ).format(appointment.appointmentDateTime),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Client: ${appointment.clientName}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Text(
                      'PENDING',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800],
                      ),
                    ),
                  ),
                ],
              ),
              if (appointment.notes != null &&
                  appointment.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  appointment.notes!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
              // Action buttons row
              SizedBox(height: compact ? 8 : 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Message icon button
                  IconButton(
                    icon: Icon(
                      Icons.message,
                      color: AppTheme.royalBlue,
                      size: 18,
                    ),
                    tooltip: 'Message Client',
                    onPressed: () =>
                        unawaited(_openChatWithClient(appointment)),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.royalBlue.withOpacity(0.1),
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(36, 36),
                      fixedSize: const Size(36, 36),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Accept button
                  ElevatedButton(
                    onPressed: () async {
                      // Navigate to confirm schedule screen
                      await Get.to(
                        () => ConfirmAppointmentSchedulePage(
                          pendingRequest: appointment,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.royalBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      'Accept',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPendingRequestDetails(AppointmentModel appointment) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Appointment Request',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat(
                  'MMM dd, yyyy – hh:mm a',
                ).format(appointment.appointmentDateTime),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Client: ${appointment.clientName}',
                style: TextStyle(fontSize: 13),
              ),
              if (appointment.notes != null &&
                  appointment.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Notes:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(appointment.notes!, style: TextStyle(fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle()),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _showDeclineRequestDialog(appointment);
              },
              child: Text('Decline', style: TextStyle(color: Colors.red)),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Message icon button
                IconButton(
                  icon: Icon(
                    Icons.message,
                    color: AppTheme.royalBlue,
                    size: 18,
                  ),
                  tooltip: 'Message Client',
                  onPressed: () {
                    Navigator.pop(context);
                    unawaited(_openChatWithClient(appointment));
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.royalBlue.withOpacity(0.1),
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(36, 36),
                    fixedSize: const Size(36, 36),
                  ),
                ),
                const SizedBox(width: 4),
                // Accept button
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    // Navigate to confirm schedule screen instead of auto-accept
                    await Get.to(
                      () => ConfirmAppointmentSchedulePage(
                        pendingRequest: appointment,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.royalBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    'Accept',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Opens a chat with the client from the appointment
  Future<void> _openChatWithClient(AppointmentModel appointment) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening chat...'),
          duration: Duration(milliseconds: 600),
        ),
      );
    }

    try {
      // Get or create chat with the client
      final chatId = await _chatService.getOrCreateChat(
        user.uid,
        appointment.clientId,
      );

      // Navigate to attorney chat screen
      Get.to(
        () => AttorneyClientChatScreen(
          chatId: chatId,
          clientId: appointment.clientId,
          clientName: appointment.clientName,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open chat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Secondary dialog to capture optional decline reason and update Firestore.
  Future<void> _showDeclineRequestDialog(AppointmentModel appointment) async {
    final TextEditingController reasonController = TextEditingController();
    bool isSubmitting = false;
    Map<String, dynamic>? declineResult;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Decline Request',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You can optionally provide a reason for declining this appointment.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Reason (optional)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          Navigator.pop(context);
                        },
                  child: Text('Cancel', style: TextStyle()),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          // Capture navigator before async operation
                          final navigator = Navigator.of(context);
                          setState(() {
                            isSubmitting = true;
                          });
                          final result = await _appointmentService
                              .updateRequestStatus(
                                appointment.id,
                                status: 'declined',
                                declineReason: reasonController.text,
                              );
                          if (!mounted) return;
                          declineResult = result;
                          navigator.pop();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          'Decline Request',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    // Show snackbar after dialog closes if result is available
    if (declineResult != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(declineResult!['message'] ?? 'Request declined'),
          backgroundColor: declineResult!['success'] == true
              ? Colors.red
              : Colors.grey,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
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
  String _statusFilter = CaseStatusFilter.active;
  bool _closedFolder = false;

  @override
  void initState() {
    super.initState();
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
      stream: widget.caseService.getCasesForUser(widget.attorneyId, 'attorney'),
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
            : (_statusFilter == CaseStatusFilter.all
                ? CaseStatusFilter.active
                : _statusFilter);
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
            selected: _statusFilter == CaseStatusFilter.all
                ? CaseStatusFilter.active
                : _statusFilter,
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
                  : CaseStatusFilter.active;
              setState(() {
                _closedFolder = nextClosed;
                _statusFilter = widget.statusFilter.value;
              });
            },
            child: Text(_closedFolder ? 'My Cases' : 'Closed cases'),
          );
        }

        if (widget.isMobile) {
          return Column(
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
                          child: Text(
                            emptyMessage(),
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
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
