import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../common/brand_logo.dart';
import '../common/nav_unread_dot.dart';
import 'staff_ui_theme.dart';

class StaffNavRail extends StatelessWidget {
  const StaffNavRail({
    super.key,
    required this.activeItem,
    required this.onItemSelected,
    required this.onLogout,
    this.messageUnreadCount = 0,
  });

  final String activeItem;
  final ValueChanged<String> onItemSelected;
  final VoidCallback onLogout;
  final int messageUnreadCount;

  static const _items = <({String key, String label, IconData icon})>[
    (key: 'dashboard', label: 'Dashboard', icon: Icons.dashboard_outlined),
    (key: 'cases', label: 'Cases', icon: Icons.folder_outlined),
    (key: 'closed_cases', label: 'Closed Cases', icon: Icons.folder_off_outlined),
    (key: 'draft_cases', label: 'Create Draft Case', icon: Icons.edit_document),
    (key: 'tasks', label: 'Tasks', icon: Icons.task_alt_outlined),
    (key: 'clients', label: 'Clients', icon: Icons.people_outline),
    (key: 'calendar', label: 'Calendar', icon: Icons.calendar_today_outlined),
    (key: 'notary', label: 'Notary', icon: Icons.draw_outlined),
    (
      key: 'billing',
      label: 'Billing & Payments',
      icon: Icons.account_balance_wallet_outlined,
    ),
    (key: 'communication', label: 'Messages', icon: Icons.chat_bubble_outline),
    (key: 'reports', label: 'Reports & Logs', icon: Icons.assessment_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: StaffUi.sidebarWidth,
      decoration: const BoxDecoration(gradient: StaffUi.sidebarGradient),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 16, 24),
              child: _Brand(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final item in _items)
                    _NavTile(
                      label: item.label,
                      icon: item.icon,
                      selected: activeItem == item.key,
                      badge: item.key == 'communication'
                          ? messageUnreadCount
                          : 0,
                      onTap: () => onItemSelected(item.key),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              child: _NavTile(
                label: 'Logout',
                icon: Icons.logout_rounded,
                selected: false,
                onTap: onLogout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const BrandLogo(size: 42),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'APAOStaff',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Legal Assistant',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? StaffUi.navy : Colors.white.withValues(alpha: 0.88);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? StaffUi.gold : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                navIconWithBadge(
                  icon,
                  badge: badge,
                  color: fg,
                  iconSize: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
