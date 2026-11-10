import 'dart:async' show StreamSubscription, Timer, unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../models/case_model.dart';
import '../../models/task_model.dart';
import '../../screens/client/chat_screen.dart';
import '../../screens/staff/staff_cases_screen.dart';
import '../../screens/staff/staff_tasks_screen.dart';
import '../../services/chat_service.dart';
import '../../services/staff_service.dart';
import '../../services/task_service.dart';
import '../../utils/open_work_tasks.dart';
import '../../widgets/staff/staff_overview_card.dart';
import '../../widgets/staff/staff_ui_theme.dart';
import '../../theme/app_theme.dart';
import '../../screens/staff/staff_calendar_screen.dart';
import '../../screens/staff/staff_pending_appointments_screen.dart';
import '../../screens/staff/staff_notary_management_screen.dart';
import '../../screens/billing/billing_management_screen.dart'
    show openPaymentHistoryScreen;
import '../../utils/case_status_filter.dart';

/// Self-contained staff dashboard overview — updates via its own [setState]
/// so the parent tab stack is not rebuilt on every Firestore tick.
class StaffDashboardHomeTab extends StatefulWidget {
  final String staffName;
  final String? assignedAttorneyId;
  final VoidCallback? onNavigateToCases;
  final VoidCallback? onNavigateToCalendar;
  final VoidCallback? onNavigateToPendingAppointments;
  final VoidCallback? onNavigateToNotary;
  final int pendingAppointmentsCount;
  final Widget? headerActions;

  const StaffDashboardHomeTab({
    super.key,
    required this.staffName,
    this.assignedAttorneyId,
    this.onNavigateToCases,
    this.onNavigateToCalendar,
    this.onNavigateToPendingAppointments,
    this.onNavigateToNotary,
    this.pendingAppointmentsCount = 0,
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
  StreamSubscription<List<Map<String, dynamic>>>? _calendarEventsSub;

  List<CaseModel> _staffAssignedCases = [];
  List<CaseModel> _attorneyCases = [];

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

    _tasksSub = _taskService
        .getStaffTasks(user.uid, staffEmail: user.email)
        .listen(
      (tasks) {
        if (!mounted) return;
        _myTasks = tasks;
        _scheduleUiUpdate();
      },
      onError: (_) => unawaited(_refreshSnapshot()),
    );

    _subscribeCaseStreams(user.uid);
  }

  void _mergeAssignedCases() {
    final map = <String, CaseModel>{};
    for (final c in _staffAssignedCases) {
      map[c.id] = c;
    }
    for (final c in _attorneyCases) {
      map.putIfAbsent(c.id, () => c);
    }
    final merged = map.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _assignedCases = merged;
    _scheduleUiUpdate();
  }

  void _subscribeCaseStreams(String staffId) {
    _assignedCasesSub?.cancel();
    final staffEmail = FirebaseAuth.instance.currentUser?.email;
    _assignedCasesSub = _staffService.getAssignedCases(staffId, staffEmail: staffEmail).listen(
      (cases) {
        if (!mounted) return;
        _staffAssignedCases = cases;
        _mergeAssignedCases();
      },
      onError: (_) => unawaited(_refreshSnapshot()),
    );

    final attorneyId = _assignedAttorneyId?.trim() ?? '';
    _attorneyCasesSub?.cancel();
    _attorneyCasesSub = null;
    _calendarEventsSub?.cancel();
    _calendarEventsSub = null;
    if (attorneyId.isEmpty) return;

    _attorneyCasesSub = _staffService.getAttorneyCases(attorneyId).listen(
      (cases) {
        if (!mounted) return;
        _attorneyCases = cases;
        _mergeAssignedCases();
      },
      onError: (_) {},
    );

    _calendarEventsSub = _staffService.getCalendarEvents(attorneyId).listen(
      (events) {
        if (!mounted) return;
        final now = DateTime.now();
        final upcoming = events.where((e) {
          final dt = e['eventDate'] as DateTime?;
          return dt != null && dt.isAfter(now);
        }).toList()
          ..sort((a, b) {
            final da = a['eventDate'] as DateTime;
            final db = b['eventDate'] as DateTime;
            return da.compareTo(db);
          });
        setState(() {
          _upcomingDeadlines = upcoming;
          _stats = _computeStats();
        });
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
          await user.getIdToken();
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
      final email = user.email?.trim() ?? '';
      final taskEmailFuture = email.isNotEmpty
          ? _firestoreGet(
              FirebaseFirestore.instance
                  .collection('tasks')
                  .where('assignedTo', isEqualTo: email),
              60,
            )
          : null;
      final assignedFuture = _firestoreGet(
        FirebaseFirestore.instance
            .collection('cases')
            .where('staffAssigned', arrayContains: user.uid),
        60,
      );
      final staffIdFuture = _firestoreGet(
        FirebaseFirestore.instance
            .collection('cases')
            .where('staffId', isEqualTo: user.uid),
        60,
      );
      final assignedEmailFuture = email.isNotEmpty
          ? _firestoreGet(
              FirebaseFirestore.instance
                  .collection('cases')
                  .where('staffAssigned', arrayContains: email),
              60,
            )
          : null;
      final staffIdEmailFuture = email.isNotEmpty
          ? _firestoreGet(
              FirebaseFirestore.instance
                  .collection('cases')
                  .where('staffId', isEqualTo: email),
              60,
            )
          : null;

      Object? taskResult;
      Object? taskEmailResult;
      Object? assignedResult;
      Object? staffIdResult;
      Object? assignedEmailResult;
      Object? staffIdEmailResult;
      Object? userDocResult;
      await Future.wait<void>([
        () async {
          try {
            taskResult = await taskFuture;
          } catch (_) {}
        }(),
        if (taskEmailFuture != null)
          () async {
            try {
              taskEmailResult = await taskEmailFuture;
            } catch (_) {}
          }(),
        () async {
          try {
            assignedResult = await assignedFuture;
          } catch (_) {}
        }(),
        () async {
          try {
            staffIdResult = await staffIdFuture;
          } catch (_) {}
        }(),
        if (assignedEmailFuture != null)
          () async {
            try {
              assignedEmailResult = await assignedEmailFuture;
            } catch (_) {}
          }(),
        if (staffIdEmailFuture != null)
          () async {
            try {
              staffIdEmailResult = await staffIdEmailFuture;
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
        final taskEmailSnap =
            taskEmailResult as QuerySnapshot<Map<String, dynamic>>?;
        final taskMap = <String, TaskModel>{};
        if (taskSnap != null) {
          for (final doc in taskSnap.docs) {
            taskMap[doc.id] = TaskModel.fromFirestore(doc);
          }
        }
        if (taskEmailSnap != null) {
          for (final doc in taskEmailSnap.docs) {
            taskMap.putIfAbsent(doc.id, () => TaskModel.fromFirestore(doc));
          }
        }
        tasks = taskMap.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } catch (_) {}

      try {
        final assignedSnap =
            assignedResult as QuerySnapshot<Map<String, dynamic>>?;
        final staffIdSnap =
            staffIdResult as QuerySnapshot<Map<String, dynamic>>?;
        final caseMap = <String, CaseModel>{};
        if (assignedSnap != null) {
          for (final doc in assignedSnap.docs) {
            caseMap[doc.id] = CaseModel.fromFirestore(doc);
          }
        }
        if (staffIdSnap != null) {
          for (final doc in staffIdSnap.docs) {
            caseMap.putIfAbsent(doc.id, () => CaseModel.fromFirestore(doc));
          }
        }
        final assignedEmailSnap =
            assignedEmailResult as QuerySnapshot<Map<String, dynamic>>?;
        if (assignedEmailSnap != null) {
          for (final doc in assignedEmailSnap.docs) {
            caseMap.putIfAbsent(doc.id, () => CaseModel.fromFirestore(doc));
          }
        }
        final staffIdEmailSnap =
            staffIdEmailResult as QuerySnapshot<Map<String, dynamic>>?;
        if (staffIdEmailSnap != null) {
          for (final doc in staffIdEmailSnap.docs) {
            caseMap.putIfAbsent(doc.id, () => CaseModel.fromFirestore(doc));
          }
        }
        cases = caseMap.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } catch (_) {}

      if (attorneyId.isEmpty && userDocResult != null) {
        try {
          final userDoc =
              userDocResult as DocumentSnapshot<Map<String, dynamic>>;
          attorneyId =
              (userDoc.data()?['assignedAttorneyId'] as String?)?.trim() ?? '';
        } catch (_) {}
      }

      // If attorneyId is still empty, resolve from assigned cases
      if (attorneyId.isEmpty && cases.isNotEmpty) {
        for (final c in cases) {
          final aid = c.attorneyId?.trim() ?? '';
          if (aid.isNotEmpty) {
            attorneyId = aid;
            break;
          }
        }
      }

      // If still empty, resolve from active attorney in users collection
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

      if (attorneyId.isNotEmpty && attorneyId != _assignedAttorneyId) {
        _assignedAttorneyId = attorneyId;
      }

      if (cases.isEmpty && attorneyId.isNotEmpty) {
        try {
          final attorneySnap = await _firestoreGet(
            FirebaseFirestore.instance
                .collection('cases')
                .where('attorneyId', isEqualTo: attorneyId),
            60,
          );
          final attCases = attorneySnap.docs
              .map((doc) => CaseModel.fromFirestore(doc))
              .toList();
          if (attCases.isNotEmpty) {
            _attorneyCases = attCases;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      if (tasks.isNotEmpty) _myTasks = tasks;
      if (cases.isNotEmpty) {
        _staffAssignedCases = cases;
      }
      _mergeAssignedCases();
      setState(() {
        _stats = _computeStats();
        _snapshotLoading = false;
      });

      unawaited(_loadPreviewData());

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
    final attorneyId = _assignedAttorneyId?.trim() ?? '';
    final user = FirebaseAuth.instance.currentUser;
    if (attorneyId.isEmpty && user == null) return;
    if (!mounted) return;

    try {
      final now = DateTime.now();
      final targetAids = <String>{
        if (attorneyId.isNotEmpty) attorneyId,
        if (user != null) user.uid,
      };

      final allEventDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final aid in targetAids) {
        QuerySnapshot<Map<String, dynamic>> deadlinesSnap;
        try {
          deadlinesSnap = await FirebaseFirestore.instance
              .collection('calendar_events')
              .where('assignedTo', isEqualTo: aid)
              .where('eventDate', isGreaterThan: Timestamp.fromDate(now))
              .orderBy('eventDate')
              .limit(20)
              .get();
        } catch (_) {
          deadlinesSnap = await FirebaseFirestore.instance
              .collection('calendar_events')
              .where('assignedTo', isEqualTo: aid)
              .limit(50)
              .get();
        }
        allEventDocs.addAll(deadlinesSnap.docs);
      }

      QuerySnapshot<Map<String, dynamic>>? hearingSnap;
      if (attorneyId.isNotEmpty) {
        try {
          hearingSnap = await FirebaseFirestore.instance
              .collection('hearing_notifications')
              .where('attorneyId', isEqualTo: attorneyId)
              .where('status', isEqualTo: 'pending')
              .limit(15)
              .get();
        } catch (_) {}
      }

      final twoDays = now.add(const Duration(days: 2));
      final hearings = (hearingSnap?.docs ?? [])
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

      final seenDocIds = <String>{};
      final events = allEventDocs
          .where((doc) => seenDocIds.add(doc.id))
          .map((doc) {
            final data = doc.data();
            DateTime? dt;
            if (data['eventDate'] is Timestamp) {
              dt = (data['eventDate'] as Timestamp).toDate();
            } else if (data['eventDate'] is String) {
              dt = DateTime.tryParse(data['eventDate'] as String);
            }
            return <String, dynamic>{
              'id': doc.id,
              ...data,
              'eventDate': dt,
            };
          })
          .where((e) {
            final dt = e['eventDate'] as DateTime?;
            return dt != null && dt.isAfter(now);
          })
          .toList()
        ..sort((a, b) {
          final da = a['eventDate'] as DateTime;
          final db = b['eventDate'] as DateTime;
          return da.compareTo(db);
        });

      if (!mounted) return;
      setState(() {
        _upcomingDeadlines = events;
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
    try {
      return await q.get();
    } catch (_) {
      return q.get(const GetOptions(source: Source.server));
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _firestoreGetDoc(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      return await ref.get();
    } catch (_) {
      return ref.get(const GetOptions(source: Source.server));
    }
  }

  bool _isActiveCase(CaseModel c) {
    if (c.isArchived) return false;
    if (CaseStatusFilter.isCompleted(c.status)) return false;
    if (OpenWorkTasks.isClosedCase(c)) return false;
    final s = c.status.toLowerCase().trim();
    if (s == 'declined' || s == 'cancelled' || s == 'canceled') return false;
    return true;
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

    final nonCancelledTasks =
        _myTasks.where((t) => !OpenWorkTasks.isCancelled(t.status)).toList();

    return {
      'totalTasks': nonCancelledTasks.length,
      'pendingTasks':
          nonCancelledTasks.where((t) => isPending(t.status)).length,
      'inProgressTasks':
          nonCancelledTasks.where((t) => isInProgress(t.status)).length,
      'completedTasks': _myTasks.where((t) => isCompleted(t.status)).length,
      'activeCases': _assignedCases.where(_isActiveCase).length,
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

  @override
  void dispose() {
    _uiDebounce?.cancel();
    _tasksSub?.cancel();
    _assignedCasesSub?.cancel();
    _attorneyCasesSub?.cancel();
    _calendarEventsSub?.cancel();
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
        isDesktop ? 28 : 100,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hearingNotifications.isNotEmpty) ...[
            _HearingReminders(notifications: _hearingNotifications),
            const SizedBox(height: 20),
          ],
          if (!isDesktop) ...[
            _MobileQuickActions(
              onMessage: _assignedAttorneyId != null
                  ? () => unawaited(_openChatWithAttorney())
                  : null,
              onPendingAppointments: widget.onNavigateToPendingAppointments,
              pendingCount: widget.pendingAppointmentsCount,
              onNotary: widget.onNavigateToNotary,
            ),
            const SizedBox(height: 20),
          ],
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: overviewCount,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              mainAxisExtent: isDesktop ? 132 : 128,
            ),
            children: [
              StaffOverviewCard(
                title: 'Total Tasks',
                value: '${_stats['totalTasks'] ?? 0}',
                subtitle: 'All assigned tasks',
                badgeText: 'All Work',
                icon: Icons.task_alt_rounded,
                iconColor: const Color(0xFF2563EB),
                pastel: const Color(0xFFEFF6FF),
                onTap: () => Get.to(
                  () => const StaffTasksScreen(initialFilter: 'all'),
                ),
              ),
              StaffOverviewCard(
                title: 'Pending Tasks',
                value: '${_stats['pendingTasks'] ?? 0}',
                subtitle: 'Awaiting action',
                badgeText: 'Action needed',
                icon: Icons.hourglass_top_rounded,
                iconColor: const Color(0xFFEA580C),
                pastel: const Color(0xFFFFF7ED),
                onTap: () => Get.to(
                  () => const StaffTasksScreen(initialFilter: 'pending'),
                ),
              ),
              StaffOverviewCard(
                title: 'In Progress',
                value: '${_stats['inProgressTasks'] ?? 0}',
                subtitle: 'Currently working',
                badgeText: 'Working',
                icon: Icons.work_outline_rounded,
                iconColor: const Color(0xFF0D9488),
                pastel: const Color(0xFFF0FDFA),
                onTap: () => Get.to(
                  () => const StaffTasksScreen(initialFilter: 'in_progress'),
                ),
              ),
              StaffOverviewCard(
                title: 'Active Cases',
                value: '${_stats['activeCases'] ?? 0}',
                subtitle: 'Assigned cases',
                badgeText: 'Active',
                icon: Icons.folder_open_rounded,
                iconColor: const Color(0xFF7C3AED),
                pastel: const Color(0xFFF5F3FF),
                onTap: widget.onNavigateToCases ??
                    () => Get.to(() => const StaffCasesScreen()),
              ),
              StaffOverviewCard(
                title: 'Completed Tasks',
                value: '${_stats['completedTasks'] ?? 0}',
                subtitle: 'Finished tasks',
                badgeText: 'Done',
                icon: Icons.check_circle_rounded,
                iconColor: const Color(0xFF16A34A),
                pastel: const Color(0xFFF0FDF4),
                onTap: () => Get.to(
                  () => const StaffTasksScreen(initialFilter: 'completed'),
                ),
              ),
              StaffOverviewCard(
                title: 'Upcoming Deadlines',
                value: '${_stats['upcomingDeadlines'] ?? 0}',
                subtitle: 'Hearings & deadlines',
                badgeText: 'Hearings',
                icon: Icons.event_note_rounded,
                iconColor: const Color(0xFF0284C7),
                pastel: const Color(0xFFF0F9FF),
                onTap: widget.onNavigateToCalendar ??
                    () => Get.to(
                          () => StaffCalendarScreen(
                            assignedAttorneyId: _assignedAttorneyId,
                          ),
                        ),
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
              onPaymentHistory: () => openPaymentHistoryScreen(
                context,
                recorderRole: 'staff',
                recorderName: widget.staffName,
              ),
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
            onPaymentHistory: () => openPaymentHistoryScreen(
              context,
              recorderRole: 'staff',
              recorderName: widget.staffName,
            ),
          ),
          Expanded(child: scroll),
        ],
      ),
    );
  }

  Widget _buildCasesPanel() {
    final cases = _assignedCases
        .where(_isActiveCase)
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
      actionLabel: 'View Calendar',
      onAction: widget.onNavigateToCalendar ??
          () => Get.to(
                () => StaffCalendarScreen(
                  assignedAttorneyId: _assignedAttorneyId,
                ),
              ),
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
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _getDeadlineColor(
                            deadline['eventDate'] as DateTime,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.event_note_rounded,
                          color: _getDeadlineColor(
                            deadline['eventDate'] as DateTime,
                          ),
                          size: 18,
                        ),
                      ),
                      title: Text(
                        deadline['title'] ?? 'Event',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StaffUi.style(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        DateFormat('MMM dd, yyyy • hh:mm a').format(
                          deadline['eventDate'] as DateTime,
                        ),
                        style: StaffUi.style(
                          fontSize: 11.5,
                          color: StaffUi.muted,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _buildActivityPanel() {
    final nonCancelled = _myTasks
        .where((t) => !OpenWorkTasks.isCancelled(t.status))
        .toList();
    final tasks = nonCancelled.take(5).toList();
    return _Panel(
      title: 'Recent Activity',
      actionLabel: tasks.isEmpty ? null : 'View All',
      onAction: tasks.isEmpty
          ? null
          : () => Get.to(() => const StaffTasksScreen(initialFilter: 'all')),
      child: tasks.isEmpty
          ? const _EmptyNote(
              icon: Icons.task_outlined,
              text: 'No tasks',
            )
          : Column(
              children: tasks
                  .map(
                    (task) => ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 2),
                      onTap: () =>
                          Get.to(() => const StaffTasksScreen(initialFilter: 'all')),
                      leading: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _getTaskStatusColor(task.status),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: _getTaskStatusIcon(task.status),
                      ),
                      title: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StaffUi.style(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        task.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StaffUi.style(
                          fontSize: 11.5,
                          color: StaffUi.muted,
                        ),
                      ),
                      trailing: Text(
                        _timeAgo(task.updatedAt ?? task.createdAt),
                        style: StaffUi.style(
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
        return Colors.orange.withValues(alpha: 0.2);
      case 'in_progress':
        return Colors.blue.withValues(alpha: 0.2);
      case 'completed':
        return Colors.green.withValues(alpha: 0.2);
      case 'cancelled':
      case 'canceled':
        return Colors.grey.withValues(alpha: 0.2);
      default:
        return Colors.grey.withValues(alpha: 0.2);
    }
  }

  Color _getCaseStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange.withValues(alpha: 0.2);
      case 'in_progress':
        return Colors.blue.withValues(alpha: 0.2);
      case 'completed':
        return Colors.green.withValues(alpha: 0.2);
      default:
        return Colors.grey.withValues(alpha: 0.2);
    }
  }
}

class _StaffHero extends StatelessWidget {
  const _StaffHero({
    required this.name,
    this.headerActions,
    this.onMessage,
    this.onPaymentHistory,
    this.compact = false,
  });

  final String name;
  final Widget? headerActions;
  final VoidCallback? onMessage;
  final VoidCallback? onPaymentHistory;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final todayStr = DateFormat('EEEE, MMMM d, y').format(DateTime.now());

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: StaffUi.heroGradient,
        boxShadow: StaffUi.heroShadow,
      ),
      child: ClipRect(
        child: Stack(
          children: [
            // Lightweight legal emblem watermark (Zero GPU memory overhead, freeze-proof)
            Positioned(
              right: compact ? -15 : 20,
              top: compact ? -15 : -30,
              bottom: compact ? -15 : -30,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.05,
                  child: Icon(
                    Icons.balance_rounded,
                    size: compact ? 180 : 250,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 18 : 28,
                compact ? 16 : 24,
                compact ? 18 : 28,
                compact ? 18 : 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top bar row: Date badge pill on left, Action Icons on far right ("pa kilid")
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 11,
                              color: StaffUi.gold,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              todayStr,
                              style: StaffUi.style(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (headerActions != null) headerActions!,
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Welcome greeting: Gets full width of screen, no truncation!
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Welcome, $name!',
                          style: StaffUi.style(
                            fontSize: compact ? 22 : 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.15,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('👋', style: TextStyle(fontSize: 20)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Here's your operational overview for today",
                    style: StaffUi.style(
                      fontSize: compact ? 12.5 : 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                  if (onMessage != null || onPaymentHistory != null) ...[
                    SizedBox(height: compact ? 12 : 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        if (onMessage != null)
                          Container(
                            decoration: BoxDecoration(
                              gradient: StaffUi.goldGradient,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: StaffUi.goldButtonShadow,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: onMessage,
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.chat_bubble_rounded,
                                        size: 16,
                                        color: StaffUi.navyDeep,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Message Attorney',
                                        style: StaffUi.style(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: StaffUi.navyDeep,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (onPaymentHistory != null)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.28),
                                width: 1,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: onPaymentHistory,
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.receipt_long_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Payment History',
                                        style: StaffUi.style(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
        color: StaffUi.card,
        borderRadius: BorderRadius.circular(StaffUi.radius),
        border: Border.all(color: StaffUi.line, width: 1),
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
                InkWell(
                  onTap: onAction,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: StaffUi.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: StaffUi.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          actionLabel!,
                          style: StaffUi.style(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: StaffUi.navy,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 10,
                          color: StaffUi.navy,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
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
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: StaffUi.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              size: 24,
              color: StaffUi.muted.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: StaffUi.style(color: StaffUi.muted, fontSize: 12.5),
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
    final style = StaffUi.style(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: StaffUi.muted,
      letterSpacing: 0.4,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
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
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.description_outlined,
                        size: 16,
                        color: StaffUi.navy,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        caseModel.caseTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StaffUi.style(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: StaffUi.navy,
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
                  style: StaffUi.style(fontSize: 12, color: StaffUi.muted),
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StaffUi.style(
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
                  style: StaffUi.style(fontSize: 12, color: StaffUi.muted),
                ),
              ),
              SizedBox(
                width: 72,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'View',
                      style: StaffUi.style(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: StaffUi.navy,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 10,
                      color: StaffUi.navy,
                    ),
                  ],
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
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(StaffUi.radius),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel_rounded, color: StaffUi.navy, size: 20),
              const SizedBox(width: 8),
              Text(
                'Hearing Reminders',
                style: StaffUi.style(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: StaffUi.navyDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...notifications.map((notification) {
            final hearingDate = notification['hearingDate'] as DateTime?;
            final daysUntil = hearingDate != null
                ? hearingDate.difference(DateTime.now()).inDays
                : 0;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: StaffUi.navy,
                  size: 18,
                ),
              ),
              title: Text(
                notification['caseTitle'] as String? ?? 'Hearing',
                style: StaffUi.style(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: StaffUi.navyDeep,
                ),
              ),
              subtitle: hearingDate == null
                  ? null
                  : Text(
                      daysUntil == 0
                          ? 'Today at ${DateFormat('hh:mm a').format(hearingDate)}'
                          : daysUntil == 1
                              ? 'Tomorrow at ${DateFormat('hh:mm a').format(hearingDate)}'
                              : 'In $daysUntil days • ${DateFormat('MMM dd, yyyy').format(hearingDate)}',
                      style: StaffUi.style(fontSize: 11.5, color: StaffUi.muted),
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
    this.onMessage,
    this.onPendingAppointments,
    this.onNotary,
    this.pendingCount = 0,
  });

  final VoidCallback? onMessage;
  final VoidCallback? onPendingAppointments;
  final VoidCallback? onNotary;
  final int pendingCount;

  Widget _buildButton({
    required String label,
    required IconData icon,
    required bool isGold,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: isGold ? StaffUi.goldGradient : null,
        color: isGold ? null : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isGold ? null : Border.all(color: StaffUi.line, width: 1.2),
        boxShadow: isGold ? StaffUi.goldButtonShadow : StaffUi.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(14),
          splashColor: isGold
              ? StaffUi.navyDeep.withValues(alpha: 0.15)
              : StaffUi.gold.withValues(alpha: 0.15),
          highlightColor: isGold
              ? StaffUi.navyDeep.withValues(alpha: 0.08)
              : StaffUi.gold.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isGold ? StaffUi.navyDeep : StaffUi.navy,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StaffUi.style(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isGold ? StaffUi.navyDeep : StaffUi.navyMid,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingAppointmentsCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: pendingCount > 0
              ? const Color(0xFFF97316).withValues(alpha: 0.35)
              : StaffUi.line,
          width: 1.2,
        ),
        boxShadow: StaffUi.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            if (onPendingAppointments != null) {
              onPendingAppointments!();
            } else {
              Get.to(() => const StaffPendingAppointmentsScreen());
            }
          },
          borderRadius: BorderRadius.circular(14),
          splashColor: const Color(0xFF1E6BFF).withValues(alpha: 0.1),
          highlightColor: const Color(0xFF1E6BFF).withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E6BFF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.pending_actions_rounded,
                    color: Color(0xFF1E6BFF),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Pending Appointments',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: StaffUi.style(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: StaffUi.navyDeep,
                              ),
                            ),
                          ),
                          if (pendingCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6.5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Text(
                                pendingCount > 99 ? '99+' : '$pendingCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Review client requests & schedule consultations',
                        style: StaffUi.style(
                          fontSize: 11.5,
                          color: StaffUi.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: StaffUi.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotaryCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StaffUi.line, width: 1.2),
        boxShadow: StaffUi.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            if (onNotary != null) {
              onNotary!();
            } else {
              Get.to(() => const StaffNotaryManagementScreen());
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: StaffUi.navyDeep.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.draw_outlined,
                    color: StaffUi.navyDeep,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notary Services',
                        style: StaffUi.style(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: StaffUi.navyDeep,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Manage document guidelines, requirements & templates',
                        style: StaffUi.style(
                          fontSize: 11.5,
                          color: StaffUi.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: StaffUi.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (onMessage != null) ...[
          _buildButton(
            label: 'Message Attorney',
            icon: Icons.chat_bubble_rounded,
            isGold: true,
            onTap: onMessage!,
          ),
          const SizedBox(height: 10),
        ],
        _buildPendingAppointmentsCard(context),
        const SizedBox(height: 10),
        _buildNotaryCard(context),
      ],
    );
  }
}

