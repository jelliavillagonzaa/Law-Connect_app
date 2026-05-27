import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/input_field.dart';
import '../../services/auth_service.dart';
import 'signup_screen.dart';
import 'dashboard_screen.dart';
import '../../pages/attorney/attorney_dashboard.dart';
import '../../pages/admin/admin_dashboard.dart';
import '../../pages/auth/forgot_password_page.dart';
import '../../pages/auth/otp_verification.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        if (result['success'] == true) {
          final role = result['role'] ?? 'client';

          if (result['needsVerification'] == true && role == 'client') {
            Get.snackbar(
              'Verification Required',
              result['message'] ?? 'Please verify your email first.',
              backgroundColor: AppTheme.gold,
              colorText: AppTheme.deepNavy,
              duration: const Duration(seconds: 3),
            );
            Future.delayed(const Duration(milliseconds: 400), () {
              if (mounted) {
                Get.offAll(() => const OtpVerificationPage());
              }
            });
          } else if (role == 'admin') {
            Get.offAll(() => const AdminDashboard());
          } else if (role == 'attorney') {
            Get.offAll(() => const AttorneyDashboard());
          } else {
            Get.offAll(() => const DashboardScreen());
          }
        } else {
          // Show error message
          final message =
              result['message'] ?? 'Login failed. Please try again.';

          if (result['needsVerification'] == true) {
            Get.snackbar(
              'Verification Required',
              message,
              backgroundColor: AppTheme.gold,
              colorText: AppTheme.deepNavy,
              duration: const Duration(seconds: 4),
            );
            Future.delayed(const Duration(milliseconds: 400), () {
              if (mounted) {
                Get.offAll(() => const OtpVerificationPage());
              }
            });
          } else {
            Get.snackbar(
              'Login Failed',
              message,
              backgroundColor: Colors.red,
              colorText: AppTheme.cleanWhite,
              duration: const Duration(seconds: 3),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'An unexpected error occurred: ${e.toString()}',
          backgroundColor: Colors.red,
          colorText: AppTheme.cleanWhite,
          duration: const Duration(seconds: 3),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                // Logo
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: AppTheme.royalBlue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.shield,
                    color: AppTheme.cleanWhite,
                    size: 70,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Welcome Back',
                  style: AppTheme.heading1.copyWith(color: AppTheme.darkText),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to continue to your account',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.mutedText,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                InputField(
                  label: 'Email Address',
                  hint: 'Enter your email',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.email_outlined,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                InputField(
                  label: 'Password',
                  hint: 'Enter your password',
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  prefixIcon: Icons.lock_outline,
                  suffixIcon: _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  onSuffixTap: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Get.to(() => const ForgotPasswordPage());
                    },
                    child: Text(
                      'Forgot Password?',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.royalBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                PrimaryButton(
                  text: 'Sign In',
                  onPressed: _handleLogin,
                  isLoading: _isLoading,
                  icon: Icons.login,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Don't have an account? ", style: AppTheme.bodyMedium),
                    TextButton(
                      onPressed: () {
                        Get.to(() => const SignupScreen());
                      },
                      child: Text(
                        'Sign Up',
                        style: AppTheme.bodyMedium.copyWith(
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
      ),
    );
  }
}
