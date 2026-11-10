import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
import '../../services/hearing_calendar_fields.dart';
import '../../screens/admin/case_oversight_screen.dart';
import '../../screens/admin/archive_storage_screen.dart';
import '../../screens/admin/backup_settings_screen.dart';
import '../../screens/admin/system_logs_screen.dart';
import '../../screens/admin/reports_analytics_screen.dart';
import '../../screens/admin/system_settings_screen.dart';
import '../../routes/portal_navigation.dart';
import '../../utils/quiet_console.dart';

class AdminDashboard extends StatefulWidget {
  final bool inline;
  final ValueChanged<String>? onNavigateToItem;

  const AdminDashboard({
    super.key,
    this.inline = false,
    this.onNavigateToItem,
  });

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

  DateTime _calendarSelectedDate = DateTime.now();
  DateTime _calendarCurrentMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  Map<DateTime, List<Map<String, dynamic>>> _calendarHearingsByDay = {};
  int _calendarHearingsCount = 0;

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

  /// Each section loads independently so one failing query (permission
  /// denied on `system_logs`, unsupported `count()` aggregation on desktop,
  /// missing index, ...) no longer wipes every stat card back to 0.
  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    final results = await Future.wait<Object?>([
      _loadUserStats(),
      _loadCaseStats(),
      _loadRecentLogs(),
      _loadSystemAlerts(),
      _loadHearingsByDay(),
    ]);
    if (!mounted) return;

    final userStats = results[0] as Map<String, int>?;
    final caseStats = results[1] as Map<String, int>?;
    final logsSnapshot = results[2] as QuerySnapshot<Map<String, dynamic>>?;
    final alerts = results[3] as List<Map<String, dynamic>>;
    final hearings =
        results[4] as (Map<DateTime, List<Map<String, dynamic>>>, int)?;

    final recentActivity = (logsSnapshot?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
        .take(5)
        .map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            'id': doc.id,
            'action': data['action'] ?? 'Unknown',
            'userName': data['userName'] ?? 'Unknown',
            'timestamp': data['timestamp'],
            'details': data['details'],
          };
        })
        .toList();

    final searchIndex = await _loadSearchIndex(logsSnapshot);
    if (!mounted) return;

    setState(() {
      _stats = {
        ..._stats,
        if (userStats != null) ...userStats,
        if (caseStats != null) ...caseStats,
      };
      _recentActivity = recentActivity;
      _systemAlerts = alerts;
      _searchUsers = searchIndex.users;
      _searchCases = searchIndex.cases;
      _searchLogs = searchIndex.logs;
      if (hearings != null) {
        _calendarHearingsByDay = hearings.$1;
        _calendarHearingsCount = hearings.$2;
      }
    });
  }

  static String _norm(Object? raw) =>
      (raw ?? '').toString().trim().toLowerCase();

  /// User counts: fast `count()` aggregation first, then a full read fallback
  /// (also tolerant of role casing like `Client` / `Attorney`).
  Future<Map<String, int>?> _loadUserStats() async {
    final users = _firestore.collection('users');
    try {
      final r = await Future.wait([
        users.count().get(),
        users.where('role', whereIn: ['client', 'Client']).count().get(),
        users.where('role', whereIn: ['attorney', 'Attorney']).count().get(),
        users.where('role', whereIn: ['staff', 'Staff']).count().get(),
      ]);
      final total = r[0].count ?? 0;
      if (total > 0) {
        return {
          'totalUsers': total,
          'totalClients': r[1].count ?? 0,
          'attorneys': r[2].count ?? 0,
          'staff': r[3].count ?? 0,
        };
      }
    } catch (e) {
      appLog('Admin dashboard: user count() failed, falling back: $e');
    }
    try {
      final snap = await users.get();
      var clients = 0, attorneys = 0, staff = 0;
      for (final doc in snap.docs) {
        switch (_norm(doc.data()['role'])) {
          case 'client':
            clients++;
          case 'attorney':
          case 'lawyer':
            attorneys++;
          case 'staff':
          case 'paralegal':
          case 'legal_assistant':
            staff++;
        }
      }
      return {
        'totalUsers': snap.docs.length,
        'totalClients': clients,
        'attorneys': attorneys,
        'staff': staff,
      };
    } catch (e) {
      appLog('Admin dashboard: loading users failed: $e');
      return null;
    }
  }

  /// Case counts: read case docs (skips archived, same as Case Oversight);
  /// `count()` aggregation is the fallback.
  Future<Map<String, int>?> _loadCaseStats() async {
    final cases = _firestore.collection('cases');
    try {
      final snap = await cases.get();
      var total = 0, completed = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['isArchived'] == true) continue;
        total++;
        if (_norm(data['status']) == 'completed') completed++;
      }
      return {
        'totalCases': total,
        'completedCases': completed,
        'activeCases': total - completed,
      };
    } catch (e) {
      appLog('Admin dashboard: reading cases failed, trying count(): $e');
    }
    try {
      final r = await Future.wait([
        cases.count().get(),
        cases.where('status', isEqualTo: 'completed').count().get(),
      ]);
      final total = r[0].count ?? 0;
      final completed = r[1].count ?? 0;
      return {
        'totalCases': total,
        'completedCases': completed,
        'activeCases': (total - completed).clamp(0, total),
      };
    } catch (e) {
      appLog('Admin dashboard: case count() failed: $e');
      return null;
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>?> _loadRecentLogs() async {
    final logs = _firestore.collection('system_logs');
    try {
      return await logs.orderBy('timestamp', descending: true).limit(30).get();
    } catch (_) {}
    try {
      return await logs.limit(30).get();
    } catch (e) {
      appLog('Admin dashboard: system_logs unavailable: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _loadSystemAlerts() async {
    final alerts = <Map<String, dynamic>>[];
    try {
      final settingsDoc = await _firestore
          .collection('system_settings')
          .doc('maintenance')
          .get();
      final notify = await SystemSettingsService.instance.load();
      if (notify.systemAlerts &&
          settingsDoc.exists &&
          settingsDoc.data()?['maintenanceMode'] == true) {
        alerts.add({
          'type': 'warning',
          'title': 'Maintenance Mode Active',
          'message': 'System is currently in maintenance mode',
          'icon': Icons.build,
        });
      }
    } catch (e) {
      appLog('Admin dashboard: system alerts unavailable: $e');
    }
    return alerts;
  }

  Future<(Map<DateTime, List<Map<String, dynamic>>>, int)?>
      _loadHearingsByDay() async {
    QuerySnapshot<Map<String, dynamic>> hearingsSnapshot;
    try {
      try {
        hearingsSnapshot = await _firestore
            .collection('hearings')
            .orderBy('createdAt', descending: true)
            .limit(100)
            .get();
      } catch (_) {
        hearingsSnapshot =
            await _firestore.collection('hearings').limit(100).get();
      }
    } catch (e) {
      appLog('Admin dashboard: hearings unavailable: $e');
      return null;
    }

    final hearingsByDay = <DateTime, List<Map<String, dynamic>>>{};
    for (final doc in hearingsSnapshot.docs) {
      final data = doc.data();
      DateTime? dt;
      Map<String, dynamic> e = data;
      try {
        e = HearingCalendarFields.enrichForAlerts(data);
      } catch (_) {}
      try {
        dt = HearingCalendarFields.resolveEventDate(e) ??
            HearingCalendarFields.resolveEventDateFromHearingDateField(e);
      } catch (_) {}
      if (dt == null) {
        final rawDt =
            data['hearingDateTime'] ?? data['eventDate'] ?? data['scheduledDate'];
        if (rawDt is Timestamp) {
          dt = rawDt.toDate();
        } else if (rawDt is DateTime) {
          dt = rawDt;
        } else if (data['createdAt'] is Timestamp) {
          dt = (data['createdAt'] as Timestamp).toDate();
        }
      }

      if (dt != null) {
        String pick(List<String> keys) {
          for (final k in keys) {
            final v = _safeText(HearingCalendarFields.asDisplayString(e[k]));
            if (v.isNotEmpty) return v;
          }
          return '';
        }

        var caseNo = pick(['caseNo', 'caseNumber', 'docketNo']);
        try {
          caseNo = HearingCalendarFields.cleanCaseDocketNo(caseNo);
        } catch (_) {}
        if (HearingCalendarFields.isPlaceholderCaseNo(caseNo)) caseNo = '';
        final caseTitle = pick(['caseTitle', 'title', 'clientName']);
        var venue = '';
        try {
          venue = _safeText(HearingCalendarFields.resolveVenueForDisplay(e));
        } catch (_) {}
        if (venue.isEmpty) venue = pick(['courtBranch', 'location', 'venue']);
        final timeText = pick(['hearingTime']);

        final dayKey = DateTime(dt.year, dt.month, dt.day);
        hearingsByDay.putIfAbsent(dayKey, () => []).add({
          'id': doc.id,
          'caseId': data['caseId']?.toString() ?? '',
          'caseNo': caseNo,
          'caseTitle': caseTitle,
          'courtBranch': venue,
          'time': timeText.isNotEmpty ? timeText : DateFormat('h:mm a').format(dt),
          'dateTime': dt,
          'message': data['message'] ?? data['remarks'] ?? '',
        });
      }
    }
    for (final list in hearingsByDay.values) {
      list.sort((a, b) =>
          (a['dateTime'] as DateTime).compareTo(b['dateTime'] as DateTime));
    }
    return (hearingsByDay, hearingsSnapshot.docs.length);
  }

  /// Agenda headline: docket no. → case title → generic label (never blank).
  String _hearingHeadline(Map<String, dynamic> h) {
    final no = _safeText(h['caseNo']);
    if (no.isNotEmpty) return no;
    final title = _safeText(h['caseTitle']);
    if (title.isNotEmpty) return title;
    return 'Court hearing';
  }

  /// Case title shown under the docket no. (only when the headline is the no.).
  String _hearingSubtitleTitle(Map<String, dynamic> h) {
    if (_safeText(h['caseNo']).isEmpty) return '';
    return _safeText(h['caseTitle']);
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
    QuerySnapshot<Map<String, dynamic>>? logsSnapshot,
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

    final logs = (logsSnapshot?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
        .map((doc) {
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
    if (widget.inline && widget.onNavigateToItem != null) {
      widget.onNavigateToItem!('admin_users');
      return;
    }
    setState(() {
      _activeItem = 'users';
      _userManagementRoleFilter = role;
      _userManagementSearch = search?.trim() ?? '';
    });
    _closeMobileDrawerIfNeeded();
  }

  void _openCasesFiltered(String status) {
    if (widget.inline && widget.onNavigateToItem != null) {
      widget.onNavigateToItem!('admin_cases');
      return;
    }
    setState(() {
      _activeItem = 'cases';
      _caseOversightStatusFilter = status;
    });
    _closeMobileDrawerIfNeeded();
  }

  void _handleItemSelected(String item) {
    if (widget.inline && widget.onNavigateToItem != null) {
      switch (item) {
        case 'users':
          widget.onNavigateToItem!('admin_users');
          return;
        case 'cases':
          widget.onNavigateToItem!('admin_cases');
          return;
        case 'logs':
          widget.onNavigateToItem!('admin_logs');
          return;
        case 'reports':
          widget.onNavigateToItem!('admin_analytics');
          return;
        case 'settings':
          widget.onNavigateToItem!('admin_settings');
          return;
        default:
          widget.onNavigateToItem!(item);
          return;
      }
    }
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
              if (screenWidth > 1050) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: 3x2 stats grid + Recent Activity
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GridView(
                            clipBehavior: Clip.none,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              mainAxisExtent: 88,
                            ),
                            children: [
                              _buildCardTotalUsers(),
                              _buildCardTotalClients(),
                              _buildCardAttorneys(),
                              _buildCardTotalCases(),
                              _buildCardActiveCases(),
                              _buildCardCompletedCases(),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildRecentActivity(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Right Column: Staff card at top, Calendar directly underneath, System Alerts below
                    SizedBox(
                      width: 350,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildCardStaff(),
                          const SizedBox(height: 10),
                          _buildAdminCalendar(),
                          const SizedBox(height: 16),
                          _buildSystemAlerts(),
                        ],
                      ),
                    ),
                  ],
                );
              }

              // Tablet and Mobile layout
              final crossAxisCount = screenWidth > 650 ? 2 : 1;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GridView(
                    clipBehavior: Clip.none,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      mainAxisExtent: 84,
                    ),
                    children: [
                      _buildCardTotalUsers(),
                      _buildCardTotalClients(),
                      _buildCardAttorneys(),
                      _buildCardStaff(),
                      _buildCardTotalCases(),
                      _buildCardActiveCases(),
                      _buildCardCompletedCases(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildAdminCalendar(),
                  const SizedBox(height: 16),
                  _buildRecentActivity(),
                  const SizedBox(height: 16),
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

  Widget _buildCardTotalUsers() => DashboardCard(
        title: 'Total Users',
        value: '${_stats['totalUsers'] ?? 0}',
        subtitle: 'All registered users',
        icon: Icons.people_outlined,
        iconColor: const Color(0xFF2C5282),
        pastel: const Color(0xFFD6E6F8),
        onTap: () => _openUsersFiltered('all'),
      );

  Widget _buildCardTotalClients() => DashboardCard(
        title: 'Total Clients',
        value: '${_stats['totalClients'] ?? 0}',
        subtitle: 'Active clients',
        icon: Icons.person_outline,
        iconColor: const Color(0xFF2F7A4F),
        pastel: const Color(0xFFD8F0DC),
        onTap: () => _openUsersFiltered('client'),
      );

  Widget _buildCardAttorneys() => DashboardCard(
        title: 'Attorneys',
        value: '${_stats['attorneys'] ?? 0}',
        subtitle: 'Registered attorneys',
        icon: Icons.badge_outlined,
        iconColor: const Color(0xFFE56A1A),
        pastel: const Color(0xFFFFE8D6),
        onTap: () => _openUsersFiltered('attorney'),
      );

  Widget _buildCardStaff() => DashboardCard(
        title: 'Staff',
        value: '${_stats['staff'] ?? 0}',
        subtitle: 'Registered staff',
        icon: Icons.support_agent,
        iconColor: const Color(0xFF5A5478),
        pastel: const Color(0xFFE6E0F6),
        onTap: () => _openUsersFiltered('staff'),
      );

  Widget _buildCardTotalCases() => DashboardCard(
        title: 'Total Cases',
        value: '${_stats['totalCases'] ?? 0}',
        subtitle: 'Firm caseload',
        icon: Icons.folder_outlined,
        iconColor: const Color(0xFFB42318),
        pastel: const Color(0xFFFFE4E1),
        onTap: () => _openCasesFiltered('all'),
      );

  Widget _buildCardActiveCases() => DashboardCard(
        title: 'Active Cases',
        value: '${_stats['activeCases'] ?? 0}',
        subtitle: 'Ongoing & open',
        icon: Icons.work_outline,
        iconColor: const Color(0xFF1D4E89),
        pastel: const Color(0xFFD6E6F8),
        onTap: () => _openCasesFiltered('active'),
      );

  Widget _buildCardCompletedCases() => DashboardCard(
        title: 'Completed Cases',
        value: '${_stats['completedCases'] ?? 0}',
        subtitle: 'Closed & resolved',
        icon: Icons.task_alt_rounded,
        iconColor: const Color(0xFF2F7A4F),
        pastel: const Color(0xFFD8F0DC),
        onTap: () => _openCasesFiltered('completed'),
      );

  Widget _buildAdminCalendar() {
    final now = DateTime.now();
    final isViewingCurrentMonthAndSelectedToday =
        _calendarCurrentMonth.year == now.year &&
            _calendarCurrentMonth.month == now.month &&
            _calendarSelectedDate.year == now.year &&
            _calendarSelectedDate.month == now.month &&
            _calendarSelectedDate.day == now.day;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AdminUi.card,
        borderRadius: BorderRadius.circular(AdminUi.radius),
        boxShadow: AdminUi.cardShadow,
        border: Border.all(color: AdminUi.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Month Year with chevron + Navigation buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => _showMonthYearPicker(context),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('MMMM yyyy').format(_calendarCurrentMonth),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AdminUi.text,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: Color(0xFF64748B),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isViewingCurrentMonthAndSelectedToday) ...[
                    InkWell(
                      onTap: () {
                        setState(() {
                          final current = DateTime.now();
                          _calendarCurrentMonth =
                              DateTime(current.year, current.month, 1);
                          _calendarSelectedDate = current;
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Today',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ),
                  ],
                  IconButton(
                    tooltip: 'Previous month',
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      size: 20,
                      color: Color(0xFF64748B),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      setState(() {
                        _calendarCurrentMonth = DateTime(
                          _calendarCurrentMonth.year,
                          _calendarCurrentMonth.month - 1,
                          1,
                        );
                      });
                    },
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    icon: const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: Color(0xFF64748B),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      setState(() {
                        _calendarCurrentMonth = DateTime(
                          _calendarCurrentMonth.year,
                          _calendarCurrentMonth.month + 1,
                          1,
                        );
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          // Subtle hairline separator matching design mockup
          Container(
            height: 1,
            color: AdminUi.line.withOpacity(0.7),
            margin: const EdgeInsets.symmetric(vertical: 12),
          ),
          // Weekday row (SUN, MON, TUE, WED, THU, FRI, SAT)
          Row(
            children: const [
              'SUN',
              'MON',
              'TUE',
              'WED',
              'THU',
              'FRI',
              'SAT',
            ].map((d) {
              return Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          // Day grid rows
          ..._buildCalendarWeekRows(context),
          // Agenda & scheduled hearings preview
          _buildCalendarAgendaSection(),
        ],
      ),
    );
  }

  List<Widget> _buildCalendarWeekRows(BuildContext context) {
    final days = _computeDaysForMonth(_calendarCurrentMonth);
    final now = DateTime.now();
    final weekCount = days.length ~/ 7;
    return List.generate(weekCount, (weekIdx) {
      final weekDays = days.sublist(weekIdx * 7, (weekIdx + 1) * 7);
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: weekDays.map((day) {
            return Expanded(child: _buildDayCell(day, now));
          }).toList(),
        ),
      );
    });
  }

  List<DateTime> _computeDaysForMonth(DateTime monthDate) {
    final firstDay = DateTime(monthDate.year, monthDate.month, 1);
    final leading = firstDay.weekday % 7; // Sunday is 0
    final start = firstDay.subtract(Duration(days: leading));
    final days = <DateTime>[];
    for (int i = 0; i < 42; i++) {
      days.add(DateTime(start.year, start.month, start.day + i));
    }
    // If the 6th row (days 35 to 41) has no days in the current month, trim to 35 days
    if (days.length == 42 && days[35].month != monthDate.month) {
      return days.sublist(0, 35);
    }
    return days;
  }

  Widget _buildDayCell(DateTime day, DateTime now) {
    final isCurrentMonth = day.month == _calendarCurrentMonth.month;
    final isSelected = day.year == _calendarSelectedDate.year &&
        day.month == _calendarSelectedDate.month &&
        day.day == _calendarSelectedDate.day;
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    final dayKey = DateTime(day.year, day.month, day.day);
    final dayHearings = _calendarHearingsByDay[dayKey] ?? const [];
    final hasEvents = dayHearings.isNotEmpty;

    final dayText = day.day.toString().padLeft(2, '0');

    Color textColor;
    if (isSelected) {
      textColor = Colors.white;
    } else if (isToday) {
      textColor = const Color(0xFF2563EB);
    } else if (isCurrentMonth) {
      textColor = const Color(0xFF0F172A);
    } else {
      textColor = const Color(0xFF94A3B8); // Muted grey for other months
    }

    return InkWell(
      onTap: () {
        setState(() {
          _calendarSelectedDate = day;
          if (day.month != _calendarCurrentMonth.month) {
            _calendarCurrentMonth = DateTime(day.year, day.month, 1);
          }
        });
      },
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 38,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isSelected)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withOpacity(0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              )
            else if (isToday)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
                  color: const Color(0xFFEFF6FF),
                ),
              ),
            Text(
              dayText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected || isToday
                    ? FontWeight.w700
                    : isCurrentMonth
                        ? FontWeight.w600
                        : FontWeight.w400,
                color: textColor,
              ),
            ),
            if (hasEvents)
              Positioned(
                bottom: 2,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? Colors.white
                        : const Color(0xFFE56A1A), // Amber/orange dot for hearings
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarAgendaSection() {
    final dayKey = DateTime(
      _calendarSelectedDate.year,
      _calendarSelectedDate.month,
      _calendarSelectedDate.day,
    );
    final dayHearings = _calendarHearingsByDay[dayKey] ?? const [];

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 13,
                color: Color(0xFF2563EB),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  DateFormat('EEE, MMMM d, yyyy').format(_calendarSelectedDate),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AdminUi.text,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: dayHearings.isNotEmpty
                      ? const Color(0xFFFEF3C7)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  dayHearings.isNotEmpty
                      ? '${dayHearings.length} hearing${dayHearings.length == 1 ? '' : 's'}'
                      : 'No hearings',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: dayHearings.isNotEmpty
                        ? const Color(0xFFB45309)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          if (dayHearings.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...dayHearings.take(3).map((h) {
              return Container(
                margin: const EdgeInsets.only(top: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AdminUi.line),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE56A1A),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _hearingHeadline(h),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AdminUi.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_hearingSubtitleTitle(h).isNotEmpty)
                            Text(
                              _hearingSubtitleTitle(h),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AdminUi.text,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            [
                              _safeText(h['courtBranch']),
                              _safeText(h['time']),
                            ].where((s) => s.isNotEmpty).join(' • '),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AdminUi.muted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ] else ...[
            const SizedBox(height: 6),
            const Text(
              'No court hearings scheduled for this date.',
              style: TextStyle(
                fontSize: 11,
                color: AdminUi.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showMonthYearPicker(BuildContext context) async {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    int selectedYear = _calendarCurrentMonth.year;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AdminUi.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AdminUi.radius),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Month',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setDialogState(() => selectedYear--);
                        },
                      ),
                      Text(
                        '$selectedYear',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AdminUi.text,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setDialogState(() => selectedYear++);
                        },
                      ),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: 280,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(12, (index) {
                    final isCurrent =
                        _calendarCurrentMonth.month == (index + 1) &&
                            _calendarCurrentMonth.year == selectedYear;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() {
                          _calendarCurrentMonth =
                              DateTime(selectedYear, index + 1, 1);
                        });
                        Navigator.of(dialogCtx).pop();
                      },
                      child: Container(
                        width: 80,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? const Color(0xFF2563EB)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            months[index],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isCurrent ? Colors.white : AdminUi.text,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            );
          },
        );
      },
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
        AlertCard(
          title: 'All systems operational',
          description: 'No active maintenance or critical alerts right now.',
          timestamp: 'Live • Tap to view settings',
          icon: Icons.check_circle_outline,
          tone: AlertTone.success,
          onTap: () => _handleItemSelected('settings'),
        ),
      );
    } else {
      cards.addAll(_systemAlerts.map(_buildAlertItem));
    }

    final users = _stats['totalUsers'] as int? ?? 0;
    cards.add(
      AlertCard(
        title: 'Platform monitoring is live',
        description:
            'Tracking $users registered user${users == 1 ? '' : 's'} across the system.',
        timestamp: 'Live • Tap to manage users',
        icon: Icons.shield_outlined,
        tone: AlertTone.info,
        onTap: () => _openUsersFiltered('all'),
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
    final isMaintenance = title.toLowerCase().contains('maintenance') ||
        title.toLowerCase().contains('setting');

    return AlertCard(
      title: title,
      description: alert['message']?.toString() ?? '',
      timestamp: timestamp ?? (isMaintenance ? 'Active • Tap for settings' : 'Active'),
      icon: alert['icon'] as IconData? ?? Icons.warning_amber_rounded,
      tone: tone,
      onTap: () {
        if (isMaintenance) {
          _handleItemSelected('settings');
        } else {
          _handleItemSelected('logs');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inline) {
      return Container(
        color: AdminUi.background,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth > 1400
                ? 32.0
                : constraints.maxWidth > 1200
                ? 24.0
                : constraints.maxWidth > 768
                ? 20.0
                : 16.0;
            return _buildDashboardContent(horizontalPadding);
          },
        ),
      );
    }

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
