import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/task_service.dart';
import '../../models/task_model.dart';
import '../../theme/app_theme.dart';
import '../../pages/case/case_detail_page.dart';
import 'attorney_create_task_screen.dart';
import 'attorney_task_detail_screen.dart';

class AttorneyTasksScreen extends StatefulWidget {
  const AttorneyTasksScreen({super.key});

  @override
  State<AttorneyTasksScreen> createState() => _AttorneyTasksScreenState();
}

class _AttorneyTasksScreenState extends State<AttorneyTasksScreen> {
  final TaskService _taskService = TaskService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _selectedFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      appBar: AppBar(
        title: const Text('Tasks'),
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
            tooltip: 'Create Task',
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
      body: StreamBuilder<List<TaskModel>>(
        stream: _selectedFilter == 'all'
            ? _taskService.getAttorneyTasks(user.uid)
            : _taskService.getAttorneyTasksByStatus(user.uid, _selectedFilter),
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
                    'No tasks created yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
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
                    icon: const Icon(Icons.add_task),
                    label: const Text('Create Your First Task'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.royalBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
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
      ),
    );
  }

  Future<Map<String, String?>> _loadTaskContext(TaskModel task) async {
    String? staffName;
    String? caseTitle;

    try {
      // Load staff name
      if (task.assignedTo.isNotEmpty) {
        final staffDoc = await _firestore
            .collection('users')
            .doc(task.assignedTo)
            .get();
        if (staffDoc.exists) {
          final data = staffDoc.data();
          staffName = data?['fullName'] ?? data?['name'] ?? 'Staff Member';
        }
      }

      // Load case title
      if (task.caseId != null && task.caseId!.isNotEmpty) {
        final caseDoc = await _firestore
            .collection('cases')
            .doc(task.caseId)
            .get();
        if (caseDoc.exists) {
          final data = caseDoc.data();
          caseTitle = data?['caseTitle'] ?? 'Case';
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
        return Colors.grey;
      default:
        return AppTheme.royalBlue;
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
