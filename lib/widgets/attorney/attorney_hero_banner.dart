import 'dart:ui';

import 'package:flutter/material.dart';

import 'attorney_ui_theme.dart';

class AttorneyHeroBanner extends StatelessWidget {
  const AttorneyHeroBanner({super.key, this.flush = false});

  final bool flush;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    final radius = flush
        ? BorderRadius.zero
        : BorderRadius.circular(AttorneyUi.heroRadius);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AttorneyUi.heroGradient,
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: compact
            ? const Padding(
                padding: EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _WelcomeBlock(compact: true),
                    SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: _QuotePanel.width,
                        height: _QuotePanel.height,
                        child: _QuotePanel(),
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox(
                height: _QuotePanel.height,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(18, 10, 14, 10),
                        child: _WelcomeBlock(),
                      ),
                    ),
                    SizedBox(
                      width: _QuotePanel.width,
                      child: _QuotePanel(),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _WelcomeBlock extends StatelessWidget {
  const _WelcomeBlock({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: compact ? 36 : 40,
              height: compact ? 36 : 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: Icon(
                Icons.gavel_rounded,
                color: Colors.white,
                size: compact ? 18 : 20,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WELCOME BACK,',
                style: AttorneyUi.style(
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.78),
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                'Dashboard',
                style: AttorneyUi.style(
                  fontSize: compact ? 20 : 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your cases and appointments',
                style: AttorneyUi.style(
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'JUSTICE  ·  SERVICE  ·  ACCESSIBILITY',
                style: AttorneyUi.style(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.55),
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuotePanel extends StatelessWidget {
  const _QuotePanel();

  static const double width = 248;
  static const double height = 108;
  static const Color navy = Color(0xFF0D2B4E);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: navy,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 150,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.72,
                child: Image.asset(
                  'assets/Landingpage.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  navy,
                  navy,
                  Color(0x990D2B4E),
                  Color(0x330D2B4E),
                ],
                stops: [0, 0.28, 0.55, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 72, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  "Law is not just a profession,\nit's a service to people.",
                  style: AttorneyUi.style(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    color: Colors.white,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 42,
                  height: 3,
                  color: AttorneyUi.accent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
