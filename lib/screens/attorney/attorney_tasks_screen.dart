import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/task_service.dart';
import '../../models/task_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/task_priority.dart';
import '../../pages/case/case_detail_page.dart';
import 'attorney_create_task_screen.dart';
import 'attorney_task_detail_screen.dart';

class AttorneyTasksScreen extends StatefulWidget {
  final String? attorneyId;
  final bool embedded;

  const AttorneyTasksScreen({
    super.key,
    this.attorneyId,
    this.embedded = false,
  });

  @override
  State<AttorneyTasksScreen> createState() => _AttorneyTasksScreenState();
}

class _AttorneyTasksScreenState extends State<AttorneyTasksScreen> {
  final TaskService _taskService = TaskService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, String> _staffNameCache = {};
  final Map<String, String> _caseTitleCache = {};
  String _selectedFilter = 'all';
  Stream<List<TaskModel>>? _tasksStream;
  String? _streamUid;
  String? _streamFilter;

  String get _resolvedUid {
    final explicit = widget.attorneyId?.trim() ?? '';
    if (explicit.isNotEmpty) return explicit;
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  Stream<List<TaskModel>> _getTasksStream(String uid) {
    if (_tasksStream != null &&
        _streamUid == uid &&
        _streamFilter == _selectedFilter) {
      return _tasksStream!;
    }
    _streamUid = uid;
    _streamFilter = _selectedFilter;
    _tasksStream = _selectedFilter == 'all'
        ? _taskService.getAttorneyTasks(uid)
        : _taskService.getAttorneyTasksByStatus(uid, _selectedFilter);
    return _tasksStream!;
  }

  @override
  Widget build(BuildContext context) {
    final uid = _resolvedUid;
    if (uid.isEmpty) {
      return StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          final liveUid = snapshot.data?.uid ?? '';
          if (liveUid.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildTasksShell(context, liveUid);
        },
      );
    }
    return _buildTasksShell(context, uid);
  }

  Widget _buildTasksShell(BuildContext context, String uid) {
    if (widget.embedded) {
      return Container(
        color: const Color(0xFFF4F7FC),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E6BFF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.checklist_rounded,
                    color: Color(0xFF1E6BFF),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Staff Tasks',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedFilter,
                      icon: const Icon(Icons.filter_list, size: 18),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedFilter = val);
                      },
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Tasks')),
                        DropdownMenuItem(value: 'pending', child: Text('Pending')),
                        DropdownMenuItem(
                          value: 'in_progress',
                          child: Text('In Progress'),
                        ),
                        DropdownMenuItem(value: 'completed', child: Text('Completed')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
                  icon: const Icon(Icons.add_task, size: 16),
                  label: const Text('New Staff Task'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E6BFF),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildTasksStreamView(uid)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      appBar: AppBar(
        title: const Text('Staff Tasks'),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_task),
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
            tooltip: 'New Staff Task',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            color: AppTheme.cleanWhite,
            onSelected: (value) {
              setState(() => _selectedFilter = value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All Tasks')),
              const PopupMenuItem(value: 'pending', child: Text('Pending')),
              const PopupMenuItem(
                value: 'in_progress',
                child: Text('In Progress'),
              ),
              const PopupMenuItem(value: 'completed', child: Text('Completed')),
            ],
          ),
        ],
      ),
      body: _buildTasksStreamView(uid),
    );
  }

  Widget _buildTasksStreamView(String uid) {
    return StreamBuilder<List<TaskModel>>(
      stream: _getTasksStream(uid),
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
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          final tasks = snapshot.data ?? [];

          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.task_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No staff tasks yet',
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
              return FutureBuilder<Map<String, String?>>(
                future: _loadTaskContext(task),
                builder: (context, contextSnapshot) {
                  final taskContext = contextSnapshot.data ?? {};
                  final staffName = taskContext['staffName'] ?? 'Staff Member';
                  final caseTitle = taskContext['caseTitle'];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    child: InkWell(
                      onTap: () {
                        // Navigate to task detail page for attorney to view and edit
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AttorneyTaskDetailScreen(
                              taskId: task.id,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                                _buildPriorityBadge(task.priority),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (caseTitle != null) ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.folder,
                                    size: 16,
                                    color: AppTheme.royalBlue,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Case: $caseTitle',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  if (task.caseId != null && task.caseId!.isNotEmpty)
                                    Icon(
                                      Icons.arrow_forward_ios,
                                      size: 14,
                                      color: AppTheme.royalBlue,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                            ],
                            Text(
                              'Assigned to: $staffName',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              task.description,
                              style: const TextStyle(fontSize: 14),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
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
                                      _getDueDateLabel(task.dueDate!),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _getDueDateColor(task.dueDate!),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    backgroundColor: _getDueDateColor(
                                      task.dueDate!,
                                    ).withValues(alpha: 0.1),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap to view and edit task details',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.royalBlue,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            if (task.caseId != null && task.caseId!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: () {
                                  // Navigate to case detail page
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CaseDetailPage(
                                        caseId: task.caseId!,
                                      ),
                                    ),
                                  );
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.folder_open,
                                      size: 14,
                                      color: AppTheme.royalBlue,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'View Case Details',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.royalBlue,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
      );
    }

  Future<Map<String, String?>> _loadTaskContext(TaskModel task) async {
    String? staffName = _staffNameCache[task.assignedTo];
    String? caseTitle =
        task.caseId != null ? _caseTitleCache[task.caseId!] : null;

    if (staffName != null &&
        (task.caseId == null || task.caseId!.isEmpty || caseTitle != null)) {
      return {'staffName': staffName, 'caseTitle': caseTitle};
    }

    try {
      // Load staff name
      if (staffName == null && task.assignedTo.isNotEmpty) {
        final staffDoc = await _firestore
            .collection('users')
            .doc(task.assignedTo)
            .get();
        if (staffDoc.exists) {
          final data = staffDoc.data();
          staffName = data?['fullName'] ?? data?['name'] ?? 'Staff Member';
          if (staffName != null) {
            _staffNameCache[task.assignedTo] = staffName;
          }
        }
      }

      // Load case title
      if (caseTitle == null && task.caseId != null && task.caseId!.isNotEmpty) {
        final caseDoc = await _firestore
            .collection('cases')
            .doc(task.caseId)
            .get();
        if (caseDoc.exists) {
          final data = caseDoc.data();
          caseTitle = data?['caseTitle'] ?? 'Case';
          if (caseTitle != null) {
            _caseTitleCache[task.caseId!] = caseTitle;
          }
        }
      }
    } catch (_) {
      // Fail silently
    }

    return {'staffName': staffName, 'caseTitle': caseTitle};
  }

  Widget _buildPriorityBadge(int? priority) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getPriorityColor(priority).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getPriorityColor(priority), width: 1),
      ),
      child: Text(
        _getPriorityLabel(priority),
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

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
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
      default:
        return Colors.grey;
    }
  }

  String _getDueDateLabel(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = target.difference(today).inDays;

    if (diff < 0) {
      return 'Overdue (${-diff} days)';
    } else if (diff == 0) {
      return 'Due Today';
    } else if (diff == 1) {
      return 'Due Tomorrow';
    } else {
      return '$diff days left';
    }
  }

  Color _getDueDateColor(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = target.difference(today).inDays;

    if (diff < 0) {
      return Colors.red;
    } else if (diff == 0) {
      return Colors.orange;
    } else if (diff <= 7) {
      return Colors.blue;
    } else {
      return Colors.green;
    }
  }
}
