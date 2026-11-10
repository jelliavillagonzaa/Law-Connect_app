import 'package:flutter/material.dart';

import 'staff_ui_theme.dart';

class StaffOverviewCard extends StatelessWidget {
  const StaffOverviewCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.pastel,
    this.badgeText,
    this.onTap,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color pastel;
  final String? badgeText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: StaffUi.card,
        borderRadius: BorderRadius.circular(StaffUi.radius),
        border: Border.all(color: StaffUi.line, width: 1),
        boxShadow: StaffUi.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(StaffUi.radius),
          splashColor: iconColor.withValues(alpha: 0.08),
          highlightColor: iconColor.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: pastel,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, color: iconColor, size: 18),
                    ),
                    const SizedBox(width: 4),
                    if (badgeText != null)
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: pastel.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badgeText!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: StaffUi.style(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: iconColor,
                            ),
                          ),
                        ),
                      )
                    else if (onTap != null)
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 11,
                        color: StaffUi.muted.withValues(alpha: 0.5),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: StaffUi.style(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: StaffUi.text,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 1.5),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StaffUi.style(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: StaffUi.text,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StaffUi.style(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: StaffUi.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

