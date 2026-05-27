import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../auth/login_page.dart';
import '../auth/signup_page.dart';

/// Public landing (web / app) for all roles. Same deep navy background as [LoginPage].
class ClientLandingPage extends StatelessWidget {
  const ClientLandingPage({super.key});

  static Widget _brandLogo(double size) {
    return ClipOval(
      child: Image.asset(
        'assets/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }

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
                                child: _HeroColumn(
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
                                child: _SidePanel(),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Transform.translate(
                              offset: const Offset(0, -16),
                              child: _HeroColumn(
                                logo: _brandLogo(88),
                                compact: true,
                              ),
                            ),
                            const SizedBox(height: 28),
                            _SidePanel(),
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

class _HeroColumn extends StatelessWidget {
  const _HeroColumn({required this.logo, required this.compact});

  final Widget logo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: compact
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
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
            _FeatureChip(icon: Icons.gavel_rounded, label: 'Case updates'),
            _FeatureChip(
              icon: Icons.calendar_month_rounded,
              label: 'Appointments',
            ),
            _FeatureChip(icon: Icons.lock_rounded, label: 'Private & secure'),
          ],
        ),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

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

class _SidePanel extends StatelessWidget {
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
            onPressed: () => Get.to(() => const LoginPage()),
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
