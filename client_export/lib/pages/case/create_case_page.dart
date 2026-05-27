import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/case_service.dart';
import '../../services/search_service.dart';
import '../../models/case_model.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import 'search_attorney_page.dart';

class CreateCasePage extends StatefulWidget {
  const CreateCasePage({super.key});

  @override
  State<CreateCasePage> createState() => _CreateCasePageState();
}

class _CreateCasePageState extends State<CreateCasePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _caseTypeController = TextEditingController();
  final CaseService _caseService = CaseService();
  final SearchService _searchService = SearchService();
  
  List<String> _suggestions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _caseTypeController.addListener(_onCaseTypeChanged);
    _suggestions = _searchService.getAllCaseTypes();
  }

  void _onCaseTypeChanged() {
    if (!mounted) return;
    final query = _caseTypeController.text;
    // Use WidgetsBinding to schedule setState after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _suggestions = _searchService.getCaseTypeSuggestions(query);
        });
      }
    });
  }

  Future<void> _submitCase() async {
    if (!_formKey.currentState!.validate()) return;

    // Set loading state before async operations
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          Get.snackbar('Error', 'User not logged in');
          setState(() => _isLoading = false);
        }
        return;
      }

      // Check if user is verified (for clients)
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (userDoc.exists) {
        final userData = userDoc.data();
        final role = userData?['role'] ?? 'client';
        final isVerified = userData?['isVerified'] ?? false;
        
        if (role == 'client' && !isVerified) {
          if (mounted) {
            Get.snackbar(
              'Verification Required',
              'Please verify your email before creating a case. Check your email for the verification link.',
              backgroundColor: Colors.orange,
              colorText: Colors.white,
              duration: const Duration(seconds: 5),
            );
            setState(() => _isLoading = false);
          }
          return;
        }
      }

      final caseModel = CaseModel(
        id: '',
        clientId: user.uid,
        caseTitle: _titleController.text.trim(),
        caseType: _caseTypeController.text.trim(),
        caseDescription: _descriptionController.text.trim(),
        status: 'pending',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Await createCase() which now returns String? (caseId)
      final caseId = await _caseService.createCase(caseModel);
      
      // Set loading to false before navigation
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      if (caseId != null) {
        // Show success message
        if (mounted) {
          Get.snackbar(
            'Success',
            'Case created successfully',
            backgroundColor: Colors.green,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
          );
        }
        
        // Navigate back to dashboard after a short delay to ensure UI updates
        await Future.delayed(const Duration(milliseconds: 300));
        
        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        // Handle failure
        if (mounted) {
          Get.snackbar(
            'Error',
            'Failed to create case. Please try again.',
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 5),
          );
        }
      }
    } catch (e) {
      // Set loading to false on error
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      String errorMessage = 'Failed to create case';
      if (e.toString().contains('permission-denied')) {
        errorMessage = 'Permission denied. Please make sure you are logged in and verified.';
      } else if (e.toString().contains('Missing or insufficient permissions')) {
        errorMessage = 'You do not have permission to create cases. Please verify your email first.';
      } else {
        errorMessage = 'Failed to create case: ${e.toString()}';
      }
      
      if (mounted) {
        Get.snackbar(
          'Error',
          errorMessage,
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Case'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'Case Title',
                hint: 'Enter case title',
                controller: _titleController,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a case title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Case Type',
                hint: 'e.g., child abuse, theft, cybercrime',
                controller: _caseTypeController,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a case type';
                  }
                  return null;
                },
              ),
              if (_suggestions.isNotEmpty && _caseTypeController.text.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _suggestions.take(5).map((suggestion) {
                      return ListTile(
                        title: Text(suggestion),
                        onTap: () {
                          _caseTypeController.text = suggestion;
                          if (mounted) {
                            setState(() {
                              _suggestions = [];
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Case Description',
                hint: 'Describe your case in detail',
                controller: _descriptionController,
                maxLines: 5,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a case description';
                  }
                  if (value.length < 20) {
                    return 'Description must be at least 20 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              AppButton(
                text: 'Create Case',
                onPressed: _submitCase,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Get.to(() => const SearchAttorneyPage());
                },
                child: const Text('Search for an Attorney First'),
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
    _caseTypeController.dispose();
    super.dispose();
  }
}

