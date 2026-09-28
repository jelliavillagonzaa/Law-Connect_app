import 'dart:async' show StreamSubscription, Timer, unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
import '../../screens/billing/billing_management_screen.dart';
import '../../screens/attorney/attorney_notary_requests_screen.dart';

import '../../pages/staff/staff_profile_page.dart';
import 'staff_dashboard_home_tab.dart';
import '../../widgets/common/lazy_indexed_stack.dart';
import '../../widgets/common/nav_unread_dot.dart';
import '../../widgets/common/profile_picture_widget.dart';
import '../../widgets/staff/staff_nav_rail.dart';
import '../../widgets/staff/staff_ui_theme.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../../services/lightweight_reminders_inbox_service.dart';
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _bellNotifSub;
  int _bellBadgeCount = 0;

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
      (count) {
        if (mounted && count != _messageUnreadCount) {
          setState(() => _messageUnreadCount = count);
        }
      },
      onError: (_) {},
    );
  }

  void _attachBellWatcher() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _bellNotifSub?.cancel();
    _bellNotifSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .limit(60)
        .snapshots()
        .listen(
      (snap) {
        final count =
            LightweightRemindersInboxService.unreadCountFromNotificationDocs(
          snap.docs,
        );
        if (mounted && count != _bellBadgeCount) {
          setState(() => _bellBadgeCount = count);
        }
      },
      onError: (_) {
        unawaited(_refreshBellBadge());
      },
    );
  }

  /// Returns false when the user is signed out or redirected away.
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
      Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        unawaited(_loadMessageUnreadCount());
      });
      Timer(const Duration(seconds: 6), () {
        if (!mounted) return;
        unawaited(_refreshBellBadge());
      });
    } else {
      Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        unawaited(_loadMessageUnreadCount());
        unawaited(_refreshBellBadge());
      });
    }

    // Web: defer calendar prewarm â€” opening it on dashboard load causes jank.
    if (kIsWeb) {
      Timer(const Duration(seconds: 12), () {
        if (!mounted) return;
        _mobileTabStackKey.currentState?.prewarm(3);
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
      final count =
          await LightweightRemindersInboxService.countUnreadReminders(uid);
      if (mounted && count != _bellBadgeCount) {
        setState(() => _bellBadgeCount = count);
      }
    } catch (_) {}
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _firestoreGet(
    Query<Map<String, dynamic>> query,
    int limit,
  ) async {
    final q = query.limit(limit);
    if (kIsWeb) return q.get();
    try {
      return await q.get(const GetOptions(source: Source.server));
    } catch (_) {
      return q.get();
    }
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

    final staff = await _staffAuthService.getCurrentStaff();
    if (staff != null) {
      if (!mounted) return;
      setState(() {
        _currentStaff = staff;
        _assignedAttorneyId = staff.assignedAttorneyId;
      });
      _attachSharedAppointmentsStream(staff.assignedAttorneyId);
      return;
    }

    try {
      final userDoc = await _firestoreGetDoc(
        FirebaseFirestore.instance.collection('users').doc(user.uid),
      );
      if (!userDoc.exists || !mounted) return;
      final data = userDoc.data() ?? {};
      final attorneyId = (data['assignedAttorneyId'] as String?)?.trim() ?? '';
      final name = (data['name'] as String?)?.trim();
      setState(() {
        if (attorneyId.isNotEmpty) _assignedAttorneyId = attorneyId;
        if (name != null && name.isNotEmpty && _currentStaff == null) {
          _currentStaff = StaffModel(
            id: user.uid,
            name: name,
            email: (data['email'] as String?) ?? user.email ?? '',
            assignedAttorneyId: attorneyId,
            createdAt: DateTime.now(),
          );
        }
      });
      if (attorneyId.isNotEmpty) _attachSharedAppointmentsStream(attorneyId);
    } catch (_) {}
  }

  void _attachSharedAppointmentsStream(String? attorneyId) {
    final aid = attorneyId?.trim() ?? '';
    if (aid.isEmpty) return;

    _sharedAppointmentsStream ??=
        _appointmentService.getAttorneyAppointments(aid);
    final stream = _sharedAppointmentsStream!;

    _appointmentsSub?.cancel();
    _appointmentsSub = stream.listen(
      (appointments) {
        if (!mounted) return;
        _allAppointments = appointments;
      },
      onError: (_) {},
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

  void _openBilling() {
    final attorneyId = _assignedAttorneyId;
    if (attorneyId == null || attorneyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No assigned attorney to view billing for.'),
        ),
      );
      return;
    }
    Get.to(
      () => BillingManagementScreen(
        attorneyId: attorneyId,
        title: 'Billing & Payments',
        recorderRole: 'staff',
        recorderName: FirebaseAuth.instance.currentUser?.displayName,
      ),
    );
  }

  void _openNotary({bool push = false}) {
    final attorneyId = _assignedAttorneyId;
    if (attorneyId == null || attorneyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No assigned attorney. Ask admin to link your account.',
          ),
        ),
      );
      return;
    }
    if (push) {
      Get.to(
        () => AttorneyNotaryRequestsScreen(
          staffAssignedAttorneyId: attorneyId,
        ),
      );
      return;
    }
    setState(() => _activeItem = 'notary');
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

    final unreadCount = _safeInt(_bellBadgeCount);
    final showBadge = unreadCount > 0;
    final labelText =
        unreadCount > 99 ? '99+' : unreadCount > 9 ? '9+' : '$unreadCount';

    return IconButton(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.notifications_active,
            color: onNavy ? Colors.white : null,
          ),
          if (showBadge)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  labelText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
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
      tooltip: showBadge
          ? 'Notifications ($unreadCount unread)'
          : 'Notifications',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    if (!isDesktop) {
      return Scaffold(
        drawer: _buildMobileDrawer(),
        body: _safeBottomNavIndex == 0
            ? SafeArea(bottom: false, child: _buildContent())
            : _buildContent(),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _safeBottomNavIndex,
          onTap: (index) {
            if (index == 2) {
              // Navigate to create draft screen instead of showing it directly
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StaffCreateCaseDraftScreen(),
                ),
              ).then((created) {
                if (created == true && mounted) {
                  _reloadHomeTab();
                  setState(() => _selectedBottomNavIndex = 0);
                }
              });
            } else {
              setState(() => _selectedBottomNavIndex = index);
              if (index == 5) unawaited(_loadMessageUnreadCount());
            }
          },
          type: BottomNavigationBarType.fixed,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            const BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Cases'),
            const BottomNavigationBarItem(
              icon: Icon(Icons.edit_document),
              label: 'Draft',
            ),
            const BottomNavigationBarItem(icon: Icon(Icons.task), label: 'Tasks'),
            const BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today),
              label: 'Calendar',
            ),
            BottomNavigationBarItem(
              icon: _navIconWithBadge(
                Icons.message,
                badge: _messageUnreadCount,
              ),
              label: 'Messages',
            ),
          ],
        ),
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
    if (item == 'billing') {
      _openBilling();
    } else if (item == 'draft_cases') {
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
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: AppTheme.royalBlue),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ProfilePictureWidget(
                  photoUrl: _currentStaff?.photoUrl,
                  userName: _currentStaff?.name ?? 'Staff',
                  size: 60,
                  isEditable: false,
                  onUpdated: () {
                    // Reload staff data when profile picture is updated
                    _loadUserData();
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  _currentStaff?.name ?? 'Staff Member',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.cleanWhite,
                  ),
                ),
                Text(
                  'Paralegal / Legal Assistant',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.cleanWhite.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 0);
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('Cases'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 1);
            },
          ),
          ListTile(
            leading: const Icon(Icons.task),
            title: const Text('Tasks'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 3);
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Calendar'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 4);
            },
          ),

          ListTile(
            leading: const Icon(Icons.draw_outlined),
            title: const Text('Notary'),
            onTap: () {
              Navigator.pop(context);
              _openNotary(push: true);
            },
          ),
          ListTile(
            leading: _navIconWithBadge(
              Icons.message,
              badge: _messageUnreadCount,
            ),
            title: const Text('Messages'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 5);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
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
      case 'tasks':
        return 3;
      case 'clients':
        return 4;
      case 'calendar':
        return 5;
      case 'communication':
        return 6;
      case 'reports':
        return 7;
      case 'profile':
        return 8;
      case 'notary':
        return 9;
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
                ? 'staff_calendar_${_assignedAttorneyId ?? 'none'}'
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
          : desktopIndex == 5
              ? 'staff_calendar_${_assignedAttorneyId ?? 'none'}'
              : desktopIndex == 9
                  ? 'staff_notary_${_assignedAttorneyId ?? 'none'}'
                  : 'desktop_tab_$desktopIndex',
      builders: [
        () => _buildDashboardView(),
        () => const StaffCasesScreen(),
        () => const StaffCasesScreen(closedFolder: true),
        () => const StaffTasksScreen(),
        () => const StaffClientsScreen(),
        () => _buildStaffCalendarTab(),
        () => const StaffCommunicationScreen(),
        () => const StaffReportsScreen(),
        () => const StaffProfilePage(),
        () => AttorneyNotaryRequestsScreen(
          embedded: true,
          staffAssignedAttorneyId: _assignedAttorneyId ?? '',
        ),
      ],
    );

    return Column(
      children: [
        if (_activeItem != 'dashboard')
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Spacer(),
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

  Widget _buildDashboardView() {
    return StaffDashboardHomeTab(
      key: _homeTabKey,
      staffName: _currentStaff?.name ?? 'Staff',
      assignedAttorneyId: _assignedAttorneyId,
      onNavigateToCases: () => setState(() => _activeItem = 'cases'),
      headerActions: _buildHeroActions(),
    );
  }

  Widget _buildHeroActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildNotificationBellIconButton(onNavy: true),
        const SizedBox(width: 4),
        InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const StaffProfilePage(),
              ),
            );
          },
          borderRadius: BorderRadius.circular(24),
          child: Row(
            children: [
              ProfilePictureWidget(
                photoUrl: _currentStaff?.photoUrl,
                userName: _currentStaff?.name ?? 'Staff',
                size: 36,
                isEditable: false,
                onUpdated: _loadUserData,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentStaff?.name ?? 'APAOStaff',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Legal Assistant',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
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
    _bellNotifSub?.cancel();
    _appointmentsSub?.cancel();
    HearingNotificationFanoutService.instance.detach();
    CalendarSessionCleanup.onLogout();
    super.dispose();
  }
}
