import 'dart:async' show StreamSubscription, Timer, unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/chat_service.dart';
import '../../services/staff_auth_service.dart';
import '../../models/staff_model.dart';
import '../../theme/app_theme.dart';
import '../../screens/staff/staff_cases_screen.dart';
import '../../screens/staff/staff_tasks_screen.dart';
import '../../screens/staff/staff_calendar_screen.dart';
import '../../screens/staff/staff_clients_screen.dart';
import '../../screens/staff/staff_communication_screen.dart';
import '../../screens/staff/staff_reports_screen.dart';
import '../../screens/staff/staff_notifications_screen.dart';
import '../../services/auth_service.dart';
import '../../screens/staff/staff_create_case_draft_screen.dart';
import '../../screens/staff/staff_pending_appointments_screen.dart';
import '../../pages/admin/admin_dashboard.dart';
import '../../screens/admin/user_management_screen.dart';
import '../../screens/admin/case_oversight_screen.dart';
import '../../screens/admin/archive_storage_screen.dart';
import '../../screens/admin/backup_settings_screen.dart';
import '../../screens/admin/reports_analytics_screen.dart';
import '../../screens/admin/system_logs_screen.dart';
import '../../screens/admin/system_settings_screen.dart';
import '../../screens/staff/staff_notary_management_screen.dart';
import '../../screens/billing/billing_management_screen.dart'
    show openPaymentHistoryScreen;

import '../../pages/staff/staff_profile_page.dart';
import '../../screens/client/help_center_screen.dart';
import '../../help/staff_help_catalog.dart';
import 'staff_dashboard_home_tab.dart';
import '../../widgets/common/lazy_indexed_stack.dart';
import '../../widgets/common/nav_unread_dot.dart';
import '../../widgets/common/profile_picture_widget.dart';
import '../../widgets/staff/staff_nav_rail.dart';
import '../../widgets/staff/staff_ui_theme.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../services/calendar_session_cleanup.dart';
import '../../services/hearing_calendar_sync_service.dart';
import '../../services/fcm_service.dart';
import '../../services/staff_service.dart';
import '../../models/appointment_model.dart';
import '../auth/login_page.dart';

class StaffDashboard extends StatefulWidget {
  const StaffDashboard({super.key});

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  final GlobalKey<LazyIndexedStackState> _mobileTabStackKey =
      GlobalKey<LazyIndexedStackState>();
  final GlobalKey<LazyIndexedStackState> _desktopTabStackKey =
      GlobalKey<LazyIndexedStackState>();
  final GlobalKey<StaffDashboardHomeTabState> _homeTabKey =
      GlobalKey<StaffDashboardHomeTabState>();
  Timer? _tabPrewarmTimer;
  Timer? _fanoutDeferTimer;
  StreamSubscription<int>? _messageUnreadSub;
  VoidCallback? _sharedBellListener;
  ValueNotifier<int>? _sharedBell;
  final ValueNotifier<int> _bellCount = ValueNotifier<int>(0);

  final ChatService _chatService = ChatService();
  final StaffAuthService _staffAuthService = StaffAuthService();
  final EnhancedAppointmentService _appointmentService =
      EnhancedAppointmentService();

  StaffModel? _currentStaff;
  String? _assignedAttorneyId;
  Stream<List<AppointmentModel>>? _sharedAppointmentsStream;
  StreamSubscription<List<AppointmentModel>>? _appointmentsSub;
  List<AppointmentModel> _allAppointments = [];
  String _activeItem = 'dashboard';
  bool _initialRoleResolved = false;
  int _selectedBottomNavIndex = 0;
  int _messageUnreadCount = 0;

  static const int _bottomNavItemCount = 6;

  /// Web hot reload can leave int fields null at runtime â€” coerce before math/UI.
  static int _safeInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }

  int get _safeBottomNavIndex =>
      _safeInt(_selectedBottomNavIndex).clamp(0, _bottomNavItemCount - 1);

  Object _homeTabRevision() =>
      Object.hash(_assignedAttorneyId, _currentStaff?.name);

  void _reloadHomeTab() => _homeTabKey.currentState?.reload();

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    if (args is Map && args['initialItem'] is String) {
      _activeItem = args['initialItem'] as String;
      _initialRoleResolved = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void reassemble() {
    super.reassemble();
    _selectedBottomNavIndex = _safeInt(_selectedBottomNavIndex);
    _messageUnreadCount = _safeInt(_messageUnreadCount);
  }

  Future<void> _bootstrap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Get.offAll(() => const LoginPage());
      return;
    }

    unawaited(_loadUserData());
    unawaited(_logStaffSession());
    _attachUnreadWatcher();
    _attachBellWatcher();
    _attachPendingAppointmentsFallback();
    unawaited(_refreshBellBadge());
    unawaited(_verifyAccountAndBootstrap(user));
  }

  static bool _sessionActivityLogged = false;

  Future<void> _logStaffSession() async {
    if (_sessionActivityLogged) return;
    _sessionActivityLogged = true;
    try {
      await StaffService().logActivity(
        action: 'Signed in',
        details: 'Staff session started',
        resourceType: 'session',
      );
    } catch (_) {
      _sessionActivityLogged = false;
    }
  }

  void _attachUnreadWatcher() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _messageUnreadSub?.cancel();
    _messageUnreadSub = _chatService.watchUnreadCount(uid).listen(
      (unreadCount) {
        if (mounted && unreadCount != _messageUnreadCount) {
          setState(() => _messageUnreadCount = unreadCount);
        }
      },
      onError: (_) {},
    );
  }

  void _attachBellWatcher() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final fanout = HearingNotificationFanoutService.instance;
    fanout.attachAttorneyBellWatcher(uid);
    final shared = fanout.attorneyUnreadNotificationBellListenable(uid);
    if (_sharedBell != null && _sharedBellListener != null) {
      _sharedBell!.removeListener(_sharedBellListener!);
    }
    _sharedBell = shared;
    _sharedBellListener = () {
      if (!mounted) return;
      _setBellCount(shared.value);
    };
    shared.addListener(_sharedBellListener!);
    _setBellCount(shared.value);
    unawaited(fanout.refreshAttorneyBellFromNotifications(uid));
  }

  void _setBellCount(int count) {
    final next = _safeInt(count);
    if (_bellCount.value != next) _bellCount.value = next;
  }
  Future<bool> _verifyAccountAndBootstrap(User user) async {
    DocumentSnapshot<Map<String, dynamic>>? doc;
    try {
      doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
    } catch (_) {
      doc = null;
    }

    if (doc != null) {
      if (!doc.exists) {
        if (!mounted) return false;
        Get.offAll(() => const LoginPage());
        return false;
      }
      final data = doc.data()!;
      if (data['role'] == 'staff' && data['isActive'] == false) {
        CalendarSessionCleanup.onLogout();
        await FirebaseAuth.instance.signOut();
        if (!mounted) return false;
        Get.snackbar(
          'Account not active',
          'Your staff access is turned off. If you are still waiting on application approval, sign in after an admin approves. Otherwise contact an administrator.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
        Get.offAll(() => const LoginPage());
        return false;
      }

      final email = (data['email'] as String?)?.toString() ?? user.email ?? '';
      if (!mounted) return false;
      unawaited(_runDeferredBootstrap(user.uid, email, data));
      return true;
    }

    // Transient/offline verify failure — still warm secondary dashboard data.
    if (!mounted) return false;
    unawaited(_runDeferredBootstrap(user.uid, user.email ?? '', const {}));
    return true;
  }

  /// Auth repair + deferred warmup (bell badge, tab prewarm).
  Future<void> _runDeferredBootstrap(
    String uid,
    String email,
    Map<String, dynamic> data,
  ) async {
    try {
      unawaited(
        AuthService().syncStaffRoleFromStaffApplication(uid: uid, email: email),
      );
      unawaited(
        AuthService().repairPortalRoleIfNeeded(
          uid: uid,
          email: email,
          firestoreRole: data['role'] as String?,
        ),
      );
      unawaited(FCMService().initialize().catchError((_) {}));
      unawaited(FCMService().saveTokenForUser(uid).catchError((_) {}));
    } catch (_) {}

    if (!mounted) return;
    if (kIsWeb) {
      unawaited(_refreshBellBadge());
      Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        unawaited(_loadMessageUnreadCount());
      });
    } else {
      Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        unawaited(_loadMessageUnreadCount());
        unawaited(_refreshBellBadge());
      });
    }

    // Progressive tab prewarm: ensures clicking mobile tabs is instant and butter-smooth
    Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _mobileTabStackKey.currentState?.prewarm(1); // Cases
      _mobileTabStackKey.currentState?.prewarm(3); // Tasks
    });
    Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      _mobileTabStackKey.currentState?.prewarm(4); // Calendar
      _mobileTabStackKey.currentState?.prewarm(5); // Messages
    });
    if (kIsWeb) {
      Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        _desktopTabStackKey.currentState?.prewarm(4);
      });
    }

    _fanoutDeferTimer?.cancel();
    _fanoutDeferTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      unawaited(
        HearingNotificationFanoutService.instance.prepareBellCount(uid),
      );
    });
  }

  Future<void> _refreshBellBadge() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !mounted) return;
    try {
      final count = await HearingNotificationFanoutService.instance
          .refreshAttorneyBellFromNotifications(uid);
      if (mounted) _setBellCount(count);
    } catch (_) {}
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _firestoreGetDoc(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    if (kIsWeb) return ref.get();
    try {
      return await ref.get(const GetOptions(source: Source.server));
    } catch (_) {
      return ref.get();
    }
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    var attorneyId = '';
    StaffModel? staff;
    try {
      staff = await _staffAuthService.getCurrentStaff();
    } catch (_) {}

    if (staff != null) {
      attorneyId = staff.assignedAttorneyId.trim();
      _currentStaff = staff;
    }

    try {
      final userDoc = await _firestoreGetDoc(
        FirebaseFirestore.instance.collection('users').doc(user.uid),
      );
      if (userDoc.exists && mounted) {
        final data = userDoc.data() ?? {};
        if (attorneyId.isEmpty) {
          attorneyId = (data['assignedAttorneyId'] as String?)?.trim() ?? '';
        }
        final name = (data['name'] as String?)?.trim();
        final role = (data['role'] as String?)?.toLowerCase();
        if (!_initialRoleResolved) {
          _initialRoleResolved = true;
          if ((role == 'admin' ||
                  AuthService.resolvePortalRole(user.email ?? '',
                          firestoreRole: role) ==
                      'admin') &&
              _activeItem == 'dashboard') {
            setState(() => _activeItem = 'admin_dashboard');
          }
        }
        if (name != null && name.isNotEmpty && _currentStaff == null) {
          _currentStaff = StaffModel(
            id: user.uid,
            name: name,
            email: (data['email'] as String?) ?? user.email ?? '',
            assignedAttorneyId: attorneyId,
            createdAt: DateTime.now(),
          );
        }
      }
    } catch (_) {}

    // Fallback: resolve attorney from assigned cases
    if (attorneyId.isEmpty) {
      try {
        final casesSnap = await FirebaseFirestore.instance
            .collection('cases')
            .where('staffAssigned', arrayContains: user.uid)
            .limit(5)
            .get();
        for (final doc in casesSnap.docs) {
          final aid = (doc.data()['attorneyId'] as String?)?.trim() ?? '';
          if (aid.isNotEmpty) {
            attorneyId = aid;
            break;
          }
        }
        if (attorneyId.isEmpty) {
          final staffCasesSnap = await FirebaseFirestore.instance
              .collection('cases')
              .where('staffId', isEqualTo: user.uid)
              .limit(5)
              .get();
          for (final doc in staffCasesSnap.docs) {
            final aid = (doc.data()['attorneyId'] as String?)?.trim() ?? '';
            if (aid.isNotEmpty) {
              attorneyId = aid;
              break;
            }
          }
        }
      } catch (_) {}
    }

    // Fallback: resolve from active attorney in users
    if (attorneyId.isEmpty) {
      try {
        final attSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'attorney')
            .where('isActive', isEqualTo: true)
            .limit(1)
            .get();
        if (attSnap.docs.isNotEmpty) {
          attorneyId = attSnap.docs.first.id;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      if (attorneyId.isNotEmpty) _assignedAttorneyId = attorneyId;
    });
    if (attorneyId.isNotEmpty) {
      _attachSharedAppointmentsStream(attorneyId);
    } else {
      _attachPendingAppointmentsFallback();
    }
  }

  int get _pendingAppointmentsCount => _allAppointments
      .where((apt) => apt.status.toLowerCase() == 'pending')
      .length;

  void _attachSharedAppointmentsStream(String? attorneyId) {
    final aid = attorneyId?.trim() ?? '';
    if (aid.isEmpty) {
      _attachPendingAppointmentsFallback();
      return;
    }

    _sharedAppointmentsStream ??=
        _appointmentService.getAttorneyAppointments(aid);
    final stream = _sharedAppointmentsStream!;

    _appointmentsSub?.cancel();
    _appointmentsSub = stream.listen(
      (appointments) {
        if (!mounted) return;
        setState(() {
          _allAppointments = appointments;
        });
      },
      onError: (_) {},
    );
  }

  void _attachPendingAppointmentsFallback() {
    _appointmentsSub?.cancel();
    _appointmentsSub = FirebaseFirestore.instance
        .collection('appointments')
        .where('status', isEqualTo: 'pending')
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppointmentModel.fromFirestore(doc))
              .toList(),
        )
        .listen(
      (list) {
        if (!mounted) return;
        setState(() => _allAppointments = list);
      },
      onError: (_) {},
    );
  }

  Widget _buildStaffPendingAppointmentsTab() {
    return StaffPendingAppointmentsScreen(
      embedded: true,
      assignedAttorneyId: _assignedAttorneyId,
      sharedAppointmentsStream: _sharedAppointmentsStream,
      initialAppointments: _allAppointments,
    );
  }

  Widget _buildStaffCalendarTab() {
    return StaffCalendarScreen(
      embedded: true,
      assignedAttorneyId: _assignedAttorneyId,
      initialAppointments: _allAppointments,
      sharedAppointmentsStream: _sharedAppointmentsStream,
    );
  }

  Future<void> _loadMessageUnreadCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final count = await _chatService.getUnreadCount(user.uid);
      if (mounted && count != _messageUnreadCount) {
        setState(() => _messageUnreadCount = count);
      }
    } catch (_) {}
  }

  Widget _navIconWithBadge(IconData icon, {int badge = 0}) {
    return navIconWithBadge(icon, badge: _safeInt(badge));
  }

  void _openHelpCenter() {
    Get.to(
      () => const HelpCenterScreen(
        articles: staffHelpArticles,
        intro:
            'Answers come from the staff guide: cases, drafts, tasks, billing, and messages.',
        hint: 'Example: How do I create a draft case?',
      ),
    );
  }

  void _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      CalendarSessionCleanup.onLogout();
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Get.offAll(() => const LoginPage());
      }
    }
  }

  /// Bell in AppBar: unread count from Firestore `notifications` (matches notification inbox).
  Widget _buildNotificationBellIconButton({bool onNavy = false}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return IconButton(
        icon: Icon(
          Icons.notifications_active,
          color: onNavy ? Colors.white : null,
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const StaffNotificationsScreen(),
            ),
          );
        },
        tooltip: 'Notifications',
      );
    }

    return ValueListenableBuilder<int>(
      valueListenable: _bellCount,
      builder: (context, bellValue, _) {
        final unread = _safeInt(bellValue);
        final show = unread > 0;
        final label = unread > 99 ? '99+' : unread > 9 ? '9+' : '$unread';
        return IconButton(
          padding: EdgeInsets.zero,
          iconSize: 20,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.notifications_active_rounded,
                color: onNavy ? Colors.white : null,
                size: 20,
              ),
              if (show)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF07152B),
                        width: 1.5,
                      ),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const StaffNotificationsScreen(),
              ),
            ).then((_) {
              if (mounted) unawaited(_refreshBellBadge());
            });
          },
          tooltip: show ? 'Notifications ($unread unread)' : 'Notifications',
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    if (!isDesktop) {
      return Scaffold(
        extendBody: true,
        drawer: _buildMobileDrawer(),
        body: _safeBottomNavIndex == 0
            ? SafeArea(bottom: false, child: _buildContent())
            : _buildContent(),
        bottomNavigationBar: _buildIphoneFloatingNavBar(),
      );
    } else {
      return Scaffold(
        backgroundColor: StaffUi.background,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StaffNavRail(
              activeItem: _activeItem,
              messageUnreadCount: _safeInt(_messageUnreadCount),
              pendingAppointmentsCount: _pendingAppointmentsCount,
              onLogout: _handleLogout,
              onItemSelected: _onSidebarItemSelected,
            ),
            Expanded(child: _buildContent()),
          ],
        ),
      );
    }
  }

  void _onSidebarItemSelected(String item) {
    if (item == 'payment_history') {
      openPaymentHistoryScreen(
        context,
        recorderRole: 'staff',
        recorderName: _currentStaff?.name,
      );
      return;
    }
    if (item == 'draft_cases') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const StaffCreateCaseDraftScreen(),
        ),
      ).then((created) {
        if (created == true) {
          _reloadHomeTab();
          if (mounted) {
            setState(() {
              _selectedBottomNavIndex = 0;
              _activeItem = 'dashboard';
            });
          }
        }
      });
    } else {
      if (item == 'calendar') {
        final aid = _assignedAttorneyId?.trim() ?? '';
        if (aid.isNotEmpty) {
          HearingCalendarSyncService.instance.attachForAttorney(aid);
        }
      }
      setState(() => _activeItem = item);
    }
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(gradient: StaffUi.heroGradient),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ProfilePictureWidget(
                  photoUrl: _currentStaff?.photoUrl,
                  userName: _currentStaff?.name ?? 'Staff',
                  size: 60,
                  isEditable: false,
                  onUpdated: () {
                    _loadUserData();
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  _currentStaff?.name ?? 'Staff Member',
                  style: StaffUi.style(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Legal Assistant & Administrator',
                    style: StaffUi.style(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: StaffUi.gold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.dashboard_rounded,
              color: _selectedBottomNavIndex == 0 ? StaffUi.gold : StaffUi.navy,
            ),
            title: Text(
              'Dashboard',
              style: StaffUi.style(
                fontWeight: _selectedBottomNavIndex == 0
                    ? FontWeight.w700
                    : FontWeight.w500,
                color:
                    _selectedBottomNavIndex == 0 ? StaffUi.navy : StaffUi.text,
              ),
            ),
            selected: _selectedBottomNavIndex == 0,
            selectedTileColor: StaffUi.goldSoft.withValues(alpha: 0.4),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 0);
            },
          ),
          ListTile(
            leading: Icon(
              Icons.folder_rounded,
              color: _selectedBottomNavIndex == 1 ? StaffUi.gold : StaffUi.navy,
            ),
            title: Text(
              'Cases',
              style: StaffUi.style(
                fontWeight: _selectedBottomNavIndex == 1
                    ? FontWeight.w700
                    : FontWeight.w500,
                color:
                    _selectedBottomNavIndex == 1 ? StaffUi.navy : StaffUi.text,
              ),
            ),
            selected: _selectedBottomNavIndex == 1,
            selectedTileColor: StaffUi.goldSoft.withValues(alpha: 0.4),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 1);
            },
          ),
          ListTile(
            leading: _navIconWithBadge(
              Icons.pending_actions_rounded,
              badge: _pendingAppointmentsCount,
            ),
            title: Text(
              'Pending Appointments',
              style: StaffUi.style(
                fontWeight: FontWeight.w500,
                color: StaffUi.text,
              ),
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              _openStaffPendingAppointments();
            },
          ),
          ListTile(
            leading: Icon(
              Icons.task_alt_rounded,
              color: _selectedBottomNavIndex == 3 ? StaffUi.gold : StaffUi.navy,
            ),
            title: Text(
              'Tasks',
              style: StaffUi.style(
                fontWeight: _selectedBottomNavIndex == 3
                    ? FontWeight.w700
                    : FontWeight.w500,
                color:
                    _selectedBottomNavIndex == 3 ? StaffUi.navy : StaffUi.text,
              ),
            ),
            selected: _selectedBottomNavIndex == 3,
            selectedTileColor: StaffUi.goldSoft.withValues(alpha: 0.4),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 3);
            },
          ),
          ListTile(
            leading: Icon(
              Icons.calendar_month_rounded,
              color: _selectedBottomNavIndex == 4 ? StaffUi.gold : StaffUi.navy,
            ),
            title: Text(
              'Calendar',
              style: StaffUi.style(
                fontWeight: _selectedBottomNavIndex == 4
                    ? FontWeight.w700
                    : FontWeight.w500,
                color:
                    _selectedBottomNavIndex == 4 ? StaffUi.navy : StaffUi.text,
              ),
            ),
            selected: _selectedBottomNavIndex == 4,
            selectedTileColor: StaffUi.goldSoft.withValues(alpha: 0.4),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 4);
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.draw_outlined,
              color: StaffUi.navy,
            ),
            title: Text(
              'Notary',
              style: StaffUi.style(
                fontWeight: FontWeight.w500,
                color: StaffUi.text,
              ),
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StaffNotaryManagementScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.receipt_long_rounded,
              color: StaffUi.navy,
            ),
            title: Text(
              'Payment History',
              style: StaffUi.style(
                fontWeight: FontWeight.w500,
                color: StaffUi.text,
              ),
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              openPaymentHistoryScreen(
                context,
                recorderRole: 'staff',
                recorderName: _currentStaff?.name,
              );
            },
          ),
          ListTile(
            leading: _navIconWithBadge(
              Icons.chat_bubble_rounded,
              badge: _messageUnreadCount,
            ),
            title: Text(
              'Messages',
              style: StaffUi.style(
                fontWeight: _selectedBottomNavIndex == 5
                    ? FontWeight.w700
                    : FontWeight.w500,
                color:
                    _selectedBottomNavIndex == 5 ? StaffUi.navy : StaffUi.text,
              ),
            ),
            selected: _selectedBottomNavIndex == 5,
            selectedTileColor: StaffUi.goldSoft.withValues(alpha: 0.4),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 5);
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: StaffUi.line),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'ADMINISTRATION',
              style: StaffUi.style(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: StaffUi.muted,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.space_dashboard_outlined, color: StaffUi.navy),
            title: Text(
              'Admin Dashboard',
              style: StaffUi.style(fontWeight: FontWeight.w500, color: StaffUi.text),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminDashboard()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined, color: StaffUi.navy),
            title: Text(
              'User Management',
              style: StaffUi.style(fontWeight: FontWeight.w500, color: StaffUi.text),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const UserManagementScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.policy_outlined, color: StaffUi.navy),
            title: Text(
              'Case Oversight',
              style: StaffUi.style(fontWeight: FontWeight.w500, color: StaffUi.text),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CaseOversightScreen(
                    onOpenArchiveStorage: () {
                      Get.to(
                        () => ArchiveStorageScreen(
                          onOpenBackup: () => Get.to(() => const BackupSettingsScreen()),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.analytics_outlined, color: StaffUi.navy),
            title: Text(
              'System Analytics',
              style: StaffUi.style(fontWeight: FontWeight.w500, color: StaffUi.text),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ReportsAnalyticsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined, color: StaffUi.navy),
            title: Text(
              'System Logs',
              style: StaffUi.style(fontWeight: FontWeight.w500, color: StaffUi.text),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SystemLogsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined, color: StaffUi.navy),
            title: Text(
              'Archive Storage',
              style: StaffUi.style(fontWeight: FontWeight.w500, color: StaffUi.text),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ArchiveStorageScreen(
                    onOpenBackup: () => Get.to(() => const BackupSettingsScreen()),
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore_outlined, color: StaffUi.navy),
            title: Text(
              'Backup & Restore',
              style: StaffUi.style(fontWeight: FontWeight.w500, color: StaffUi.text),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const BackupSettingsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined, color: StaffUi.navy),
            title: Text(
              'System Settings',
              style: StaffUi.style(fontWeight: FontWeight.w500, color: StaffUi.text),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SystemSettingsScreen()),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(color: StaffUi.line),
          ),
          ListTile(
            leading:
                const Icon(Icons.help_outline_rounded, color: StaffUi.muted),
            title:
                Text('Help Center', style: StaffUi.style(color: StaffUi.muted)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              _openHelpCenter();
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: StaffUi.danger),
            title: Text('Logout',
                style: StaffUi.style(
                    color: StaffUi.danger, fontWeight: FontWeight.w600)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onTap: () {
              Navigator.pop(context);
              _handleLogout();
            },
          ),
        ],
      ),
    );
  }

  int _desktopTabIndex() {
    switch (_activeItem) {
      case 'cases':
        return 1;
      case 'closed_cases':
        return 2;
      case 'pending':
        return 3;
      case 'tasks':
        return 4;
      case 'clients':
        return 5;
      case 'calendar':
        return 6;
      case 'notary':
        return 7;
      case 'communication':
        return 8;
      case 'reports':
        return 9;
      case 'profile':
        return 10;
      case 'admin_dashboard':
        return 11;
      case 'admin_users':
        return 12;
      case 'admin_cases':
        return 13;
      case 'admin_analytics':
        return 14;
      case 'admin_logs':
        return 15;
      case 'admin_archive':
        return 16;
      case 'admin_backup':
        return 17;
      case 'admin_settings':
        return 18;
      default:
        return 0;
    }
  }

  Widget _buildContent() {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    if (!isDesktop) {
      return LazyIndexedStack(
        key: _mobileTabStackKey,
        index: _safeBottomNavIndex,
        activeTabRevision: _safeBottomNavIndex == 0
            ? _homeTabRevision()
            : _safeBottomNavIndex == 4
                ? 'staff_calendar_web_${_assignedAttorneyId ?? 'none'}'
                : 'mobile_tab_$_safeBottomNavIndex',
        builders: [
          () => _buildDashboardView(),
          () => const StaffCasesScreen(),
          () => const SizedBox.shrink(),
          () => const StaffTasksScreen(),
          () => _buildStaffCalendarTab(),
          () => const StaffCommunicationScreen(),
        ],
      );
    }

    final desktopIndex = _desktopTabIndex();
    final stack = LazyIndexedStack(
      key: _desktopTabStackKey,
      index: desktopIndex,
      activeTabRevision: desktopIndex == 0
          ? _homeTabRevision()
          : desktopIndex == 6
              ? 'staff_calendar_web_${_assignedAttorneyId ?? 'none'}'
              : 'desktop_tab_$desktopIndex',
      builders: [
        () => _buildDashboardView(),
        () => const StaffCasesScreen(),
        () => const StaffCasesScreen(closedFolder: true),
        () => _buildStaffPendingAppointmentsTab(),
        () => const StaffTasksScreen(),
        () => const StaffClientsScreen(),
        () => _buildStaffCalendarTab(),
        () => const StaffNotaryManagementScreen(),
        () => const StaffCommunicationScreen(),
        () => const StaffReportsScreen(),
        () => const StaffProfilePage(),
        () => AdminDashboard(
              inline: true,
              onNavigateToItem: (item) => setState(() => _activeItem = item),
            ),
        () => const UserManagementScreen(inline: true),
        () => CaseOversightScreen(
              inline: true,
              onOpenArchiveStorage: () => setState(() => _activeItem = 'admin_archive'),
            ),
        () => ReportsAnalyticsScreen(
              inline: true,
              onNavigateToUsers: ({String role = 'all'}) =>
                  setState(() => _activeItem = 'admin_users'),
              onNavigateToCases: ({String status = 'all'}) =>
                  setState(() => _activeItem = 'admin_cases'),
            ),
        () => const SystemLogsScreen(inline: true),
        () => ArchiveStorageScreen(
              inline: true,
              onOpenBackup: () => setState(() => _activeItem = 'admin_backup'),
            ),
        () => const BackupSettingsScreen(inline: true),
        () => const SystemSettingsScreen(inline: true),
      ],
    );

    return Column(
      children: [
        if (_activeItem != 'dashboard' && !_activeItem.startsWith('admin_'))
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Spacer(),
                IconButton(
                  tooltip: 'Help Center',
                  icon: const Icon(Icons.help_outline),
                  color: AppTheme.royalBlue,
                  onPressed: _openHelpCenter,
                ),
                _buildNotificationBellIconButton(),
                IconButton(
                  icon: const Icon(Icons.person_outline),
                  tooltip: 'Profile',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const StaffProfilePage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        Expanded(child: stack),
      ],
    );
  }

  void _openStaffPendingAppointments() {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    if (isDesktop) {
      setState(() => _activeItem = 'pending');
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StaffPendingAppointmentsScreen(
            embedded: false,
            assignedAttorneyId: _assignedAttorneyId,
            sharedAppointmentsStream: _sharedAppointmentsStream,
            initialAppointments: _allAppointments,
          ),
        ),
      );
    }
  }

  Widget _buildDashboardView() {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    return StaffDashboardHomeTab(
      key: _homeTabKey,
      staffName: _currentStaff?.name ?? 'Staff',
      assignedAttorneyId: _assignedAttorneyId,
      pendingAppointmentsCount: _pendingAppointmentsCount,
      onNavigateToPendingAppointments: _openStaffPendingAppointments,
      onNavigateToCases: () {
        if (isDesktop) {
          setState(() => _activeItem = 'cases');
        } else {
          setState(() => _selectedBottomNavIndex = 1);
        }
      },
      onNavigateToCalendar: () {
        if (isDesktop) {
          setState(() => _activeItem = 'calendar');
        } else {
          setState(() => _selectedBottomNavIndex = 4);
        }
      },
      onNavigateToNotary: () {
        if (isDesktop) {
          setState(() => _activeItem = 'notary');
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const StaffNotaryManagementScreen(),
            ),
          );
        }
      },
      headerActions: _buildHeroActions(),
    );
  }

  Widget _buildIphoneFloatingNavBar() {
    final navItems = [
      (
        icon: Icons.grid_view_rounded,
        unselectedIcon: Icons.grid_view_outlined,
        label: 'Dashboard',
      ),
      (
        icon: Icons.folder_rounded,
        unselectedIcon: Icons.folder_outlined,
        label: 'Cases',
      ),
      (
        icon: Icons.edit_document,
        unselectedIcon: Icons.edit_document,
        label: 'Draft',
      ),
      (
        icon: Icons.task_alt_rounded,
        unselectedIcon: Icons.task_alt_outlined,
        label: 'Tasks',
      ),
      (
        icon: Icons.calendar_month_rounded,
        unselectedIcon: Icons.calendar_today_outlined,
        label: 'Calendar',
      ),
      (
        icon: Icons.chat_bubble_rounded,
        unselectedIcon: Icons.chat_bubble_outline_rounded,
        label: 'Messages',
      ),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF07152B).withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF07152B).withValues(alpha: 0.45),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: List.generate(navItems.length, (index) {
                  final isSelected = _safeBottomNavIndex == index;
                  final item = navItems[index];
                  final isMessages = index == 5;

                  return _IphoneNavButton(
                    item: item,
                    isSelected: isSelected,
                    isMessages: isMessages,
                    unreadCount: _messageUnreadCount,
                    onTap: () {
                      if (index == 2) {
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (context) =>
                                const StaffCreateCaseDraftScreen(),
                          ),
                        ).then((created) {
                          if (created == true && mounted) {
                            _reloadHomeTab();
                            setState(() => _selectedBottomNavIndex = 0);
                          }
                        });
                      } else {
                        if (_selectedBottomNavIndex != index) {
                          setState(() => _selectedBottomNavIndex = index);
                          if (index == 5) unawaited(_loadMessageUnreadCount());
                        }
                      }
                    },
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: 'Help Center',
            icon: const Icon(
              Icons.help_outline_rounded,
              color: Colors.white,
              size: 19,
            ),
            onPressed: _openHelpCenter,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: _buildNotificationBellIconButton(onNavy: true),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const StaffProfilePage(),
              ),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: StaffUi.gold.withValues(alpha: 0.7),
                width: 1.5,
              ),
            ),
            child: ProfilePictureWidget(
              photoUrl: _currentStaff?.photoUrl,
              userName: _currentStaff?.name ?? 'Staff',
              size: 32,
              isEditable: false,
              onUpdated: _loadUserData,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _tabPrewarmTimer?.cancel();
    _fanoutDeferTimer?.cancel();
    _messageUnreadSub?.cancel();
    if (_sharedBell != null && _sharedBellListener != null) {
      _sharedBell!.removeListener(_sharedBellListener!);
    }
    _bellCount.dispose();
    _appointmentsSub?.cancel();
    HearingNotificationFanoutService.instance.detach();
    CalendarSessionCleanup.onLogout();
    super.dispose();
  }
}

class _IphoneNavButton extends StatefulWidget {
  const _IphoneNavButton({
    required this.item,
    required this.isSelected,
    required this.isMessages,
    required this.unreadCount,
    required this.onTap,
  });

  final ({IconData icon, IconData unselectedIcon, String label}) item;
  final bool isSelected;
  final bool isMessages;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  State<_IphoneNavButton> createState() => _IphoneNavButtonState();
}

class _IphoneNavButtonState extends State<_IphoneNavButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _isPressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? StaffUi.gold.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedScale(
                      scale: widget.isSelected ? 1.08 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        widget.isSelected
                            ? widget.item.icon
                            : widget.item.unselectedIcon,
                        size: 20,
                        color: widget.isSelected
                            ? StaffUi.gold
                            : Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                    if (widget.isMessages && widget.unreadCount > 0)
                      Positioned(
                        right: -7,
                        top: -5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF07152B),
                              width: 1.5,
                            ),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            widget.unreadCount > 99
                                ? '99+'
                                : '${widget.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  style: StaffUi.style(
                    fontSize: 10,
                    fontWeight: widget.isSelected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: widget.isSelected
                        ? StaffUi.gold
                        : Colors.white.withValues(alpha: 0.65),
                    height: 1.1,
                  ),
                  child: Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

