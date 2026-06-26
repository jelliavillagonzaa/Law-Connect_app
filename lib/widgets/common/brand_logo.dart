import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// App logo — uses [assets/logo.png] when present, otherwise a gold scales icon.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
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
      ),
    );
  }
}
