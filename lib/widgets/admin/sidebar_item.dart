import 'package:flutter/material.dart';

import 'admin_ui_theme.dart';

class SidebarItem extends StatefulWidget {
  const SidebarItem({
    super.key,
    required this.title,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: AdminUi.anim,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: active
                ? Colors.white
                : (_hover ? Colors.white.withValues(alpha: 0.10) : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(12),
              hoverColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: AdminUi.anim,
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: active
                            ? AdminUi.primary.withValues(alpha: 0.10)
                            : Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        widget.icon,
                        size: 15,
                        color: active ? AdminUi.primary : Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? AdminUi.primary : Colors.white,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    if (active)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: AdminUi.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
