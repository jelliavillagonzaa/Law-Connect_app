import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/task_service.dart';
import '../../services/staff_service.dart';
import '../../models/task_model.dart';
import '../../models/case_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/open_work_tasks.dart';
import '../../utils/task_priority.dart';
import 'task_detail_screen.dart';

class StaffTasksScreen extends StatefulWidget {
  final String? initialFilter;
  const StaffTasksScreen({super.key, this.initialFilter});

  @override
  State<StaffTasksScreen> createState() => _StaffTasksScreenState();
}

class _StaffTasksScreenState extends State<StaffTasksScreen> {
  final TaskService _taskService = TaskService();
  final StaffService _staffService = StaffService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _selectedFilter = 'all';
  Set<String> _closedCaseIds = {};
  StreamSubscription<List<CaseModel>>? _assignedCasesSub;
  StreamSubscription<List<CaseModel>>? _attorneyCasesSub;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilter != null) {
      _selectedFilter = widget.initialFilter!;
    }
    _listenClosedCases();
  }

  @override
  void didUpdateWidget(StaffTasksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFilter != null &&
        widget.initialFilter != oldWidget.initialFilter &&
        widget.initialFilter != _selectedFilter) {
      setState(() => _selectedFilter = widget.initialFilter!);
    }
  }

  @override
  void dispose() {
    _assignedCasesSub?.cancel();
    _attorneyCasesSub?.cancel();
    super.dispose();
  }

  void _listenClosedCases() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _assignedCasesSub = _staffService.getAssignedCases(user.uid).listen((
      cases,
    ) {
      if (!mounted) return;
      _mergeClosedCases(cases);
    });

    _firestore.collection('users').doc(user.uid).get().then((doc) {
      final attorneyId =
          (doc.data()?['assignedAttorneyId'] as String?)?.trim() ?? '';
      if (attorneyId.isEmpty || !mounted) return;
      _attorneyCasesSub = _staffService.getAttorneyCases(attorneyId).listen((
        cases,
      ) {
        if (!mounted) return;
        _mergeClosedCases(cases);
      });
    });
  }

  Future<void> _showCreateTaskDialog(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime? selectedDate = DateTime.now().add(const Duration(days: 3));
    int priority = 3; // 2 = High, 3 = Normal, 4 = Low
    String? selectedCaseId;
    List<CaseModel> availableCases = [];

    try {
      final snap = await FirebaseFirestore.instance
          .collection('cases')
          .where('staffAssigned', arrayContains: user.uid)
          .limit(30)
          .get();
      availableCases =
          snap.docs.map((doc) => CaseModel.fromFirestore(doc)).toList();
    } catch (_) {}

    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Create New Task',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Task Title *',
                        border: OutlineInputBorder(),
                        hintText: 'e.g., Draft affidavit, Review case documents',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                        hintText: 'Details about this task...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: priority,
                      decoration: const InputDecoration(
                        labelText: 'Priority',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 2, child: Text('High Priority')),
                        DropdownMenuItem(value: 3, child: Text('Normal Priority')),
                        DropdownMenuItem(value: 4, child: Text('Low Priority')),
                      ],
                      onChanged: (v) {
                        if (v != null) setModalState(() => priority = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    if (availableCases.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        value: selectedCaseId,
                        decoration: const InputDecoration(
                          labelText: 'Related Case (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('None / General Task')),
                          ...availableCases.map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(
                                c.caseTitle.length > 35
                                    ? '${c.caseTitle.substring(0, 32)}...'
                                    : c.caseTitle,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) => setModalState(() => selectedCaseId = v),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedDate == null
                                ? 'No due date set'
                                : 'Due: ${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: const Text('Pick Date'),
                          onPressed: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: modalCtx,
                              initialDate: selectedDate ?? now,
                              firstDate: now,
                              lastDate: now.add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setModalState(() => selectedDate = picked);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.royalBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () async {
                          final title = titleCtrl.text.trim();
                          if (title.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a task title')),
                            );
                            return;
                          }
                          Navigator.pop(modalCtx);
                          final res = await _taskService.createTask(
                            title: title,
                            description: descCtrl.text.trim(),
                            assignedTo: user.uid,
                            caseId: selectedCaseId,
                            dueDate: selectedDate,
                            priority: priority,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  res['success'] == true
                                      ? 'Task created successfully!'
                                      : 'Failed to create task: ${res['message']}',
                                ),
                                backgroundColor: res['success'] == true
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            );
                          }
                        },
                        child: const Text('Save Task', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _mergeClosedCases(List<CaseModel> cases) {
    setState(() {
      _closedCaseIds = {
        ..._closedCaseIds,
        ...OpenWorkTasks.closedCaseIds(cases),
      };
    });
  }

  String _filterLabel(String filter) {
    switch (filter) {
      case 'open':
        return 'Open Work';
      case 'pending':
        return 'Pending Tasks';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed Tasks';
      case 'closed':
        return 'Closed Cases';
      case 'all':
      default:
        return 'All Tasks';
    }
  }

  List<TaskModel> _applyFilter(List<TaskModel> tasks) {
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

    switch (_selectedFilter) {
      case 'open':
        return OpenWorkTasks.live(tasks, _closedCaseIds);
      case 'closed':
        return tasks.where((t) {
          if (OpenWorkTasks.isCancelled(t.status)) return true;
          final id = t.caseId?.trim() ?? '';
          return id.isNotEmpty && _closedCaseIds.contains(id);
        }).toList();
      case 'pending':
        return tasks
            .where((t) =>
                !OpenWorkTasks.isCancelled(t.status) && isPending(t.status))
            .toList();
      case 'in_progress':
        return tasks
            .where((t) =>
                !OpenWorkTasks.isCancelled(t.status) && isInProgress(t.status))
            .toList();
      case 'completed':
        return tasks.where((t) => isCompleted(t.status)).toList();
      case 'all':
      default:
        return tasks
            .where((t) => !OpenWorkTasks.isCancelled(t.status))
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Not logged in'));
    }

    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateTaskDialog(context),
        backgroundColor: AppTheme.royalBlue,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Task', style: TextStyle(color: Colors.white)),
      ),
      appBar: AppBar(
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: AppTheme.cleanWhite,
        elevation: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'My Tasks',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.cleanWhite,
              ),
            ),
            Text(
              _filterLabel(_selectedFilter),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppTheme.cleanWhite.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            color: AppTheme.cleanWhite,
            onSelected: (value) {
              setState(() => _selectedFilter = value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'open', child: Text('Open work')),
              const PopupMenuItem(value: 'pending', child: Text('Pending')),
              const PopupMenuItem(
                value: 'in_progress',
                child: Text('In Progress'),
              ),
              const PopupMenuItem(value: 'completed', child: Text('Completed')),
              const PopupMenuItem(
                value: 'closed',
                child: Text('Closed cases'),
              ),
              const PopupMenuItem(value: 'all', child: Text('All Tasks')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<TaskModel>>(
        stream: _taskService.getStaffTasks(user.uid, staffEmail: user.email),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const SizedBox.shrink();
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}', style: TextStyle()),
                ],
              ),
            );
          }

          final tasks = _applyFilter(snapshot.data ?? []);

          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.task_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    _emptyFilterMessage(),
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return FutureBuilder<_TaskContext>(
                future: _loadTaskContext(task),
                builder: (context, contextSnapshot) {
                  final taskContext = contextSnapshot.data;

                  // Compute due label and color
                  final dueInfo = _getDueInfo(task.dueDate);
                  final priorityLabel = _getPriorityLabel(task.priority);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TaskDetailScreen(taskId: task.id),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title and Priority
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    task.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                _buildPriorityBadge(
                                  priorityLabel,
                                  task.priority,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Case • Client line
                            if (taskContext != null &&
                                (taskContext.caseTitle != null ||
                                    taskContext.clientName != null))
                              Text(
                                [
                                  if (taskContext.caseTitle != null)
                                    taskContext.caseTitle!,
                                  if (taskContext.clientName != null)
                                    taskContext.clientName!,
                                ].join(' • '),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                ),
                              ),
                            if (taskContext != null &&
                                (taskContext.caseTitle != null ||
                                    taskContext.clientName != null))
                              const SizedBox(height: 8),
                            // Description preview
                            Text(
                              task.description,
                              style: const TextStyle(fontSize: 14),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            // Status and Due Date chips
                            Row(
                              children: [
                                Chip(
                                  label: Text(
                                    _getStatusLabel(task.status),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  backgroundColor: _getStatusColor(task.status),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                if (task.dueDate != null) ...[
                                  const SizedBox(width: 8),
                                  Chip(
                                    label: Text(
                                      dueInfo.label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: dueInfo.color,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    backgroundColor: dueInfo.color.withValues(
                                      alpha: 0.1,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                // Priority indicator dot
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: _getPriorityColor(task.priority),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPriorityBadge(String label, int? priority) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getPriorityColor(priority).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getPriorityColor(priority), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: _getPriorityColor(priority),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getPriorityLabel(int? priority) => TaskPriority.label(priority);

  Color _getPriorityColor(int? priority) => TaskPriority.color(priority);

  String _emptyFilterMessage() {
    switch (_selectedFilter) {
      case 'open':
        return 'No open tasks';
      case 'closed':
        return 'No closed-case tasks';
      case 'pending':
        return 'No pending tasks';
      case 'in_progress':
        return 'No in-progress tasks';
      case 'completed':
        return 'No completed tasks';
      default:
        return 'No tasks assigned yet';
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
      case 'canceled':
        return 'Cancelled';
      case 'overdue':
        return 'Overdue';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
      case 'canceled':
        return Colors.grey;
      case 'overdue':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Load extra context for a task: case title, client and attorney names, etc.
  Future<_TaskContext> _loadTaskContext(TaskModel task) async {
    String? caseTitle;
    String? clientId;
    String? clientName;
    String? attorneyName;
    String? staffName;

    try {
      // Load case info if available
      if (task.caseId != null && task.caseId!.isNotEmpty) {
        final caseDoc = await _firestore
            .collection('cases')
            .doc(task.caseId)
            .get();
        if (caseDoc.exists) {
          final caseModel = CaseModel.fromFirestore(caseDoc);
          caseTitle = caseModel.caseTitle;
          clientId = caseModel.clientId;

          // Load client name
          final clientDoc = await _firestore
              .collection('users')
              .doc(caseModel.clientId)
              .get();
          if (clientDoc.exists) {
            final data = clientDoc.data();
            clientName = data?['fullName'] ?? data?['name'] ?? data?['email'];
          }
        }
      }

      // Load attorney name
      if (task.attorneyId.isNotEmpty) {
        final attorneyDoc = await _firestore
            .collection('users')
            .doc(task.attorneyId)
            .get();
        if (attorneyDoc.exists) {
          final data = attorneyDoc.data();
          attorneyName = data?['fullName'] ?? data?['name'] ?? data?['email'];
        }
      }

      // Load staff name (assignedTo)
      if (task.assignedTo.isNotEmpty) {
        final staffDoc = await _firestore
            .collection('users')
            .doc(task.assignedTo)
            .get();
        if (staffDoc.exists) {
          final data = staffDoc.data();
          staffName = data?['fullName'] ?? data?['name'] ?? data?['email'];
        }
      }
    } catch (_) {
      // Fail silently – UI will just show less info
    }

    return _TaskContext(
      caseTitle: caseTitle,
      clientId: clientId,
      clientName: clientName,
      attorneyName: attorneyName,
      staffName: staffName,
    );
  }

  /// Compute human‑readable due label with color (Overdue, Today, etc.)
  _DueInfo _getDueInfo(DateTime? dueDate) {
    if (dueDate == null) {
      return const _DueInfo(label: 'No due date', color: Colors.grey);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = target.difference(today).inDays;

    if (diff < 0) {
      return _DueInfo(label: 'Overdue (${-diff} days)', color: Colors.red);
    } else if (diff == 0) {
      return const _DueInfo(label: 'Due Today', color: Colors.orange);
    } else if (diff == 1) {
      return const _DueInfo(label: 'Due Tomorrow', color: Colors.blue);
    } else if (diff <= 7) {
      return _DueInfo(label: '$diff days left', color: Colors.blue);
    } else {
      return _DueInfo(label: '$diff days left', color: Colors.green);
    }
  }
}

/// Extra context for displaying a task in the staff UI
class _TaskContext {
  final String? caseTitle;
  final String? clientId;
  final String? clientName;
  final String? attorneyName;
  final String? staffName;

  _TaskContext({
    this.caseTitle,
    this.clientId,
    this.clientName,
    this.attorneyName,
    this.staffName,
  });
}

class _DueInfo {
  final String label;
  final Color color;

  const _DueInfo({required this.label, required this.color});
}
