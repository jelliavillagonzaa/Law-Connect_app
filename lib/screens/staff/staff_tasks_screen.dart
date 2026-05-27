import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/task_service.dart';
import '../../models/task_model.dart';
import '../../models/case_model.dart';
import '../../theme/app_theme.dart';
import 'task_detail_screen.dart';

class StaffTasksScreen extends StatefulWidget {
  const StaffTasksScreen({super.key});

  @override
  State<StaffTasksScreen> createState() => _StaffTasksScreenState();
}

class _StaffTasksScreenState extends State<StaffTasksScreen> {
  final TaskService _taskService = TaskService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _selectedFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Not logged in'));
    }

    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      appBar: AppBar(
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: AppTheme.cleanWhite,
        elevation: 0,
        title: const Text(
          'My Tasks',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.cleanWhite,
          ),
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
      body: StreamBuilder<List<TaskModel>>(
        stream: _selectedFilter == 'all'
            ? _taskService.getStaffTasks(user.uid)
            : _taskService.getStaffTasksByStatus(user.uid, _selectedFilter),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
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

          final tasks = snapshot.data ?? [];

          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.task_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No tasks assigned yet',
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

  String _getPriorityLabel(int? priority) {
    switch (priority) {
      case 1:
        return 'Urgent';
      case 2:
        return 'High';
      case 3:
        return 'Normal';
      case 4:
        return 'Low';
      default:
        return 'Normal';
    }
  }

  Color _getPriorityColor(int? priority) {
    switch (priority) {
      case 1:
        return Colors.orange; // Professional warning color for urgent
      case 2:
        return Colors.orange;
      case 3:
        return AppTheme.royalBlue;
      case 4:
        return Colors.green;
      default:
        return Colors.grey;
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
