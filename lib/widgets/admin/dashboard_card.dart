import 'package:flutter/material.dart';

import 'admin_ui_theme.dart';
import 'stat_badge.dart';

class DashboardCard extends StatefulWidget {
  const DashboardCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.pastel,
    this.subtitle,
    this.percentageChange,
    this.isPositiveChange = true,
    this.onTap,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final Color pastel;
  final String? percentageChange;
  final bool isPositiveChange;
  final VoidCallback? onTap;

  @override
  State<DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<DashboardCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 800;
    final iconSize = compact ? 32.0 : 34.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: AdminUi.anim,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: AdminUi.card,
          borderRadius: BorderRadius.circular(AdminUi.radius),
          boxShadow: _hover ? AdminUi.cardShadowHover : AdminUi.cardShadow,
          border: Border.all(
            color: _hover
                ? widget.iconColor.withValues(alpha: 0.28)
                : AdminUi.line,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(AdminUi.radius),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AdminUi.radius),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            widget.pastel,
                            widget.pastel.withValues(alpha: 0.35),
                            AdminUi.card,
                          ],
                          stops: const [0, 0.42, 1],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 12 : 14,
                      compact ? 10 : 12,
                      compact ? 10 : 12,
                      compact ? 10 : 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: iconSize,
                          height: iconSize,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white,
                                widget.pastel,
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: widget.iconColor.withValues(alpha: 0.28),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.iconColor,
                            size: compact ? 16 : 17,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: compact ? 20 : 22,
                                        fontWeight: FontWeight.w800,
                                        color: AdminUi.text,
                                        height: 1.1,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ),
                                  if (widget.percentageChange != null) ...[
                                    const SizedBox(width: 6),
                                    StatBadge(
                                      label: widget.percentageChange!,
                                      positive: widget.isPositiveChange,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AdminUi.text,
                                ),
                              ),
                              if (widget.subtitle != null)
                                Text(
                                  widget.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: AdminUi.muted,
                                    height: 1.2,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

