import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/law_connect_logo.dart';
import '../auth/login_page.dart';

/// Attorney portal landing — login only.
class AttorneyLandingPage extends StatelessWidget {
  const AttorneyLandingPage({super.key});

  static Widget _brandLogo(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: LawConnectLogo(
        size: size,
        color: AppTheme.white,
        goldColor: AppTheme.gold,
        showGlow: true,
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
                          child: _AttorneyHero(logo: _brandLogo(96)),
                        ),
                        const SizedBox(width: 40),
                        Expanded(flex: 4, child: _AttorneyCard()),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AttorneyHero(logo: _brandLogo(80), compact: true),
                        const SizedBox(height: 24),
                        _AttorneyCard(),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AttorneyHero extends StatelessWidget {
  const _AttorneyHero({required this.logo, this.compact = false});

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
                    'Attorney portal',
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
          'Manage cases, clients, and hearings in one place.',
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
          'Licensed counsel can register to join the platform; your profile may be reviewed before activation.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: compact ? 14 : 15,
            height: 1.5,
            color: AppTheme.white.withValues(alpha: 0.82),
          ),
        ),
      ],
    );
  }
}

class _AttorneyCard extends StatelessWidget {
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
            'Welcome, counsel',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.royalBlue,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to your dashboard, or create an attorney account to request access.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 20),
          AppButton(
            text: 'Sign in',
            onPressed: () => Get.to(() => const LoginPage()),
          ),
        ],
      ),
    );
  }
}
