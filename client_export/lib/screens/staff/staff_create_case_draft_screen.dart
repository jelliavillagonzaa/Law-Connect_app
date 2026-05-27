import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../services/case_service.dart';
import '../../services/staff_auth_service.dart';
import '../../services/fcm_service.dart';
import '../../models/case_model.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';

class StaffCreateCaseDraftScreen extends StatefulWidget {
  const StaffCreateCaseDraftScreen({super.key});

  @override
  State<StaffCreateCaseDraftScreen> createState() => _StaffCreateCaseDraftScreenState();
}

class _StaffCreateCaseDraftScreenState extends State<StaffCreateCaseDraftScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _clientBackgroundController = TextEditingController();
  final _remarksController = TextEditingController();
  final _internalNotesController = TextEditingController();
  final CaseService _caseService = CaseService();
  final StaffAuthService _staffAuthService = StaffAuthService();
  final FCMService _fcmService = FCMService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _selectedClientId;
  String? _selectedCategory;
  String? _selectedStaffId; // For assigning other staff
  DateTime? _selectedHearingDate;
  bool _isLoading = false;
  bool _isLoadingClients = false;
  String? _assignedAttorneyId;
  List<Map<String, dynamic>> _clients = [];
  List<UserModel> _staffMembers = [];

  final List<String> _categories = [
    'Criminal',
    'Civil',
    'Family Law',
    'Corporate',
    'Real Estate',
    'Employment',
    'Personal Injury',
    'Immigration',
    'Intellectual Property',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    // First load staff info to get assigned attorney ID
    await _loadStaffInfo();
    // Then load clients and staff members (they depend on attorney ID)
    if (_assignedAttorneyId != null) {
      await Future.wait([
        _loadClients(),
        _loadStaffMembers(),
      ]);
    }
  }

  Future<void> _loadStaffInfo() async {
    try {
      final staff = await _staffAuthService.getCurrentStaff();
      if (staff != null && mounted) {
        setState(() {
          _assignedAttorneyId = staff.assignedAttorneyId;
        });
        debugPrint('✅ Staff attorney ID loaded: ${staff.assignedAttorneyId}');
      } else {
        debugPrint('⚠️ Staff not found or not mounted');
      }
    } catch (e) {
      debugPrint('❌ Error loading staff info: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading staff information: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadClients() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _assignedAttorneyId == null) {
        if (mounted) {
          setState(() => _isLoadingClients = false);
        }
        return;
      }

      if (mounted) {
        setState(() => _isLoadingClients = true);
      }

      final clientIds = <String>{};
      final clientsMap = <String, Map<String, dynamic>>{};

      // Get clients from existing cases
      try {
        final casesSnapshot = await _firestore
            .collection('cases')
            .where('attorneyId', isEqualTo: _assignedAttorneyId)
            .get();

        for (var caseDoc in casesSnapshot.docs) {
          final caseData = caseDoc.data();
          final clientId = caseData['clientId'] as String?;
          if (clientId != null &&
              clientId.trim().isNotEmpty &&
              !clientIds.contains(clientId)) {
            clientIds.add(clientId);
          }
        }
      } catch (e) {
        debugPrint('Error loading clients from cases: $e');
      }

      // Get clients from appointments
      try {
        final appointmentsSnapshot = await _firestore
            .collection('appointments')
            .where('attorneyId', isEqualTo: _assignedAttorneyId)
            .get();

        for (var aptDoc in appointmentsSnapshot.docs) {
          final aptData = aptDoc.data();
          final clientId = aptData['clientId'] as String?;
          if (clientId != null && !clientIds.contains(clientId)) {
            clientIds.add(clientId);
          }
        }
      } catch (e) {
        debugPrint('Error loading clients from appointments: $e');
      }

      // Note: Staff members don't have permission to read case_requests collection
      // Clients are loaded from existing cases and appointments only

      // Get client details
      for (var clientId in clientIds) {
        if (clientId.trim().isEmpty) continue;
        try {
          final clientDoc = await _firestore.collection('users').doc(clientId).get();
          if (clientDoc.exists) {
            final clientData = clientDoc.data()!;
            final name = clientData['name'] as String? ?? '';
            final fullName = clientData['fullName'] as String? ?? '';
            final email = clientData['email'] as String? ?? '';

            String displayName;
            if (fullName.isNotEmpty && fullName.trim().isNotEmpty) {
              displayName = fullName.trim();
            } else if (name.isNotEmpty && name.trim().isNotEmpty) {
              displayName = name.trim();
            } else if (email.isNotEmpty) {
              displayName = email;
            } else {
              displayName = 'Client';
            }

            clientsMap[clientId] = {
              'id': clientId,
              'name': name,
              'fullName': fullName,
              'displayName': displayName,
              'email': email,
            };
          }
        } catch (e) {
          debugPrint('Error loading client $clientId: $e');
        }
      }

      final clientsList = clientsMap.values.toList();
      clientsList.sort((a, b) {
        final nameA = (a['displayName'] as String? ?? '').toLowerCase();
        final nameB = (b['displayName'] as String? ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });

      if (mounted) {
        setState(() {
          _clients = clientsList;
          _isLoadingClients = false;
        });
        debugPrint('✅ Loaded ${clientsList.length} clients for attorney $_assignedAttorneyId');
        if (clientsList.isEmpty) {
          debugPrint('⚠️ No clients found. Checked cases and appointments for attorney $_assignedAttorneyId');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingClients = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading clients: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadStaffMembers() async {
    try {
      if (_assignedAttorneyId == null) return;

      final staffSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'staff')
          .where('assignedAttorneyId', isEqualTo: _assignedAttorneyId)
          .get();

      if (mounted) {
        setState(() {
          _staffMembers = staffSnapshot.docs
              .map((doc) => UserModel.fromFirestore(doc.data(), doc.id))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading staff members: $e');
    }
  }

  Future<void> _selectHearingDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedHearingDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.royalBlue,
              onPrimary: Colors.white,
              onSurface: AppTheme.darkText,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.royalBlue,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedHearingDate) {
      setState(() {
        _selectedHearingDate = picked;
      });
    }
  }

  Future<void> _submitDraft() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedClientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a client')),
      );
      return;
    }

    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a case category')),
      );
      return;
    }

    if (_assignedAttorneyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No attorney assigned')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in')),
        );
        setState(() => _isLoading = false);
        return;
      }

      // Build description with client background if provided
      String fullDescription = _descriptionController.text.trim();
      if (_clientBackgroundController.text.trim().isNotEmpty) {
        fullDescription += '\n\nClient Background:\n${_clientBackgroundController.text.trim()}';
      }

      // Build progress with internal notes and remarks
      final progressMap = <String, dynamic>{
        'timeline': [
          {
            'date': DateTime.now().toIso8601String(),
            'action': 'Draft case created by staff',
            'actor': user.uid,
          }
        ],
        'internalNotes': _internalNotesController.text.trim(),
        'remarks': _remarksController.text.trim(),
        'isDraft': true,
        'createdByStaff': user.uid,
      };

      if (_selectedHearingDate != null) {
        progressMap['hearingDate'] = _selectedHearingDate!.toIso8601String();
      }

      // Build staff assigned list
      List<String>? staffAssignedList;
      if (_selectedStaffId != null) {
        staffAssignedList = [user.uid, _selectedStaffId!];
      } else {
        staffAssignedList = [user.uid];
      }

      final caseModel = CaseModel(
        id: '',
        clientId: _selectedClientId!,
        attorneyId: _assignedAttorneyId,
        caseTitle: _titleController.text.trim(),
        caseType: _selectedCategory!,
        caseDescription: fullDescription,
        status: 'under_review', // Draft status - needs attorney review
        staffId: user.uid, // Set staffId to current staff member
        staffAssigned: staffAssignedList,
        hearingDate: _selectedHearingDate,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        progress: progressMap,
      );
      
      debugPrint('📋 CaseModel created:');
      debugPrint('   - clientId: ${caseModel.clientId}');
      debugPrint('   - attorneyId: ${caseModel.attorneyId}');
      debugPrint('   - status: ${caseModel.status}');
      debugPrint('   - staffId: ${caseModel.staffId}');
      debugPrint('   - staffAssigned: ${caseModel.staffAssigned}');

      debugPrint('📝 Submitting draft case...');
      debugPrint('   Client ID: $_selectedClientId');
      debugPrint('   Attorney ID: $_assignedAttorneyId');
      debugPrint('   Title: ${_titleController.text.trim()}');
      debugPrint('   Category: $_selectedCategory');
      debugPrint('   Status: under_review');
      debugPrint('   Staff ID: ${user.uid}');

      String? caseId;
      try {
        caseId = await _caseService.createCase(caseModel);
      } catch (e) {
        // Re-throw to be caught by outer catch block
        rethrow;
      }

      if (!mounted) return;

      if (caseId != null) {
        debugPrint('✅ Draft case created successfully: $caseId');
        
        // Notify attorney that draft is ready for review
        try {
          await _notifyAttorneyDraftReady(caseId, _titleController.text.trim());
          debugPrint('✅ Attorney notification sent');
        } catch (e) {
          debugPrint('⚠️ Failed to notify attorney (non-critical): $e');
          // Don't fail the operation if notification fails
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Draft case created! Attorney has been notified for review.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          
          // Add a small delay to ensure the snackbar is shown
          await Future.delayed(const Duration(milliseconds: 500));
          
          if (mounted) {
            // Check if we can pop before trying to pop
            if (Navigator.canPop(context)) {
              Navigator.pop(context, true);
            } else {
              // If we can't pop (e.g., screen was shown directly in bottom nav),
              // just notify the parent via a callback or do nothing
              // The parent widget should handle the refresh
              debugPrint('✅ Draft case created, but cannot pop navigation stack');
            }
          }
        }
      } else {
        debugPrint('❌ Failed to create draft case - caseId is null');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create draft case. Please check your connection and try again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      
      debugPrint('❌ Error creating case: $e');
      
      String errorMessage = 'Failed to create draft case';
      if (e.toString().contains('permission-denied') || e.toString().contains('Missing or insufficient permissions')) {
        errorMessage = 'Permission denied. Please ensure:\n'
            '1. You are logged in as a staff member\n'
            '2. You have an assigned attorney\n'
            '3. Your assigned attorney ID matches the case attorney ID';
      } else {
        errorMessage = 'Error creating case: ${e.toString()}';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _notifyAttorneyDraftReady(String caseId, String caseTitle) async {
    if (_assignedAttorneyId == null) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      final staffName = user?.displayName ?? 'Staff member';

      final title = 'Draft Case Ready for Review';
      final body = '$staffName has created a draft case: "$caseTitle"';

      // Send FCM notification
      await _fcmService.sendNotificationToUser(
        userId: _assignedAttorneyId!,
        title: title,
        body: body,
        data: {
          'type': 'draft_case_ready',
          'caseId': caseId,
          'staffId': user?.uid,
        },
      );

      // Save in-app notification to Firestore
      await _firestore.collection('notifications').add({
        'userId': _assignedAttorneyId!,
        'title': title,
        'message': body,
        'type': 'draft_case_ready',
        'data': {
          'caseId': caseId,
          'staffId': user?.uid,
        },
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Attorney notified about draft case $caseId');
    } catch (e) {
      debugPrint('⚠️ Failed to notify attorney: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Draft Case'),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.royalBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.royalBlue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.royalBlue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This draft will be sent to your attorney for review and approval.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.darkText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Client Selection
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Client *',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_assignedAttorneyId != null)
                    TextButton.icon(
                      onPressed: _loadClients,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.royalBlue,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _isLoadingClients || _clients.isEmpty
                    ? null
                    : (_selectedClientId != null &&
                            _clients.any((client) => client['id'] == _selectedClientId)
                        ? _selectedClientId
                        : null),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Select a client',
                ),
                items: _isLoadingClients
                    ? [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Loading clients...'),
                          enabled: false,
                        ),
                      ]
                    : _clients.isEmpty
                        ? [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('No clients found'),
                              enabled: false,
                            ),
                          ]
                        : _clients.map((client) {
                            final displayName = client['displayName'] as String? ??
                                client['fullName'] as String? ??
                                client['name'] as String? ??
                                'Client';
                            final email = client['email'] as String? ?? '';
                            return DropdownMenuItem<String>(
                              value: client['id'] as String,
                              child: Text(
                                email.isNotEmpty
                                    ? '$displayName ($email)'
                                    : displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedClientId = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a client';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Case Title
              const Text(
                'Case Title *',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter case title',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a case title';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Case Category
              const Text(
                'Case Category *',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Select a category',
                ),
                items: _categories.map((category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a category';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Case Description
              const Text(
                'Case Description *',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Describe the case in detail...',
                ),
                maxLines: 6,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  if (value.trim().length < 20) {
                    return 'Description must be at least 20 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Client Background (Optional)
              const Text(
                'Client Background (Optional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _clientBackgroundController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Add client background information...',
                ),
                maxLines: 4,
              ),

              const SizedBox(height: 24),

              // Assign Other Staff (Optional)
              const Text(
                'Assign Other Staff (Optional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedStaffId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Select staff member',
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('No Additional Staff'),
                  ),
                  ..._staffMembers.map((staff) {
                    return DropdownMenuItem<String>(
                      value: staff.id,
                      child: Text(staff.name),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedStaffId = value;
                  });
                },
              ),

              const SizedBox(height: 24),

              // First Hearing Date (Optional)
              const Text(
                'First Hearing Date (Optional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _selectHearingDate(context),
                child: AbsorbPointer(
                  child: TextFormField(
                    controller: TextEditingController(
                      text: _selectedHearingDate == null
                          ? ''
                          : DateFormat('yyyy-MM-dd').format(_selectedHearingDate!),
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Select date',
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Remarks for Attorney (Optional)
              const Text(
                'Remarks for Attorney Review (Optional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _remarksController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Add any remarks or notes for the attorney...',
                ),
                maxLines: 3,
              ),

              const SizedBox(height: 24),

              // Internal Notes (Optional)
              const Text(
                'Internal Notes (Optional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _internalNotesController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Add internal notes (not visible to client)...',
                ),
                maxLines: 3,
              ),

              const SizedBox(height: 32),

              // Submit Button
              ElevatedButton(
                onPressed: _isLoading ? null : _submitDraft,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.royalBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Create Draft & Notify Attorney',
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

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _clientBackgroundController.dispose();
    _remarksController.dispose();
    _internalNotesController.dispose();
    super.dispose();
  }
}

