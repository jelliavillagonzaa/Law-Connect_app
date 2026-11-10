import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/task_service.dart';
import '../../services/case_service.dart';
import '../../models/case_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/task_priority.dart';
import '../../utils/case_status_filter.dart';
import '../../widgets/common/dropdown_helpers.dart';

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
  int? _selectedPriority = TaskPriority.normal;
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

      var staffQuery = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'staff')
          .get();

      if (staffQuery.docs.isEmpty) {
        staffQuery = await _firestore
            .collection('users')
            .where('email', isEqualTo: 'staff@gmail.com')
            .limit(1)
            .get();
      }

      var docs = staffQuery.docs;

      // 1. Filter out inactive accounts (isActive == false)
      final activeOnly = docs.where((d) => d.data()['isActive'] != false).toList();
      if (activeOnly.isNotEmpty) docs = activeOnly;

      // 2. Prioritize staff explicitly assigned to this attorney
      final assignedToMe = docs.where((d) {
        final aid = (d.data()['assignedAttorneyId'] ?? d.data()['attorneyId'] ?? '').toString().trim();
        return aid == user.uid;
      }).toList();
      if (assignedToMe.isNotEmpty) {
        docs = assignedToMe;
      } else if (docs.length > 1) {
        // 3. Prioritize 'apaostaff' (official office staff) over generic/dummy account
        final apao = docs.where((d) {
          final email = (d.data()['email'] ?? '').toString().toLowerCase();
          final name = (d.data()['fullName'] ?? d.data()['name'] ?? '').toString().toLowerCase();
          return email.contains('apao') || name.contains('apao');
        }).toList();
        if (apao.isNotEmpty) {
          docs = apao;
        }
      }

      // 4. Ensure only 1 active staff member remains so no manual filtering or dropdown is needed
      if (docs.length > 1) {
        docs = [docs.first];
      }

      final list = docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['fullName'] ?? data['name'] ?? 'Staff Member',
          'email': data['email'] ?? '',
        };
      }).toList();

      if (!mounted) return;
      setState(() {
        _staffList = list;
        if (_staffList.isNotEmpty) {
          _selectedStaffId = _staffList.first['id'] as String;
        }
        _isLoadingStaff = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingStaff = false;
      });
      if (kDebugMode) {
        debugPrint('Error loading staff: $e');
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
            _casesList = cases
                .where((c) => !CaseStatusFilter.isCompleted(c.status))
                .toList();
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

    _selectedStaffId ??=
        (_staffList.isNotEmpty ? _staffList.first['id'] as String? : null);

    if (_selectedStaffId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No staff member available to assign the task to'),
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
        priority: TaskPriority.coerce(_selectedPriority),
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
        title: const Text('New Staff Task'),
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
                  labelText: 'Task *',
                  hintText: 'Short name for the list',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.title),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a task';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Description Field
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Instructions *',
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
                    return 'Please enter instructions';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Assign To Staff
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: _isLoadingStaff
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : (_staffList.isEmpty
                        ? const Row(
                            children: [
                              Icon(Icons.person_outline, color: Colors.grey),
                              SizedBox(width: 12),
                              Text(
                                'No staff account found in system',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          )
                        : (_staffList.length == 1
                            ? Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E6BFF)
                                          .withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.person,
                                      color: Color(0xFF1E6BFF),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Assign Staff',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _staffList.first['name'] as String,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1A2744),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.check_circle_rounded,
                                          size: 14,
                                          color: Color(0xFF10B981),
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Auto-assigned',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF10B981),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _selectedStaffId,
                                decoration: const InputDecoration(
                                  labelText: 'Assign Staff *',
                                  border: InputBorder.none,
                                  prefixIcon: Icon(Icons.person),
                                  isDense: true,
                                ),
                                hint: const Text('Select staff member'),
                                items: _staffList.map((staff) {
                                  return DropdownMenuItem<String>(
                                    value: staff['id'] as String,
                                    child: dropdownEllipsisText(
                                      staff['name'] as String,
                                      fontSize: 16,
                                    ),
                                  );
                                }).toList(),
                                selectedItemBuilder: (context) =>
                                    dropdownSelectedLabels(
                                  _staffList
                                      .map((staff) => staff['name'] as String)
                                      .toList(),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedStaffId = value;
                                  });
                                },
                              ))),
              ),
              const SizedBox(height: 20),

              // Link to Case Dropdown (Optional)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
                        isExpanded: true,
                        initialValue: _selectedCaseId,
                        decoration: const InputDecoration(
                          labelText: 'Case',
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.folder),
                          isDense: true,
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
                              child: dropdownEllipsisText(
                                caseModel.caseTitle,
                                fontSize: 16,
                              ),
                            );
                          }),
                        ],
                        selectedItemBuilder: (context) => [
                          dropdownSelectedLabel('None'),
                          ...dropdownSelectedLabels(
                            _casesList
                                .map((caseModel) => caseModel.caseTitle)
                                .toList(),
                          ),
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
                              'Due',
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
                        'Create Staff Task',
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
}
