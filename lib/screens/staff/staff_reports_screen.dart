import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/staff_service.dart';
import '../../services/task_service.dart';
import '../../models/task_model.dart';
import '../../theme/app_theme.dart';

enum DateFilterType {
  all,
  today,
  thisWeek,
  thisMonth,
  thisYear,
  customDate,
  customRange,
}

class StaffReportsScreen extends StatefulWidget {
  const StaffReportsScreen({super.key});

  @override
  State<StaffReportsScreen> createState() => _StaffReportsScreenState();
}

class _StaffReportsScreenState extends State<StaffReportsScreen> {
  final StaffService _staffService = StaffService();
  final TaskService _taskService = TaskService();

  // Date filtering for activity logs
  DateFilterType _dateFilterType = DateFilterType.all;
  DateTime? _selectedDate;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
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
                  _buildFilterChip('All', DateFilterType.all),
                  _buildFilterChip('Today', DateFilterType.today),
                  _buildFilterChip('This Week', DateFilterType.thisWeek),
                  _buildFilterChip('This Month', DateFilterType.thisMonth),
                  _buildFilterChip('This Year', DateFilterType.thisYear),
                  _buildFilterChip('Custom Date', DateFilterType.customDate),
                  _buildFilterChip('Date Range', DateFilterType.customRange),
                ],
              ),
              // Custom Date/Range Selection
              if (_dateFilterType == DateFilterType.customDate ||
                  _dateFilterType == DateFilterType.customRange) ...[
                const SizedBox(height: 12),
                if (_dateFilterType == DateFilterType.customDate) ...[
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _selectDate(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppTheme.royalBlue),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Selected Date',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _selectedDate != null
                                          ? DateFormat(
                                              'MMMM dd, yyyy',
                                            ).format(_selectedDate!)
                                          : 'Select Date',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.royalBlue,
                                      ),
                                    ),
                                  ],
                                ),
                                Icon(
                                  Icons.calendar_today,
                                  color: AppTheme.royalBlue,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.today),
                        onPressed: () {
                          setState(() {
                            _selectedDate = DateTime.now();
                          });
                        },
                        tooltip: 'Today',
                        color: AppTheme.royalBlue,
                      ),
                    ],
                  ),
                ] else if (_dateFilterType == DateFilterType.customRange) ...[
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _selectStartDate(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppTheme.royalBlue),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Start Date',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _startDate != null
                                          ? DateFormat(
                                              'MMM dd, yyyy',
                                            ).format(_startDate!)
                                          : 'Select Start',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.royalBlue,
                                      ),
                                    ),
                                  ],
                                ),
                                Icon(
                                  Icons.calendar_today,
                                  color: AppTheme.royalBlue,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => _selectEndDate(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppTheme.royalBlue),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'End Date',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _endDate != null
                                          ? DateFormat(
                                              'MMM dd, yyyy',
                                            ).format(_endDate!)
                                          : 'Select End',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.royalBlue,
                                      ),
                                    ),
                                  ],
                                ),
                                Icon(
                                  Icons.calendar_today,
                                  color: AppTheme.royalBlue,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
        // Activity Logs List
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _staffService.getStaffActivityLogs(staffId),
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
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading logs',
                          style: TextStyle(fontSize: 18, color: Colors.red),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${snapshot.error}',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

              final allLogs = snapshot.data ?? [];

              // Filter logs based on selected filter type
              final filteredLogs = _filterLogsByDateRange(allLogs);

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
                      if (_dateFilterType != DateFilterType.all) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _dateFilterType = DateFilterType.all;
                            });
                          },
                          child: const Text('Show All Logs'),
                        ),
                      ],
                    ],
                  ),
                );
              }

              // Group logs by date
              final groupedLogs = <String, List<Map<String, dynamic>>>{};
              for (var log in filteredLogs) {
                final timestamp = log['timestamp'] as DateTime?;
                if (timestamp != null) {
                  final dateKey = DateFormat('MMMM dd, yyyy').format(timestamp);
                  groupedLogs.putIfAbsent(dateKey, () => []).add(log);
                }
              }

              final sortedDates = groupedLogs.keys.toList()
                ..sort((a, b) {
                  final dateA = DateFormat('MMMM dd, yyyy').parse(a);
                  final dateB = DateFormat('MMMM dd, yyyy').parse(b);
                  return dateB.compareTo(dateA);
                });

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: sortedDates.length,
                itemBuilder: (context, dateIndex) {
                  final dateKey = sortedDates[dateIndex];
                  final logsForDate = groupedLogs[dateKey]!;

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
                      // Logs for this date
                      ...logsForDate.map((log) => _buildLogCard(log)),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
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
          if (type == DateFilterType.today) {
            _selectedDate = DateTime.now();
          }
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
    DateTime startDate;
    DateTime endDate;

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
      case DateFilterType.thisYear:
        startDate = DateTime(now.year, 1, 1);
        endDate = DateTime(now.year + 1, 1, 1);
        break;
      case DateFilterType.customDate:
        if (_selectedDate == null) return [];
        startDate = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
        );
        endDate = startDate.add(const Duration(days: 1));
        break;
      case DateFilterType.customRange:
        if (_startDate == null || _endDate == null) return [];
        startDate = DateTime(
          _startDate!.year,
          _startDate!.month,
          _startDate!.day,
        );
        endDate = DateTime(
          _endDate!.year,
          _endDate!.month,
          _endDate!.day,
        ).add(const Duration(days: 1));
        break;
      default:
        return logs;
    }

    return logs.where((log) {
      final timestamp = log['timestamp'] as DateTime?;
      if (timestamp == null) return false;
      return timestamp.isAfter(
            startDate.subtract(const Duration(milliseconds: 1)),
          ) &&
          timestamp.isBefore(endDate);
    }).toList();
  }

  String _getEmptyStateMessage() {
    switch (_dateFilterType) {
      case DateFilterType.today:
        return 'No logs for today';
      case DateFilterType.thisWeek:
        return 'No logs for this week';
      case DateFilterType.thisMonth:
        return 'No logs for this month';
      case DateFilterType.thisYear:
        return 'No logs for this year';
      case DateFilterType.customDate:
        return 'No logs for selected date';
      case DateFilterType.customRange:
        return 'No logs for selected date range';
      default:
        return 'No activity logs yet';
    }
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final timestamp = log['timestamp'] as DateTime?;
    final action = log['action'] ?? 'Activity';
    final details = log['details'] ?? '';
    final resourceType = log['resourceType'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
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
            // Content
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
            // Resource Type Chip
            if (resourceType != null)
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

  Widget _buildTaskReports(String staffId) {
    return StreamBuilder<List<TaskModel>>(
      stream: _taskService.getStaffTasks(staffId),
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
        final completedTasks = tasks
            .where((t) => t.status == 'completed')
            .length;
        final pendingTasks = tasks.where((t) => t.status == 'pending').length;
        final inProgressTasks = tasks
            .where((t) => t.status == 'in_progress')
            .length;
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

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Cards
              Text(
                'Task Summary',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.royalBlue,
                ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _buildStatCard(
                    'Total Tasks',
                    '$totalTasks',
                    Icons.task,
                    AppTheme.royalBlue,
                  ),
                  _buildStatCard(
                    'Completed',
                    '$completedTasks',
                    Icons.check_circle,
                    Colors.green,
                  ),
                  _buildStatCard(
                    'In Progress',
                    '$inProgressTasks',
                    Icons.work,
                    Colors.blue,
                  ),
                  _buildStatCard(
                    'Pending',
                    '$pendingTasks',
                    Icons.pending,
                    Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Completed Tasks Section
              Text(
                'Completed Tasks',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.royalBlue,
                ),
              ),
              const SizedBox(height: 12),
              ...tasks
                  .where((t) => t.status == 'completed')
                  .take(20)
                  .map((task) => _buildTaskCard(task)),
              if (tasks.where((t) => t.status == 'completed').length > 20)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'Showing first 20 of ${tasks.where((t) => t.status == 'completed').length} completed tasks',
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
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
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
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _staffService.getDocumentUploadHistory(staffId),
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
                    'Error loading documents',
                    style: TextStyle(fontSize: 18, color: Colors.red),
                  ),
                ],
              ),
            ),
          );
        }

        final uploads = snapshot.data ?? [];

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
        for (var upload in uploads) {
          final timestamp = upload['timestamp'] as DateTime?;
          if (timestamp != null) {
            final dateKey = DateFormat('MMMM dd, yyyy').format(timestamp);
            groupedUploads.putIfAbsent(dateKey, () => []).add(upload);
          }
        }

        final sortedDates = groupedUploads.keys.toList()
          ..sort((a, b) {
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
    final timestamp = upload['timestamp'] as DateTime?;
    final details = upload['details'] ?? 'Document uploaded';
    final resourceType = upload['resourceType'] as String?;
    final resourceId = upload['resourceId'] as String?;

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
                  if (resourceType != null && resourceId != null) ...[
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
            if (resourceType != null)
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

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030, 12, 31), // Extended to 2030
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.royalBlue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateFilterType = DateFilterType.customDate;
      });
    }
  }

  Future<void> _selectStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030, 12, 31), // Extended to 2030
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.royalBlue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate != null && _startDate!.isAfter(_endDate!)) {
          _endDate = null; // Reset end date if start is after end
        }
        _dateFilterType = DateFilterType.customRange;
      });
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime(2030, 12, 31), // Extended to 2030
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.royalBlue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
        if (_startDate != null && _endDate!.isBefore(_startDate!)) {
          _startDate = _endDate; // Adjust start date if end is before start
        }
        _dateFilterType = DateFilterType.customRange;
      });
    }
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
