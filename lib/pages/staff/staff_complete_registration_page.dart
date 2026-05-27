import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/staff_auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/otp_input_field.dart';
import '../auth/login_page.dart';

/// Set password, email OTP, then create account. If the application was still pending,
/// sign-in works right after an admin approves it (and turns the account on). If already approved, sign-in works after this step.
class StaffCompleteRegistrationPage extends StatefulWidget {
  const StaffCompleteRegistrationPage({super.key});

  @override
  State<StaffCompleteRegistrationPage> createState() =>
      _StaffCompleteRegistrationPageState();
}

class _StaffCompleteRegistrationPageState
    extends State<StaffCompleteRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _staffAuth = StaffAuthService();

  bool _loading = false;
  bool _awaitingOtp = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String _otp = '';

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmController.text) {
      Get.snackbar(
        'Passwords',
        'Passwords do not match.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _loading = true);
    final result = await _staffAuth.sendStaffRegistrationOtp(
      _emailController.text.trim(),
    );
    setState(() => _loading = false);

    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _awaitingOtp = true;
        _otp = '';
      });
      Get.snackbar(
        'Check your email',
        result['message'] as String? ?? 'Enter the 6-digit code below.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    } else {
      Get.snackbar(
        'Could not send code',
        result['message'] as String? ?? 'Try again later.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _resendCode() async {
    setState(() => _loading = true);
    final result = await _staffAuth.sendStaffRegistrationOtp(
      _emailController.text.trim(),
    );
    setState(() => _loading = false);
    if (!mounted) return;
    Get.snackbar(
      result['success'] == true ? 'Sent' : 'Error',
      result['message'] as String? ?? '',
      backgroundColor: result['success'] == true ? Colors.green : Colors.red,
      colorText: Colors.white,
    );
  }

  Future<void> _completeRegistration() async {
    if (_otp.length != 6) {
      Get.snackbar(
        'Code',
        'Enter the 6-digit code from your email.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _loading = true);
    final result = await _staffAuth.completeStaffRegistrationAfterApproval(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      otp: _otp,
    );
    setState(() => _loading = false);

    if (!mounted) return;
    if (result['success'] == true) {
      final msg = result['message'] as String? ??
          'Account created.';
      final canSignIn = result['canSignInNow'] == true;
      Get.snackbar(
        'Account created',
        msg,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(canSignIn ? 'You can sign in' : 'Next step'),
          content: Text(
            canSignIn
                ? '$msg\n\nUse Sign in with the email and password you just set.'
                : '$msg\n\nYou will be able to sign in as soon as an administrator approves your application.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Get.offAll(() => const LoginPage());
    } else {
      Get.snackbar(
        'Registration',
        result['message'] as String? ?? 'Something went wrong.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.white,
        title: const Text('Complete staff registration'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.white.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppTheme.white.withValues(alpha: 0.95),
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Use the email from your staff application. You can verify your email with a code even while the application is still under review, or after it is approved. '
                              'You can sign in as soon as an administrator approves your application (if it was still pending). If it was already approved before you finish here, you can sign in right after you complete this form.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: AppTheme.white.withValues(alpha: 0.92),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _awaitingOtp
                          ? 'Step 2: Enter the 6-digit code we sent to your email. Then create your account. If your application was still pending, you can sign in after an admin approves it; if it was already approved, you can sign in right away.'
                          : 'Step 1: Use the same email as on your staff application and choose a password. Tap Continue — we send the verification code to your email immediately.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: AppTheme.white.withValues(alpha: 0.88),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppTextField(
                            label: 'Email',
                            hint: 'Email used on your application',
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            readOnly: _awaitingOtp,
                            validator: (v) {
                              if (v == null || !v.contains('@')) {
                                return 'Valid email required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          AppTextField(
                            label: 'Password',
                            hint: 'At least 8 characters',
                            controller: _passwordController,
                            obscureText: _obscure1,
                            readOnly: _awaitingOtp,
                            suffixIcon: _awaitingOtp
                                ? null
                                : IconButton(
                                    icon: Icon(
                                      _obscure1
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.grey[700],
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure1 = !_obscure1),
                                  ),
                            validator: (v) {
                              if (v == null || v.length < 8) {
                                return 'Minimum 8 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          AppTextField(
                            label: 'Confirm password',
                            hint: 'Confirm password',
                            controller: _confirmController,
                            obscureText: _obscure2,
                            readOnly: _awaitingOtp,
                            suffixIcon: _awaitingOtp
                                ? null
                                : IconButton(
                                    icon: Icon(
                                      _obscure2
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.grey[700],
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure2 = !_obscure2),
                                  ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
                          ),
                          if (_awaitingOtp) ...[
                            const SizedBox(height: 22),
                            Text(
                              'Verification code',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 10),
                            OtpInputField(
                              onChanged: (value) =>
                                  setState(() => _otp = value),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _loading ? null : _resendCode,
                                child: const Text('Resend code'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          if (!_awaitingOtp)
                            AppButton(
                              text: 'Continue — send code to email',
                              onPressed: _sendCode,
                              isLoading: _loading,
                            )
                          else ...[
                            AppButton(
                              text: 'Verify OTP & create account',
                              onPressed: _completeRegistration,
                              isLoading: _loading,
                            ),
                            TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => setState(() {
                                        _awaitingOtp = false;
                                        _otp = '';
                                      }),
                              child: const Text('Edit email or password'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
