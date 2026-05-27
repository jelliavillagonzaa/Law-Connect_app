import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../../services/staff_application_service.dart';
import '../../widgets/common/app_text_field.dart';
import '../../theme/app_theme.dart';
import '../staff/staff_complete_registration_page.dart';
import 'otp_verification_signup.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key, this.initialRole});

  /// When set from role-specific landings, pre-selects `client`, `attorney`, or `staff`.
  final String? initialRole;

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _addressController = TextEditingController();
  final _specializationController = TextEditingController(); // For attorneys
  final _barNumberController = TextEditingController(); // For attorneys
  final _licenseStateController = TextEditingController(); // For attorneys
  final _staffMessageController = TextEditingController();

  final AuthService _authService = AuthService();
  final StorageService _storageService = StorageService();
  final StaffApplicationService _staffApplicationService =
      StaffApplicationService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String _selectedRole = 'client'; // 'client' | 'attorney' | 'staff'
  PlatformFile? _licenseDocument; // For attorney license document
  bool _isUploadingDocument = false;

  // Password strength indicators
  bool _hasMinLength = false;
  bool _hasUpperCase = false;
  bool _hasLowerCase = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;

  @override
  void initState() {
    super.initState();
    final r = widget.initialRole?.toLowerCase().trim();
    if (r == 'attorney') {
      _selectedRole = 'attorney';
    } else if (r == 'client') {
      _selectedRole = 'client';
    } else if (r == 'staff') {
      _selectedRole = 'staff';
    }
  }

  bool _staffReqExperience = false;
  bool _staffReqSupervision = false;
  bool _staffReqConfidentiality = false;
  bool _staffReqAccurate = false;

  bool get _allStaffRequirements =>
      _staffReqExperience &&
      _staffReqSupervision &&
      _staffReqConfidentiality &&
      _staffReqAccurate;

  String? _validateAddressForRole(String? value) {
    if (_selectedRole == 'staff') {
      if (value == null || value.trim().isEmpty) return null;
      if (value.trim().length < 5) {
        return 'If provided, address should be at least 5 characters';
      }
      return null;
    }
    return _validateAddress(value);
  }

  // Validation methods
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }

    // Check password strength
    _hasMinLength = value.length >= 8;
    _hasUpperCase = value.contains(RegExp(r'[A-Z]'));
    _hasLowerCase = value.contains(RegExp(r'[a-z]'));
    _hasNumber = value.contains(RegExp(r'[0-9]'));
    _hasSpecialChar = value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    // Update UI to show password strength
    setState(() {});

    if (!_hasMinLength) {
      return 'Password must be at least 8 characters';
    }
    if (!_hasUpperCase) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!_hasLowerCase) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!_hasNumber) {
      return 'Password must contain at least one number';
    }
    if (!_hasSpecialChar) {
      return 'Password must contain at least one special character (!@#\$%^&*...)';
    }

    return null;
  }

  String? _validatePhoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone number';
    }

    final cleaned = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    if (!RegExp(r'^\d+$').hasMatch(cleaned)) {
      return 'Phone number must contain only digits';
    }

    if (cleaned.length < 10 || cleaned.length > 15) {
      return 'Phone number must be between 10-15 digits';
    }

    return null;
  }

  String? _validateAddress(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your address';
    }

    final trimmed = value.trim();
    if (trimmed.length < 10) {
      return 'Address must be at least 10 characters';
    }

    if (!RegExp(r'[a-zA-Z]').hasMatch(trimmed)) {
      return 'Address must contain letters';
    }

    if (RegExp(r'^(.)\1+$').hasMatch(trimmed)) {
      return 'Please enter a valid address';
    }

    return null;
  }

  String? _validateAttorneyField(String? value, String fieldName) {
    if (_selectedRole != 'attorney') return null;
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your $fieldName';
    }
    if (value.trim().length < 2) {
      return '$fieldName must be at least 2 characters';
    }
    return null;
  }

  Future<void> _pickLicenseDocument() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;

        // Check file size (max 10MB)
        if (file.size > 10 * 1024 * 1024) {
          if (mounted) {
            Get.snackbar(
              'File Too Large',
              'License document must be less than 10MB',
              backgroundColor: Colors.red,
              colorText: Colors.white,
            );
          }
          return;
        }

        setState(() {
          _licenseDocument = file;
        });

        if (mounted) {
          Get.snackbar(
            'Document Selected',
            'License document: ${file.name}',
            backgroundColor: Colors.green,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error picking document: $e');
      }
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to pick document. Please try again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRole == 'staff') {
      if (!_allStaffRequirements) {
        Get.snackbar(
          'Requirements',
          'Please confirm all staff requirements below.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      setState(() => _isLoading = true);
      try {
        final result = await _staffApplicationService.submitApplication(
          email: _emailController.text.trim(),
          name: _fullNameController.text.trim(),
          phone: _phoneNumberController.text.trim(),
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          message: _staffMessageController.text.trim().isEmpty
              ? null
              : _staffMessageController.text.trim(),
          agreedToRequirements: true,
        );

        if (!mounted) return;

        if (result['success'] == true) {
          Get.snackbar(
            'Application sent',
            result['message'] as String? ??
                'An administrator will review your request. After approval, return here or use the Staff portal to set your password.',
            backgroundColor: Colors.green,
            colorText: Colors.white,
            duration: const Duration(seconds: 5),
          );
          await Future.delayed(const Duration(milliseconds: 600));
          if (!mounted) return;
          await Get.dialog<void>(
            AlertDialog(
              title: const Text('Next steps'),
              content: const Text(
                'When an admin approves your application, open '
                'Staff portal → “Complete registration (after approval)” '
                'or choose Staff on this sign-up page and use the same link from the staff landing page to create your password.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Get.back(),
                  child: const Text('Stay here'),
                ),
                TextButton(
                  onPressed: () {
                    Get.back();
                    Get.to(() => const StaffCompleteRegistrationPage());
                  },
                  child: const Text('Set password (if approved)'),
                ),
              ],
            ),
          );
        } else {
          Get.snackbar(
            'Could not submit',
            result['message'] as String? ?? 'Try again later.',
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 4),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }

    // Check if passwords match
    if (_passwordController.text != _confirmPasswordController.text) {
      Get.snackbar(
        'Error',
        'Passwords do not match',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      Map<String, dynamic> result;

      if (_selectedRole == 'client') {
        // Client signup
        result = await _authService.clientSignup(
          fullName: _fullNameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          phoneNumber: _phoneNumberController.text.trim(),
          address: _addressController.text.trim(),
        );
      } else {
        // Attorney signup - try to upload license document if provided
        String? licenseDocumentUrl;

        if (_licenseDocument != null) {
          // Try to upload license document
          setState(() {
            _isUploadingDocument = true;
          });

          try {
            licenseDocumentUrl = await _storageService.uploadAttorneyLicense(
              email: _emailController.text.trim(),
              file: _licenseDocument!,
            );

            if (kDebugMode) {
              debugPrint('✅ License document uploaded successfully');
            }
          } catch (e) {
            // Upload failed - allow signup to continue but show warning
            if (mounted) {
              String errorMessage = 'Could not upload license document. ';
              final errorString = e.toString().toLowerCase();

              if (errorString.contains('permission') ||
                  errorString.contains('unauthorized')) {
                errorMessage +=
                    'Storage permission issue. You can upload it later from your profile after account creation.';
              } else if (errorString.contains('network') ||
                  errorString.contains('connection')) {
                errorMessage +=
                    'Network error. You can upload it later from your profile after account creation.';
              } else {
                errorMessage +=
                    'You can upload it later from your profile after account creation.';
              }

              if (kDebugMode) {
                debugPrint('⚠️ License upload error (continuing signup): $e');
              }

              Get.snackbar(
                'Upload Warning',
                errorMessage,
                backgroundColor: Colors.orange,
                colorText: Colors.white,
                duration: const Duration(seconds: 6),
              );
            }

            // Continue with signup even if upload fails
            licenseDocumentUrl = null;
          } finally {
            setState(() {
              _isUploadingDocument = false;
            });
          }
        } else {
          // No document selected - show notice but allow signup
          if (mounted) {
            Get.snackbar(
              'Notice',
              'License document not uploaded. You can upload it later from your profile for verification.',
              backgroundColor: Colors.orange,
              colorText: Colors.white,
              duration: const Duration(seconds: 4),
            );
          }
        }

        // Attorney signup with required fields
        result = await _authService.attorneySignup(
          fullName: _fullNameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          phoneNumber: _phoneNumberController.text.trim(),
          address: _addressController.text.trim(),
          specialization: _specializationController.text.trim(),
          barNumber: _barNumberController.text.trim(),
          licenseState: _licenseStateController.text.trim(),
          licenseDocumentUrl: licenseDocumentUrl,
        );
      }

      if (!mounted) return;

      if (result['success'] == true) {
        // Show success message
        Get.snackbar(
          'Success',
          result['message'] ?? 'Verification code sent to your email',
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );

        // Navigate to OTP verification page after a short delay
        await Future.delayed(const Duration(milliseconds: 500));

        if (!mounted) return;

        Get.offAll(
          () => OtpVerificationPage(
            email: _emailController.text.trim(),
            fullName: _fullNameController.text.trim(),
            role: _selectedRole, // Pass role to OTP page
            otp: result['otp'] as String?,
          ),
        );
      } else {
        if (mounted) {
          Get.snackbar(
            'Error',
            result['message'] ?? 'Registration failed. Please try again.',
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 4),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'An unexpected error occurred';
        if (e.toString().contains('FIRESTORE')) {
          errorMessage =
              'Database connection error. Please check your internet connection and try again.';
        } else {
          errorMessage = 'Error: ${e.toString()}';
        }

        Get.snackbar(
          'Error',
          errorMessage,
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 20 : 32,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Title Section
                  Text(
                    'Create Your Account',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedRole == 'staff'
                        ? 'Staff: apply first — admin must approve before you set a password'
                        : 'Fill in your details to get started',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  // Form Card
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Role Selection Buttons
                          Text(
                            'I am a:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedRole = 'client';
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _selectedRole == 'client'
                                          ? AppTheme.royalBlue
                                          : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _selectedRole == 'client'
                                            ? AppTheme.royalBlue
                                            : Colors.grey[300]!,
                                        width: 2,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.person_outline,
                                          color: _selectedRole == 'client'
                                              ? Colors.white
                                              : Colors.grey[700],
                                          size: 22,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Client',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: _selectedRole == 'client'
                                                ? Colors.white
                                                : Colors.grey[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedRole = 'attorney';
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _selectedRole == 'attorney'
                                          ? AppTheme.royalBlue
                                          : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _selectedRole == 'attorney'
                                            ? AppTheme.royalBlue
                                            : Colors.grey[300]!,
                                        width: 2,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.gavel,
                                          color: _selectedRole == 'attorney'
                                              ? Colors.white
                                              : Colors.grey[700],
                                          size: 22,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Attorney',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: _selectedRole == 'attorney'
                                                ? Colors.white
                                                : Colors.grey[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedRole = 'staff';
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _selectedRole == 'staff'
                                          ? AppTheme.royalBlue
                                          : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _selectedRole == 'staff'
                                            ? AppTheme.royalBlue
                                            : Colors.grey[300]!,
                                        width: 2,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.badge_outlined,
                                          color: _selectedRole == 'staff'
                                              ? Colors.white
                                              : Colors.grey[700],
                                          size: 22,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Staff',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: _selectedRole == 'staff'
                                                ? Colors.white
                                                : Colors.grey[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Common Fields
                          AppTextField(
                            label: 'Full Name',
                            hint: 'Full Name',
                            controller: _fullNameController,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your full name';
                              }
                              if (value.length < 3) {
                                return 'Name must be at least 3 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Email',
                            hint: 'Email',
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!value.contains('@') ||
                                  !value.contains('.')) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Phone Number',
                            hint: 'e.g., 09123456789 or +639123456789',
                            controller: _phoneNumberController,
                            keyboardType: TextInputType.phone,
                            validator: _validatePhoneNumber,
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: _selectedRole == 'staff'
                                ? 'Address (optional)'
                                : 'Address',
                            hint: 'e.g., Street, City, Province/State, Country',
                            controller: _addressController,
                            maxLines: 3,
                            validator: _validateAddressForRole,
                          ),
                          // Attorney-specific Professional Identity Section
                          if (_selectedRole == 'attorney') ...[
                            const SizedBox(height: 32),
                            // Professional Identity Section Header
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.royalBlue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.royalBlue.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.verified_user,
                                    color: AppTheme.royalBlue,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Professional Identity',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.royalBlue,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Verify your attorney credentials',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            AppTextField(
                              label: 'Specialization *',
                              hint:
                                  'e.g., Criminal Law, Family Law, Corporate Law',
                              controller: _specializationController,
                              validator: (value) => _validateAttorneyField(
                                value,
                                'Specialization',
                              ),
                            ),
                            const SizedBox(height: 16),
                            AppTextField(
                              label: 'Bar Number *',
                              hint: 'Bar association number',
                              controller: _barNumberController,
                              validator: (value) =>
                                  _validateAttorneyField(value, 'Bar Number'),
                            ),
                            const SizedBox(height: 16),
                            AppTextField(
                              label: 'License State/Province *',
                              hint: 'State or province where you are licensed',
                              controller: _licenseStateController,
                              validator: (value) => _validateAttorneyField(
                                value,
                                'License State/Province',
                              ),
                            ),
                            const SizedBox(height: 16),
                            // License Document Upload
                            Text(
                              'License Document (Optional - can upload later)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: _isUploadingDocument
                                  ? null
                                  : _pickLicenseDocument,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _licenseDocument != null
                                      ? Colors.green[50]
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _licenseDocument != null
                                        ? Colors.green
                                        : Colors.grey[300]!,
                                    width: 2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _licenseDocument != null
                                          ? Icons.check_circle
                                          : Icons.upload_file,
                                      color: _licenseDocument != null
                                          ? Colors.green
                                          : Colors.grey[600],
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _licenseDocument != null
                                                ? _licenseDocument!.name
                                                : 'Upload License Document',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.grey[800],
                                            ),
                                          ),
                                          if (_licenseDocument != null)
                                            Text(
                                              'Tap to change',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            )
                                          else
                                            Text(
                                              'PDF, JPG, PNG (Max 10MB)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (_isUploadingDocument)
                                      const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    else if (_licenseDocument != null)
                                      Icon(
                                        Icons.edit,
                                        color: Colors.grey[600],
                                        size: 20,
                                      )
                                    else
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        color: Colors.grey[600],
                                        size: 16,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _licenseDocument == null
                                    ? 'Optional: Upload now or later from your profile'
                                    : 'Document selected. You can change it if needed.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _licenseDocument == null
                                      ? Colors.grey[600]
                                      : Colors.green[700],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.blue[700],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Your license document will be verified by our admin team. Please ensure it clearly shows your name, bar number, and license details.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue[900],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (_selectedRole == 'staff') ...[
                            const SizedBox(height: 24),
                            Text(
                              'Staff requirements',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Confirm each item to apply. You will not create a password until an admin approves you.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _SignupStaffReqTile(
                              value: _staffReqExperience,
                              onChanged: (v) => setState(
                                () => _staffReqExperience = v ?? false,
                              ),
                              title: 'Relevant experience',
                              subtitle:
                                  'Administrative, legal-support, or similar experience suitable for a law office.',
                            ),
                            _SignupStaffReqTile(
                              value: _staffReqSupervision,
                              onChanged: (v) => setState(
                                () => _staffReqSupervision = v ?? false,
                              ),
                              title: 'Supervision',
                              subtitle:
                                  'You will work under a licensed attorney assigned by the firm.',
                            ),
                            _SignupStaffReqTile(
                              value: _staffReqConfidentiality,
                              onChanged: (v) => setState(
                                () => _staffReqConfidentiality = v ?? false,
                              ),
                              title: 'Confidentiality',
                              subtitle:
                                  'You will protect client information and follow firm policies.',
                            ),
                            _SignupStaffReqTile(
                              value: _staffReqAccurate,
                              onChanged: (v) =>
                                  setState(() => _staffReqAccurate = v ?? false),
                              title: 'Accurate information',
                              subtitle:
                                  'Everything you submit is truthful; the firm may verify your background.',
                            ),
                            const SizedBox(height: 12),
                            AppTextField(
                              label: 'Note to administrator (optional)',
                              hint:
                                  'Prior role, availability, references…',
                              controller: _staffMessageController,
                              maxLines: 3,
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.blue[200]!,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.blue[700],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'After approval, use Staff portal → Complete registration, or the button in the dialog after you submit, to set your password.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue[900],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (_selectedRole != 'staff') ...[
                            const SizedBox(height: 16),
                            AppTextField(
                              label: 'Password',
                              hint: 'Create a strong password',
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              validator: _validatePassword,
                              onChanged: (value) {
                                if (_formKey.currentState != null) {
                                  _formKey.currentState!.validate();
                                }
                              },
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey[700],
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                            if (_passwordController.text.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.grey[300]!,
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Password Requirements:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildRequirementItem(
                                      'At least 8 characters',
                                      _hasMinLength,
                                    ),
                                    _buildRequirementItem(
                                      'One uppercase letter (A-Z)',
                                      _hasUpperCase,
                                    ),
                                    _buildRequirementItem(
                                      'One lowercase letter (a-z)',
                                      _hasLowerCase,
                                    ),
                                    _buildRequirementItem(
                                      'One number (0-9)',
                                      _hasNumber,
                                    ),
                                    _buildRequirementItem(
                                      'One special character (!@#\$%...)',
                                      _hasSpecialChar,
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 16),
                            AppTextField(
                              label: 'Confirm Password',
                              hint: 'Confirm Password',
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirmPassword,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please confirm your password';
                                }
                                if (value != _passwordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey[700],
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword =
                                        !_obscureConfirmPassword;
                                  });
                                },
                              ),
                            ),
                          ],
                          const SizedBox(height: 28),
                          // Create Account Button
                          Center(
                            child: SizedBox(
                              width: _selectedRole == 'staff' ? 260 : 180,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _signup,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.royalBlue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  elevation: 3,
                                  shadowColor: AppTheme.royalBlue.withOpacity(
                                    0.4,
                                  ),
                                  disabledBackgroundColor: AppTheme.royalBlue
                                      .withOpacity(0.6),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : Text(
                                        _selectedRole == 'staff'
                                            ? 'Submit staff application'
                                            : 'Sign Up',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.3,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          if (_selectedRole == 'attorney') ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.orange[200]!,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.orange[700],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Your attorney account will need admin approval before activation.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.orange[900],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          // Login Link
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Already have an account? ',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                ),
                              ),
                              TextButton(
                                onPressed: () => Get.back(),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Login',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.royalBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequirementItem(String text, bool isValid) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.circle,
            size: 16,
            color: isValid ? Colors.green : Colors.grey[400],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: isValid ? Colors.green[700] : Colors.grey[600],
                decoration: isValid ? null : TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneNumberController.dispose();
    _addressController.dispose();
    _specializationController.dispose();
    _barNumberController.dispose();
    _licenseStateController.dispose();
    _staffMessageController.dispose();
    super.dispose();
  }
}

class _SignupStaffReqTile extends StatelessWidget {
  const _SignupStaffReqTile({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        child: CheckboxListTile(
          value: value,
          onChanged: onChanged,
          activeColor: AppTheme.royalBlue,
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppTheme.darkText,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: Colors.grey[700],
            ),
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ),
    );
  }
}
