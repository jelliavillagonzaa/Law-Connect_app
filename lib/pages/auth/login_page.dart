import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/auth_service.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/brand_logo.dart';
import '../../widgets/common/app_text_field.dart';
import '../../theme/app_theme.dart';
import '../../routes/portal_navigation.dart';
import '../client/client_landing_page.dart';
import 'signup_page.dart';
import 'otp_verification.dart';
import 'forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Keep login lightweight; portal navigation already prefetches the
    // resolved role dashboard on successful login.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      prefetchAllPortalDashboards();
    });
  }

  void _navigateToPortal(String portalRole) {
    navigateToPortalDashboard(portalRole);
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _authService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (result['success'] == true) {
        if (!mounted) return;

        // Get role first - staff, admin, and attorney don't need verification
        final role = result['role'] ?? 'client';

        // Check if user needs verification - but skip for staff, admin, attorney
        if (result['needsVerification'] == true && role == 'client') {
          if (mounted) {
            Get.snackbar(
              'Verification Required',
              result['message'] ?? 'Please verify your email first.',
              backgroundColor: Colors.orange,
              colorText: Colors.white,
              duration: const Duration(seconds: 2),
            );
            // Navigate immediately after showing snackbar
            Get.offAll(() => const OtpVerificationPage());
          }
          return;
        }

        if (!mounted) return;

        final portalRole = AuthService.resolvePortalRole(
          _emailController.text.trim(),
          firestoreRole: role,
        );
        // Navigation failures must not look like a bad password / failed login.
        try {
          _navigateToPortal(portalRole);
        } catch (e) {
          Get.offAllNamed(
            switch (portalRole.toLowerCase()) {
              'admin' => '/AdminDashboard',
              'attorney' => '/AttorneyDashboard',
              'staff' => '/StaffDashboard',
              _ => '/ClientDashboard',
            },
          );
        }
      } else {
        Get.snackbar(
          'Login Failed',
          result['message'] ?? 'Invalid email or password',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      Get.snackbar(
        'Login Failed',
        'Unexpected error: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  static ButtonStyle get _compactTextButtonStyle => TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const ClientLandingPage();
    }

    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppTheme.navy,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 24 : 40,
                    vertical: 16,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(child: BrandLogo(size: 150)),
                          const SizedBox(height: 12),
                          Text(
                            'Law Connect',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 40),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
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
                                    label: 'Email',
                                    hint: 'Email',
                                    showFloatingLabel: false,
                                    controller: _emailController,
                                    focusNode: _emailFocus,
                                    textInputAction: TextInputAction.next,
                                    onFieldSubmitted: (_) =>
                                        _passwordFocus.requestFocus(),
                                    keyboardType: TextInputType.emailAddress,
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
                                  const SizedBox(height: 14),
                                  AppTextField(
                                    label: 'Password',
                                    hint: 'Password',
                                    showFloatingLabel: false,
                                    controller: _passwordController,
                                    focusNode: _passwordFocus,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _login(),
                                    obscureText: _obscurePassword,
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: Colors.grey[700],
                                        size: 22,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 40,
                                        minHeight: 40,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter your password';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () {
                                        Get.to(
                                          () => const ForgotPasswordPage(),
                                        );
                                      },
                                      style: _compactTextButtonStyle,
                                      child: Text(
                                        'Forgot password?',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.royalBlue,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  AppButton(
                                    text: 'Login',
                                    onPressed: _login,
                                    isLoading: _isLoading,
                                    backgroundColor: AppTheme.navy,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Don\'t have an account? ',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Get.to(() => const SignupPage());
                                        },
                                        style: _compactTextButtonStyle,
                                        child: Text(
                                          'Register',
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
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
