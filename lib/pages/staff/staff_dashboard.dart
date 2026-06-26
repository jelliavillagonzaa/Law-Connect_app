import 'dart:async' show StreamSubscription, Timer, unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/staff_service.dart';
import '../../services/task_service.dart';
import '../../services/chat_service.dart';
import '../../services/staff_auth_service.dart';
import '../../models/staff_model.dart';
import '../../models/task_model.dart';
import '../../models/case_model.dart';
import '../../widgets/admin/stat_card.dart';
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

import '../../screens/client/chat_screen.dart';
import '../../pages/staff/staff_profile_page.dart';
import '../../widgets/common/lazy_indexed_stack.dart';
import '../../widgets/common/profile_picture_widget.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../../services/lightweight_reminders_inbox_service.dart';
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
  Timer? _tabPrewarmTimer;
  Timer? _fanoutDeferTimer;
  bool _dashboardStreamsAttached = false;
  StreamSubscription<List<TaskModel>>? _tasksSub;
  StreamSubscription<List<CaseModel>>? _assignedCasesSub;
  StreamSubscription<List<CaseModel>>? _attorneyCasesSub;
  int _bellBadgeCount = 0;

  final StaffService _staffService = StaffService();
  final TaskService _taskService = TaskService();
  final ChatService _chatService = ChatService();
  final StaffAuthService _staffAuthService = StaffAuthService();

  StaffModel? _currentStaff;
  String? _assignedAttorneyId;
  String _activeItem = 'dashboard';
  int _selectedBottomNavIndex = 0;
  int _messageUnreadCount = 0;
  bool _snapshotLoading = false;
  bool _snapshotRefreshQueued = false;
  bool _dashboardSnapshotRetried = false;

  static const int _bottomNavItemCount = 6;

  /// Web hot reload can leave int fields null at runtime — coerce before math/UI.
  static int _safeInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }

  int get _safeBottomNavIndex =>
      _safeInt(_selectedBottomNavIndex).clamp(0, _bottomNavItemCount - 1);

  Object get _dashboardTabRevision => Object.hash(
        _myTasks.length,
        _stats['totalTasks'],
        _stats['pendingTasks'],
        _stats['inProgressTasks'],
        _stats['activeCases'],
        _stats['completedTasks'],
        _stats['upcomingDeadlines'],
        _assignedCases.length,
        _hearingNotifications.length,
        _upcomingDeadlines.length,
      );

  Map<String, dynamic> _stats = {};
  List<TaskModel> _myTasks = [];
  List<CaseModel> _assignedCases = [];
  List<Map<String, dynamic>> _upcomingDeadlines = [];
  List<Map<String, dynamic>> _hearingNotifications = [];

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

    final ok = await _verifyAccountAndBootstrap(user);
    if (!ok || !mounted) return;

    await _loadUserData();
    if (!mounted) return;

    _loadDashboardData();

    await _refreshDashboardSnapshot();
    if (!mounted) return;

    await _loadDashboardPreviewData();
    if (!mounted) return;

    unawaited(_loadMessageUnreadCount());
    unawaited(_refreshBellBadge());
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
      await _runDeferredBootstrap(user.uid, email, data);
      return true;
    }

    // Transient/offline verify failure — still warm secondary dashboard data.
    if (!mounted) return false;
    await _runDeferredBootstrap(user.uid, user.email ?? '', const {});
    return true;
  }

  /// Auth repair + deferred warmup (bell badge, tab prewarm).
  Future<void> _runDeferredBootstrap(
    String uid,
    String email,
    Map<String, dynamic> data,
  ) async {
    try {
      await AuthService().syncStaffRoleFromStaffApplication(uid: uid, email: email);
      await AuthService().repairPortalRoleIfNeeded(
        uid: uid,
        email: email,
        firestoreRole: data['role'] as String?,
      );
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
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

    // Web: defer calendar prewarm — opening it on dashboard load causes jank.
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
      var count =
          await LightweightRemindersInboxService.countUnreadReminders(uid);

      try {
        final snap = await FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: uid)
            .limit(60)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final fsType = (data['type'] as String? ?? '').toLowerCase();
          if (fsType == 'court_email_ingest' || fsType.startsWith('court_')) {
            continue;
          }
          if (hearingOrAppointmentBellType(fsType)) continue;
          if (data['isRead'] == true) continue;
          count++;
        }
      } catch (_) {}

      try {
        final taskSnap = await _firestoreGet(
          FirebaseFirestore.instance
              .collection('tasks')
              .where('assignedTo', isEqualTo: uid),
          30,
        );
        count += taskSnap.docs.where((d) {
          final status = (d.data()['status'] as String?)?.toLowerCase().trim();
          return status == 'pending';
        }).length;
      } catch (_) {}

      if (mounted && count != _bellBadgeCount) {
        setState(() => _bellBadgeCount = count);
      }
    } catch (_) {}
  }

  Future<void> _refreshDashboardSnapshot() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_snapshotLoading) {
      _snapshotRefreshQueued = true;
      return;
    }
    _snapshotLoading = true;

    var tasks = <TaskModel>[];
    var cases = <CaseModel>[];
    var attorneyId = _assignedAttorneyId?.trim() ?? '';

    try {
      try {
        await user.getIdToken(true);
      } catch (_) {}

      if (attorneyId.isEmpty) {
        try {
          final userDoc = await _firestoreGetDoc(
            FirebaseFirestore.instance.collection('users').doc(user.uid),
          );
          attorneyId =
              (userDoc.data()?['assignedAttorneyId'] as String?)?.trim() ?? '';
          if (attorneyId.isNotEmpty && mounted) {
            _assignedAttorneyId = attorneyId;
          }
        } catch (_) {}
      }

      try {
        final taskSnap = await _firestoreGet(
          FirebaseFirestore.instance
              .collection('tasks')
              .where('assignedTo', isEqualTo: user.uid),
          60,
        );
        tasks = taskSnap.docs
            .map((doc) => TaskModel.fromFirestore(doc))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } catch (_) {}

      try {
        final assignedSnap = await _firestoreGet(
          FirebaseFirestore.instance
              .collection('cases')
              .where('staffAssigned', arrayContains: user.uid),
          60,
        );
        cases = assignedSnap.docs
            .map((doc) => CaseModel.fromFirestore(doc))
            .toList();
      } catch (_) {}

      if (cases.isEmpty && attorneyId.isNotEmpty) {
        try {
          final attorneySnap = await _firestoreGet(
            FirebaseFirestore.instance
                .collection('cases')
                .where('attorneyId', isEqualTo: attorneyId),
            60,
          );
          cases = attorneySnap.docs
              .map((doc) => CaseModel.fromFirestore(doc))
              .toList();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        if (tasks.isNotEmpty) {
          _myTasks = tasks;
        }
        if (cases.isNotEmpty) {
          _assignedCases = cases
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
        _stats = _computeStats();
      });

      if (attorneyId.isNotEmpty && _attorneyCasesSub == null) {
        _subscribeCaseStreams(user.uid);
      }

      if (tasks.isEmpty &&
          cases.isEmpty &&
          !_dashboardSnapshotRetried) {
        _dashboardSnapshotRetried = true;
        Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          unawaited(_refreshDashboardSnapshot());
        });
      }
    } finally {
      _snapshotLoading = false;
      if (_snapshotRefreshQueued) {
        _snapshotRefreshQueued = false;
        unawaited(_refreshDashboardSnapshot());
      }
    }
  }

  Future<void> _handleDashboardRefresh() async {
    _dashboardSnapshotRetried = false;
    await _loadUserData();
    if (!mounted) return;
    await _refreshDashboardSnapshot();
    if (!mounted) return;
    await _loadDashboardPreviewData();
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

  void _subscribeCaseStreams(String staffId) {
    _assignedCasesSub?.cancel();
    _assignedCasesSub = _staffService.getAssignedCases(staffId).listen(
      (cases) {
        if (!mounted) return;
        if (cases.isNotEmpty) {
          setState(() {
            _assignedCases = cases;
            _stats = _computeStats();
          });
        }
      },
      onError: (_) => unawaited(_refreshDashboardSnapshot()),
    );

    final attorneyId = _assignedAttorneyId?.trim() ?? '';
    _attorneyCasesSub?.cancel();
    _attorneyCasesSub = null;
    if (attorneyId.isEmpty) return;

    _attorneyCasesSub = _staffService.getAttorneyCases(attorneyId).listen(
      (cases) {
        if (!mounted) return;
        setState(() {
          _assignedCases = cases;
          _stats = _computeStats();
        });
      },
      onError: (_) {},
    );
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
    } catch (_) {}
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

  Future<void> _openChatWithAttorney() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening chat...'),
          duration: Duration(milliseconds: 600),
        ),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Get.snackbar(
        'Error',
        'You must be logged in to send messages',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    if (_assignedAttorneyId == null || _assignedAttorneyId!.isEmpty) {
      Get.snackbar(
        'No Attorney Assigned',
        'You are not assigned to an attorney yet',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    try {
      // Get attorney info
      final attorneyDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_assignedAttorneyId!)
          .get();

      if (!attorneyDoc.exists) {
        Get.snackbar(
          'Error',
          'Attorney not found',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      final attorneyData = attorneyDoc.data()!;
      final attorneyName =
          attorneyData['fullName'] ?? attorneyData['name'] ?? 'Attorney';

      // Create or get chat with attorney
      final chatId = await _chatService.getOrCreateChat(
        user.uid,
        _assignedAttorneyId!,
      );

      // Navigate to chat
      Get.to(
        () => ChatScreen(
          conversationId: chatId,
          otherUserId: _assignedAttorneyId!,
          otherUserName: attorneyName,
        ),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to open chat: ${e.toString()}',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    }
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
    final safeBadge = _safeInt(badge);
    if (safeBadge <= 0) return Icon(icon);
    final label = safeBadge > 99 ? '99+' : safeBadge > 9 ? '9+' : '$safeBadge';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -8,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  void _loadDashboardData() {
    if (_dashboardStreamsAttached) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _dashboardStreamsAttached = true;

    _tasksSub = _taskService.getStaffTasks(user.uid).listen(
      (tasks) {
        if (!mounted) return;
        setState(() {
          _myTasks = tasks;
          _stats = _computeStats();
        });
      },
      onError: (_) => unawaited(_refreshDashboardSnapshot()),
    );

    _subscribeCaseStreams(user.uid);
  }

  /// One-shot preview for dashboard cards — not a live duplicate of calendar streams.
  Future<void> _loadDashboardPreviewData() async {
    final attorneyId = _assignedAttorneyId;
    if (attorneyId == null || !mounted) return;

    try {
      final now = DateTime.now();
      final deadlinesSnap = await FirebaseFirestore.instance
          .collection('calendar_events')
          .where('assignedTo', isEqualTo: attorneyId)
          .where('eventDate', isGreaterThan: Timestamp.fromDate(now))
          .orderBy('eventDate')
          .limit(5)
          .get();

      final hearingSnap = await FirebaseFirestore.instance
          .collection('hearing_notifications')
          .where('attorneyId', isEqualTo: attorneyId)
          .where('status', isEqualTo: 'pending')
          .limit(15)
          .get();

      final twoDays = now.add(const Duration(days: 2));
      final hearings = hearingSnap.docs
          .map((doc) {
            final data = doc.data();
            return <String, dynamic>{
              'id': doc.id,
              ...data,
              'hearingDate': (data['hearingDate'] as Timestamp?)?.toDate(),
              'notificationDate':
                  (data['notificationDate'] as Timestamp?)?.toDate(),
            };
          })
          .where((n) {
            final d = n['notificationDate'] as DateTime?;
            return d != null &&
                d.isAfter(now.subtract(const Duration(days: 1))) &&
                d.isBefore(twoDays.add(const Duration(days: 1)));
          })
          .toList();

      if (!mounted) return;
      setState(() {
        _upcomingDeadlines = deadlinesSnap.docs.map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            'id': doc.id,
            ...data,
            'eventDate': (data['eventDate'] as Timestamp?)?.toDate(),
          };
        }).toList();
        _hearingNotifications = hearings;
      });
    } catch (_) {}
  }

  Map<String, dynamic> _computeStats() {
    bool isPending(String status) =>
        status.toLowerCase().trim() == 'pending';
    bool isInProgress(String status) {
      final s = status.toLowerCase().trim();
      return s == 'in_progress' || s == 'in progress';
    }
    bool isCompleted(String status) {
      final s = status.toLowerCase().trim();
      return s == 'completed' || s == 'done';
    }
    bool isActiveCase(String status) {
      final s = status.toLowerCase().trim();
      return s == 'in_progress' ||
          s == 'in progress' ||
          s == 'accepted' ||
          s == 'active';
    }

    return {
      'totalTasks': _myTasks.length,
      'pendingTasks': _myTasks.where((t) => isPending(t.status)).length,
      'inProgressTasks': _myTasks.where((t) => isInProgress(t.status)).length,
      'completedTasks': _myTasks.where((t) => isCompleted(t.status)).length,
      'activeCases': _assignedCases.where((c) => isActiveCase(c.status)).length,
      'upcomingDeadlines': _upcomingDeadlines.length,
    };
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
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Get.offAll(() => const LoginPage());
      }
    }
  }

  /// Bell in AppBar: unread count from Firestore `notifications` (matches notification inbox).
  Widget _buildNotificationBellIconButton() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return IconButton(
        icon: const Icon(Icons.notifications_active),
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
          const Icon(Icons.notifications_active),
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
        appBar: AppBar(
          title: const Text(''),
          automaticallyImplyLeading: false,
          actions: [
            _buildNotificationBellIconButton(),
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const StaffProfilePage(),
                  ),
                );
              },
              tooltip: 'Profile',
            ),
          ],
        ),
        body: _buildContent(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const StaffCreateCaseDraftScreen(),
              ),
            ).then((created) {
              if (created == true) {
                _loadDashboardData(); // Refresh dashboard
                // Reset to dashboard view after successful creation
                if (mounted) {
                  setState(() {
                    _selectedBottomNavIndex = 0;
                    _activeItem = 'dashboard';
                  });
                }
              }
            });
          },
          backgroundColor: AppTheme.royalBlue,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.edit_document),
          label: const Text('Create Draft'),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
                  _loadDashboardData();
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
        appBar: AppBar(
          title: const Text(''),
          automaticallyImplyLeading: false,
          actions: [
            _buildNotificationBellIconButton(),
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const StaffProfilePage(),
                  ),
                );
              },
              tooltip: 'Profile',
            ),
          ],
        ),
        body: Row(
          children: [
            _buildSidebar(),
            Expanded(child: _buildContent()),
          ],
        ),
      );
    }
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      color: AppTheme.deepNavy,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
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
                  textAlign: TextAlign.center,
                ),
                Text(
                  'Paralegal / Legal Assistant',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.cleanWhite.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: ListView(
              children: [
                _buildSidebarItem('dashboard', 'Dashboard', Icons.dashboard),
                _buildSidebarItem('cases', 'Cases', Icons.folder),
                _buildSidebarItem(
                  'draft_cases',
                  'Create Draft Case',
                  Icons.edit_document,
                ),
                _buildSidebarItem('tasks', 'Tasks', Icons.task),
                _buildSidebarItem('clients', 'Clients', Icons.people),
                _buildSidebarItem('calendar', 'Calendar', Icons.calendar_today),
                _buildSidebarItem(
                  'billing',
                  'Billing & Payments',
                  Icons.account_balance_wallet,
                ),

                _buildSidebarItem(
                  'communication',
                  'Messages',
                  Icons.message,
                  badge: _safeInt(_messageUnreadCount),
                ),
                _buildSidebarItem(
                  'reports',
                  'Reports & Logs',
                  Icons.assessment,
                ),
                _buildSidebarItem('profile', 'Profile', Icons.person),
              ],
              // Add Create Draft Case button at the bottom of sidebar
              // This will be added after the list
            ),
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white70),
            title: Text('Logout', style: TextStyle(color: Colors.white70)),
            onTap: _handleLogout,
          ),
        ],
      ),
    );
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
            leading: Stack(
              children: [
                const Icon(Icons.message),
                if (_safeInt(_messageUnreadCount) > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(


                        '${_safeInt(_messageUnreadCount) > 9 ? '9+' : _safeInt(_messageUnreadCount)}',
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
            title: const Text('Messages'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 5);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profile'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StaffProfilePage(),
                ),
              );
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

  Widget _buildSidebarItem(
    String item,
    String label,
    IconData icon, {
    int badge = 0,
  }) {
    final safeBadge = _safeInt(badge);
    final isActive = _activeItem == item;
    return ListTile(
      leading: Stack(
        children: [
          Icon(icon, color: isActive ? AppTheme.gold : Colors.white70),
          if (safeBadge > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  '${safeBadge > 9 ? '9+' : safeBadge}',
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
      title: Text(
        label,
        style: TextStyle(
          color: isActive ? AppTheme.gold : Colors.white70,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isActive,
      selectedTileColor: Colors.white.withOpacity(0.1),
      onTap: () {
        if (item == 'billing') {
          _openBilling();
        } else if (item == 'draft_cases') {
          // Navigate to create draft case screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const StaffCreateCaseDraftScreen(),
            ),
          ).then((created) {
            if (created == true) {
              _loadDashboardData(); // Refresh dashboard
              // Reset to dashboard view after successful creation
              if (mounted) {
                setState(() {
                  _selectedBottomNavIndex = 0;
                  _activeItem = 'dashboard';
                });
              }
            }
          });
        } else {
          setState(() => _activeItem = item);
        }
      },
    );
  }

  int _desktopTabIndex() {
    switch (_activeItem) {
      case 'cases':
        return 1;
      case 'tasks':
        return 2;
      case 'clients':
        return 3;
      case 'calendar':
        return 4;
      case 'communication':
        return 5;
      case 'reports':
        return 6;
      case 'profile':
        return 7;
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
        activeTabRevision: _dashboardTabRevision,
        builders: [
          () => _buildDashboardView(),
          () => const StaffCasesScreen(),
          () => const SizedBox.shrink(),
          () => const StaffTasksScreen(),
          () => const StaffCalendarScreen(),
          () => const StaffCommunicationScreen(),
        ],
      );
    }

    return LazyIndexedStack(
      key: _desktopTabStackKey,
      index: _desktopTabIndex(),
      activeTabRevision: _dashboardTabRevision,
      builders: [
        () => _buildDashboardView(),
        () => const StaffCasesScreen(),
        () => const StaffTasksScreen(),
        () => const StaffClientsScreen(),
        () => const StaffCalendarScreen(),
        () => const StaffCommunicationScreen(),
        () => const StaffReportsScreen(),
        () => const StaffProfilePage(),
      ],
    );
  }

  Widget _buildDashboardView() {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    final crossAxisCount = isDesktop ? 4 : 2;

    return RefreshIndicator(
      onRefresh: _handleDashboardRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dark Blue Header Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.deepNavy,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${_currentStaff?.name ?? 'Staff'}!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.cleanWhite,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Here\'s your overview for today',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.cleanWhite.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          // Content Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // Hearing Notifications (2 days before)
                if (_hearingNotifications.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.notifications_active,
                              color: Colors.blue.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Hearing Reminders',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._hearingNotifications.map((notification) {
                          final hearingDate =
                              notification['hearingDate'] as DateTime?;
                          final daysUntil = hearingDate != null
                              ? hearingDate.difference(DateTime.now()).inDays
                              : 0;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: Colors.white,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue.shade100,
                                child: Icon(
                                  Icons.gavel,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              title: Text(
                                notification['title'] ?? 'Hearing',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (hearingDate != null)
                                    Text(
                                      'Hearing Date: ${DateFormat('EEEE, MMMM dd, yyyy • hh:mm a').format(hearingDate)}',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: daysUntil <= 2
                                          ? Colors.orange.shade100
                                          : Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      daysUntil == 0
                                          ? 'Today!'
                                          : daysUntil == 1
                                          ? 'Tomorrow'
                                          : '$daysUntil days remaining',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: daysUntil <= 2
                                            ? Colors.orange.shade900
                                            : Colors.green.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Quick Actions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
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
                          color: AppTheme.royalBlue,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const StaffCreateCaseDraftScreen(),
                                  ),
                                ).then((created) {
                                  if (created == true) {
                                    _loadDashboardData(); // Refresh dashboard
                                  }
                                });
                              },
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('Create Draft Case'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.royalBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          if (_assignedAttorneyId != null) ...[
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: () =>
                                  unawaited(_openChatWithAttorney()),
                              icon: const Icon(Icons.message),
                              label: const Text('Message Attorney'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.gold,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_assignedAttorneyId != null) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _openBilling(),
                            icon: const Icon(
                              Icons.account_balance_wallet_outlined,
                            ),
                            label: const Text('Billing & Payments'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.royalBlue,
                              side: const BorderSide(color: AppTheme.royalBlue),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_upcomingDeadlines.isNotEmpty) ...[
                  Text(
                    'Upcoming Deadlines',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.royalBlue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._upcomingDeadlines.map(
                    (deadline) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          Icons.event,
                          color: _getDeadlineColor(
                            deadline['eventDate'] as DateTime,
                          ),
                        ),
                        title: Text(deadline['title'] ?? 'Event'),
                        subtitle: Text(
                          DateFormat(
                            'MMM dd, yyyy • hh:mm a',
                          ).format(deadline['eventDate'] as DateTime),
                        ),
                        trailing: Chip(
                          label: Text(deadline['eventType'] ?? 'event'),
                          backgroundColor: AppTheme.lightGray,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Stats Grid
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Overview',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.royalBlue,
                        ),
                      ),
                    ),
                    if (_snapshotLoading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: isDesktop ? 1.1 : 0.92,
                  children: [
                    StatCard(
                      title: 'Total Tasks',
                      value: '${_stats['totalTasks'] ?? 0}',
                      description: 'All assigned tasks',
                      icon: Icons.task_outlined,
                      iconColor: AppTheme.royalBlue,
                    ),
                    StatCard(
                      title: 'Pending Tasks',
                      value: '${_stats['pendingTasks'] ?? 0}',
                      description: 'Awaiting action',
                      icon: Icons.pending_outlined,
                      iconColor: const Color(0xFFF56565),
                    ),
                    StatCard(
                      title: 'In Progress',
                      value: '${_stats['inProgressTasks'] ?? 0}',
                      description: 'Currently working',
                      icon: Icons.work_outline,
                      iconColor: const Color(0xFF48BB78),
                    ),
                    StatCard(
                      title: 'Active Cases',
                      value: '${_stats['activeCases'] ?? 0}',
                      description: 'Assigned cases',
                      icon: Icons.folder_outlined,
                      iconColor: const Color(0xFF764BA2),
                    ),
                    StatCard(
                      title: 'Completed Tasks',
                      value: '${_stats['completedTasks'] ?? 0}',
                      description: 'Finished tasks',
                      icon: Icons.check_circle_outline,
                      iconColor: const Color(0xFFED8936),
                    ),
                    StatCard(
                      title: 'Upcoming Deadlines',
                      value: '${_stats['upcomingDeadlines'] ?? 0}',
                      description: 'Hearings & deadlines',
                      icon: Icons.event_outlined,
                      iconColor: const Color(0xFFF56565),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Active Cases Quick Access
                if (_assignedCases.isNotEmpty) ...[
                  Text(
                    'Active Cases',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.royalBlue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 132,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _assignedCases.take(5).length,
                      itemBuilder: (context, index) {
                        final caseModel = _assignedCases[index];
                        return Container(
                          width: 200,
                          margin: const EdgeInsets.only(right: 12),
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                setState(() => _activeItem = 'cases');
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        caseModel.caseTitle,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Chip(
                                      label: Text(
                                        caseModel.status.toUpperCase(),
                                        style: const TextStyle(fontSize: 10),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: EdgeInsets.zero,
                                      labelPadding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      backgroundColor: _getCaseStatusColor(
                                        caseModel.status,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Recent Tasks
                Text(
                  'Recent Tasks',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.royalBlue,
                  ),
                ),
                const SizedBox(height: 12),
                if (_myTasks.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.task_outlined,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No tasks assigned yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ..._myTasks
                      .take(5)
                      .map(
                        (task) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: _getTaskStatusIcon(task.status),
                            title: Text(task.title),
                            subtitle: Text(task.description),
                            trailing: Chip(
                              label: Text(
                                task.status.replaceAll('_', ' ').toUpperCase(),
                              ),
                              backgroundColor: _getTaskStatusColor(task.status),
                            ),
                            onTap: () {
                              Get.to(() => const StaffTasksScreen());
                            },
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Color _getDeadlineColor(DateTime deadline) {
    final daysUntil = deadline.difference(DateTime.now()).inDays;
    if (daysUntil < 0) return Colors.red;
    if (daysUntil <= 1) return Colors.orange;
    if (daysUntil <= 3) return Colors.amber;
    return Colors.blue;
  }

  Widget _getTaskStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return const Icon(Icons.pending, color: Colors.orange);
      case 'in_progress':
        return const Icon(Icons.work, color: Colors.blue);
      case 'completed':
        return const Icon(Icons.check_circle, color: Colors.green);
      default:
        return const Icon(Icons.task, color: Colors.grey);
    }
  }

  Color _getTaskStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange.withOpacity(0.2);
      case 'in_progress':
        return Colors.blue.withOpacity(0.2);
      case 'completed':
        return Colors.green.withOpacity(0.2);
      default:
        return Colors.grey.withOpacity(0.2);
    }
  }

  Color _getCaseStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange.withOpacity(0.2);
      case 'accepted':
      case 'in_progress':
        return Colors.blue.withOpacity(0.2);
      case 'completed':
        return Colors.green.withOpacity(0.2);
      default:
        return Colors.grey.withOpacity(0.2);
    }
  }

  @override
  void dispose() {
    _tabPrewarmTimer?.cancel();
    _fanoutDeferTimer?.cancel();
    _tasksSub?.cancel();
    _assignedCasesSub?.cancel();
    _attorneyCasesSub?.cancel();
    HearingNotificationFanoutService.instance.detach();
    super.dispose();
  }
}
