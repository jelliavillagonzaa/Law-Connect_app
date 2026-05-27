import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../theme/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/law_connect_logo.dart';
import '../auth/login_page.dart';
import 'staff_application_page.dart';
import 'staff_complete_registration_page.dart';
import 'staff_application_status_page.dart';

/// Staff portal landing — navy background matches [LoginPage].
class StaffLandingPage extends StatelessWidget {
  const StaffLandingPage({super.key});

  static Widget _brandLogo(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Builder(
        builder: (context) {
          if (kIsWeb) {
            return Image.network(
              '/log.png',
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: (ctx, err, stack) {
                return LawConnectLogo(
                  size: size,
                  color: AppTheme.white,
                  goldColor: AppTheme.gold,
                  showGlow: true,
                );
              },
            );
          }
          return Image.asset(
            'assets/logo.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) {
              return LawConnectLogo(
                size: size,
                color: AppTheme.white,
                goldColor: AppTheme.gold,
                showGlow: true,
              );
            },
          );
        },
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
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _StaffHero(logo: _brandLogo(96)),
                        ),
                        const SizedBox(width: 40),
                        Expanded(
                          flex: 4,
                          child: _StaffActionsCard(),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _StaffHero(logo: _brandLogo(80), compact: true),
                        const SizedBox(height: 24),
                        _StaffActionsCard(),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StaffHero extends StatelessWidget {
  const _StaffHero({required this.logo, this.compact = false});

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
            const SizedBox(width: 14),
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
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Staff portal',
                    textAlign: compact ? TextAlign.center : TextAlign.start,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.gold.withValues(alpha: 0.95),
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 22 : 28),
        Text(
          'Support the practice with secure tools for cases, tasks, and clients.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: compact ? 26 : 30,
            fontWeight: FontWeight.w700,
            height: 1.12,
            color: AppTheme.white,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'New staff must apply and receive administrator approval before creating an account.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: compact ? 14 : 15,
            height: 1.5,
            color: AppTheme.white.withValues(alpha: 0.82),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: compact ? WrapAlignment.center : WrapAlignment.start,
          children: [
            _MiniChip(icon: Icons.task_alt_rounded, label: 'Tasks & deadlines'),
            _MiniChip(icon: Icons.forum_outlined, label: 'Firm messaging'),
            _MiniChip(icon: Icons.admin_panel_settings_outlined, label: 'Admin-approved access'),
          ],
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.gold),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffActionsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Get started',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.royalBlue,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in if you already have an account. Otherwise submit an application—an admin will review it first.',
            style: TextStyle(fontSize: 13, height: 1.45, color: Colors.grey[800]),
          ),
          const SizedBox(height: 20),
          AppButton(
            text: 'Sign in',
            onPressed: () => Get.to(() => const LoginPage()),
          ),
          const SizedBox(height: 10),
          AppButton(
            text: 'Request staff access',
            isSecondary: true,
            onPressed: () => Get.to(() => const StaffApplicationPage()),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Get.to(() => const StaffCompleteRegistrationPage()),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.royalBlue,
              side: const BorderSide(color: AppTheme.royalBlue, width: 1.2),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Complete registration (after approval)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Get.to(() => const StaffApplicationStatusPage()),
            child: const Text('Check application status'),
          ),
        ],
      ),
    );
  }
}
