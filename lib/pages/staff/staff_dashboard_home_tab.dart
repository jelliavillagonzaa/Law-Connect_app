import 'dart:async' show StreamSubscription, Timer, unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/case_model.dart';
import '../../models/task_model.dart';
import '../../screens/billing/billing_management_screen.dart';
import '../../screens/client/chat_screen.dart';
import '../../screens/staff/staff_cases_screen.dart';
import '../../screens/staff/staff_tasks_screen.dart';
import '../../screens/attorney/attorney_notary_requests_screen.dart';
import '../../services/chat_service.dart';
import '../../services/staff_service.dart';
import '../../services/task_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/case_status_filter.dart';
import '../../utils/open_work_tasks.dart';
import '../../widgets/staff/staff_overview_card.dart';
import '../../widgets/staff/staff_ui_theme.dart';

/// Self-contained staff dashboard overview — updates via its own [setState]
/// so the parent tab stack is not rebuilt on every Firestore tick.
class StaffDashboardHomeTab extends StatefulWidget {
  final String staffName;
  final String? assignedAttorneyId;
  final VoidCallback? onNavigateToCases;
  final Widget? headerActions;

  const StaffDashboardHomeTab({
    super.key,
    required this.staffName,
    this.assignedAttorneyId,
    this.onNavigateToCases,
    this.headerActions,
  });

  @override
  StaffDashboardHomeTabState createState() => StaffDashboardHomeTabState();
}

class StaffDashboardHomeTabState extends State<StaffDashboardHomeTab> {
  final StaffService _staffService = StaffService();
  final TaskService _taskService = TaskService();
  final ChatService _chatService = ChatService();

  bool _streamsAttached = false;
  bool _snapshotLoading = false;
  bool _snapshotRefreshQueued = false;
  bool _snapshotRetried = false;
  Timer? _uiDebounce;

  StreamSubscription<List<TaskModel>>? _tasksSub;
  StreamSubscription<List<CaseModel>>? _assignedCasesSub;
  StreamSubscription<List<CaseModel>>? _attorneyCasesSub;

  String? _assignedAttorneyId;
  Map<String, dynamic> _stats = {};
  List<TaskModel> _myTasks = [];
  List<CaseModel> _assignedCases = [];
  List<Map<String, dynamic>> _upcomingDeadlines = [];
  List<Map<String, dynamic>> _hearingNotifications = [];

  bool get _hasOverviewData =>
      _myTasks.isNotEmpty ||
      _assignedCases.isNotEmpty ||
      (_stats['totalTasks'] as int? ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    _assignedAttorneyId = widget.assignedAttorneyId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attachStreams();
      unawaited(_refreshSnapshot());
      unawaited(_loadPreviewData());
    });
  }

  @override
  void didUpdateWidget(StaffDashboardHomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextId = widget.assignedAttorneyId?.trim();
    final prevId = oldWidget.assignedAttorneyId?.trim();
    if (nextId != prevId && nextId != _assignedAttorneyId) {
      _assignedAttorneyId = nextId;
      unawaited(_refreshSnapshot());
      unawaited(_loadPreviewData());
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) _subscribeCaseStreams(uid);
    }
  }

  /// Pull-to-refresh and post–create-draft reload.
  Future<void> reload() async {
    _snapshotRetried = false;
    await _refreshSnapshot();
    if (!mounted) return;
    await _loadPreviewData();
  }

  void _scheduleUiUpdate() {
    _uiDebounce?.cancel();
    _uiDebounce = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      setState(() {
        _stats = _computeStats();
        _snapshotLoading = false;
      });
    });
  }

  void _attachStreams() {
    if (_streamsAttached) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _streamsAttached = true;

    _tasksSub = _taskService.getStaffTasks(user.uid).listen(
      (tasks) {
        if (!mounted) return;
        _myTasks = tasks;
        _scheduleUiUpdate();
      },
      onError: (_) => unawaited(_refreshSnapshot()),
    );

    _subscribeCaseStreams(user.uid);
  }

  void _subscribeCaseStreams(String staffId) {
    _assignedCasesSub?.cancel();
    _assignedCasesSub = _staffService.getAssignedCases(staffId).listen(
      (cases) {
        if (!mounted) return;
        if (cases.isNotEmpty) {
          _assignedCases = cases;
          _scheduleUiUpdate();
        }
      },
      onError: (_) => unawaited(_refreshSnapshot()),
    );

    final attorneyId = _assignedAttorneyId?.trim() ?? '';
    _attorneyCasesSub?.cancel();
    _attorneyCasesSub = null;
    if (attorneyId.isEmpty) return;

    _attorneyCasesSub = _staffService.getAttorneyCases(attorneyId).listen(
      (cases) {
        if (!mounted) return;
        _assignedCases = cases;
        _scheduleUiUpdate();
      },
      onError: (_) {},
    );
  }

  Future<void> _refreshSnapshot() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_snapshotLoading) {
      _snapshotRefreshQueued = true;
      return;
    }

    if (mounted && !kIsWeb && !_hasOverviewData) {
      setState(() => _snapshotLoading = true);
    } else {
      _snapshotLoading = true;
    }

    var tasks = <TaskModel>[];
    var cases = <CaseModel>[];
    var attorneyId = _assignedAttorneyId?.trim() ?? '';

    try {
      if (!kIsWeb) {
        try {
          await user.getIdToken(true);
        } catch (_) {}
      }

      final userDocFuture = attorneyId.isEmpty
          ? _firestoreGetDoc(
              FirebaseFirestore.instance.collection('users').doc(user.uid),
            )
          : null;
      final taskFuture = _firestoreGet(
        FirebaseFirestore.instance
            .collection('tasks')
            .where('assignedTo', isEqualTo: user.uid),
        60,
      );
      final assignedFuture = _firestoreGet(
        FirebaseFirestore.instance
            .collection('cases')
            .where('staffAssigned', arrayContains: user.uid),
        60,
      );

      Object? taskResult;
      Object? assignedResult;
      Object? userDocResult;
      await Future.wait<void>([
        () async {
          try {
            taskResult = await taskFuture;
          } catch (_) {}
        }(),
        () async {
          try {
            assignedResult = await assignedFuture;
          } catch (_) {}
        }(),
        if (userDocFuture != null)
          () async {
            try {
              userDocResult = await userDocFuture;
            } catch (_) {}
          }(),
      ]);

      try {
        final taskSnap = taskResult as QuerySnapshot<Map<String, dynamic>>?;
        if (taskSnap != null) {
          tasks = taskSnap.docs
              .map((doc) => TaskModel.fromFirestore(doc))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
      } catch (_) {}

      try {
        final assignedSnap =
            assignedResult as QuerySnapshot<Map<String, dynamic>>?;
        if (assignedSnap != null) {
          cases = assignedSnap.docs
              .map((doc) => CaseModel.fromFirestore(doc))
              .toList();
        }
      } catch (_) {}

      if (attorneyId.isEmpty && userDocResult != null) {
        try {
          final userDoc =
              userDocResult as DocumentSnapshot<Map<String, dynamic>>;
          attorneyId =
              (userDoc.data()?['assignedAttorneyId'] as String?)?.trim() ?? '';
          if (attorneyId.isNotEmpty) _assignedAttorneyId = attorneyId;
        } catch (_) {}
      }

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
        if (tasks.isNotEmpty) _myTasks = tasks;
        if (cases.isNotEmpty) {
          _assignedCases = cases
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
        _stats = _computeStats();
        _snapshotLoading = false;
      });

      if (attorneyId.isNotEmpty && _attorneyCasesSub == null) {
        _subscribeCaseStreams(user.uid);
      }

      if (tasks.isEmpty && cases.isEmpty && !_snapshotRetried) {
        _snapshotRetried = true;
        Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          unawaited(_refreshSnapshot());
        });
      }
    } finally {
      if (_snapshotLoading && mounted) {
        setState(() => _snapshotLoading = false);
      } else {
        _snapshotLoading = false;
      }
      if (_snapshotRefreshQueued) {
        _snapshotRefreshQueued = false;
        unawaited(_refreshSnapshot());
      }
    }
  }

  Future<void> _loadPreviewData() async {
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
        _stats = _computeStats();
      });
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
    final closedCaseIds = OpenWorkTasks.closedCaseIds(_assignedCases);
    final liveTasks = OpenWorkTasks.live(_myTasks, closedCaseIds);

    return {
      'totalTasks': liveTasks.length,
      'pendingTasks': liveTasks.where((t) => isPending(t.status)).length,
      'inProgressTasks': liveTasks.where((t) => isInProgress(t.status)).length,
      'completedTasks': _myTasks.where((t) => isCompleted(t.status)).length,
      'activeCases': _assignedCases.where((c) => isActiveCase(c.status)).length,
      'upcomingDeadlines': _upcomingDeadlines.length,
    };
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

    final attorneyId = _assignedAttorneyId;
    if (attorneyId == null || attorneyId.isEmpty) {
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
      final attorneyDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(attorneyId)
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

      final chatId = await _chatService.getOrCreateChat(user.uid, attorneyId);

      Get.to(
        () => ChatScreen(
          conversationId: chatId,
          otherUserId: attorneyId,
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

  void _openNotary() {
    final attorneyId = (_assignedAttorneyId ?? '').trim();
    if (attorneyId.isEmpty) {
      Get.snackbar(
        'Notary',
        'No assigned attorney. Ask admin to link your account.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    Get.to(
      () => AttorneyNotaryRequestsScreen(
        staffAssignedAttorneyId: attorneyId,
      ),
    );
  }

  @override
  void dispose() {
    _uiDebounce?.cancel();
    _tasksSub?.cancel();
    _assignedCasesSub?.cancel();
    _attorneyCasesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 800;
    final width = MediaQuery.sizeOf(context).width;
    final overviewCount = width >= 1200
        ? 6
        : width >= 800
            ? 3
            : 2;

    final body = Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 24 : 16,
        isDesktop ? 20 : 16,
        isDesktop ? 24 : 16,
        28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hearingNotifications.isNotEmpty) ...[
            _HearingReminders(notifications: _hearingNotifications),
            const SizedBox(height: 20),
          ],
          if (!isDesktop && _assignedAttorneyId != null) ...[
            _MobileQuickActions(
              onMessage: () => unawaited(_openChatWithAttorney()),
              onBilling: _openBilling,
              onNotary: _openNotary,
            ),
            const SizedBox(height: 20),
          ],
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: overviewCount,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: isDesktop ? 118 : 122,
            ),
            children: [
              StaffOverviewCard(
                title: 'Total Tasks',
                value: '${_stats['totalTasks'] ?? 0}',
                subtitle: 'All assigned tasks',
                icon: Icons.description_outlined,
                iconColor: AppTheme.inkBlue,
                pastel: const Color(0xFFE8F0F8),
              ),
              StaffOverviewCard(
                title: 'Pending Tasks',
                value: '${_stats['pendingTasks'] ?? 0}',
                subtitle: 'Awaiting action',
                icon: Icons.more_horiz,
                iconColor: AppTheme.inkCoral,
                pastel: const Color(0xFFF8E8E4),
              ),
              StaffOverviewCard(
                title: 'In Progress',
                value: '${_stats['inProgressTasks'] ?? 0}',
                subtitle: 'Currently working',
                icon: Icons.work_outline,
                iconColor: AppTheme.inkGreen,
                pastel: const Color(0xFFE3F3E8),
              ),
              StaffOverviewCard(
                title: 'Active Cases',
                value: '${_stats['activeCases'] ?? 0}',
                subtitle: 'Assigned cases',
                icon: Icons.folder_outlined,
                iconColor: AppTheme.inkPurple,
                pastel: const Color(0xFFEDE8F8),
              ),
              StaffOverviewCard(
                title: 'Completed Tasks',
                value: '${_stats['completedTasks'] ?? 0}',
                subtitle: 'Finished tasks',
                icon: Icons.check_circle_outline,
                iconColor: AppTheme.inkGreen,
                pastel: const Color(0xFFE5F6EA),
              ),
              StaffOverviewCard(
                title: 'Upcoming Deadlines',
                value: '${_stats['upcomingDeadlines'] ?? 0}',
                subtitle: 'Hearings & deadlines',
                icon: Icons.event_outlined,
                iconColor: AppTheme.inkPurple,
                pastel: const Color(0xFFE8E8F6),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildCasesPanel()),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      _buildDeadlinesPanel(),
                      const SizedBox(height: 16),
                      _buildActivityPanel(),
                    ],
                  ),
                ),
              ],
            )
          else ...[
            _buildCasesPanel(),
            const SizedBox(height: 16),
            _buildDeadlinesPanel(),
            const SizedBox(height: 16),
            _buildActivityPanel(),
          ],
        ],
      ),
    );

    final scroll = RefreshIndicator(
      onRefresh: reload,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: body,
      ),
    );

    if (!isDesktop) {
      return ColoredBox(
        color: StaffUi.background,
        child: Column(
          children: [
            _StaffHero(
              name: widget.staffName,
              compact: true,
              headerActions: widget.headerActions,
            ),
            Expanded(child: scroll),
          ],
        ),
      );
    }

    return ColoredBox(
      color: StaffUi.background,
      child: Column(
        children: [
          _StaffHero(
            name: widget.staffName,
            headerActions: widget.headerActions,
            onMessage: () => unawaited(_openChatWithAttorney()),
            onBilling: _openBilling,
          ),
          Expanded(child: scroll),
        ],
      ),
    );
  }

  Widget _buildCasesPanel() {
    final cases = _assignedCases
        .where((c) => !OpenWorkTasks.isClosedCase(c))
        .take(6)
        .toList();
    return _Panel(
      title: 'Active Cases',
      actionLabel: 'View All',
      onAction: widget.onNavigateToCases,
      child: cases.isEmpty
          ? const _EmptyNote(
              icon: Icons.folder_open_outlined,
              text: 'No active cases assigned yet.',
            )
          : Column(
              children: [
                const _CasesHeader(),
                const Divider(height: 1, color: StaffUi.line),
                ...cases.map(
                  (c) => _CaseRow(
                    caseModel: c,
                    onView: () => Get.to(
                      () => StaffCaseDetailPage(caseModel: c),
                    ),
                    statusColor: _getCaseStatusColor(c.status),
                    statusLabel: _statusLabel(c.status),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDeadlinesPanel() {
    return _Panel(
      title: 'Upcoming Deadlines',
      child: _upcomingDeadlines.isEmpty
          ? const _EmptyNote(
              icon: Icons.event_available_outlined,
              text: "No upcoming deadlines. You're all caught up!",
            )
          : Column(
              children: _upcomingDeadlines
                  .take(5)
                  .map(
                    (deadline) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.event,
                        color: _getDeadlineColor(
                          deadline['eventDate'] as DateTime,
                        ),
                      ),
                      title: Text(
                        deadline['title'] ?? 'Event',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        DateFormat('MMM dd, yyyy • hh:mm a').format(
                          deadline['eventDate'] as DateTime,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _buildActivityPanel() {
    final liveTasks = OpenWorkTasks.live(
      _myTasks,
      OpenWorkTasks.closedCaseIds(_assignedCases),
    );
    final tasks = liveTasks.take(5).toList();
    return _Panel(
      title: 'Recent Activity',
      actionLabel: tasks.isEmpty ? null : 'View All',
      onAction: tasks.isEmpty
          ? null
          : () => Get.to(() => const StaffTasksScreen()),
      child: tasks.isEmpty
          ? const _EmptyNote(
              icon: Icons.task_outlined,
              text: 'No open tasks',
            )
          : Column(
              children: tasks
                  .map(
                    (task) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onTap: () => Get.to(() => const StaffTasksScreen()),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: _getTaskStatusColor(task.status),
                        child: _getTaskStatusIcon(task.status),
                      ),
                      title: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        task.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: StaffUi.muted,
                        ),
                      ),
                      trailing: Text(
                        _timeAgo(task.updatedAt ?? task.createdAt),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: StaffUi.muted,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase().trim()) {
      case 'pending':
        return 'Pending';
      case 'in_progress':
      case 'active':
        return 'In Progress';
      case 'accepted':
        return 'Ongoing';
      case 'under_review':
      case 'draft':
        return 'Under Review';
      case 'completed':
        return 'Completed';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return DateFormat('MMM d').format(dt);
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
        return const Icon(Icons.pending, color: Colors.orange, size: 16);
      case 'in_progress':
        return const Icon(Icons.work, color: Colors.blue, size: 16);
      case 'completed':
        return const Icon(Icons.check_circle, color: Colors.green, size: 16);
      case 'cancelled':
      case 'canceled':
        return const Icon(Icons.cancel, color: Colors.grey, size: 16);
      default:
        return const Icon(Icons.task, color: Colors.grey, size: 16);
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
      case 'cancelled':
      case 'canceled':
        return Colors.grey.withOpacity(0.2);
      default:
        return Colors.grey.withOpacity(0.2);
    }
  }

  Color _getCaseStatusColor(String status) {
    switch (status.toLowerCase()) {
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
}

class _StaffHero extends StatelessWidget {
  const _StaffHero({
    required this.name,
    this.headerActions,
    this.onMessage,
    this.onBilling,
    this.compact = false,
  });

  final String name;
  final Widget? headerActions;
  final VoidCallback? onMessage;
  final VoidCallback? onBilling;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: StaffUi.heroGradient),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              right: compact ? -30 : 8,
              top: -28,
              bottom: -28,
              width: compact ? 160 : 280,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.28,
                  child: Image.asset(
                    'assets/Landingpage.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 28,
                compact ? 16 : 22,
                compact ? 16 : 28,
                compact ? 16 : 22,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome, $name!',
                              style: GoogleFonts.inter(
                                fontSize: compact ? 22 : 28,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Here's your overview for today",
                              style: GoogleFonts.inter(
                                fontSize: compact ? 13 : 15,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.78),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (headerActions != null) headerActions!,
                    ],
                  ),
                  if (onMessage != null || onBilling != null) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (onMessage != null)
                          FilledButton.icon(
                            onPressed: onMessage,
                            icon: const Icon(Icons.chat_bubble_outline, size: 18),
                            label: const Text('Message Attorney'),
                            style: FilledButton.styleFrom(
                              backgroundColor: StaffUi.gold,
                              foregroundColor: StaffUi.navy,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                              textStyle: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        if (onBilling != null)
                          OutlinedButton.icon(
                            onPressed: onBilling,
                            icon: const Icon(
                              Icons.credit_card_outlined,
                              size: 18,
                            ),
                            label: const Text('Billing & Payments'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white70),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                              textStyle: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: StaffUi.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: StaffUi.title),
              ),
              if (actionLabel != null)
                TextButton(
                  onPressed: onAction,
                  child: Text(
                    '$actionLabel  >',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: StaffUi.navyMid,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(icon, size: 40, color: StaffUi.muted.withValues(alpha: 0.7)),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: StaffUi.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _CasesHeader extends StatelessWidget {
  const _CasesHeader();

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: StaffUi.muted,
      letterSpacing: 0.4,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('CASE', style: style)),
          Expanded(flex: 2, child: Text('TYPE', style: style)),
          Expanded(flex: 2, child: Text('STATUS', style: style)),
          Expanded(flex: 2, child: Text('UPDATED', style: style)),
          const SizedBox(width: 72, child: Text('')),
        ],
      ),
    );
  }
}

class _CaseRow extends StatelessWidget {
  const _CaseRow({
    required this.caseModel,
    required this.statusLabel,
    required this.statusColor,
    this.onView,
  });

  final CaseModel caseModel;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onView,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 18,
                      color: StaffUi.navyMid,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        caseModel.caseTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: StaffUi.navyMid,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  caseModel.caseType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, color: StaffUi.muted),
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: StaffUi.text,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  DateFormat('MMM d, y').format(caseModel.updatedAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, color: StaffUi.muted),
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  'View',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: StaffUi.navyMid,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HearingReminders extends StatelessWidget {
  const _HearingReminders({required this.notifications});

  final List<Map<String, dynamic>> notifications;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hearing Reminders', style: StaffUi.title),
          const SizedBox(height: 8),
          ...notifications.map((notification) {
            final hearingDate = notification['hearingDate'] as DateTime?;
            final daysUntil = hearingDate != null
                ? hearingDate.difference(DateTime.now()).inDays
                : 0;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFDBEAFE),
                child: Icon(Icons.gavel, color: StaffUi.navyMid, size: 18),
              ),
              title: Text(
                notification['caseTitle'] as String? ?? 'Hearing',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
              subtitle: hearingDate == null
                  ? null
                  : Text(
                      daysUntil == 0
                          ? 'Today at ${DateFormat('hh:mm a').format(hearingDate)}'
                          : daysUntil == 1
                              ? 'Tomorrow at ${DateFormat('hh:mm a').format(hearingDate)}'
                              : 'In $daysUntil days • ${DateFormat('MMM dd, yyyy').format(hearingDate)}',
                    ),
            );
          }),
        ],
      ),
    );
  }
}

class _MobileQuickActions extends StatelessWidget {
  const _MobileQuickActions({
    required this.onMessage,
    required this.onBilling,
    required this.onNotary,
  });

  final VoidCallback onMessage;
  final VoidCallback onBilling;
  final VoidCallback onNotary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onNotary,
            icon: const Icon(Icons.draw_outlined),
            label: const Text('Notary'),
            style: FilledButton.styleFrom(
              backgroundColor: StaffUi.navy,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onMessage,
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Message Attorney'),
            style: FilledButton.styleFrom(
              backgroundColor: StaffUi.gold,
              foregroundColor: StaffUi.navy,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onBilling,
            icon: const Icon(Icons.credit_card_outlined),
            label: const Text('Billing & Payments'),
          ),
        ),
      ],
    );
  }
}
