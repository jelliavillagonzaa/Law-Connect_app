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
    this.onTap,
  });

  final String title;
  final String description;
  final String? timestamp;
  final IconData? icon;
  final AlertTone tone;
  final VoidCallback? onTap;

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
    final bool isClickable = widget.onTap != null;

    return MouseRegion(
      cursor: isClickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AdminUi.anim,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hover && isClickable ? -3 : 0, 0),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: _hover ? 0.20 : 0.12),
                color.withValues(alpha: _hover ? 0.09 : 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(AdminUi.radius),
            border: Border.all(
              color: color.withValues(alpha: _hover && isClickable ? 0.55 : 0.28),
              width: _hover && isClickable ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: _hover && isClickable ? 0.22 : 0.10),
                blurRadius: _hover && isClickable ? 20 : 16,
                offset: Offset(0, _hover && isClickable ? 10 : 8),
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
              if (isClickable) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: color.withValues(alpha: _hover ? 0.9 : 0.45),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
