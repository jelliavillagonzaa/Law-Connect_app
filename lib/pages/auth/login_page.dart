import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/brand_logo.dart';
import '../../widgets/common/login_error_dialog.dart';
import '../../routes/portal_navigation.dart';
import 'signup_page.dart';
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

        final role = result['role'] ?? 'client';
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
        if (!mounted) return;
        await showLoginErrorDialog(
          context,
          message: result['message'] ?? 'Invalid email or password',
          onForgotPassword: () {
            Get.to(() => const ForgotPasswordPage());
          },
        );
      }
    } catch (e) {
      if (!mounted) return;
      await showLoginErrorDialog(
        context,
        message: e,
        onForgotPassword: () {
          Get.to(() => const ForgotPasswordPage());
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  static const _gold = Color(0xFFE4A11A);
  static const _muted = Color(0xFFB7C3D4);
  static const _inputFill = Color(0xFF071422);
  static const _inputBorder = Color(0xFF2A4060);
  static const _loginBlue = Color(0xFF3B6CB5);

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF8A97AB), fontSize: 14),
      prefixIcon: Icon(prefix, color: _gold.withValues(alpha: 0.9), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: _inputFill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _gold, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
    );
  }

  void _openSignup() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => const SignupPage(),
        fullscreenDialog: true,
      ),
    );
  }

  /// Phone app login. A wide website keeps the firm-portal card below.
  ///
  /// [kIsWeb] is also true in a phone browser, so width decides: a phone
  /// always gets this screen, including after logout.
  bool _useWebLogin(BuildContext context) {
    if (!kIsWeb) return false;
    return MediaQuery.sizeOf(context).shortestSide >= 600;
  }

  Widget _buildAppLogin(BuildContext context) {
    final isSmallScreen = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 24 : 40,
              vertical: 20,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipOval(
                    child: Image.asset(
                      'assets/logo.png',
                      width: 150,
                      height: 150,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
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
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
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
                            controller: _emailController,
                            focusNode: _emailFocus,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) =>
                                _passwordFocus.requestFocus(),
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
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Password',
                            hint: 'Password',
                            controller: _passwordController,
                            focusNode: _passwordFocus,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _login(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey[700],
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
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
                              child: const Text(
                                'Forgot password?',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.royalBlue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          AppButton(
                            text: 'Login',
                            onPressed: _login,
                            isLoading: _isLoading,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Don't have an account? ",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                ),
                              ),
                              TextButton(
                                onPressed: _openSignup,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
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
  }

  @override
  Widget build(BuildContext context) {
    if (!_useWebLogin(context)) return _buildAppLogin(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF071526),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Image(
            image: AssetImage('assets/Landingpage.png'),
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                // Keep the right side open so Lady Justice sits beside the card.
                final statueSpace = (constraints.maxWidth * 0.24)
                    .clamp(200.0, 360.0);
                final content = wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Expanded(child: _LoginHero()),
                          const SizedBox(width: 32),
                          _loginCard(),
                          SizedBox(width: statueSpace),
                        ],
                      )
                    : Column(
                        children: [
                          const _LoginHero(compact: true),
                          const SizedBox(height: 28),
                          _loginCard(),
                        ],
                      );

                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        wide ? 48 : 24,
                        28,
                        wide ? 12 : 24,
                        28,
                      ),
                      child: content,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginCard() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
        decoration: BoxDecoration(
          color: const Color(0xF20C1B30),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _gold, width: 1.3),
                  ),
                  child: const Icon(Icons.balance, color: _gold, size: 22),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Welcome back',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Sign in to access your firm portal',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _muted),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                focusNode: _emailFocus,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: _gold,
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                decoration: _fieldDecoration(
                  hint: 'Email',
                  prefix: Icons.mail_outline_rounded,
                ),
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
              const SizedBox(height: 10),
              TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: _gold,
                onFieldSubmitted: (_) => _login(),
                decoration: _fieldDecoration(
                  hint: 'Password',
                  prefix: Icons.lock_outline_rounded,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: _muted,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Get.to(() => const ForgotPasswordPage()),
                  style: TextButton.styleFrom(
                    foregroundColor: _gold,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _loginBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _loginBlue.withValues(alpha: 0.7),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Login',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Expanded(child: Divider(color: Color(0xFF2A4060))),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or',
                      style: TextStyle(color: _muted, fontSize: 13),
                    ),
                  ),
                  Expanded(child: Divider(color: Color(0xFF2A4060))),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _openSignup,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _gold,
                    side: const BorderSide(color: _gold, width: 1.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text(
                    'Create account',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_outlined, size: 16, color: _muted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your information is handled in line with professional confidentiality standards.',
                      style: TextStyle(fontSize: 11.5, height: 1.4, color: _muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
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

class _LoginHero extends StatelessWidget {
  const _LoginHero({this.compact = false});

  final bool compact;

  static const _gold = Color(0xFFE4A11A);

  @override
  Widget build(BuildContext context) {
    final align = compact ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = compact ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment: align,
      children: [
        Row(
          mainAxisAlignment:
              compact ? MainAxisAlignment.center : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogo(size: 72),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: align,
              children: [
                const Text(
                  'Law Connect',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Firm portal',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _gold,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: compact ? 22 : 32),
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: compact ? 30 : 36,
              fontWeight: FontWeight.w800,
              height: 1.15,
              color: Colors.white,
            ),
            children: const [
              TextSpan(text: 'Counsel you can trust.\n'),
              TextSpan(
                text: 'Clarity when it matters.',
                style: TextStyle(color: _gold),
              ),
            ],
          ),
          textAlign: textAlign,
        ),
        const SizedBox(height: 8),
        Container(
          width: 72,
          height: 3,
          decoration: BoxDecoration(
            color: _gold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Secure access to cases, appointments, and messages—'
          'built for a modern law practice.',
          textAlign: textAlign,
          style: const TextStyle(
            fontSize: 15,
            height: 1.5,
            color: Color(0xFFD5DEEA),
          ),
        ),
        SizedBox(height: compact ? 20 : 28),
        const _FeatureRow(
          icon: Icons.gavel_rounded,
          title: 'Case updates',
          subtitle: 'Real-time updates on your cases.',
        ),
        const SizedBox(height: 14),
        const _FeatureRow(
          icon: Icons.calendar_month_rounded,
          title: 'Appointments',
          subtitle: 'Manage schedules with ease.',
        ),
        const SizedBox(height: 14),
        const _FeatureRow(
          icon: Icons.lock_rounded,
          title: 'Private & secure',
          subtitle: 'Your data is protected with top security.',
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF102743),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4A11A).withValues(alpha: 0.45)),
          ),
          child: Icon(icon, color: const Color(0xFFE4A11A), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFFB7C3D4),
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
