import 'package:flutter/material.dart';

import 'admin_ui_theme.dart';

enum AlertTone { danger, warning, info, success }

class AlertCard extends StatefulWidget {
  const AlertCard({
    super.key,
    required this.title,
    required this.description,
    this.timestamp,
    this.icon,
    this.tone = AlertTone.warning,
  });

  final String title;
  final String description;
  final String? timestamp;
  final IconData? icon;
  final AlertTone tone;

  @override
  State<AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<AlertCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (widget.tone) {
      AlertTone.danger => AdminUi.danger,
      AlertTone.warning => AdminUi.warning,
      AlertTone.info => AdminUi.info,
      AlertTone.success => AdminUi.success,
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: AdminUi.anim,
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: _hover ? 0.16 : 0.12),
              color.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(AdminUi.radius),
          border: Border.all(color: color.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: _hover ? 0.16 : 0.10),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                widget.icon ?? Icons.notifications_active_outlined,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AdminUi.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.description,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AdminUi.muted,
                      height: 1.4,
                    ),
                  ),
                  if (widget.timestamp != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.timestamp!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
