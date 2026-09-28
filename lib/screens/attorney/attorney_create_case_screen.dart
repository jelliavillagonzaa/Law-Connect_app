import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../services/case_service.dart';
import '../../services/case_request_service.dart';
import '../../services/client_directory_service.dart';
import '../../models/case_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/case_status_filter.dart';
import '../../widgets/common/dropdown_helpers.dart';

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
  final _opposingPartyController = TextEditingController();
  final CaseService _caseService = CaseService();
  final CaseRequestService _requestService = CaseRequestService();
  final ClientDirectoryService _clientDirectory = ClientDirectoryService();

  String? _selectedClientId;
  String? _selectedCategory;
  bool _isLoading = false;
  bool _isLoadingClients = false;
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
  ];

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      setState(() => _isLoadingClients = true);

      final clientsList = await _clientDirectory.loadSignedUpClients(
        ensureClientId: widget.clientId,
      );

      if (mounted) {
        setState(() {
          _clients = clientsList;
          _isLoadingClients = false;

          if (widget.clientId != null && _selectedClientId == null) {
            final clientExists =
                clientsList.any((client) => client['id'] == widget.clientId);
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

    if (_selectedCategory == null || _selectedCategory!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or enter a case category')),
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

      final progressMap = {
        'timeline': [
          {
            'date': DateTime.now().toIso8601String(),
        'action': 'Case opened',
            'actor': user.uid,
          }
        ],
      };

      final caseModel = CaseModel(
        id: '',
        clientId: _selectedClientId!,
        attorneyId: user.uid,
        caseTitle: _titleController.text.trim(),
        caseType: _selectedCategory!.trim(),
        caseDescription: _descriptionController.text.trim(),
        status: CaseStatusFilter.openStoredStatus,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        opposingParty: _opposingPartyController.text.trim().isEmpty
            ? null
            : _opposingPartyController.text.trim(),
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

  String _clientLabel(Map<String, dynamic> client) {
    final displayName = client['displayName'] as String? ??
        client['fullName'] as String? ??
        client['name'] as String? ??
        'Client';
    final email = client['email'] as String? ?? '';
    return email.isNotEmpty ? '$displayName ($email)' : displayName;
  }

  String _clientLabelById(String id) {
    for (final client in _clients) {
      if (client['id'] == id) return _clientLabel(client);
    }
    return widget.clientName ?? id;
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
              const Text(
                'Add a new case to your law firm records',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.mutedText,
                ),
              ),
              const SizedBox(height: 24),
              _sectionHeader('CLIENT'),
              _fieldLabel('Select Client *'),
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
                      final matches = query.isEmpty
                          ? _clients
                          : _clients.where(
                              (client) => _clientLabel(client)
                                  .toLowerCase()
                                  .contains(query),
                            );
                      return matches.map((client) => client['id'] as String);
                    },
                    onSelected: (id) {
                      setState(() => _selectedClientId = id);
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
                          String? matchId;
                          for (final client in _clients) {
                            if (_clientLabel(client).toLowerCase() == typed) {
                              matchId = client['id'] as String;
                              break;
                            }
                          }
                          _selectedClientId = matchId;
                        },
                        onFieldSubmitted: (_) => onFieldSubmitted(),
                        validator: (_) {
                          if (_selectedClientId == null) {
                            return 'Please select a client';
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
                              child: options.isEmpty
                                  ? const ListTile(
                                      title: Text('No matching clients'),
                                    )
                                  : ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (context, index) {
                                        final id = options.elementAt(index);
                                        return ListTile(
                                          title: dropdownEllipsisText(
                                            _clientLabelById(id),
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
              const SizedBox(height: 28),
              _sectionHeader('CASE INFORMATION'),
              _fieldLabel('Case Title *'),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
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
                          _selectedCategory = trimmed.isEmpty ? null : trimmed;
                        },
                        onFieldSubmitted: (value) {
                          final trimmed = value.trim();
                          setState(() {
                            _selectedCategory =
                                trimmed.isEmpty ? null : trimmed;
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
              const SizedBox(height: 20),
              _fieldLabel('Opposing Party'),
              TextFormField(
                controller: _opposingPartyController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              _fieldLabel('Case Description *'),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Describe the case and client\'s legal concern...',
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
              const SizedBox(height: 32),
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
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
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
    _opposingPartyController.dispose();
    super.dispose();
  }
}

