import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/staff_auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import 'staff_dashboard.dart';

/// After admin approves the Firestore application, applicant sets password here.
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
  bool _obscure1 = true;
  bool _obscure2 = true;

  Future<void> _complete() async {
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
    final result = await _staffAuth.completeStaffRegistrationAfterApproval(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    setState(() => _loading = false);

    if (!mounted) return;
    if (result['success'] == true) {
      Get.snackbar(
        'Welcome',
        result['message'] as String? ?? 'Account ready.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
      Get.offAll(() => const StaffDashboard());
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
                    Text(
                      'Use the same email you applied with. Your application must show as approved by an administrator.',
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
                            suffixIcon: IconButton(
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
                            suffixIcon: IconButton(
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
                          const SizedBox(height: 20),
                          AppButton(
                            text: 'Create account',
                            onPressed: _complete,
                            isLoading: _loading,
                          ),
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
