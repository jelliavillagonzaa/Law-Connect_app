import 'package:flutter/material.dart';

import 'admin_ui_theme.dart';

/// Shared premium chrome for nested admin pages shown inside the dashboard shell.
class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 18, 24, bottom == null ? 18 : 16),
      decoration: BoxDecoration(
        color: AdminUi.card,
        boxShadow: [
          BoxShadow(
            color: AdminUi.primary.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: const Border(
          bottom: BorderSide(color: AdminUi.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.text,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (actions != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    runSpacing: 8,
                    children: actions!,
                  ),
                ),
              ],
            ],
          ),
          if (bottom != null) ...[
            const SizedBox(height: 12),
            bottom!,
          ],
        ],
      ),
    );
  }
}
