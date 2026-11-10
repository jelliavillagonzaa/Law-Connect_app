import 'package:flutter/material.dart';

import '../common/brand_logo.dart';
import 'staff_ui_theme.dart';

class StaffNavRail extends StatelessWidget {
  const StaffNavRail({
    super.key,
    required this.activeItem,
    required this.onItemSelected,
    required this.onLogout,
    this.messageUnreadCount = 0,
    this.pendingAppointmentsCount = 0,
  });

  final String activeItem;
  final ValueChanged<String> onItemSelected;
  final VoidCallback onLogout;
  final int messageUnreadCount;
  final int pendingAppointmentsCount;

  static const _operationItems = <({String key, String label, IconData icon})>[
    (key: 'dashboard', label: 'Dashboard', icon: Icons.dashboard_outlined),
    (key: 'cases', label: 'Cases', icon: Icons.folder_outlined),
    (key: 'closed_cases', label: 'Closed Cases', icon: Icons.folder_off_outlined),
    (key: 'draft_cases', label: 'Create Draft Case', icon: Icons.edit_document),
    (key: 'pending', label: 'Pending Appointments', icon: Icons.pending_actions_outlined),
    (key: 'tasks', label: 'Tasks', icon: Icons.task_alt_outlined),
    (key: 'clients', label: 'Clients', icon: Icons.people_outline),
    (key: 'calendar', label: 'Calendar', icon: Icons.calendar_today_outlined),
    (key: 'notary', label: 'Notary', icon: Icons.draw_outlined),
    (key: 'payment_history', label: 'Payment History', icon: Icons.receipt_long_outlined),
    (key: 'communication', label: 'Messages', icon: Icons.chat_bubble_outline),
    (key: 'reports', label: 'Reports', icon: Icons.assessment_outlined),
  ];

  static const _adminItems = <({String key, String label, IconData icon})>[
    (key: 'admin_dashboard', label: 'Admin Dashboard', icon: Icons.space_dashboard_outlined),
    (key: 'admin_users', label: 'User Management', icon: Icons.manage_accounts_outlined),
    (key: 'admin_cases', label: 'Case Oversight', icon: Icons.policy_outlined),
    (key: 'admin_analytics', label: 'System Analytics', icon: Icons.analytics_outlined),
    (key: 'admin_logs', label: 'System Logs', icon: Icons.receipt_long_outlined),
    (key: 'admin_archive', label: 'Archive Storage', icon: Icons.inventory_2_outlined),
    (key: 'admin_backup', label: 'Backup & Restore', icon: Icons.settings_backup_restore_outlined),
    (key: 'admin_settings', label: 'System Settings', icon: Icons.settings_outlined),
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
                  const _SectionHeader(title: 'OPERATIONS'),
                  for (final item in _operationItems)
                    _NavTile(
                      label: item.label,
                      icon: item.icon,
                      selected: activeItem == item.key,
                      badge: item.key == 'communication'
                          ? messageUnreadCount
                          : (item.key == 'pending' ? pendingAppointmentsCount : 0),
                      onTap: () => onItemSelected(item.key),
                    ),
                  const SizedBox(height: 12),
                  const _SectionHeader(title: 'ADMINISTRATION'),
                  for (final item in _adminItems)
                    _NavTile(
                      label: item.label,
                      icon: item.icon,
                      selected: activeItem == item.key,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Row(
        children: [
          Text(
            title,
            style: StaffUi.style(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: StaffUi.goldSoft.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ],
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
        const BrandLogo(size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'APAOStaff',
                style: StaffUi.style(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Legal Assistant & Administrator',
                style: StaffUi.style(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.65),
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
    final fg = selected ? StaffUi.navyDeep : Colors.white.withValues(alpha: 0.88);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          child: Container(
            decoration: BoxDecoration(
              gradient: selected ? StaffUi.goldGradient : null,
              borderRadius: BorderRadius.circular(12),
              boxShadow: selected ? StaffUi.goldButtonShadow : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StaffUi.style(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? StaffUi.navyDeep : const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      textAlign: TextAlign.center,
                      style: StaffUi.style(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? StaffUi.gold : Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

