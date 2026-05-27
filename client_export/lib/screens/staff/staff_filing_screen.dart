import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/staff_service.dart';
import '../../services/staff_auth_service.dart';
import '../../theme/app_theme.dart';

class StaffFilingScreen extends StatefulWidget {
  const StaffFilingScreen({super.key});

  @override
  State<StaffFilingScreen> createState() => _StaffFilingScreenState();
}

class _StaffFilingScreenState extends State<StaffFilingScreen> {
  final StaffService _staffService = StaffService();
  final StaffAuthService _staffAuthService = StaffAuthService();
  String? _assignedAttorneyId;

  @override
  void initState() {
    super.initState();
    _loadAttorneyId();
  }

  Future<void> _loadAttorneyId() async {
    final staff = await _staffAuthService.getCurrentStaff();
    if (staff != null) {
      setState(() {
        _assignedAttorneyId = staff.assignedAttorneyId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_assignedAttorneyId == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Filing & Submission', style: TextStyle()),
        ),
        body: const Center(child: Text('No attorney assigned')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Filing & Submission', style: TextStyle()),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddFilingDialog(),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _staffService.getCalendarEvents(_assignedAttorneyId!)
            .map((events) => events.where((e) => 
                e['eventType'] == 'filing' || e['eventType'] == 'deadline').toList()),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}', style: TextStyle()),
            );
          }

          final filings = snapshot.data ?? [];

          if (filings.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.file_upload_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No filing deadlines',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // Sort by date
          filings.sort((a, b) {
            final dateA = a['eventDate'] as DateTime?;
            final dateB = b['eventDate'] as DateTime?;
            if (dateA == null || dateB == null) return 0;
            return dateA.compareTo(dateB);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filings.length,
            itemBuilder: (context, index) {
              final filing = filings[index];
              final eventDate = filing['eventDate'] as DateTime?;
              final daysUntil = eventDate != null
                  ? eventDate.difference(DateTime.now()).inDays
                  : 0;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: _getUrgencyColor(daysUntil),
                    child: Icon(
                      Icons.file_upload,
                      color: AppTheme.cleanWhite,
                    ),
                  ),
                  title: Text(
                    filing['title'] ?? 'Filing Deadline',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eventDate != null)
                        Text(
                          'Due: ${DateFormat('MMM dd, yyyy • hh:mm a').format(eventDate)}',
                          style: TextStyle(),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        _getUrgencyText(daysUntil),
                        style: TextStyle(
                          fontSize: 12,
                          color: _getUrgencyColor(daysUntil),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (filing['description'] != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          filing['description'],
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Chip(
                        label: Text(
                          '${daysUntil.abs()} ${daysUntil < 0 ? 'days overdue' : 'days left'}',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.cleanWhite,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        backgroundColor: _getUrgencyColor(daysUntil),
                      ),
                      if (daysUntil <= 3 && daysUntil >= 0)
                        IconButton(
                          icon: const Icon(Icons.checklist),
                          tooltip: 'View filing checklist',
                          onPressed: () => _showFilingChecklist(filing),
                        ),
                    ],
                  ),
                  onTap: () => _showFilingDetails(filing),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getUrgencyColor(int daysUntil) {
    if (daysUntil < 0) return Colors.red;
    if (daysUntil <= 1) return Colors.orange;
    if (daysUntil <= 3) return Colors.amber;
    return Colors.blue;
  }

  String _getUrgencyText(int daysUntil) {
    if (daysUntil < 0) return 'OVERDUE';
    if (daysUntil == 0) return 'DUE TODAY';
    if (daysUntil == 1) return 'DUE TOMORROW';
    if (daysUntil <= 3) return 'DUE SOON';
    return 'UPCOMING';
  }

  Future<void> _showAddFilingDialog() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime? selectedDate;
    TimeOfDay? selectedTime;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Add Filing Deadline', style: TextStyle()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Filing Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Requirements / Notes',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: Text(
                    selectedDate == null
                        ? 'Select Due Date'
                        : DateFormat('MMM dd, yyyy').format(selectedDate!),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setState(() => selectedDate = date);
                    }
                  },
                ),
                ListTile(
                  title: Text(
                    selectedTime == null
                        ? 'Select Time'
                        : selectedTime!.format(context),
                  ),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time != null) {
                      setState(() => selectedTime = time);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.isEmpty ||
                    selectedDate == null ||
                    selectedTime == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all required fields')),
                  );
                  return;
                }

                final eventDateTime = DateTime(
                  selectedDate!.year,
                  selectedDate!.month,
                  selectedDate!.day,
                  selectedTime!.hour,
                  selectedTime!.minute,
                );

                final result = await _staffService.createCalendarEvent(
                  eventType: 'filing',
                  eventDate: eventDateTime,
                  title: titleController.text,
                  description: descriptionController.text.isEmpty
                      ? null
                      : descriptionController.text,
                  assignedTo: _assignedAttorneyId,
                );

                if (result['success'] == true) {
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Filing deadline added successfully')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result['message'] ?? 'Failed to add deadline')),
                  );
                }
              },
              child: const Text('Add Deadline'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFilingDetails(Map<String, dynamic> filing) async {
    final eventDate = filing['eventDate'] as DateTime?;
    final daysUntil = eventDate != null
        ? eventDate.difference(DateTime.now()).inDays
        : 0;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(filing['title'] ?? 'Filing Deadline', style: TextStyle()),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eventDate != null)
                Text(
                  'Due: ${DateFormat('MMM dd, yyyy • hh:mm a').format(eventDate)}',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              const SizedBox(height: 12),
              Text(
                _getUrgencyText(daysUntil),
                style: TextStyle(
                  fontSize: 14,
                  color: _getUrgencyColor(daysUntil),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (filing['description'] != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Requirements:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  filing['description'],
                  style: TextStyle(),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showFilingChecklist(filing);
                },
                icon: const Icon(Icons.checklist),
                label: const Text('View Filing Checklist'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFilingChecklist(Map<String, dynamic> filing) async {
    final checklistItems = [
      'Documents prepared and reviewed',
      'All required signatures obtained',
      'Filing fees calculated and ready',
      'Court forms completed correctly',
      'Supporting documents attached',
      'Filing deadline verified',
      'Attorney approval obtained',
    ];

    final checkedItems = <int>{};

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Filing Checklist', style: TextStyle()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: checklistItems.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final isChecked = checkedItems.contains(index);

                return CheckboxListTile(
                  title: Text(item, style: TextStyle()),
                  value: isChecked,
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        checkedItems.add(index);
                      } else {
                        checkedItems.remove(index);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: checkedItems.length == checklistItems.length
                  ? () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('All filing requirements completed!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  : null,
              child: const Text('Complete'),
            ),
          ],
        ),
      ),
    );
  }
}

