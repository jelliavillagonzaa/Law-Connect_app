import 'dart:async' show StreamSubscription, Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
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
import '../../widgets/common/lazy_indexed_stack.dart';
import '../../widgets/admin/stat_card.dart';
import '../../widgets/attorney/attorney_thin_nav_rail.dart';
import '../../theme/app_theme.dart';
import '../case/case_detail_page.dart';
import '../chat/chat_list_page.dart';
import '../auth/login_page.dart';
import '../../screens/attorney/appointment_calendar_view.dart';

import '../../widgets/attorney/reminders_bell_button.dart';
import '../../widgets/common/app_icon_button.dart';
import '../../pages/attorney/attorney_profile_page.dart';
import '../../pages/attorney/confirm_appointment_schedule_page.dart';
import '../../services/chat_service.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../../screens/attorney/attorney_case_requests_screen.dart';
import '../../screens/attorney/attorney_create_case_screen.dart';
import '../../screens/attorney/attorney_client_chat_screen.dart';
import '../../screens/attorney/attorney_tasks_screen.dart';
import '../../screens/attorney/attorney_create_task_screen.dart';

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

  StreamSubscription<List<CaseModel>>? _casesSub;
  StreamSubscription<List<AppointmentModel>>? _appointmentsSub;
  StreamSubscription? _chatsSub;
  Stream<List<AppointmentModel>>? _sharedAppointmentsStream;
  Timer? _unreadDebounce;
  Timer? _dashboardDebounce;
  Timer? _calendarPrewarmTimer;
  Map<String, dynamic> _stats = {};
  List<CaseModel> _myCases = [];
  // Pending appointment requests from clients (status == 'pending')
  List<AppointmentModel> _allAppointments = [];
  List<AppointmentModel> _pendingRequests = [];
  // Upcoming confirmed/scheduled appointments
  List<AppointmentModel> _upcomingAppointments = [];
  int _unreadCount = 0;
  String _casesSearchQuery = '';

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
      unawaited(_loadUnreadCount());
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty && !kIsWeb) {
        _calendarPrewarmTimer = Timer(const Duration(seconds: 6), () {
          if (!mounted) return;
          final fanout = HearingNotificationFanoutService.instance;
          fanout.attach();
          unawaited(fanout.prepareBellCount(uid));
          fanout.warmInbox(uid);
        });
      }
    });
  }

  @override
  void dispose() {
    _casesSub?.cancel();
    _appointmentsSub?.cancel();
    _unreadDebounce?.cancel();
    _dashboardDebounce?.cancel();
    _calendarPrewarmTimer?.cancel();
    if (!kIsWeb) {
      HearingNotificationFanoutService.instance.detach();
    }
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

  Widget _buildRemindersBellIcon({bool includeMessageCount = false}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Icon(
        Icons.notifications_active,
        color: Colors.white.withValues(alpha: 0.8),
      );
    }

    return RemindersBellButton(
      userId: user.uid,
      messageUnreadCount: _unreadCount,
      includeMessageCount: includeMessageCount,
    );
  }

  Widget _buildMessageIcon() {
    return AppIconButton.appBar(
      icon: Icons.message_outlined,
      tooltip: 'Messages',
      badgeCount: _unreadCount,
      onPressed: () => Get.to(() => const ChatListPage()),
    );
  }

  Future<void> _loadUnreadCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final count = await _chatService.getUnreadCount(user.uid);
      _applyUnreadCount(count);

      await _chatsSub?.cancel();
      _chatsSub = _chatService.getUserChats(user.uid).listen((_) {
        _scheduleUnreadCountRefresh(user.uid);
      });
    } catch (_) {
      // Non-critical; avoid console noise on tab switches.
    }
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && mounted) {
        final userData = userDoc.data()!;
        setState(() {
          _currentUser = UserModel.fromFirestore(userData, user.uid);
          _isAvailable = _currentUser?.isAvailable ?? true;
        });

        // Automatically set user to online when they open the dashboard
        if (!_isAvailable) {
          await _firestore.collection('users').doc(user.uid).update({
            'isAvailable': true,
          });
          if (mounted) {
            setState(() {
              _isAvailable = true;
            });
          }
        }
      }
    } catch (_) {
      // Non-critical; avoid console noise on tab switches.
    }
  }

  Future<void> _loadDashboardData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      // Load cases and appointments
      final casesStream = _caseService.getCasesForUser(user.uid, 'attorney');
      _sharedAppointmentsStream ??= _appointmentService.getAttorneyAppointments(
        user.uid,
      );
      final appointmentsStream = _sharedAppointmentsStream!;

      await _casesSub?.cancel();
      _casesSub = casesStream.listen(
        (cases) {
          if (!mounted) return;
          _myCases = cases;
          _stats = _computeStats();
          _scheduleDashboardRebuild();
        },
        onError: (_) {},
      );

      await _appointmentsSub?.cancel();
      _appointmentsSub = appointmentsStream.listen(
        (appointments) {
          if (!mounted) return;
          final now = DateTime.now();
          _allAppointments = appointments;
          _pendingRequests = appointments
              .where((apt) => apt.status.toLowerCase() == 'pending')
              .toList();
          _upcomingAppointments = appointments
              .where(
                (apt) =>
                    apt.status.toLowerCase() != 'pending' &&
                    apt.appointmentDateTime.isAfter(now),
              )
              .take(5)
              .toList();
          _stats = _computeStats();
          _scheduleDashboardRebuild();
        },
        onError: (_) {},
      );
    } catch (_) {
      // Streams will retry via Firestore; keep UI responsive.
    }
  }

  void _scheduleDashboardRebuild() {
    _dashboardDebounce?.cancel();
    _dashboardDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _scheduleUnreadCountRefresh(String userId) {
    _unreadDebounce?.cancel();
    _unreadDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      try {
        final next = await _chatService.getUnreadCount(userId);
        _applyUnreadCount(next);
      } catch (_) {}
    });
  }

  void _applyUnreadCount(int count) {
    if (!mounted || _unreadCount == count) return;
    setState(() => _unreadCount = count);
  }

  Map<String, dynamic> _computeStats() {
    final totalCases = _myCases.length;
    final activeCases = _myCases
        .where((c) => c.status == 'in_progress' || c.status == 'active')
        .length;
    final completedCases = _myCases
        .where((c) => c.status == 'completed')
        .length;
    return {
      'totalCases': totalCases,
      'activeCases': activeCases,
      'completedCases': completedCases,
      'pendingCases': _pendingRequests.length,
      'upcomingAppointments': _upcomingAppointments.length,
    };
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

  void _handleItemSelected(String item) {
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
        Get.to(() => const ChatListPage());
        return;
    }

    int? bottomIndex;
    switch (item) {
      case 'cases':
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
      case 'settings':
        bottomIndex = 5;
        break;
    }

    setState(() {
      _activeItem = item;
      if (bottomIndex != null) {
        _selectedBottomNavIndex = bottomIndex;
      }
    });
  }

  int _desktopTabIndex() {
    switch (_activeItem) {
      case 'cases':
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
              // No drawer on mobile anymore, so no menu button
              automaticallyImplyLeading: false,
              title: Text(
                _currentUser?.fullName ?? _currentUser?.name ?? 'Attorney',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              backgroundColor: AppTheme.royalBlue,
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                _buildRemindersBellIcon(),
                _buildMessageIcon(),
              ],
            )
          : null,
      body: Row(
        children: [
          // Thin Navigation Rail - Desktop only (Web optimized)
          if (isDesktop)
            AttorneyThinNavRail(
              activeItem: _activeItem,
              onItemSelected: _handleItemSelected,
              onLogout: _handleLogout,
              isAvailable: _isAvailable,
              onAvailabilityChanged: (value) => _toggleAvailability(),
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
                        Row(
                          children: [
                            _buildRemindersBellIcon(includeMessageCount: true),
                            const SizedBox(width: 8),
                            _buildMessageIcon(),
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
                      _buildBottomNavItem(Icons.settings, 'Settings', 5),
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
          () => const AttorneyProfilePage(embedded: true),
        ],
      );
    }

    final attorneyId = FirebaseAuth.instance.currentUser?.uid ?? '';
    return LazyIndexedStack(
      key: _desktopTabStackKey,
      index: _desktopTabIndex(),
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
          // Header
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
                Expanded(
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
                      const SizedBox(height: 4),
                      Text(
                        'Manage your cases and appointments',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Stats Grid
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
              ),
              StatCard(
                title: 'Active Cases',
                value: '${_stats['activeCases'] ?? 0}',
                description: 'In progress',
                icon: Icons.work_outline,
                iconColor: const Color(0xFF48BB78),
                percentageChange: '+1.2%',
              ),
              StatCard(
                title: 'Completed Cases',
                value: '${_stats['completedCases'] ?? 0}',
                description: 'Finished cases',
                icon: Icons.check_circle_outline,
                iconColor: const Color(0xFFED8936),
                percentageChange: '+0.8%',
              ),
              StatCard(
                title: 'Pending Requests',
                value: '${_stats['pendingCases'] ?? 0}',
                description: 'Appointment requests',
                icon: Icons.pending_outlined,
                iconColor: const Color(0xFFF56565),
                isPositiveChange: false,
                percentageChange: '-2.1%',
              ),
              StatCard(
                title: 'Upcoming Appointments',
                value: '${_stats['upcomingAppointments'] ?? 0}',
                description: 'Scheduled meetings',
                icon: Icons.calendar_today_outlined,
                iconColor: const Color(0xFF764BA2),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Create Case Button (below dashboard stats)
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
                        builder: (context) => const AttorneyCreateCaseScreen(),
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
                        if (kDebugMode) debugPrint('Navigation error: $error');
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
        ],
      ),
    );
  }

  Widget _buildUpcomingAppointmentsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Soft blue-tinted card to match dashboard background/theme
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
          if (_upcomingAppointments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No upcoming appointments',
                style: TextStyle(fontSize: 14, color: const Color(0xFF6D6D6D)),
              ),
            )
          else
            ..._upcomingAppointments.take(5).map((appointment) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.royalBlue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.event_available,
                        color: AppTheme.royalBlue,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat(
                              'MMM dd, yyyy – hh:mm a',
                            ).format(appointment.appointmentDateTime),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Client: ${appointment.clientName}',
                            style: TextStyle(
                              fontSize: 12,
                              color: const Color(0xFF6D6D6D),
                            ),
                          ),
                          if (appointment.caseTitle != null &&
                              appointment.caseTitle!.trim().isNotEmpty)
                            Text(
                              appointment.caseTitle!,
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xFF6D6D6D),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildPendingRequestsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Soft red-tinted card to match pending stats card styling
        color: const Color(0xFFFFF5F5),
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

    return StreamBuilder<List<CaseModel>>(
      stream: _caseService.getCasesForUser(user.uid, 'attorney'),
      builder: (context, snapshot) {
        final List<CaseModel> cases =
            snapshot.data ?? List<CaseModel>.from(_myCases);
        if (snapshot.hasError && cases.isEmpty) {
          return _mobileTabShell(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
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
        final filteredCases = cases.where((c) {
          if (_casesSearchQuery.isEmpty) return true;
          return c.caseTitle.toLowerCase().contains(
            _casesSearchQuery.toLowerCase(),
          );
        }).toList();

        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search cases by title...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (value) {
                    setState(() => _casesSearchQuery = value);
                  },
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
                            _casesSearchQuery.isNotEmpty
                                ? 'No cases match your search'
                                : 'No cases yet',
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
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CaseCard(
                          caseModel: filteredCases[index],
                          onTap: () {
                            Get.to(
                              () => CaseDetailPage(
                                caseId: filteredCases[index].id,
                              ),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search cases by title...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: (value) {
                  setState(() {
                    _casesSearchQuery = value;
                  });
                },
              ),
            ),
            if (filteredCases.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.folder_open,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _casesSearchQuery.isNotEmpty
                            ? 'No pending cases match your search'
                            : 'No requested cases yet',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
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
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.4, // Making cards less tall
                        ),
                    itemCount: filteredCases.length,
                    itemBuilder: (context, index) {
                      return CaseCard(
                        caseModel: filteredCases[index],
                        onTap: () {
                          Get.to(
                            () =>
                                CaseDetailPage(caseId: filteredCases[index].id),
                          );
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
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.25),
              const Icon(Icons.pending_actions, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'No pending requests',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ),
            ],
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
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.2,
              ),
              itemCount: displayPending.length,
              itemBuilder: (context, index) {
                final appointment = displayPending[index];
                return _buildPendingRequestCard(appointment);
              },
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
        return 'settings';
      default:
        return 'dashboard';
    }
  }

  Widget _buildBottomNavItem(IconData icon, String label, int index) {
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
          },
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 64,
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 24,
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
          padding: const EdgeInsets.all(16),
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
              const SizedBox(height: 12),
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
                ? AppTheme.royalBlue.withOpacity(0.1)
                : (_isHovered
                      ? AppTheme.royalBlue.withOpacity(0.05)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: widget.isActive
                ? Border.all(
                    color: AppTheme.royalBlue.withOpacity(0.3),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: widget.isActive
                    ? AppTheme.royalBlue
                    : (_isHovered
                          ? AppTheme.royalBlue.withOpacity(0.7)
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
                      ? AppTheme.royalBlue
                      : (_isHovered
                            ? AppTheme.royalBlue.withOpacity(0.8)
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
