import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'min_touch_target.dart';

/// App bar / header icon with 48dp touch target, ripple, and optional badge.
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final int badgeCount;
  final Color iconColor;
  final Color? backgroundColor;
  final double iconSize;
  final EdgeInsetsGeometry? margin;

  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.badgeCount = 0,
    this.iconColor = Colors.white,
    this.backgroundColor,
    this.iconSize = 24,
    this.margin,
  });

  /// Light-on-blue style used in attorney/admin app bars.
  factory AppIconButton.appBar({
    Key? key,
    required IconData icon,
    VoidCallback? onPressed,
    String? tooltip,
    int badgeCount = 0,
    bool dimWhenEmpty = true,
    EdgeInsetsGeometry? margin,
  }) {
    final active = badgeCount > 0 || !dimWhenEmpty;
    return AppIconButton(
      key: key,
      icon: icon,
      onPressed: onPressed,
      tooltip: tooltip,
      badgeCount: badgeCount,
      iconColor: active ? Colors.white : Colors.white.withValues(alpha: 0.85),
      backgroundColor: Colors.white.withValues(alpha: 0.2),
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final button = MinTouchTarget(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      splashColor: Colors.white.withValues(alpha: 0.2),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      tooltip: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: margin,
            padding: const EdgeInsets.all(10),
            decoration: backgroundColor != null
                ? BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(10),
                  )
                : null,
            child: Icon(icon, color: iconColor, size: iconSize),
          ),
          if (badgeCount > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: const TextStyle(
                    color: AppTheme.royalBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );

    return button;
  }
}
