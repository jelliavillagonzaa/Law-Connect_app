import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../services/case_service.dart';
import '../../services/case_request_service.dart';
import '../../models/case_model.dart';
import '../../theme/app_theme.dart';

class AttorneyCreateCaseScreen extends StatefulWidget {
  final String? clientId; // Pre-selected client (from request)
  final String? requestId; // Optional: if creating from a request
  final String? clientName; // Pre-filled client name

  const AttorneyCreateCaseScreen({
    super.key,
    this.clientId,
    this.requestId,
    this.clientName,
  });

  @override
  State<AttorneyCreateCaseScreen> createState() => _AttorneyCreateCaseScreenState();
}

class _AttorneyCreateCaseScreenState extends State<AttorneyCreateCaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final CaseService _caseService = CaseService();
  final CaseRequestService _requestService = CaseRequestService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _selectedClientId;
  String? _selectedCategory;
  String _selectedStatus = 'pending';
  String? _selectedStaffId;
  DateTime? _selectedHearingDate;
  bool _isLoading = false;
  bool _isLoadingClients = false;
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _staffMembers = [];

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

  final List<String> _statusOptions = [
    'pending',
    'under_review',
    'in_progress',
    'open',
    'ongoing',
  ];

  @override
  void initState() {
    super.initState();
    _loadClients();
    _loadStaffMembers();
    // Don't set _selectedClientId here - wait until clients are loaded
    // This prevents DropdownButton assertion errors
  }

  Future<void> _loadStaffMembers() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Get staff assigned to this attorney
      final staffSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'staff')
          .where('assignedAttorneyId', isEqualTo: user.uid)
          .get();

      final staffList = <Map<String, dynamic>>[];
      for (var doc in staffSnapshot.docs) {
        final data = doc.data();
        staffList.add({
          'id': doc.id,
          'name': data['fullName'] ?? data['name'] ?? 'Unknown',
          'email': data['email'] ?? '',
        });
      }

      if (mounted) {
        setState(() {
          _staffMembers = staffList;
        });
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _loadClients() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      setState(() => _isLoadingClients = true);

      final clientIds = <String>{};
      final clientsMap = <String, Map<String, dynamic>>{};

      // 1. Get clients from existing cases (same as appointment calendar)
      try {
        final casesSnapshot = await _firestore
            .collection('cases')
            .where('attorneyId', isEqualTo: user.uid)
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
        if (mounted) {
          debugPrint('Error loading clients from cases: $e');
        }
      }

      // 2. Get clients from appointments (same as appointment calendar)
      try {
        final appointmentsSnapshot = await _firestore
            .collection('appointments')
            .where('attorneyId', isEqualTo: user.uid)
            .get();

        for (var aptDoc in appointmentsSnapshot.docs) {
          final aptData = aptDoc.data();
          final clientId = aptData['clientId'] as String?;
          if (clientId != null && !clientIds.contains(clientId)) {
            clientIds.add(clientId);
          }
        }
      } catch (e) {
        if (mounted) {
          debugPrint('Error loading clients from appointments: $e');
        }
      }

      // 3. Get clients from case requests (if attorneyId matches or is null)
      try {
        final requestsSnapshot = await _firestore
            .collection('case_requests')
            .get();

        for (var requestDoc in requestsSnapshot.docs) {
          final requestData = requestDoc.data();
          final requestAttorneyId = requestData['attorneyId'] as String?;
          final clientId = requestData['clientId'] as String?;
          
          // Include if request is for this attorney or general (no attorneyId)
          if (clientId != null &&
              clientId.trim().isNotEmpty &&
              (requestAttorneyId == null || requestAttorneyId == user.uid) &&
              !clientIds.contains(clientId)) {
            clientIds.add(clientId);
          }
        }
      } catch (e) {
        if (mounted) {
          debugPrint('Error loading clients from requests: $e');
        }
      }

      // 4. If a clientId was pre-selected from widget (e.g., from case request),
      // ensure it's included even if not found in cases/appointments/requests
      if (widget.clientId != null &&
          widget.clientId!.trim().isNotEmpty &&
          !clientIds.contains(widget.clientId)) {
        clientIds.add(widget.clientId!);
      }

      // 4. Get client details from users collection (same as appointment calendar)
      for (var clientId in clientIds) {
        if (clientId.trim().isEmpty) continue;
        try {
          final clientDoc = await _firestore.collection('users').doc(clientId).get();
          if (clientDoc.exists) {
            final clientData = clientDoc.data()!;
            final name = clientData['name'] as String? ?? '';
            final fullName = clientData['fullName'] as String? ?? '';
            final email = clientData['email'] as String? ?? '';
            final isVerified = clientData['isVerified'] as bool? ?? false;

            // Build display name: prefer fullName, especially for verified clients
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

            // Store all information (same structure as appointment calendar)
            clientsMap[clientId] = {
              'id': clientId,
              'name': name,
              'fullName': fullName,
              'displayName': displayName,
              'email': email,
              'isVerified': isVerified,
            };
          }
        } catch (e) {
          if (mounted) {
            debugPrint('Error loading client $clientId: $e');
          }
        }
      }

      // Sort clients by display name (same as appointment calendar)
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
          
          // Now that clients are loaded, set the selected client if provided
          // Only set it if the client ID exists in the loaded clients
          if (widget.clientId != null && _selectedClientId == null) {
            final clientExists = clientsList.any((client) => client['id'] == widget.clientId);
            if (clientExists) {
              _selectedClientId = widget.clientId;
            }
          }
        });
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

  Future<void> _submitCase() async {
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

      // Build progress map with hearing date if selected
      Map<String, dynamic>? progressMap;
      if (_selectedHearingDate != null) {
        progressMap = {
          'hearingDate': _selectedHearingDate,
          'timeline': [
            {
              'date': DateTime.now().toIso8601String(),
              'action': 'Case created by attorney',
              'actor': user.uid,
            }
          ],
        };
      } else {
        progressMap = {
          'timeline': [
            {
              'date': DateTime.now().toIso8601String(),
              'action': 'Case created by attorney',
              'actor': user.uid,
            }
          ],
        };
      }

      final caseModel = CaseModel(
        id: '',
        clientId: _selectedClientId!,
        attorneyId: user.uid,
        caseTitle: _titleController.text.trim(),
        caseType: _selectedCategory!,
        caseDescription: _descriptionController.text.trim(),
        status: _selectedStatus,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        staffId: _selectedStaffId,
        hearingDate: _selectedHearingDate,
        progress: progressMap,
      );

      final caseId = await _caseService.createCase(caseModel);

      if (!mounted) return;

      if (caseId != null) {
        // Mark request as converted if it came from a request
        // Don't fail the entire operation if this fails - case is already created
        if (widget.requestId != null) {
          try {
            await _requestService.markRequestAsConverted(widget.requestId!, caseId);
          } catch (e) {
            // Log error but don't block success - case was created successfully
            if (mounted) {
              debugPrint('Warning: Failed to mark request as converted: $e');
              // Optionally show a warning, but don't treat it as a failure
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Case created successfully, but failed to update request status: $e'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Case created successfully! Client has been notified.'),
              backgroundColor: Colors.green,
            ),
          );
          // Check if we can pop before trying to pop
          if (Navigator.of(context).canPop()) {
            Navigator.pop(context, true); // Return true to indicate success
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create case'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Case'),
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
              // Client Selection
              const Text(
                'Client *',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                // Only set value if it exists in the items list to avoid assertion errors
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
                  hintText: 'e.g., Contract Dispute - ABC Company',
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
                  hintText: 'Select category',
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

              // Staff Assignment (Optional)
              if (_staffMembers.isNotEmpty) ...[
                const Text(
                  'Assign Staff (Optional)',
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
                      child: Text('None'),
                    ),
                    ..._staffMembers.map((staff) {
                      return DropdownMenuItem<String>(
                        value: staff['id'] as String,
                        child: Text('${staff['name']} (${staff['email']})'),
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
              ],

              // Hearing Date (Optional)
              const Text(
                'First Hearing Date (Optional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedHearingDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedHearingDate = picked;
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    _selectedHearingDate != null
                        ? '${_selectedHearingDate!.day}/${_selectedHearingDate!.month}/${_selectedHearingDate!.year}'
                        : 'Select date',
                    style: TextStyle(
                      color: _selectedHearingDate != null
                          ? Colors.black87
                          : Colors.grey[600],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Initial Status
              const Text(
                'Initial Status *',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedStatus,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: _statusOptions.map((status) {
                  return DropdownMenuItem<String>(
                    value: status,
                    child: Text(status.replaceAll('_', ' ').toUpperCase()),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedStatus = value ?? 'pending';
                  });
                },
              ),

              const SizedBox(height: 32),

              // Submit Button
              ElevatedButton(
                onPressed: _isLoading ? null : _submitCase,
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
                        'Create Case',
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
    super.dispose();
  }
}

