import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/staff_service.dart';
import '../../services/task_service.dart';
import '../../models/task_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/open_work_tasks.dart';
import '../../services/hearing_calendar_fields.dart';
import '../../utils/staff_task_report_export.dart';
import '../../widgets/staff/staff_task_report_download_button.dart';

enum DateFilterType {
  all,
  today,
  thisWeek,
  thisMonth,
}

class StaffReportsScreen extends StatefulWidget {
  const StaffReportsScreen({super.key});

  @override
  State<StaffReportsScreen> createState() => _StaffReportsScreenState();
}

class _StaffReportsScreenState extends State<StaffReportsScreen> {
  final StaffService _staffService = StaffService();
  final TaskService _taskService = TaskService();

  DateFilterType _dateFilterType = DateFilterType.thisWeek;
  bool _showSignIns = false;
  Future<List<Map<String, dynamic>>>? _logsFuture;
  String? _logsStaffId;
  Stream<List<TaskModel>>? _tasksStream;
  String? _tasksStaffId;

  Future<List<Map<String, dynamic>>> _activityLogsFuture(String staffId) {
    if (_logsFuture == null || _logsStaffId != staffId) {
      _logsStaffId = staffId;
      _logsFuture = _staffService.fetchStaffActivityLogs(staffId);
    }
    return _logsFuture!;
  }

  Stream<List<TaskModel>> _staffTasksStream(String staffId) {
    if (_tasksStream == null || _tasksStaffId != staffId) {
      _tasksStaffId = staffId;
      _tasksStream = _taskService.getStaffTasks(staffId);
    }
    return _tasksStream!;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return DefaultTabController(
      length: 3,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports & Logs'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
              tabs: const [
                Tab(icon: Icon(Icons.history, size: 20), text: 'Activity Logs'),
                Tab(icon: Icon(Icons.task_alt, size: 20), text: 'Task Reports'),
                Tab(
                  icon: Icon(Icons.description, size: 20),
                  text: 'Document History',
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _buildActivityLogs(user.uid),
            _buildTaskReports(user.uid),
            _buildDocumentHistory(user.uid),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityLogs(String staffId) {
    return Column(
      children: [
        // Date Filter Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter by Date',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.royalBlue,
                ),
              ),
              const SizedBox(height: 12),
              // Quick Filter Buttons
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFilterChip('Today', DateFilterType.today),
                  _buildFilterChip('This Week', DateFilterType.thisWeek),
                  _buildFilterChip('This Month', DateFilterType.thisMonth),
                  _buildFilterChip('All', DateFilterType.all),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Show sign-ins',
                  style: TextStyle(fontSize: 14),
                ),
                value: _showSignIns,
                activeThumbColor: AppTheme.royalBlue,
                onChanged: (value) {
                  setState(() => _showSignIns = value);
                },
              ),
            ],
          ),
        ),
        // Activity Logs List
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _activityLogsFuture(staffId),
            builder: (context, snapshot) {
              try {
                return _buildActivityLogsBody(snapshot);
              } catch (e) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not display logs. Hot restart and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActivityLogsBody(
    AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snapshot.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red[300],
              ),
              const SizedBox(height: 16),
              Text(
                'Could not load logs',
                style: TextStyle(fontSize: 18, color: Colors.red),
              ),
              const SizedBox(height: 8),
              Text(
                'Hot restart and try again.',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final allLogs = snapshot.data ?? [];
    final filteredLogs = _visibleLogs(allLogs);

    if (filteredLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _getEmptyStateMessage(),
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              _showSignIns
                  ? 'No activity in this filter.'
                  : 'Work logs appear when you update a task, create a draft, or upload a document.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
            if (_dateFilterType != DateFilterType.all) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _dateFilterType = DateFilterType.all;
                  });
                },
                child: const Text('Show all dates'),
              ),
            ],
          ],
        ),
      );
    }

    final groupedLogs = <String, List<Map<String, dynamic>>>{};
    for (final log in filteredLogs) {
      final timestamp = _safeDate(log['timestamp']);
      final dateKey = timestamp != null
          ? DateFormat('MMMM dd, yyyy').format(timestamp)
          : 'Unknown date';
      groupedLogs.putIfAbsent(dateKey, () => []).add(log);
    }

    final sortedDates = groupedLogs.keys.toList()
      ..sort((a, b) {
        if (a == 'Unknown date') return 1;
        if (b == 'Unknown date') return -1;
        final dateA = DateFormat('MMMM dd, yyyy').parse(a);
        final dateB = DateFormat('MMMM dd, yyyy').parse(b);
        return dateB.compareTo(dateA);
      });

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedDates.length + 1,
      itemBuilder: (context, dateIndex) {
        if (dateIndex == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWorkSummary(filteredLogs),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${filteredLogs.length} ${filteredLogs.length == 1 ? 'log' : 'logs'}'
                  '${_dateFilterType == DateFilterType.all ? '' : ' in this filter'}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        }
        final dateKey = sortedDates[dateIndex - 1];
        final logsForDate = groupedLogs[dateKey]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                bottom: 12,
                top: dateIndex > 1 ? 24 : 0,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.royalBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      dateKey,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.royalBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${logsForDate.length} ${logsForDate.length == 1 ? 'log' : 'logs'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...logsForDate.map((log) => _buildLogCard(log)),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(String label, DateFilterType type) {
    final isSelected = _dateFilterType == type;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _dateFilterType = type;
        });
      },
      selectedColor: AppTheme.royalBlue.withOpacity(0.2),
      checkmarkColor: AppTheme.royalBlue,
      labelStyle: TextStyle(
        color: isSelected ? AppTheme.royalBlue : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  List<Map<String, dynamic>> _filterLogsByDateRange(
    List<Map<String, dynamic>> logs,
  ) {
    if (_dateFilterType == DateFilterType.all) {
      return logs;
    }

    final now = DateTime.now();
    late DateTime startDate;
    late DateTime endDate;

    switch (_dateFilterType) {
      case DateFilterType.today:
        startDate = DateTime(now.year, now.month, now.day);
        endDate = startDate.add(const Duration(days: 1));
        break;
      case DateFilterType.thisWeek:
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        startDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
        endDate = startDate.add(const Duration(days: 7));
        break;
      case DateFilterType.thisMonth:
        startDate = DateTime(now.year, now.month, 1);
        endDate = DateTime(now.year, now.month + 1, 1);
        break;
      case DateFilterType.all:
        return logs;
    }

    return logs.where((log) {
      final timestamp = _safeDate(log['timestamp']);
      if (timestamp == null) return false;
      return timestamp.isAfter(
            startDate.subtract(const Duration(milliseconds: 1)),
          ) &&
          timestamp.isBefore(endDate);
    }).toList();
  }

  bool _isSignInLog(Map<String, dynamic> log) {
    final action = _safeString(log['action']).toLowerCase();
    final type = _safeString(log['resourceType']).toLowerCase();
    return type == 'session' ||
        action == 'signed in' ||
        action.contains('sign in') ||
        action.contains('session started');
  }

  List<Map<String, dynamic>> _visibleLogs(List<Map<String, dynamic>> allLogs) {
    var logs = _filterLogsByDateRange(allLogs);
    logs = logs
        .where((log) => !HearingCalendarFields.isJunkWorkLog(log))
        .toList();
    if (!_showSignIns) {
      logs = logs.where((log) => !_isSignInLog(log)).toList();
    }
    return logs;
  }

  String _getEmptyStateMessage() {
    switch (_dateFilterType) {
      case DateFilterType.today:
        return 'No work logs for today';
      case DateFilterType.thisWeek:
        return 'No work logs for this week';
      case DateFilterType.thisMonth:
        return 'No work logs for this month';
      case DateFilterType.all:
        return 'No work logs yet';
    }
  }

  Widget _buildWorkSummary(List<Map<String, dynamic>> logs) {
    final tasksDone = logs.where((log) {
      final action = _safeString(log['action']).toLowerCase();
      final details = _safeString(log['details']).toLowerCase();
      return action.contains('task') &&
          (details.contains('completed') || details.contains('to completed'));
    }).length;
    final drafts = logs.where((log) {
      return _safeString(log['action']).toLowerCase().contains('draft');
    }).length;
    final uploads = logs.where((log) {
      return _safeString(log['action']).toLowerCase().contains('upload');
    }).length;

    Widget chip(String label, int count) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.royalBlue.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.royalBlue,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          chip('tasks done', tasksDone),
          const SizedBox(width: 8),
          chip('drafts', drafts),
          const SizedBox(width: 8),
          chip('uploads', uploads),
        ],
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final timestamp = _safeDate(log['timestamp']);
    final action = _safeString(log['action'], 'Activity');
    final details = _safeString(log['details']);
    final resourceType = _safeString(log['resourceType']);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _getActionColor(action).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _getActionIcon(action),
                color: _getActionColor(action),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      details,
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                  ],
                  if (timestamp != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('hh:mm a').format(timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (resourceType.isNotEmpty)
              Chip(
                label: Text(resourceType, style: const TextStyle(fontSize: 10)),
                backgroundColor: AppTheme.lightGray,
                padding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
  }

  static String _safeString(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || trimmed == 'null' || trimmed == 'undefined') {
        return fallback;
      }
      return value;
    }
    try {
      final text = value.toString().trim();
      if (text.isEmpty || text == 'null' || text == 'undefined') {
        return fallback;
      }
      return text;
    } catch (_) {
      return fallback;
    }
  }

  static DateTime? _safeDate(dynamic value) {
    if (value is DateTime) return value;
    return StaffService.parseActivityTimestamp(value);
  }

  Widget _buildTaskReports(String staffId) {
    return StreamBuilder<List<TaskModel>>(
      stream: _staffTasksStream(staffId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading tasks',
                    style: TextStyle(fontSize: 18, color: Colors.red),
                  ),
                ],
              ),
            ),
          );
        }

        final tasks = snapshot.data ?? [];
        final completedTasks =
            tasks.where((t) => t.status == 'completed').length;
        final pendingTasks = tasks.where((t) => t.status == 'pending').length;
        final inProgressTasks =
            tasks.where((t) => t.status == 'in_progress').length;
        final cancelledTasks =
            tasks.where((t) => OpenWorkTasks.isCancelled(t.status)).length;
        final openWorkTasks =
            tasks.where((t) => OpenWorkTasks.isOpenStatus(t.status)).length;
        final totalTasks = tasks.length;

        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.task_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No tasks assigned yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        final completedList = tasks
            .where((t) => t.status == 'completed')
            .toList();
        final preparedBy = FirebaseAuth.instance.currentUser?.email ??
            FirebaseAuth.instance.currentUser?.displayName ??
            'Staff';
        final generatedAt = DateTime.now();
        final summaryReport = StaffTaskReportData(
          kind: StaffTaskReportKind.summary,
          preparedBy: preparedBy,
          generatedAt: generatedAt,
          totalTasks: totalTasks,
          completedCount: completedTasks,
          inProgressCount: inProgressTasks,
          pendingCount: pendingTasks,
          tasks: tasks,
        );
        final completedReport = StaffTaskReportData(
          kind: StaffTaskReportKind.completed,
          preparedBy: preparedBy,
          generatedAt: generatedAt,
          totalTasks: totalTasks,
          completedCount: completedTasks,
          inProgressCount: inProgressTasks,
          pendingCount: pendingTasks,
          tasks: completedList,
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Task Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.royalBlue,
                      ),
                    ),
                  ),
                  StaffTaskReportDownloadButton(data: summaryReport),
                ],
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxW = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : MediaQuery.sizeOf(context).width;
                  final wide = maxW >= 640;
                  return GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: wide ? 3 : 1,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      mainAxisExtent: 64,
                    ),
                    children: [
                      _buildStatCard(
                        'Open work',
                        '$openWorkTasks',
                        Icons.assignment_outlined,
                        AppTheme.royalBlue,
                      ),
                      _buildStatCard(
                        'Completed',
                        '$completedTasks',
                        Icons.check_circle,
                        Colors.green,
                      ),
                      _buildStatCard(
                        'Cancelled',
                        '$cancelledTasks',
                        Icons.cancel_outlined,
                        Colors.grey,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Completed Tasks',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.royalBlue,
                      ),
                    ),
                  ),
                  StaffTaskReportDownloadButton(data: completedReport),
                ],
              ),
              const SizedBox(height: 12),
              if (completedList.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'No completed tasks yet.',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                )
              else
                ...completedList.take(20).map((task) => _buildTaskCard(task)),
              if (completedList.length > 20)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'Showing first 20 of ${completedList.length} completed tasks',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(TaskModel task) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.check_circle, color: Colors.green, size: 24),
        ),
        title: Text(
          task.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                task.description,
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (task.completedAt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    'Completed: ${DateFormat('MMM dd, yyyy').format(task.completedAt!)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: Chip(
          label: const Text(
            'COMPLETED',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.green.withOpacity(0.2),
          labelStyle: const TextStyle(color: Colors.green),
        ),
      ),
    );
  }

  Widget _buildDocumentHistory(String staffId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _activityLogsFuture(staffId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Could not load documents',
                    style: TextStyle(fontSize: 18, color: Colors.red),
                  ),
                ],
              ),
            ),
          );
        }

        final uploads = (snapshot.data ?? []).where((log) {
          return _safeString(log['action']).toLowerCase().contains('upload');
        }).toList();

        if (uploads.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No document uploads yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        // Group uploads by date
        final groupedUploads = <String, List<Map<String, dynamic>>>{};
        for (final upload in uploads) {
          final timestamp = _safeDate(upload['timestamp']);
          final dateKey = timestamp != null
              ? DateFormat('MMMM dd, yyyy').format(timestamp)
              : 'Unknown date';
          groupedUploads.putIfAbsent(dateKey, () => []).add(upload);
        }

        final sortedDates = groupedUploads.keys.toList()
          ..sort((a, b) {
            if (a == 'Unknown date') return 1;
            if (b == 'Unknown date') return -1;
            final dateA = DateFormat('MMMM dd, yyyy').parse(a);
            final dateB = DateFormat('MMMM dd, yyyy').parse(b);
            return dateB.compareTo(dateA);
          });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sortedDates.length,
          itemBuilder: (context, dateIndex) {
            final dateKey = sortedDates[dateIndex];
            final uploadsForDate = groupedUploads[dateKey]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date Header
                Padding(
                  padding: EdgeInsets.only(
                    bottom: 12,
                    top: dateIndex > 0 ? 24 : 0,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.royalBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          dateKey,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.royalBlue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${uploadsForDate.length} ${uploadsForDate.length == 1 ? 'document' : 'documents'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Documents for this date
                ...uploadsForDate.map((upload) => _buildDocumentCard(upload)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDocumentCard(Map<String, dynamic> upload) {
    final timestamp = _safeDate(upload['timestamp']);
    final details = _safeString(upload['details'], 'Document uploaded');
    final resourceType = _safeString(upload['resourceType']);
    final resourceId = _safeString(upload['resourceId']);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.royalBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.upload,
                color: AppTheme.royalBlue,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    details,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (resourceType.isNotEmpty && resourceId.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Case: ${resourceId.substring(0, resourceId.length > 8 ? 8 : resourceId.length)}...',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                  if (timestamp != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('hh:mm a').format(timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (resourceType.isNotEmpty)
              Chip(
                label: Text(resourceType, style: const TextStyle(fontSize: 10)),
                backgroundColor: AppTheme.lightGray,
                padding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
    );
  }

  Color _getActionColor(String? action) {
    if (action == null) return AppTheme.royalBlue;
    final lowerAction = action.toLowerCase();
    if (lowerAction.contains('upload')) return Colors.blue;
    if (lowerAction.contains('note')) return Colors.orange;
    if (lowerAction.contains('update')) return Colors.green;
    if (lowerAction.contains('create')) return Colors.purple;
    return AppTheme.royalBlue;
  }

  IconData _getActionIcon(String? action) {
    if (action == null) return Icons.info;
    final lowerAction = action.toLowerCase();
    if (lowerAction.contains('upload')) return Icons.upload;
    if (lowerAction.contains('note')) return Icons.note_add;
    if (lowerAction.contains('update')) return Icons.edit;
    if (lowerAction.contains('create')) return Icons.add;
    return Icons.info;
  }
}
