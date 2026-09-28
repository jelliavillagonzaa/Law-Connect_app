import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// App logo — full artwork with no oval crop so the gavel and circuit ring stay visible.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Decode at least 3× layout size so a 40–48px header logo stays sharp
    // on Flutter web and high-DPI screens (default scaling looks muddy).
    final cacheSize = math.max((size * dpr).round(), (size * 3).round());

    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        errorBuilder: (_, __, ___) => _fallback(size),
      ),
    );
  }

  static Widget _fallback(double size) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: AppTheme.gold.withValues(alpha: 0.12),
      child: Icon(
        Icons.balance,
        size: size * 0.52,
        color: AppTheme.gold,
        textDirection: TextDirection.ltr,
      ),
    );
  }
}
