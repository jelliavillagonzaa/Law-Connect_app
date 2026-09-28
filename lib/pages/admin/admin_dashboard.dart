import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../pages/case/case_detail_page.dart';
import '../../widgets/admin/admin_sidebar.dart';
import '../../widgets/admin/admin_header.dart';
import '../../widgets/admin/activity_item.dart';
import '../../widgets/admin/admin_ui_theme.dart';
import '../../widgets/admin/alert_card.dart';
import '../../widgets/admin/dashboard_card.dart';
import '../../widgets/admin/header_hero.dart';
import '../../screens/admin/user_management_screen.dart';
import '../../services/system_settings_service.dart';
import '../../screens/admin/case_oversight_screen.dart';
import '../../screens/admin/archive_storage_screen.dart';
import '../../screens/admin/backup_settings_screen.dart';
import '../../screens/admin/system_logs_screen.dart';
import '../../screens/admin/reports_analytics_screen.dart';
import '../../screens/admin/system_settings_screen.dart';
import '../../routes/portal_navigation.dart';
import '../../utils/quiet_console.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _activeItem = 'dashboard';
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _recentActivity = [];
  List<Map<String, dynamic>> _systemAlerts = [];
  /// Role filter when opening User Management from a stat card (sidebar resets to all).
  String _userManagementRoleFilter = 'all';
  /// Name/email filter when opening User Management from header search.
  String _userManagementSearch = '';
  /// Status filter when opening Case Oversight from a stat card (sidebar resets to all).
  String _caseOversightStatusFilter = 'all';

  List<Map<String, String>> _searchUsers = const [];
  List<Map<String, String>> _searchCases = const [];
  List<Map<String, String>> _searchLogs = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadDashboardData());
    });
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    try {
      // Count queries — never download entire users/cases collections (UI freeze).
      final countResults = await Future.wait([
        _firestore.collection('users').count().get(),
        _firestore.collection('users').where('role', isEqualTo: 'client').count().get(),
        _firestore.collection('users').where('role', isEqualTo: 'attorney').count().get(),
        _firestore.collection('users').where('role', isEqualTo: 'staff').count().get(),
        _firestore.collection('cases').count().get(),
        _firestore.collection('cases').where('status', isEqualTo: 'pending').count().get(),
        _firestore.collection('cases').where('status', isEqualTo: 'in_progress').count().get(),
      ]);

      final totalUsers = countResults[0].count ?? 0;
      final clients = countResults[1].count ?? 0;
      final attorneys = countResults[2].count ?? 0;
      final staff = countResults[3].count ?? 0;
      final totalCases = countResults[4].count ?? 0;
      final pendingCases = countResults[5].count ?? 0;
      final activeCases = countResults[6].count ?? 0;

      // Load recent activity (system logs)
      QuerySnapshot<Map<String, dynamic>> logsSnapshot;
      try {
        logsSnapshot = await _firestore
            .collection('system_logs')
            .orderBy('timestamp', descending: true)
            .limit(30)
            .get();
      } catch (_) {
        logsSnapshot = await _firestore.collection('system_logs').limit(30).get();
      }

      final recentActivity = logsSnapshot.docs.take(5).map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'action': data['action'] ?? 'Unknown',
          'userName': data['userName'] ?? 'Unknown',
          'timestamp': data['timestamp'],
          'details': data['details'],
        };
      }).toList();

      // Load system alerts (maintenance mode, etc.)
      final settingsDoc = await _firestore
          .collection('system_settings')
          .doc('maintenance')
          .get();

      final alerts = <Map<String, dynamic>>[];
      final notify = await SystemSettingsService.instance.load();
      if (notify.systemAlerts && settingsDoc.exists) {
        final data = settingsDoc.data();
        if (data?['maintenanceMode'] == true) {
          alerts.add({
            'type': 'warning',
            'title': 'Maintenance Mode Active',
            'message': 'System is currently in maintenance mode',
            'icon': Icons.build,
          });
        }
      }

      final searchIndex = await _loadSearchIndex(logsSnapshot);

      setState(() {
        _stats = {
          'totalUsers': totalUsers,
          'totalClients': clients,
          'attorneys': attorneys,
          'staff': staff,
          'totalCases': totalCases,
          'pendingCases': pendingCases,
          'activeCases': activeCases,
        };
        _recentActivity = recentActivity;
        _systemAlerts = alerts;
        _searchUsers = searchIndex.users;
        _searchCases = searchIndex.cases;
        _searchLogs = searchIndex.logs;
      });
    } catch (e) {
      appLog('Error loading dashboard data: $e');
    }
  }

  String _safeText(Object? value) {
    if (value == null) return '';
    final text = '$value';
    if (text == 'null' || text == 'undefined') return '';
    return text.trim();
  }

  Future<
      ({
        List<Map<String, String>> users,
        List<Map<String, String>> cases,
        List<Map<String, String>> logs,
      })> _loadSearchIndex(
    QuerySnapshot<Map<String, dynamic>> logsSnapshot,
  ) async {
    var users = <Map<String, String>>[];
    var cases = <Map<String, String>>[];
    try {
      final snaps = await Future.wait([
        _firestore.collection('users').limit(50).get(),
        _firestore.collection('cases').limit(50).get(),
      ]);
      users = snaps[0].docs.map((doc) {
        final data = doc.data();
        final name = _safeText(
          data['name'] ??
              data['fullName'] ??
              '${_safeText(data['firstName'])} ${_safeText(data['lastName'])}',
        );
        final email = _safeText(data['email']);
        final role = _safeText(data['role']);
        return {
          'id': doc.id,
          'title': name.isNotEmpty ? name : (email.isNotEmpty ? email : 'User'),
          'subtitle': [
            if (role.isNotEmpty) role,
            if (email.isNotEmpty) email,
          ].join(' · '),
          'hay': '$name $email $role'.toLowerCase(),
          'role': role,
        };
      }).toList();
      cases = snaps[1].docs.map((doc) {
        final data = doc.data();
        final title = _safeText(data['caseTitle']);
        final type = _safeText(data['caseType']);
        final status = _safeText(data['status']);
        final description = _safeText(data['caseDescription']);
        return {
          'id': doc.id,
          'title': title.isNotEmpty ? title : 'Untitled case',
          'subtitle': [
            'Case',
            if (type.isNotEmpty) type,
            if (status.isNotEmpty) status,
          ].join(' · '),
          'hay': '$title $type $status $description'.toLowerCase(),
        };
      }).toList();
    } catch (e) {
      appLog('Error loading admin search index: $e');
    }

    final logs = logsSnapshot.docs.map((doc) {
      final data = doc.data();
      final action = _safeText(data['action']);
      final userName = _safeText(data['userName']);
      final details = _safeText(data['details']);
      return {
        'id': doc.id,
        'title': action.isNotEmpty ? action : 'System log',
        'subtitle': [
          'Log',
          if (userName.isNotEmpty) userName,
        ].join(' · '),
        'hay': '$action $userName $details'.toLowerCase(),
      };
    }).toList();

    return (users: users, cases: cases, logs: logs);
  }

  List<AdminSearchHit> _headerSearchHits(String raw) {
    try {
      final q = _safeText(raw).toLowerCase();
      if (q.isEmpty) return const [];

      final hits = <AdminSearchHit>[];

      void addHit({
        required String title,
        required String subtitle,
        required IconData icon,
        required VoidCallback onTap,
      }) {
        if (hits.length >= 8) return;
        hits.add(
          AdminSearchHit(
            title: title,
            subtitle: subtitle,
            icon: icon,
            onTap: onTap,
          ),
        );
      }

      for (final row in _searchUsers) {
        if (!(row['hay'] ?? '').contains(q)) continue;
        addHit(
          title: row['title'] ?? 'User',
          subtitle: row['subtitle'] ?? 'User',
          icon: Icons.person_outline,
          onTap: () => _openUsersFiltered(
            'all',
            search: row['title'] ?? q,
          ),
        );
        if (hits.length >= 8) return hits;
      }

      for (final row in _searchCases) {
        if (!(row['hay'] ?? '').contains(q)) continue;
        final caseId = row['id'] ?? '';
        addHit(
          title: row['title'] ?? 'Case',
          subtitle: row['subtitle'] ?? 'Case',
          icon: Icons.folder_outlined,
          onTap: () {
            if (caseId.isEmpty) {
              _openCasesFiltered('all');
              return;
            }
            Get.to(() => CaseDetailPage(caseId: caseId));
          },
        );
        if (hits.length >= 8) return hits;
      }

      for (final row in _searchLogs) {
        if (!(row['hay'] ?? '').contains(q)) continue;
        addHit(
          title: row['title'] ?? 'Log',
          subtitle: row['subtitle'] ?? 'Log',
          icon: Icons.receipt_long_outlined,
          onTap: () => _handleItemSelected('logs'),
        );
        if (hits.length >= 8) return hits;
      }

      if (hits.isEmpty && q.length >= 2) {
        if (q.contains('user') ||
            q.contains('client') ||
            q.contains('attorney') ||
            q.contains('staff') ||
            'users'.startsWith(q)) {
          addHit(
            title: 'User management',
            subtitle: 'Open users',
            icon: Icons.people_outline,
            onTap: () => _openUsersFiltered('all', search: raw.trim()),
          );
        }
        if (q.contains('case') || 'cases'.startsWith(q)) {
          addHit(
            title: 'Case oversight',
            subtitle: 'Open cases',
            icon: Icons.folder_outlined,
            onTap: () => _openCasesFiltered('all'),
          );
        }
        if (q.contains('log') || 'logs'.startsWith(q)) {
          addHit(
            title: 'System logs',
            subtitle: 'Open activity logs',
            icon: Icons.receipt_long_outlined,
            onTap: () => _handleItemSelected('logs'),
          );
        }
      }

      return hits;
    } catch (_) {
      return const [];
    }
  }

  void _onHeaderSearchSubmitted(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    final hits = _headerSearchHits(q);
    if (hits.isNotEmpty) {
      hits.first.onTap();
      return;
    }
    _openUsersFiltered('all', search: q);
  }

  void _closeMobileDrawerIfNeeded() {
    if (!mounted) return;
    if (MediaQuery.of(context).size.width < 768) {
      Navigator.of(context).pop();
    }
  }

  void _openUsersFiltered(String role, {String? search}) {
    setState(() {
      _activeItem = 'users';
      _userManagementRoleFilter = role;
      _userManagementSearch = search?.trim() ?? '';
    });
    _closeMobileDrawerIfNeeded();
  }

  void _openCasesFiltered(String status) {
    setState(() {
      _activeItem = 'cases';
      _caseOversightStatusFilter = status;
    });
    _closeMobileDrawerIfNeeded();
  }

  void _handleItemSelected(String item) {
    if (mounted) {
      setState(() {
        _activeItem = item;
        if (item == 'users') {
          _userManagementRoleFilter = 'all';
          _userManagementSearch = '';
        } else if (item == 'cases') {
          _caseOversightStatusFilter = 'all';
        }
      });

      // Close sidebar on mobile
      _closeMobileDrawerIfNeeded();
    }
  }

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      navigateAfterLogout();
    } catch (e) {
      navigateAfterLogout();
    }
  }

  Widget _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Add responsive padding for larger screens
        final horizontalPadding = constraints.maxWidth > 1400
            ? 32.0
            : constraints.maxWidth > 1200
            ? 24.0
            : constraints.maxWidth > 768
            ? 20.0
            : 16.0;

        final page = switch (_activeItem) {
          'users' => UserManagementScreen(
              inline: true,
              initialRoleFilter: _userManagementRoleFilter == 'all'
                  ? null
                  : _userManagementRoleFilter,
              initialSearchQuery: _userManagementSearch.isEmpty
                  ? null
                  : _userManagementSearch,
            ),
          'cases' => CaseOversightScreen(
              inline: true,
              initialStatusFilter: _caseOversightStatusFilter == 'all'
                  ? null
                  : _caseOversightStatusFilter,
              onOpenArchiveStorage: () {
                Get.to(
                  () => ArchiveStorageScreen(
                    onOpenBackup: () =>
                        Get.to(() => const BackupSettingsScreen()),
                  ),
                );
              },
            ),
          'logs' => const SystemLogsScreen(inline: true),
          'reports' => ReportsAnalyticsScreen(
              inline: true,
              onNavigateToUsers: ({String role = 'all'}) =>
                  _openUsersFiltered(role),
              onNavigateToCases: ({String status = 'all'}) =>
                  _openCasesFiltered(status),
            ),
          'settings' => const SystemSettingsScreen(inline: true),
          _ => _buildDashboardContent(horizontalPadding),
        };

        if (_activeItem == 'users' ||
            _activeItem == 'cases' ||
            _activeItem == 'logs' ||
            _activeItem == 'reports' ||
            _activeItem == 'settings') {
          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Container(
              constraints: constraints.maxWidth > 1600
                  ? const BoxConstraints(maxWidth: 1600)
                  : null,
              margin: constraints.maxWidth > 1600
                  ? EdgeInsets.symmetric(
                      horizontal: (constraints.maxWidth - 1600) / 2,
                    )
                  : null,
              child: page,
            ),
          );
        }

        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: page,
        );
      },
    );
  }

  Widget _buildDashboardContent([double horizontalPadding = 16.0]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeader(
          findHits: _headerSearchHits,
          onSubmitted: _onHeaderSearchSubmitted,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadDashboardData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                16,
                horizontalPadding,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = MediaQuery.of(context).size.width;
              final crossAxisCount = screenWidth > 1600
                  ? 4
                  : screenWidth > 1200
                  ? 4
                  : screenWidth > 800
                  ? 3
                  : screenWidth > 600
                  ? 2
                  : 1;
              final cardHeight = screenWidth > 800 ? 88.0 : 84.0;

              return GridView(
                clipBehavior: Clip.none,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: cardHeight,
                ),
                children: [
                  DashboardCard(
                    title: 'Total Users',
                    value: '${_stats['totalUsers'] ?? 0}',
                    subtitle: 'All registered users',
                    icon: Icons.people_outlined,
                    iconColor: const Color(0xFF2C5282),
                    pastel: const Color(0xFFD6E6F8),
                    percentageChange: '+12%',
                    onTap: () => _openUsersFiltered('all'),
                  ),
                  DashboardCard(
                    title: 'Total Clients',
                    value: '${_stats['totalClients'] ?? 0}',
                    subtitle: 'Active clients',
                    icon: Icons.person_outline,
                    iconColor: const Color(0xFF2F7A4F),
                    pastel: const Color(0xFFD8F0DC),
                    percentageChange: '+8%',
                    onTap: () => _openUsersFiltered('client'),
                  ),
                  DashboardCard(
                    title: 'Attorneys',
                    value: '${_stats['attorneys'] ?? 0}',
                    subtitle: 'Registered attorneys',
                    icon: Icons.badge_outlined,
                    iconColor: const Color(0xFFE56A1A),
                    pastel: const Color(0xFFFFE8D6),
                    percentageChange: '+6%',
                    onTap: () => _openUsersFiltered('attorney'),
                  ),
                  DashboardCard(
                    title: 'Staff',
                    value: '${_stats['staff'] ?? 0}',
                    subtitle: 'Registered staff',
                    icon: Icons.support_agent,
                    iconColor: const Color(0xFF5A5478),
                    pastel: const Color(0xFFE6E0F6),
                    percentageChange: '+3%',
                    onTap: () => _openUsersFiltered('staff'),
                  ),
                  DashboardCard(
                    title: 'Total Cases',
                    value: '${_stats['totalCases'] ?? 0}',
                    subtitle: 'All cases',
                    icon: Icons.folder_outlined,
                    iconColor: const Color(0xFFB42318),
                    pastel: const Color(0xFFFFE4E1),
                    percentageChange: '+15%',
                    onTap: () => _openCasesFiltered('all'),
                  ),
                  DashboardCard(
                    title: 'Pending Cases',
                    value: '${_stats['pendingCases'] ?? 0}',
                    subtitle: 'Awaiting review',
                    icon: Icons.pending_outlined,
                    iconColor: const Color(0xFFB45309),
                    pastel: const Color(0xFFFEF3C7),
                    percentageChange: '+4%',
                    onTap: () => _openCasesFiltered('pending'),
                  ),
                  DashboardCard(
                    title: 'Active Cases',
                    value: '${_stats['activeCases'] ?? 0}',
                    subtitle: 'In progress',
                    icon: Icons.work_outline,
                    iconColor: const Color(0xFF1D4E89),
                    pastel: const Color(0xFFD6E6F8),
                    percentageChange: '+5%',
                    onTap: () => _openCasesFiltered('active'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = MediaQuery.of(context).size.width;
              if (screenWidth > 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _buildRecentActivity()),
                    const SizedBox(width: 16),
                    Expanded(flex: 1, child: _buildSystemAlerts()),
                  ],
                );
              }
              return Column(
                children: [
                  _buildRecentActivity(),
                  const SizedBox(height: 24),
                  _buildSystemAlerts(),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivity() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.card,
        borderRadius: BorderRadius.circular(AdminUi.radius),
        boxShadow: AdminUi.cardShadow,
        border: Border.all(color: AdminUi.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _SectionGlyph(icon: Icons.timeline_rounded, color: AdminUi.primary),
              SizedBox(width: 10),
              Text(
                'Recent Activity',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AdminUi.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_recentActivity.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No recent activity',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AdminUi.muted,
                  ),
                ),
              ),
            )
          else
            ...List.generate(_recentActivity.length, (index) {
              return _buildActivityItem(
                _recentActivity[index],
                isLast: index == _recentActivity.length - 1,
              );
            }),
        ],
      ),
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> activity, {bool isLast = false}) {
    final timestamp = activity['timestamp'] as Timestamp?;
    String timeAgo = 'Just now';
    if (timestamp != null) {
      final now = DateTime.now();
      final time = timestamp.toDate();
      final difference = now.difference(time);

      if (difference.inDays > 0) {
        timeAgo =
            '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
      } else if (difference.inHours > 0) {
        timeAgo =
            '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
      } else if (difference.inMinutes > 0) {
        timeAgo =
            '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
      }
    }

    final action = activity['action']?.toString() ?? 'Unknown';
    final title = _prettyAction(action);
    final details = activity['details']?.toString();
    final icon = _iconForAction(action);
    final accent = _colorForAction(action);

    return ActivityItem(
      title: title,
      subtitle: '${activity['userName'] ?? 'Unknown user'}',
      timestamp: timeAgo,
      details: details,
      isLast: isLast,
      icon: icon,
      accent: accent,
    );
  }

  String _prettyAction(String action) {
    final words = action.replaceAll('_', ' ').toLowerCase().split(' ');
    if (words.isEmpty || words.first.isEmpty) return action;
    return '${words.first[0].toUpperCase()}${words.first.substring(1)} ${words.skip(1).join(' ')}'
        .trim();
  }

  IconData _iconForAction(String action) {
    final key = action.toLowerCase();
    if (key.contains('login') || key.contains('sign')) return Icons.login_rounded;
    if (key.contains('create') || key.contains('add')) return Icons.add_circle_outline;
    if (key.contains('update') || key.contains('edit')) return Icons.edit_outlined;
    if (key.contains('delete') || key.contains('remove')) return Icons.delete_outline;
    if (key.contains('case')) return Icons.folder_outlined;
    if (key.contains('user')) return Icons.person_outline;
    return Icons.history_rounded;
  }

  Color _colorForAction(String action) {
    final key = action.toLowerCase();
    if (key.contains('delete') || key.contains('remove')) return AdminUi.danger;
    if (key.contains('create') || key.contains('add')) return AdminUi.success;
    if (key.contains('update') || key.contains('edit')) return AdminUi.warning;
    if (key.contains('login')) return AdminUi.info;
    return AdminUi.primary;
  }

  Widget _buildSystemAlerts() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.card,
        borderRadius: BorderRadius.circular(AdminUi.radius),
        boxShadow: AdminUi.cardShadow,
        border: Border.all(color: AdminUi.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _SectionGlyph(icon: Icons.notifications_outlined, color: AdminUi.danger),
              SizedBox(width: 10),
              Text(
                'System Alerts',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AdminUi.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._buildAlertCards(),
        ],
      ),
    );
  }

  List<Widget> _buildAlertCards() {
    final cards = <Widget>[];

    if (_systemAlerts.isEmpty) {
      cards.add(
        const AlertCard(
          title: 'All systems operational',
          description: 'No active maintenance or critical alerts right now.',
          timestamp: 'Live',
          icon: Icons.check_circle_outline,
          tone: AlertTone.success,
        ),
      );
    } else {
      cards.addAll(_systemAlerts.map(_buildAlertItem));
    }

    final pending = _stats['pendingCases'] as int? ?? 0;
    if (pending > 0) {
      cards.add(
        AlertCard(
          title: '$pending case${pending == 1 ? '' : 's'} pending review',
          description: 'Requires admin attention before assignment.',
          timestamp: 'Today',
          icon: Icons.error_outline_rounded,
          tone: AlertTone.danger,
        ),
      );
    }

    final users = _stats['totalUsers'] as int? ?? 0;
    cards.add(
      AlertCard(
        title: 'Platform monitoring is live',
        description:
            'Tracking $users registered user${users == 1 ? '' : 's'} across the system.',
        timestamp: 'Live',
        icon: Icons.shield_outlined,
        tone: AlertTone.info,
      ),
    );

    return cards;
  }

  Widget _buildAlertItem(Map<String, dynamic> alert) {
    final type = (alert['type'] ?? '').toString().toLowerCase();
    final title = (alert['title'] ?? 'Alert').toString();
    final tone = switch (type) {
      'error' || 'danger' => AlertTone.danger,
      'info' => AlertTone.info,
      'success' => AlertTone.success,
      _ => title.toLowerCase().contains('maintenance')
          ? AlertTone.danger
          : AlertTone.warning,
    };
    final timestamp = alert['timestamp']?.toString();

    return AlertCard(
      title: title,
      description: alert['message']?.toString() ?? '',
      timestamp: timestamp ?? 'Active',
      icon: alert['icon'] as IconData? ?? Icons.warning_amber_rounded,
      tone: tone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: AdminUi.background,
      body: Row(
        children: [
          // Sidebar - Desktop
          if (!isMobile)
            AdminSidebar(
              activeItem: _activeItem,
              onItemSelected: _handleItemSelected,
              onLogout: _handleLogout,
            ),

          // Main Content
          Expanded(
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(),
              child: Column(
                children: [
                  // Mobile AppBar
                  if (isMobile)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: const BoxDecoration(
                        gradient: AdminUi.navyGradient,
                      ),
                      child: Builder(
                        builder: (BuildContext scaffoldContext) {
                          return Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.menu_rounded),
                                color: Colors.white,
                                onPressed: () {
                                  Scaffold.of(scaffoldContext).openDrawer();
                                },
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'Admin Dashboard',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                  // Content Area - Shows different content based on selected item
                  Expanded(child: _buildContent()),
                ],
              ),
            ),
          ),
        ],
      ),
      // Mobile Sidebar Drawer
      drawer: isMobile
          ? Drawer(
              width: AdminUi.sidebarWidth,
              backgroundColor: AdminUi.primary,
              child: AdminSidebar(
                activeItem: _activeItem,
                onItemSelected: _handleItemSelected,
                onLogout: _handleLogout,
              ),
            )
          : null,
    );
  }
}

class _SectionGlyph extends StatelessWidget {
  const _SectionGlyph({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}
