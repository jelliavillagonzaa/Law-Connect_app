import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/task_service.dart';
import '../../services/case_service.dart';
import '../../models/case_model.dart';
import '../../theme/app_theme.dart';

class AttorneyCreateTaskScreen extends StatefulWidget {
  final String? caseId; // Optional: pre-fill case if coming from case detail
  final String? caseTitle; // Optional: pre-fill case title

  const AttorneyCreateTaskScreen({super.key, this.caseId, this.caseTitle});

  @override
  State<AttorneyCreateTaskScreen> createState() =>
      _AttorneyCreateTaskScreenState();
}

class _AttorneyCreateTaskScreenState extends State<AttorneyCreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final TaskService _taskService = TaskService();
  final CaseService _caseService = CaseService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _selectedStaffId;
  String? _selectedCaseId;
  DateTime? _selectedDueDate;
  int? _selectedPriority; // 1=Urgent, 2=High, 3=Normal, 4=Low
  bool _isLoading = false;
  bool _isLoadingStaff = true;
  bool _isLoadingCases = true;

  List<Map<String, dynamic>> _staffList = [];
  List<CaseModel> _casesList = [];

  @override
  void initState() {
    super.initState();
    if (widget.caseId != null) {
      _selectedCaseId = widget.caseId;
    }
    _loadStaffMembers();
    _loadCases();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadStaffMembers() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Get staff members assigned to this attorney
      final staffQuery = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'staff')
          .where('assignedAttorneyId', isEqualTo: user.uid)
          .get();

      setState(() {
        _staffList = staffQuery.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': data['fullName'] ?? data['name'] ?? 'Staff Member',
            'email': data['email'] ?? '',
          };
        }).toList();
        _isLoadingStaff = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingStaff = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading staff: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadCases() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final casesStream = _caseService.getCasesForUser(user.uid, 'attorney');
      casesStream.listen((cases) {
        if (mounted) {
          setState(() {
            _casesList = cases;
            _isLoadingCases = false;
          });
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingCases = false;
      });
    }
  }

  Future<void> _selectDueDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _selectedDueDate ?? DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null && mounted) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      if (time != null && mounted) {
        setState(() {
          _selectedDueDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      } else if (mounted) {
        setState(() {
          _selectedDueDate = DateTime(picked.year, picked.month, picked.day);
        });
      }
    }
  }

  Future<void> _createTask() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedStaffId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a staff member to assign the task to'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _taskService.createTask(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        assignedTo: _selectedStaffId!,
        caseId: _selectedCaseId,
        dueDate: _selectedDueDate,
        priority: _selectedPriority,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Task created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          // Check if we can pop before trying to pop
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true); // Return true to indicate success
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${result['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Task'),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title Field
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Task Title *',
                  hintText: 'e.g., Draft Motion for Case 123',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.title),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a task title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Description Field
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description *',
                  hintText: 'What exactly needs to be done?',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.description),
                ),
                maxLines: 5,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Assign To Staff Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: _isLoadingStaff
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : DropdownButtonFormField<String>(
                        initialValue: _selectedStaffId,
                        decoration: const InputDecoration(
                          labelText: 'Assign To Staff *',
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.person),
                        ),
                        hint: const Text('Select staff member'),
                        items: _staffList.isEmpty
                            ? [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  enabled: false,
                                  child: Text('No staff members available'),
                                ),
                              ]
                            : _staffList.map((staff) {
                                return DropdownMenuItem<String>(
                                  value: staff['id'] as String,
                                  child: Text(
                                    staff['name'] as String,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                );
                              }).toList(),
                        onChanged: _staffList.isEmpty
                            ? null
                            : (value) {
                                setState(() {
                                  _selectedStaffId = value;
                                });
                              },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select a staff member';
                          }
                          return null;
                        },
                      ),
              ),
              const SizedBox(height: 20),

              // Link to Case Dropdown (Optional)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: _isLoadingCases
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : DropdownButtonFormField<String>(
                        initialValue: _selectedCaseId,
                        decoration: const InputDecoration(
                          labelText: 'Link to Case (Optional)',
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.folder),
                        ),
                        hint: const Text('Select a case'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('None'),
                          ),
                          ..._casesList.map((caseModel) {
                            return DropdownMenuItem<String>(
                              value: caseModel.id,
                              child: Text(
                                caseModel.caseTitle,
                                style: const TextStyle(fontSize: 16),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedCaseId = value;
                          });
                        },
                      ),
              ),
              const SizedBox(height: 20),

              // Due Date Picker
              InkWell(
                onTap: _selectDueDate,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.grey),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Due Date & Time (Optional)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedDueDate != null
                                  ? DateFormat(
                                      'MMM dd, yyyy • hh:mm a',
                                    ).format(_selectedDueDate!)
                                  : 'Select due date',
                              style: TextStyle(
                                fontSize: 16,
                                color: _selectedDueDate != null
                                    ? Colors.black
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_selectedDueDate != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            setState(() {
                              _selectedDueDate = null;
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Priority Selection
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Priority (Optional)',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildPriorityChip(1, 'Urgent', Colors.orange), // Professional warning color
                        _buildPriorityChip(2, 'High', Colors.orange),
                        _buildPriorityChip(3, 'Normal', Colors.blue),
                        _buildPriorityChip(4, 'Low', Colors.grey),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Create Button
              ElevatedButton(
                onPressed: _isLoading ? null : _createTask,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.royalBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Create Task',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityChip(int priority, String label, Color color) {
    final isSelected = _selectedPriority == priority;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedPriority = selected ? priority : null;
        });
      },
      selectedColor: color.withValues(alpha: 0.2),
      checkmarkColor: color,
      labelStyle: TextStyle(
        color: isSelected ? color : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected ? color : Colors.grey[300]!,
        width: isSelected ? 2 : 1,
      ),
    );
  }
}
