import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import '../../services/case_service.dart';
import '../../services/client_directory_service.dart';
import '../../services/staff_auth_service.dart';
import '../../services/staff_service.dart';
import '../../services/attorney_request_notify.dart';
import '../../utils/case_sms_formatter.dart';
import '../../models/case_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/dropdown_helpers.dart';

class StaffCreateCaseDraftScreen extends StatefulWidget {
  const StaffCreateCaseDraftScreen({super.key});

  @override
  State<StaffCreateCaseDraftScreen> createState() => _StaffCreateCaseDraftScreenState();
}

class _StaffCreateCaseDraftScreenState extends State<StaffCreateCaseDraftScreen> {
  static const String otherClientId = '__other_client__';

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _opposingPartyController = TextEditingController();
  final _remarksController = TextEditingController();
  final _otherCategoryController = TextEditingController();

  // Client Details Controllers
  final _clientNameController = TextEditingController();
  final _clientLocationController = TextEditingController();
  final _clientEmailController = TextEditingController();
  final _clientPhoneController = TextEditingController();

  // Court & Pleading details for the draft
  final _courtController = TextEditingController(text: 'REGIONAL TRIAL COURT');
  final _courtRegionController = TextEditingController(text: '10th Judicial Region');
  final _courtBranchController = TextEditingController(text: 'BRANCH 12 - OROQUIETA CITY');
  final _courtEmailController = TextEditingController(text: 'rtc1orq012@judiciary.gov.ph');
  final _courtContactController = TextEditingController(text: '09708694723');
  final _caseNumberController = TextEditingController();
  final _natureOfActionController = TextEditingController();

  final CaseService _caseService = CaseService();
  final StaffAuthService _staffAuthService = StaffAuthService();
  final ClientDirectoryService _clientDirectory = ClientDirectoryService();

  String? _selectedClientId;
  bool _isOtherClient = false;
  String? _selectedCategory;
  bool _isLoading = false;
  bool _isLoadingClients = false;
  String? _assignedAttorneyId;
  List<Map<String, dynamic>> _clients = [];

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
    await _loadStaffInfo();
    await _loadClients();
  }

  Future<void> _loadStaffInfo() async {
    try {
      final staff = await _staffAuthService.getCurrentStaff();
      String? aid = staff?.assignedAttorneyId.trim();
      if (aid == null || aid.isEmpty) {
        final attSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'attorney')
            .where('isActive', isEqualTo: true)
            .limit(1)
            .get();
        if (attSnap.docs.isNotEmpty) {
          aid = attSnap.docs.first.id;
        }
      }
      if (mounted) {
        setState(() {
          _assignedAttorneyId = (aid != null && aid.isNotEmpty) ? aid : null;
        });
        debugPrint('Staff attorney ID loaded: $_assignedAttorneyId');
      }
    } catch (e) {
      debugPrint('Error loading staff info: $e');
    }
  }

  Future<void> _loadClients() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() => _isLoadingClients = false);
        }
        return;
      }

      if (mounted) {
        setState(() => _isLoadingClients = true);
      }

      final clientsList = await _clientDirectory.loadSignedUpClients();

      if (mounted) {
        setState(() {
          _clients = clientsList;
          _isLoadingClients = false;
        });
        debugPrint('Loaded ${clientsList.length} signed-up clients');
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

  void _populateFromClient(Map<String, dynamic> client) {
    _isOtherClient = false;
    _selectedClientId = client['id'] as String?;
    final name = (client['displayName'] ?? client['fullName'] ?? client['name'] ?? '').toString();
    final email = (client['email'] ?? '').toString();
    final phone = (client['phone'] ?? client['phoneNumber'] ?? '').toString();
    final address = (client['address'] ?? client['location'] ?? '').toString();

    _clientNameController.text = name;
    _clientEmailController.text = email;
    _clientPhoneController.text = phone;
    _clientLocationController.text = address;
    setState(() {});
  }

  void _selectOtherClient() {
    _isOtherClient = true;
    _selectedClientId = otherClientId;
    _clientNameController.clear();
    _clientLocationController.clear();
    _clientEmailController.clear();
    _clientPhoneController.clear();
    setState(() {});
  }

  Future<void> _submitDraft() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedClientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or specify a client')),
      );
      return;
    }

    final clientName = _clientNameController.text.trim();
    if (clientName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the client name')),
      );
      return;
    }

    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a case category')),
      );
      return;
    }

    final resolvedCategory = _selectedCategory == 'Other'
        ? _otherCategoryController.text.trim()
        : _selectedCategory!.trim();
    if (resolvedCategory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please specify the case category')),
      );
      return;
    }

    if (_assignedAttorneyId == null || _assignedAttorneyId!.isEmpty) {
      try {
        final attSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'attorney')
            .where('isActive', isEqualTo: true)
            .limit(1)
            .get();
        if (attSnap.docs.isNotEmpty) {
          _assignedAttorneyId = attSnap.docs.first.id;
        }
      } catch (_) {}
    }

    if (_assignedAttorneyId == null || _assignedAttorneyId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active attorney found for assignment')),
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

      final progressMap = <String, dynamic>{
        'timeline': [
          {
            'date': DateTime.now().toIso8601String(),
            'action': 'Draft created',
            'actor': user.uid,
          }
        ],
        'remarks': _remarksController.text.trim(),
        'isDraft': true,
        'createdByStaff': user.uid,
      };

      final staffAssignedList = [user.uid];

      final resolvedClientId = (_isOtherClient || _selectedClientId == otherClientId)
          ? 'other_${DateTime.now().millisecondsSinceEpoch}'
          : _selectedClientId!;

      final caseModel = CaseModel(
        id: '',
        clientId: resolvedClientId,
        attorneyId: _assignedAttorneyId,
        caseTitle: _titleController.text.trim(),
        caseType: resolvedCategory,
        caseDescription: _remarksController.text.trim(),
        caseDescriptionDelta: '',
        status: 'under_review',
        staffId: user.uid,
        staffAssigned: staffAssignedList,
        opposingParty: _opposingPartyController.text.trim().isEmpty
            ? null
            : _opposingPartyController.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        progress: progressMap,
        clientName: clientName,
        clientEmail: _clientEmailController.text.trim().isEmpty
            ? null
            : _clientEmailController.text.trim(),
        clientPhone: _clientPhoneController.text.trim().isEmpty
            ? null
            : _clientPhoneController.text.trim(),
        clientAddress: _clientLocationController.text.trim().isEmpty
            ? null
            : _clientLocationController.text.trim(),
        court: _courtController.text.trim().isEmpty
            ? null
            : _courtController.text.trim(),
        courtBranch: _courtBranchController.text.trim().isEmpty
            ? null
            : _courtBranchController.text.trim(),
        courtRegion: _courtRegionController.text.trim().isEmpty
            ? null
            : _courtRegionController.text.trim(),
        courtEmail: _courtEmailController.text.trim().isEmpty
            ? null
            : _courtEmailController.text.trim(),
        courtContact: _courtContactController.text.trim().isEmpty
            ? null
            : _courtContactController.text.trim(),
        caseNumber: _caseNumberController.text.trim().isEmpty
            ? null
            : _caseNumberController.text.trim(),
        natureOfAction: _natureOfActionController.text.trim().isEmpty
            ? null
            : _natureOfActionController.text.trim(),
      );

      String? caseId;
      try {
        caseId = await _caseService.createCase(caseModel);
      } catch (e) {
        debugPrint('createCase returned error: $e');
        rethrow;
      }

      if (!mounted) return;

      if (caseId != null) {
        try {
          final staffName = user.displayName ?? 'Staff Member';
          final draftTitle = 'New Case Draft Submitted';
          final draftMsg = '$staffName submitted a new case draft: "${_titleController.text.trim()}" for client "$clientName".';
          await AttorneyRequestNotify.notifyAttorneys(
            attorneyIds: [_assignedAttorneyId!],
            title: draftTitle,
            message: draftMsg,
            smsBody: 'LawConnect: $draftMsg',
            type: 'case_draft',
            data: {
              'caseId': caseId,
              'caseTitle': _titleController.text.trim(),
              'clientName': clientName,
              'clientEmail': _clientEmailController.text.trim(),
              'clientPhone': _clientPhoneController.text.trim(),
              'clientAddress': _clientLocationController.text.trim(),
              'status': 'under_review',
              'submittedBy': user.uid,
              'staffName': staffName,
            },
          );
        } catch (e) {
          debugPrint('Failed to send notification: $e');
        }

        try {
          await StaffService().logActivity(
            action: 'Case draft created',
            details: 'Draft: "${_titleController.text.trim()}" for client "$clientName"',
            resourceType: 'case',
            resourceId: caseId,
          );
        } catch (_) {}

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Case draft created successfully! Awaiting attorney review.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create case draft'),
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

  String _clientLabel(Map<String, dynamic> client) {
    if (client['id'] == otherClientId) {
      return 'Other (Enter client manually)';
    }
    final displayName = client['displayName'] as String? ??
        client['fullName'] as String? ??
        client['name'] as String? ??
        'Client';
    final email = client['email'] as String? ?? '';
    return email.isNotEmpty ? '$displayName ($email)' : displayName;
  }

  String _clientLabelById(String id) {
    if (id == otherClientId) {
      return 'Other (Enter client manually)';
    }
    for (final client in _clients) {
      if (client['id'] == id) return _clientLabel(client);
    }
    return id;
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: AppTheme.royalBlue,
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> clientOptionIds = [
      ..._clients.map((c) => c['id'] as String),
      otherClientId,
    ];

    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      appBar: AppBar(
        title: const Text('Create Case Draft'),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submitDraft,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.royalBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  AppTheme.royalBlue.withValues(alpha: 0.5),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.assignment_turned_in_rounded, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Submit Draft for Review',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Prepare a case draft for attorney review and approval',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.mutedText,
                  ),
                ),
                const SizedBox(height: 24),
                _sectionHeader('CLIENT'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Select Client *',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _isLoadingClients ? null : _loadClients,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.royalBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Autocomplete<String>(
                      key: ValueKey(
                        'client-${_clients.length}-$_selectedClientId-$_isLoadingClients',
                      ),
                      initialValue: _selectedClientId == null
                          ? null
                          : TextEditingValue(
                              text: _clientLabelById(_selectedClientId!),
                            ),
                      displayStringForOption: _clientLabelById,
                      optionsBuilder: (textEditingValue) {
                        if (_isLoadingClients) {
                          return const Iterable<String>.empty();
                        }
                        final query = textEditingValue.text.trim().toLowerCase();
                        if (query.isEmpty) return clientOptionIds;
                        return clientOptionIds.where((id) {
                          if (id == otherClientId) {
                            return 'other enter manual'.contains(query);
                          }
                          final matchClient = _clients.firstWhere(
                            (c) => c['id'] == id,
                            orElse: () => {},
                          );
                          final label = _clientLabel(matchClient).toLowerCase();
                          final phone = (matchClient['phone'] ?? '').toString().toLowerCase();
                          final address = (matchClient['address'] ?? '').toString().toLowerCase();
                          return label.contains(query) ||
                              phone.contains(query) ||
                              address.contains(query);
                        });
                      },
                      onSelected: (id) {
                        if (id == otherClientId) {
                          _selectOtherClient();
                        } else {
                          final match = _clients.firstWhere((c) => c['id'] == id);
                          _populateFromClient(match);
                        }
                      },
                      fieldViewBuilder: (
                        context,
                        textEditingController,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          enabled: !_isLoadingClients,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            hintText: _isLoadingClients
                                ? 'Loading clients...'
                                : 'Search or select a client',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: const Icon(Icons.arrow_drop_down),
                          ),
                          onChanged: (value) {
                            final typed = value.trim().toLowerCase();
                            if (typed == 'other' || typed == 'other (enter client manually)') {
                              _selectOtherClient();
                              return;
                            }
                            for (final client in _clients) {
                              if (_clientLabel(client).toLowerCase() == typed ||
                                  (client['email'] ?? '').toString().toLowerCase() == typed) {
                                _populateFromClient(client);
                                return;
                              }
                            }
                          },
                          onFieldSubmitted: (_) => onFieldSubmitted(),
                          validator: (_) {
                            if (_selectedClientId == null) {
                              return 'Please select a client or choose Other';
                            }
                            return null;
                          },
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 240),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final id = options.elementAt(index);
                                    final isOther = id == otherClientId;
                                    return ListTile(
                                      leading: Icon(
                                        isOther ? Icons.person_add_alt_1_rounded : Icons.person_rounded,
                                        color: isOther ? AppTheme.royalBlue : Colors.grey.shade600,
                                        size: 20,
                                      ),
                                      title: Text(
                                        _clientLabelById(id),
                                        style: TextStyle(
                                          fontWeight: isOther ? FontWeight.w700 : FontWeight.w500,
                                          color: isOther ? AppTheme.royalBlue : Colors.black87,
                                        ),
                                      ),
                                      onTap: () => onSelected(id),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 14),

                // ── Client Details Card (Auto-filled or manual) ───────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _isOtherClient
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isOtherClient
                          ? const Color(0xFF93C5FD)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _isOtherClient ? 'Client Information (Manual)' : 'Client Information',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _isOtherClient ? const Color(0xFF1D4ED8) : AppTheme.navy,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _isOtherClient
                                  ? const Color(0xFFDBEAFE)
                                  : const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _isOtherClient ? 'Other / Manual' : 'Registered in App',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _isOtherClient ? const Color(0xFF1E40AF) : const Color(0xFF166534),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _fieldLabel('Client Full Name *'),
                      TextFormField(
                        controller: _clientNameController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Enter client full name',
                          isDense: true,
                          fillColor: Colors.white,
                          filled: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter client name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _fieldLabel('Location / Address'),
                      TextFormField(
                        controller: _clientLocationController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'e.g. Brgy. Poblacion, Oroquieta City',
                          isDense: true,
                          fillColor: Colors.white,
                          filled: true,
                          prefixIcon: Icon(Icons.location_on_outlined, size: 18),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _fieldLabel('Email Address'),
                                TextFormField(
                                  controller: _clientEmailController,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText: 'client@email.com',
                                    isDense: true,
                                    fillColor: Colors.white,
                                    filled: true,
                                    prefixIcon: Icon(Icons.email_outlined, size: 18),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _fieldLabel('Contact Number'),
                                TextFormField(
                                  controller: _clientPhoneController,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText: '09123456789',
                                    isDense: true,
                                    fillColor: Colors.white,
                                    filled: true,
                                    prefixIcon: Icon(Icons.phone_outlined, size: 18),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),
                _sectionHeader('CASE INFORMATION'),
                _fieldLabel('Case Title *'),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'e.g. Heirs of Victoriana Calib-og',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a case title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _fieldLabel('Case Category *'),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Autocomplete<String>(
                      optionsBuilder: (textEditingValue) {
                        final query = textEditingValue.text.trim().toLowerCase();
                        if (query.isEmpty) return _categories;
                        return _categories.where(
                          (category) => category.toLowerCase().contains(query),
                        );
                      },
                      onSelected: (value) {
                        setState(() {
                          _selectedCategory = value;
                          if (value != 'Other') {
                            _otherCategoryController.clear();
                          }
                        });
                      },
                      fieldViewBuilder: (
                        context,
                        textEditingController,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        return TextFormField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Select or type a category',
                            suffixIcon: Icon(Icons.arrow_drop_down),
                          ),
                          onChanged: (value) {
                            final trimmed = value.trim();
                            setState(() {
                              _selectedCategory =
                                  trimmed.isEmpty ? null : trimmed;
                              if (_selectedCategory != 'Other') {
                                _otherCategoryController.clear();
                              }
                            });
                          },
                          onFieldSubmitted: (value) {
                            final trimmed = value.trim();
                            setState(() {
                              _selectedCategory =
                                  trimmed.isEmpty ? null : trimmed;
                              if (_selectedCategory != 'Other') {
                                _otherCategoryController.clear();
                              }
                            });
                            onFieldSubmitted();
                          },
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please select or enter a category';
                            }
                            return null;
                          },
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 240),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final option = options.elementAt(index);
                                    return ListTile(
                                      title: dropdownEllipsisText(option),
                                      onTap: () => onSelected(option),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                if (_selectedCategory == 'Other') ...[
                  const SizedBox(height: 16),
                  _fieldLabel('Specify category *'),
                  TextFormField(
                    controller: _otherCategoryController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g. Tax, Labor, Maritime',
                    ),
                    validator: (value) {
                      if (_selectedCategory != 'Other') return null;
                      if (value == null || value.trim().isEmpty) {
                        return 'Please specify the case category';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 20),
                _fieldLabel('Opposing Party (Defendants)'),
                TextFormField(
                  controller: _opposingPartyController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'e.g. Ruben Montejo, Axel Joseph L. Binaoro, et al.',
                  ),
                ),

                const SizedBox(height: 20),
                // ── Court & Pleading Details ───────────────────────────────
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded: false,
                    title: const Text(
                      'Court & Pleading Header',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.royalBlue,
                      ),
                    ),
                    children: [
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _courtController,
                              decoration: const InputDecoration(
                                labelText: 'Court Name',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _courtRegionController,
                              decoration: const InputDecoration(
                                labelText: 'Judicial Region',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _courtBranchController,
                        decoration: const InputDecoration(
                          labelText: 'Branch & Station',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _caseNumberController,
                              decoration: const InputDecoration(
                                labelText: 'Civil Case No. / Docket No.',
                                hintText: 'e.g. Civil Case No. 5297',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _natureOfActionController,
                              decoration: const InputDecoration(
                                labelText: 'For: (Nature of Action)',
                                hintText: 'e.g. Recovery of Ownership with Possession',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _courtEmailController,
                              decoration: const InputDecoration(
                                labelText: 'Court Email Address',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _courtContactController,
                              decoration: const InputDecoration(
                                labelText: 'Court Contact Number',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                _fieldLabel('Case Description / Remarks *'),
                TextFormField(
                  controller: _remarksController,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Enter case facts, background, client requests, and details...',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter case description or remarks';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _opposingPartyController.dispose();
    _remarksController.dispose();
    _otherCategoryController.dispose();
    _clientNameController.dispose();
    _clientLocationController.dispose();
    _clientEmailController.dispose();
    _clientPhoneController.dispose();
    _courtController.dispose();
    _courtRegionController.dispose();
    _courtBranchController.dispose();
    _courtEmailController.dispose();
    _courtContactController.dispose();
    _caseNumberController.dispose();
    _natureOfActionController.dispose();
    super.dispose();
  }
}
