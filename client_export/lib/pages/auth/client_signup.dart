import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/app_text_field.dart';
import '../../theme/app_theme.dart';
import 'otp_verification_signup.dart';

class ClientSignupPage extends StatefulWidget {
  const ClientSignupPage({super.key});

  @override
  State<ClientSignupPage> createState() => _ClientSignupPageState();
}

class _ClientSignupPageState extends State<ClientSignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _addressController = TextEditingController();

  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Password strength indicators
  bool _hasMinLength = false;
  bool _hasUpperCase = false;
  bool _hasLowerCase = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;

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

    // Remove spaces, dashes, and parentheses for validation
    final cleaned = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Check if it's all digits
    if (!RegExp(r'^\d+$').hasMatch(cleaned)) {
      return 'Phone number must contain only digits';
    }

    // Check length (should be between 10-15 digits for international format)
    if (cleaned.length < 10 || cleaned.length > 15) {
      return 'Phone number must be between 10-15 digits';
    }

    // Check for common patterns (optional - can be more specific based on country)
    // For now, accept any 10-15 digit number
    return null;
  }

  String? _validateAddress(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your address';
    }

    // Trim and check minimum length
    final trimmed = value.trim();
    if (trimmed.length < 10) {
      return 'Address must be at least 10 characters';
    }

    // Check if address contains at least one letter (not just numbers/symbols)
    if (!RegExp(r'[a-zA-Z]').hasMatch(trimmed)) {
      return 'Address must contain letters';
    }

    // Check for suspicious patterns (all same character, etc.)
    if (RegExp(r'^(.)\1+$').hasMatch(trimmed)) {
      return 'Please enter a valid address';
    }

    return null;
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

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
      final result = await _authService.clientSignup(
        fullName: _fullNameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        phoneNumber: _phoneNumberController.text.trim(),
        address: _addressController.text.trim(),
      );

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
            otp: result['otp'] as String?, // Pass OTP for display
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
                    'Fill in your details to get started',
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
                            label: 'Address',
                            hint: 'e.g., Street, City, Province/State, Country',
                            controller: _addressController,
                            maxLines: 3,
                            validator: _validateAddress,
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Password',
                            hint: 'Create a strong password',
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            validator: _validatePassword,
                            onChanged: (value) {
                              // Trigger validation on change to update strength indicators
                              if (_formKey.currentState != null) {
                                _formKey.currentState!.validate();
                                // Also re-validate confirm password when password changes
                                if (_confirmPasswordController.text.isNotEmpty) {
                                  _formKey.currentState!.validate();
                                }
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
                          // Password Strength Indicator
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
                            hint: 'Re-enter your password',
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
                            onChanged: (value) {
                              // Re-validate when confirm password changes
                              if (_formKey.currentState != null) {
                                _formKey.currentState!.validate();
                              }
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
                          const SizedBox(height: 28),
                          // Create Account Button with pill-shaped design
                          Center(
                            child: SizedBox(
                              width: 180,
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
                                        'Sign Up',
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
    super.dispose();
  }
}
