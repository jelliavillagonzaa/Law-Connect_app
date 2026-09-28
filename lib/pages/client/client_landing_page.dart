import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../routes/portal_navigation.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/brand_logo.dart';
import '../auth/forgot_password_page.dart';
import '../auth/otp_verification.dart';
import '../auth/signup_page.dart';

const Color _cardFill = Color(0xE60B1D33);
const Color _gold = Color(0xFFE4A11A);
const Color _inputFill = Color(0xFF071422);
const Color _inputBorder = Color(0xFF2A4060);
const Color _muted = Color(0xFFB7C3D4);

/// Public landing. Web uses the firm-portal design; the app keeps the original page.
class ClientLandingPage extends StatelessWidget {
  const ClientLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const _AppLandingPage();
    }
    return const _WebLandingPage();
  }
}

class _WebLandingPage extends StatelessWidget {
  const _WebLandingPage();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final isWide = w >= 980;
    final isVeryWide = w >= 1280;
    final compact = w < 600 || h < 720;
    final padX = w < 600 ? 20.0 : w < 980 ? 32.0 : 56.0;
    final statueReserve = isVeryWide ? 220.0 : isWide ? 120.0 : 0.0;

    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _LandingBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    padX,
                    compact ? 20 : 36,
                    padX + statueReserve,
                    compact ? 24 : 36,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - (compact ? 44 : 72),
                    ),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 6,
                                child: _HeroColumn(compact: compact),
                              ),
                              SizedBox(width: isVeryWide ? 48 : 32),
                              Flexible(
                                flex: 5,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 430),
                                  child: const _FirmPortalLoginCard(),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _HeroColumn(compact: true),
                              const SizedBox(height: 28),
                              const _FirmPortalLoginCard(),
                            ],
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
}

class _LandingBackdrop extends StatelessWidget {
  const _LandingBackdrop();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (size.width * dpr).round().clamp(960, 1920);

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppTheme.navy),
        Image.asset(
          'assets/Landingpage.png',
          fit: BoxFit.cover,
          alignment: Alignment.centerRight,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          cacheWidth: cacheWidth,
          errorBuilder: (_, __, ___) => const SizedBox.expand(),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  AppTheme.navy,
                  AppTheme.navy.withValues(alpha: 0.92),
                  AppTheme.navy.withValues(alpha: 0.55),
                  AppTheme.navy.withValues(alpha: 0.22),
                ],
                stops: const [0.0, 0.38, 0.68, 1.0],
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Align(
            alignment: const Alignment(-0.35, -0.05),
            child: Icon(
              Icons.balance,
              size: 420,
              color: _gold.withValues(alpha: 0.06),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroColumn extends StatelessWidget {
  const _HeroColumn({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final titleAlign = compact ? TextAlign.center : TextAlign.start;
    final cross = compact ? CrossAxisAlignment.center : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: cross,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment:
              compact ? MainAxisAlignment.center : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandLogo(size: compact ? 72 : 88),
            const SizedBox(width: 16),
            Flexible(
              child: Column(
                crossAxisAlignment: cross,
                children: [
                  Text(
                    'Law Connect',
                    textAlign: titleAlign,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Firm portal',
                    textAlign: titleAlign,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _gold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 28 : 40),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Counsel you can trust.\n',
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: compact ? 32 : 42,
                  fontWeight: FontWeight.w600,
                  height: 1.18,
                  color: Colors.white,
                ),
              ),
              TextSpan(
                text: 'Clarity when it matters.',
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: compact ? 32 : 42,
                  fontWeight: FontWeight.w600,
                  height: 1.18,
                  color: _gold,
                ),
              ),
            ],
          ),
          textAlign: titleAlign,
        ),
        const SizedBox(height: 14),
        Container(
          width: 72,
          height: 2,
          color: _gold.withValues(alpha: 0.85),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            'Secure access to cases, appointments, and messages—built for a modern law practice.',
            textAlign: titleAlign,
            style: TextStyle(
              fontSize: compact ? 15 : 16,
              height: 1.55,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ),
        SizedBox(height: compact ? 28 : 40),
        _FeatureRow(compact: compact),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    const items = [
      (
        Icons.gavel_rounded,
        'Case updates',
        'Real-time updates on your cases.',
      ),
      (
        Icons.calendar_month_rounded,
        'Appointments',
        'Manage schedules with ease.',
      ),
      (
        Icons.lock_rounded,
        'Private & secure',
        'Your data is protected with top security.',
      ),
    ];

    if (compact) {
      return Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _FeatureItem(
              icon: items[i].$1,
              title: items[i].$2,
              subtitle: items[i].$3,
              compact: true,
            ),
            if (i != items.length - 1) const SizedBox(height: 14),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(
            child: _FeatureItem(
              icon: items[i].$1,
              title: items[i].$2,
              subtitle: items[i].$3,
              compact: false,
            ),
          ),
          if (i != items.length - 1) const SizedBox(width: 18),
        ],
      ],
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.compact,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconBox = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withValues(alpha: 0.28)),
      ),
      child: Icon(icon, color: _gold, size: 22),
    );

    if (compact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          iconBox,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        iconBox,
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: _muted,
          ),
        ),
      ],
    );
  }
}

class _FirmPortalLoginCard extends StatefulWidget {
  const _FirmPortalLoginCard();

  @override
  State<_FirmPortalLoginCard> createState() => _FirmPortalLoginCardState();
}

class _FirmPortalLoginCardState extends State<_FirmPortalLoginCard> {
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
    _emailController.addListener(_prefetchForTypedEmail);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      prefetchAllPortalDashboards();
    });
  }

  void _prefetchForTypedEmail() {
    final email = _emailController.text.trim();
    if (email.contains('@')) {
      prefetchPortalDashboard(AuthService.resolvePortalRole(email));
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _authService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (result['success'] == true) {
        if (!mounted) return;

        final role = result['role'] ?? 'client';

        if (result['needsVerification'] == true && role == 'client') {
          if (mounted) {
            Get.snackbar(
              'Verification Required',
              result['message'] ?? 'Please verify your email first.',
              backgroundColor: Colors.orange,
              colorText: Colors.white,
              duration: const Duration(seconds: 2),
            );
            Get.offAll(() => const OtpVerificationPage());
          }
          return;
        }

        if (!mounted) return;

        final portalRole = AuthService.resolvePortalRole(
          _emailController.text.trim(),
          firestoreRole: role,
        );
        try {
          navigateToPortalDashboard(portalRole);
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
        setState(() => _isLoading = false);
      }
    }
  }

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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
      decoration: BoxDecoration(
        color: _cardFill,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _gold, width: 1.4),
                ),
                child: const Icon(Icons.balance, color: _gold, size: 28),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Welcome back',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sign in to access your firm portal',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _muted),
            ),
            const SizedBox(height: 24),
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
            const SizedBox(height: 14),
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
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Get.to(() => const ForgotPasswordPage()),
                style: TextButton.styleFrom(
                  foregroundColor: _gold,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.royalBlue,
                  foregroundColor: AppTheme.white,
                  disabledBackgroundColor:
                      AppTheme.royalBlue.withValues(alpha: 0.7),
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
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.16))),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or', style: TextStyle(color: _muted, fontSize: 13)),
                ),
                Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.16))),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: () => Get.to(() => const SignupPage()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _gold,
                  side: const BorderSide(color: _gold, width: 1.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_add_alt_1_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Create account',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 16,
                  color: AppTheme.royalBlue.withValues(alpha: 0.95),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Your information is handled in line with professional confidentiality standards.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: _muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
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

/// Original app landing — used on mobile/desktop so the website redesign
/// does not change in-app screens.
class _AppLandingPage extends StatelessWidget {
  const _AppLandingPage();

  static Widget _brandLogo(double size) => BrandLogo(size: size);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isWide = w >= 900;
    final pad = w < 600 ? 24.0 : 40.0;

    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final topInset = constraints.maxHeight < 700 ? 32.0 : 56.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(pad, topInset, pad, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - topInset - 32,
                ),
                child: Align(
                  alignment: const Alignment(0, 0.42),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Transform.translate(
                                  offset: const Offset(0, -20),
                                  child: _AppHeroColumn(
                                    logo: _brandLogo(100),
                                    compact: false,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 48),
                              Expanded(
                                flex: 4,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 44),
                                  child: _AppSidePanel(),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Transform.translate(
                                offset: const Offset(0, -16),
                                child: _AppHeroColumn(
                                  logo: _brandLogo(88),
                                  compact: true,
                                ),
                              ),
                              const SizedBox(height: 28),
                              _AppSidePanel(),
                            ],
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
}

class _AppHeroColumn extends StatelessWidget {
  const _AppHeroColumn({required this.logo, required this.compact});

  final Widget logo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment:
              compact ? MainAxisAlignment.center : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            logo,
            const SizedBox(width: 16),
            Flexible(
              child: Column(
                crossAxisAlignment: compact
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    'Law Connect',
                    textAlign: compact ? TextAlign.center : TextAlign.start,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.white,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Firm portal',
                    textAlign: compact ? TextAlign.center : TextAlign.start,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.gold.withValues(alpha: 0.95),
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 28 : 36),
        Text(
          'Counsel you can trust.\nClarity when it matters.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: compact ? 30 : 36,
            fontWeight: FontWeight.w700,
            height: 1.15,
            color: AppTheme.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Secure access to cases, appointments, and messages—'
          'built for a modern law practice.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: compact ? 15 : 16,
            height: 1.55,
            color: AppTheme.white.withValues(alpha: 0.82),
          ),
        ),
        SizedBox(height: compact ? 22 : 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: compact ? WrapAlignment.center : WrapAlignment.start,
          children: const [
            _AppFeatureChip(icon: Icons.gavel_rounded, label: 'Case updates'),
            _AppFeatureChip(
              icon: Icons.calendar_month_rounded,
              label: 'Appointments',
            ),
            _AppFeatureChip(icon: Icons.lock_rounded, label: 'Private & secure'),
          ],
        ),
      ],
    );
  }
}

class _AppFeatureChip extends StatelessWidget {
  const _AppFeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppTheme.gold),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppSidePanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Welcome',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.royalBlue,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to access the portal, or create an account to get started with the firm.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            text: 'Sign in',
            onPressed: () => Get.toNamed('/LoginPage'),
          ),
          const SizedBox(height: 12),
          AppButton(
            text: 'Create account',
            isSecondary: true,
            onPressed: () => Get.to(() => const SignupPage()),
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.grey[300]),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 20,
                color: AppTheme.royalBlue.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your information is handled in line with professional confidentiality standards.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
