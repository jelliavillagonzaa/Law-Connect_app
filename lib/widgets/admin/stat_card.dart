import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? description;
  final IconData icon;
  final Color iconColor;
  final Color? iconBackgroundColor;
  final Color? backgroundColor;
  final String? percentageChange;
  final bool isPositiveChange;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.description,
    required this.icon,
    required this.iconColor,
    this.iconBackgroundColor,
    this.backgroundColor,
    this.percentageChange,
    this.isPositiveChange = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 800;
    final radius = BorderRadius.circular(compact ? 14 : 16);

    Widget card({required bool fill}) {
      final descriptionText = description == null
          ? null
          : Text(
              description!,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                color: AppTheme.mutedText,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );

      return Container(
        width: fill ? double.infinity : null,
        height: fill ? double.infinity : null,
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 14,
          compact ? 10 : 12,
          compact ? 12 : 14,
          compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: backgroundColor ?? AppTheme.pastelBlueGray,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: compact ? 8 : 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: iconBackgroundColor == null
                      ? EdgeInsets.zero
                      : EdgeInsets.all(compact ? 6 : 8),
                  decoration: iconBackgroundColor == null
                      ? null
                      : BoxDecoration(
                          color: iconBackgroundColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                  child: Icon(icon, color: iconColor, size: compact ? 18 : 20),
                ),
                if (percentageChange != null)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 6 : 8,
                      vertical: compact ? 2 : 3,
                    ),
                    decoration: BoxDecoration(
                      color: isPositiveChange
                          ? AppTheme.successSoft
                          : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      percentageChange!,
                      style: TextStyle(
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w600,
                        color: isPositiveChange
                            ? AppTheme.success
                            : const Color(0xFFDC2626),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: compact ? 6 : 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: compact ? 22 : 26,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkText,
                  height: 1.05,
                ),
              ),
            ),
            SizedBox(height: compact ? 2 : 4),
            Text(
              title,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                color: AppTheme.darkText,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (descriptionText != null) ...[
              const SizedBox(height: 2),
              if (fill)
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: descriptionText,
                  ),
                )
              else
                descriptionText,
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final fill =
            constraints.maxHeight.isFinite &&
            constraints.maxHeight < double.infinity;
        final content = card(fill: fill);
        if (onTap == null) return content;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: content,
          ),
        );
      },
    );
  }
}
