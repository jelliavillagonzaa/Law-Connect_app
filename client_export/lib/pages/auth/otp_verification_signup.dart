import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/otp_input_field.dart';
import '../auth/login_page.dart';

class OtpVerificationPage extends StatefulWidget {
  final String email;
  final String? fullName;
  final String? otp; // OTP code to display
  final String role; // 'client' or 'attorney'

  const OtpVerificationPage({
    super.key,
    required this.email,
    this.fullName,
    this.otp,
    this.role = 'client', // Default to client for backward compatibility
  });

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final AuthService _authService = AuthService();
  bool _isSubmitting = false;
  bool _isResending = false;
  String? _currentOtp; // Store current OTP for display
  String _enteredOtp = ''; // Store entered OTP from 6 boxes

  Future<void> _verifyOtp() async {
    final otp = _enteredOtp.trim();

    if (otp.isEmpty) {
      Get.snackbar(
        'Error',
        'Please enter the verification code',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    if (otp.length != 6) {
      Get.snackbar(
        'Error',
        'Verification code must be 6 digits',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final result = widget.role == 'attorney'
          ? await _authService.verifyOtpAndCreateAttorneyAccount(
              email: widget.email,
              otp: otp,
            )
          : await _authService.verifyOtpAndCreateAccount(
              email: widget.email,
              otp: otp,
            );

      if (result['success'] == true) {
        Get.snackbar(
          'Success',
          result['message'] ?? 'Email verified! Account created successfully.',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );

        // Navigate to login page
        Get.offAll(() => const LoginPage());
      } else {
        Get.snackbar(
          'Error',
          result['message'] ?? 'Verification failed',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to verify code: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _isResending = true;
    });

    try {
      final result = await _authService.sendVerificationOtp(
        email: widget.email,
        name: widget.fullName,
      );

      if (result['success'] == true) {
        // Update OTP if returned
        if (result['otp'] != null) {
          setState(() {
            _currentOtp = result['otp'] as String;
          });
        }
        Get.snackbar(
          'Success',
          result['message'] ?? 'Verification code sent to your email',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      } else {
        Get.snackbar(
          'Error',
          result['message'] ?? 'Failed to resend code',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to resend code: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      setState(() {
        _isResending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.royalBlue, // Professional royal blue background
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  // Title
                  Text(
                    'OTP Verification',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Card Container
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Green banner with message
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green[300]!,
                              width: 1,
                            ),
                          ),
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.green[800],
                                height: 1.5,
                              ),
                              children: [
                                const TextSpan(
                                  text:
                                      "We've sent a verification code to your email (and SMS if you provided a phone number) - ",
                                ),
                                TextSpan(
                                  text: widget.email,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.green[800],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const TextSpan(text: '.'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Display OTP Code (if available)
                        if (_currentOtp != null)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppTheme.royalBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppTheme.royalBlue.withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: AppTheme.royalBlue,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Your Verification Code',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.royalBlue,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _currentOtp!,
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 8,
                                    color: AppTheme.royalBlue,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Enter this code below',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_currentOtp != null) const SizedBox(height: 24),
                        // OTP Input Field - 6 separate boxes
                        Column(
                          children: [
                            Text(
                              'Enter Verification Code',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 16),
                            OtpInputField(
                              onChanged: (otp) {
                                _enteredOtp = otp;
                              },
                              onCompleted: (otp) {
                                // Auto-verify when all 6 digits are entered
                                if (!_isSubmitting && mounted) {
                                  Future.delayed(const Duration(milliseconds: 300), () {
                                    if (mounted && !_isSubmitting) {
                                      _verifyOtp();
                                    }
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        // Submit Button
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isSubmitting ? null : _verifyOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.royalBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                              disabledBackgroundColor: AppTheme.royalBlue.withOpacity(0.6),
                            ),
                            child: _isSubmitting
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
                                : Text(
                                    'Submit',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Resend Code Button
                        TextButton(
                          onPressed: _isResending
                              ? null
                              : () {
                                  if (mounted) {
                                    _resendOtp();
                                  }
                                },
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.royalBlue,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          child: _isResending
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      AppTheme.royalBlue,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Resend Code',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Back to Login
                  TextButton(
                    onPressed: () {
                      if (mounted) {
                        Get.offAll(() => const LoginPage());
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'Back to Login',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
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
}
