import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Verified badge widget
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.success.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.verified,
        color: AppTheme.success,
        size: 16,
      ),
    );
  }
}

