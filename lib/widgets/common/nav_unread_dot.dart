import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Unread dot on list rows — matches [StaffNotificationsScreen] / reminder tiles.
class ListUnreadDot extends StatelessWidget {
  final Color color;

  const ListUnreadDot({
    super.key,
    this.color = AppTheme.royalBlue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Nav icon with numeric unread badge (bottom nav, sidebar icon).
Widget navIconWithBadge(
  IconData icon, {
  int badge = 0,
  Color? color,
  double iconSize = 24,
}) {
  final iconWidget = Icon(icon, size: iconSize, color: color);
  if (badge <= 0) return iconWidget;
  final label = badge > 99 ? '99+' : badge > 9 ? '9+' : '$badge';
  return Stack(
    clipBehavior: Clip.none,
    children: [
      iconWidget,
      Positioned(
        right: -8,
        top: -4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: const BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ],
  );
}
