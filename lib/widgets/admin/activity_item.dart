import 'package:flutter/material.dart';

import 'admin_ui_theme.dart';

class ActivityItem extends StatefulWidget {
  const ActivityItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    this.details,
    this.isLast = false,
    this.icon,
    this.accent,
  });

  final String title;
  final String subtitle;
  final String timestamp;
  final String? details;
  final bool isLast;
  final IconData? icon;
  final Color? accent;

  @override
  State<ActivityItem> createState() => _ActivityItemState();
}

class _ActivityItemState extends State<ActivityItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.accent ?? AdminUi.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: AdminUi.anim,
        curve: Curves.easeOut,
        margin: EdgeInsets.only(bottom: widget.isLast ? 0 : 8),
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          color: _hover ? AdminUi.background : AdminUi.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hover ? color.withValues(alpha: 0.18) : AdminUi.line,
          ),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 22,
                child: Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    if (!widget.isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                color.withValues(alpha: 0.45),
                                color.withValues(alpha: 0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.icon ?? Icons.history_rounded,
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AdminUi.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AdminUi.muted,
                      ),
                    ),
                    if (widget.details != null && widget.details!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.details!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AdminUi.muted.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Align(
                alignment: Alignment.topRight,
                child: Text(
                  widget.timestamp,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AdminUi.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
