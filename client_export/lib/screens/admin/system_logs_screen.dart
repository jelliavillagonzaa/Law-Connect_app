import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/system_log_model.dart';
import '../../services/admin_service.dart';

enum DateFilterType { oneWeek, oneMonth, oneYear, custom }

class SystemLogsScreen extends StatefulWidget {
  final bool inline;
  const SystemLogsScreen({super.key, this.inline = false});

  @override
  State<SystemLogsScreen> createState() => _SystemLogsScreenState();
}

class _SystemLogsScreenState extends State<SystemLogsScreen> {
  final AdminService _adminService = AdminService();
  DateTime _selectedDate = DateTime.now();
  DateTime? _startDate;
  DateTime? _endDate;
  DateFilterType _selectedFilter = DateFilterType.custom;
  List<DateTime> _datesWithLogs = [];
  bool _isLoadingDates = false;
  bool _showDatesList = false;

  @override
  void initState() {
    super.initState();
    _loadDatesWithLogs();
  }

  Future<void> _loadDatesWithLogs() async {
    setState(() {
      _isLoadingDates = true;
    });
    try {
      final dates = await _adminService.getDatesWithLogs();
      setState(() {
        _datesWithLogs = dates;
        _isLoadingDates = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingDates = false;
      });
    }
  }

  Widget _buildBody() {
    // Calculate date range based on selected filter
    DateTime startDate;
    DateTime endDate;
    final now = DateTime.now();

    switch (_selectedFilter) {
      case DateFilterType.oneWeek:
        startDate = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 7));
        endDate = DateTime(
          now.year,
          now.month,
          now.day,
        ).add(const Duration(days: 1));
        break;
      case DateFilterType.oneMonth:
        startDate = DateTime(now.year, now.month - 1, now.day);
        endDate = DateTime(
          now.year,
          now.month,
          now.day,
        ).add(const Duration(days: 1));
        break;
      case DateFilterType.oneYear:
        startDate = DateTime(now.year - 1, now.month, now.day);
        endDate = DateTime(
          now.year,
          now.month,
          now.day,
        ).add(const Duration(days: 1));
        break;
      case DateFilterType.custom:
        if (_startDate != null && _endDate != null) {
          // Use custom date range
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
        } else {
          // Fallback to single date
          startDate = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
          );
          endDate = startDate.add(const Duration(days: 1));
        }
        break;
    }

    return StreamBuilder<List<SystemLogModel>>(
      stream: _adminService.getSystemLogs(
        startDate: startDate,
        endDate: endDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Error loading logs',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final logs = snapshot.data ?? [];

        if (logs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.description_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No logs found',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'System logs will appear here when actions are performed',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            final actionColor = _getActionColor(log.action);

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.withOpacity(0.1), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon with colored background
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: actionColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getActionIcon(log.action),
                        color: actionColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Action title
                          Text(
                            _formatAction(log.action),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // User info
                          if (log.userName != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.person_outline,
                                    size: 14,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    log.userName!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Details
                          if (log.details != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 14,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      log.details!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Resource type
                          if (log.resourceType != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.category_outlined,
                                    size: 14,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    log.resourceType!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                          // Timestamp
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat(
                                  'yyyy-MM-dd HH:mm:ss',
                                ).format(log.timestamp),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
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

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (widget.inline) {
      return Column(
        children: [
          // Custom header bar for inline mode
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      'System Logs',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    // Date display with better styling
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: Colors.grey[700],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _getDateRangeText(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Calendar button (only show for custom filter)
                    if (_selectedFilter == DateFilterType.custom)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: _pickDate,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.calendar_today_outlined,
                              color: Colors.grey[700],
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    // Expand button (only show for custom filter)
                    if (_selectedFilter == DateFilterType.custom)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            setState(() {
                              _showDatesList = !_showDatesList;
                            });
                            if (_showDatesList && _datesWithLogs.isEmpty) {
                              _loadDatesWithLogs();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              _showDatesList
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: Colors.grey[700],
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // Filter buttons
                _buildFilterButtons(),
                if (_showDatesList && _selectedFilter == DateFilterType.custom)
                  _buildDatesList(),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Logs'),
        actions: [
          if (_selectedFilter == DateFilterType.custom) ...[
            IconButton(
              icon: const Icon(Icons.list),
              tooltip: 'Show dates with logs',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => _buildDatesDialog(),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.calendar_today_outlined),
              tooltip: 'Select date',
              onPressed: _pickDate,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Filter buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _buildFilterButtons(),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    // Show date range picker dialog
    await showDialog(
      context: context,
      builder: (context) => _buildDateRangePickerDialog(),
    );
  }

  Widget _buildDateRangePickerDialog() {
    final now = DateTime.now();
    DateTime tempStartDate = _startDate ?? now;
    DateTime tempEndDate = _endDate ?? now;

    return StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.date_range, color: Colors.blue[700]),
              const SizedBox(width: 8),
              const Text(
                'Select Date Range',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Start Date
                ListTile(
                  title: const Text('Start Date'),
                  subtitle: Text(
                    DateFormat('MMM dd, yyyy').format(tempStartDate),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: tempStartDate,
                      firstDate: DateTime(
                        1900,
                        1,
                        1,
                      ), // Allow selecting from 1900
                      lastDate: DateTime(
                        now.year + 10,
                        now.month + 1,
                        0,
                      ), // Allow up to 10 years in the future
                    );
                    if (picked != null) {
                      setDialogState(() {
                        tempStartDate = picked;
                        // Ensure end date is not before start date
                        if (tempStartDate.isAfter(tempEndDate)) {
                          tempEndDate = tempStartDate;
                        }
                      });
                    }
                  },
                ),
                const Divider(),
                // End Date
                ListTile(
                  title: const Text('End Date'),
                  subtitle: Text(
                    DateFormat('MMM dd, yyyy').format(tempEndDate),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: tempEndDate,
                      firstDate: tempStartDate,
                      lastDate: DateTime(
                        now.year + 10,
                        now.month + 1,
                        0,
                      ), // Allow up to 10 years in the future
                    );
                    if (picked != null) {
                      setDialogState(() {
                        tempEndDate = picked;
                        // Ensure start date is not after end date
                        if (tempEndDate.isBefore(tempStartDate)) {
                          tempStartDate = tempEndDate;
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                // Quick select buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildQuickRangeButton(
                      label: 'Last 7 Days',
                      onTap: () {
                        final now = DateTime.now();
                        setDialogState(() {
                          tempStartDate = now.subtract(const Duration(days: 7));
                          tempEndDate = now;
                        });
                      },
                    ),
                    _buildQuickRangeButton(
                      label: 'This Month',
                      onTap: () {
                        final now = DateTime.now();
                        setDialogState(() {
                          tempStartDate = DateTime(now.year, now.month, 1);
                          tempEndDate = now;
                        });
                      },
                    ),
                    _buildQuickRangeButton(
                      label: 'Last 30 Days',
                      onTap: () {
                        final now = DateTime.now();
                        setDialogState(() {
                          tempStartDate = now.subtract(
                            const Duration(days: 30),
                          );
                          tempEndDate = now;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _startDate = null;
                  _endDate = null;
                });
                Navigator.pop(context);
              },
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _startDate = tempStartDate;
                  _endDate = tempEndDate;
                  _selectedDate = tempStartDate;
                  _selectedFilter = DateFilterType.custom;
                });
                Navigator.pop(context);
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickRangeButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildFilterButtons() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip(
            label: 'One Week',
            filter: DateFilterType.oneWeek,
            icon: Icons.view_week,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'One Month',
            filter: DateFilterType.oneMonth,
            icon: Icons.calendar_month,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'One Year',
            filter: DateFilterType.oneYear,
            icon: Icons.date_range,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Custom',
            filter: DateFilterType.custom,
            icon: Icons.event,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required DateFilterType filter,
    required IconData icon,
  }) {
    final isSelected = _selectedFilter == filter;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected ? Colors.white : Colors.grey[700],
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedFilter = filter;
            if (filter == DateFilterType.custom) {
              _selectedDate = DateTime.now();
            }
          });
        }
      },
      selectedColor: Colors.blue,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? Colors.blue : Colors.grey[300]!,
          width: isSelected ? 2 : 1,
        ),
      ),
    );
  }

  String _getDateRangeText() {
    switch (_selectedFilter) {
      case DateFilterType.oneWeek:
        return 'Last 7 Days';
      case DateFilterType.oneMonth:
        return 'Last Month';
      case DateFilterType.oneYear:
        return 'Last Year';
      case DateFilterType.custom:
        if (_startDate != null && _endDate != null) {
          if (_startDate!.year == _endDate!.year &&
              _startDate!.month == _endDate!.month &&
              _startDate!.day == _endDate!.day) {
            // Same day
            return DateFormat('MMM dd, yyyy').format(_startDate!);
          } else {
            // Date range
            return '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd, yyyy').format(_endDate!)}';
          }
        }
        return DateFormat('MMM dd, yyyy').format(_selectedDate);
    }
  }

  Widget _buildDatesList() {
    if (_isLoadingDates) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_datesWithLogs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          'No logs found',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _datesWithLogs.length > 10 ? 10 : _datesWithLogs.length,
        itemBuilder: (context, index) {
          final date = _datesWithLogs[index];
          final isSelected =
              date.year == _selectedDate.year &&
              date.month == _selectedDate.month &&
              date.day == _selectedDate.day;

          return InkWell(
            onTap: () {
              setState(() {
                _selectedDate = date;
                _showDatesList = false;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.blue.withOpacity(0.1)
                    : Colors.transparent,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: isSelected ? Colors.blue : Colors.grey[600],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      DateFormat('MMM dd, yyyy (EEEE)').format(date),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected ? Colors.blue : Colors.black87,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: Colors.blue, size: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDatesDialog() {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.calendar_month, color: Colors.blue[700]),
          const SizedBox(width: 8),
          const Text(
            'Dates with Logs',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoadingDates
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            : _datesWithLogs.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_busy, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No logs found',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            : Container(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _datesWithLogs.length,
                  itemBuilder: (context, index) {
                    final date = _datesWithLogs[index];
                    final isSelected =
                        date.year == _selectedDate.year &&
                        date.month == _selectedDate.month &&
                        date.day == _selectedDate.day;

                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedDate = date;
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.blue.withOpacity(0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 18,
                              color: isSelected
                                  ? Colors.blue
                                  : Colors.grey[600],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                DateFormat('MMM dd, yyyy (EEEE)').format(date),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.blue
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_circle,
                                color: Colors.blue,
                                size: 22,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        TextButton.icon(
          onPressed: () {
            _loadDatesWithLogs();
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  IconData _getActionIcon(String action) {
    if (action.contains('login')) return Icons.login;
    if (action.contains('logout')) return Icons.logout;
    if (action.contains('case')) return Icons.folder;
    if (action.contains('user')) return Icons.person;
    if (action.contains('password')) return Icons.lock;
    if (action.contains('delete')) return Icons.delete;
    return Icons.info;
  }

  Color _getActionColor(String action) {
    if (action.contains('login')) return Colors.green;
    if (action.contains('logout')) return Colors.orange;
    if (action.contains('delete')) return Colors.red;
    if (action.contains('lock')) return Colors.red;
    return Colors.blue;
  }

  String _formatAction(String action) {
    return action
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) {
          return word[0].toUpperCase() + word.substring(1);
        })
        .join(' ');
  }

  // Export functionality removed.
}
