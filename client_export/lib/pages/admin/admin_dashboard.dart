import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/admin/admin_sidebar.dart';
import '../../widgets/admin/admin_header.dart';
import '../../widgets/admin/stat_card.dart';
import '../../screens/admin/user_management_screen.dart';
import '../../screens/admin/case_oversight_screen.dart';
import '../../screens/admin/system_logs_screen.dart';
import '../../screens/admin/reports_analytics_screen.dart';
import '../../screens/admin/system_settings_screen.dart';
import '../../theme/app_theme.dart';
import '../splash_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _activeItem = 'dashboard';
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _recentActivity = [];
  List<Map<String, dynamic>> _systemAlerts = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      // Get all users count
      final usersSnapshot = await _firestore.collection('users').get();
      final totalUsers = usersSnapshot.docs.length;
      final clients = usersSnapshot.docs
          .where((u) => u.data()['role'] == 'client')
          .length;
      final attorneys = usersSnapshot.docs
          .where((u) => u.data()['role'] == 'attorney')
          .length;

      // Get all cases count
      final casesSnapshot = await _firestore.collection('cases').get();
      final totalCases = casesSnapshot.docs.length;
      final pendingCases = casesSnapshot.docs
          .where((c) => c.data()['status'] == 'pending')
          .length;
      final activeCases = casesSnapshot.docs
          .where(
            (c) =>
                c.data()['status'] == 'in_progress' ||
                c.data()['status'] == 'active',
          )
          .length;

      // Load recent activity (system logs)
      final logsSnapshot = await _firestore
          .collection('system_logs')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();

      final recentActivity = logsSnapshot.docs.map((doc) {
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
      if (settingsDoc.exists) {
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

      setState(() {
        _stats = {
          'totalUsers': totalUsers,
          'totalClients': clients,
          'attorneys': attorneys,
          'totalCases': totalCases,
          'pendingCases': pendingCases,
          'activeCases': activeCases,
        };
        _recentActivity = recentActivity;
        _systemAlerts = alerts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error loading dashboard data: $e');
    }
  }

  void _handleItemSelected(String item) {
    if (mounted) {
      setState(() {
        _activeItem = item;
      });

      // Close sidebar on mobile
      if (MediaQuery.of(context).size.width < 768) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      Get.offAll(() => const SplashScreen());
    } catch (e) {
      Get.offAll(() => const SplashScreen());
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

        return Container(
          constraints: constraints.maxWidth > 1600
              ? const BoxConstraints(maxWidth: 1600)
              : null,
          margin: constraints.maxWidth > 1600
              ? EdgeInsets.symmetric(
                  horizontal: (constraints.maxWidth - 1600) / 2,
                )
              : null,
          child: switch (_activeItem) {
            'users' => const UserManagementScreen(inline: true),
            'cases' => const CaseOversightScreen(inline: true),
            'logs' => const SystemLogsScreen(inline: true),
            'reports' => const ReportsAnalyticsScreen(inline: true),
            'settings' => const SystemSettingsScreen(inline: true),
            'dashboard' => _buildDashboardContent(horizontalPadding),
            _ => _buildDashboardContent(horizontalPadding),
          },
        );
      },
    );
  }

  Widget _buildDashboardContent([double horizontalPadding = 16.0]) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const AdminHeader(),

          const SizedBox(height: 24),

          // Stats Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = MediaQuery.of(context).size.width;
              final crossAxisCount = screenWidth > 1600
                  ? 6
                  : screenWidth > 1200
                  ? 4
                  : screenWidth > 800
                  ? 3
                  : screenWidth > 600
                  ? 2
                  : 1;

              return GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: screenWidth > 1600
                    ? 1.2
                    : screenWidth > 1200
                    ? 1.25
                    : 1.3,
                children: [
                  StatCard(
                    title: 'Total Users',
                    value: '${_stats['totalUsers'] ?? 0}',
                    description: 'All registered users',
                    icon: Icons.people_outlined,
                    iconColor: AppTheme.royalBlue,
                    backgroundColor: AppTheme.royalBlue.withOpacity(0.1),
                    percentageChange: '+12%',
                  ),
                  StatCard(
                    title: 'Total Clients',
                    value: '${_stats['totalClients'] ?? 0}',
                    description: 'Active clients',
                    icon: Icons.person_outline,
                    iconColor: const Color(0xFF2D7A4F),
                    backgroundColor: const Color(0xFF2D7A4F).withOpacity(0.1),
                    percentageChange: '+8%',
                  ),
                  StatCard(
                    title: 'Attorneys',
                    value: '${_stats['attorneys'] ?? 0}',
                    description: 'Registered attorneys',
                    icon: Icons.badge_outlined,
                    iconColor: const Color(0xFFB8860B),
                    backgroundColor: const Color(0xFFB8860B).withOpacity(0.1),
                  ),
                  StatCard(
                    title: 'Total Cases',
                    value: '${_stats['totalCases'] ?? 0}',
                    description: 'All cases',
                    icon: Icons.folder_outlined,
                    iconColor: AppTheme.deepNavy,
                    backgroundColor: AppTheme.deepNavy.withOpacity(0.1),
                    percentageChange: '+15%',
                  ),
                  StatCard(
                    title: 'Pending Cases',
                    value: '${_stats['pendingCases'] ?? 0}',
                    description: 'Awaiting review',
                    icon: Icons.pending_outlined,
                    iconColor: const Color(0xFFC55A3F),
                    backgroundColor: const Color(0xFFC55A3F).withOpacity(0.1),
                  ),
                  StatCard(
                    title: 'Active Cases',
                    value: '${_stats['activeCases'] ?? 0}',
                    description: 'In progress',
                    icon: Icons.work_outline,
                    iconColor: const Color(0xFF2E5C8A),
                    backgroundColor: const Color(0xFF2E5C8A).withOpacity(0.1),
                    percentageChange: '+5%',
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 32),

          // Bottom Section - Recent Activity and Alerts
          LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = MediaQuery.of(context).size.width;
              if (screenWidth > 900) {
                // Desktop: Side by side
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _buildRecentActivity()),
                    const SizedBox(width: 16),
                    Expanded(flex: 1, child: _buildSystemAlerts()),
                  ],
                );
              } else {
                // Mobile: Stacked
                return Column(
                  children: [
                    _buildRecentActivity(),
                    const SizedBox(height: 16),
                    _buildSystemAlerts(),
                  ],
                );
              }
            },
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: AppTheme.royalBlue, size: 24),
              const SizedBox(width: 12),
              Text(
                'Recent Activity',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1C1C1C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_recentActivity.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'No recent activity',
                  style: TextStyle(
                    fontSize: 14,
                    color: const Color(0xFF6D6D6D),
                  ),
                ),
              ),
            )
          else
            ..._recentActivity.map((activity) => _buildActivityItem(activity)),
        ],
      ),
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> activity) {
    final timestamp = activity['timestamp'] as Timestamp?;
    String timeAgo = 'Just now';
    if (timestamp != null) {
      final now = DateTime.now();
      final time = timestamp.toDate();
      final difference = now.difference(time);

      if (difference.inDays > 0) {
        timeAgo = '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        timeAgo = '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        timeAgo = '${difference.inMinutes}m ago';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.royalBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.info_outline,
              color: AppTheme.royalBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity['action']
                          ?.toString()
                          .replaceAll('_', ' ')
                          .toUpperCase() ??
                      'Unknown',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1C1C1C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${activity['userName'] ?? 'Unknown user'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF6D6D6D),
                  ),
                ),
                if (activity['details'] != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    activity['details'].toString(),
                    style: TextStyle(
                      fontSize: 11,
                      color: const Color(0xFF6D6D6D),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Text(
            timeAgo,
            style: TextStyle(fontSize: 11, color: const Color(0xFF6D6D6D)),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemAlerts() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_outlined,
                color: const Color(0xFFC55A3F),
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'System Alerts',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1C1C1C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_systemAlerts.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 48,
                      color: Colors.green.withOpacity(0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'All systems operational',
                      style: TextStyle(
                        fontSize: 14,
                        color: const Color(0xFF6D6D6D),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._systemAlerts.map((alert) => _buildAlertItem(alert)),
        ],
      ),
    );
  }

  Widget _buildAlertItem(Map<String, dynamic> alert) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: alert['type'] == 'warning'
            ? Colors.orange.withOpacity(0.1)
            : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: alert['type'] == 'warning'
              ? Colors.orange.withOpacity(0.3)
              : Colors.red.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            alert['icon'] ?? Icons.warning,
            color: alert['type'] == 'warning' ? Colors.orange : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert['title'] ?? 'Alert',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1C1C1C),
                  ),
                ),
                if (alert['message'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    alert['message'],
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF6D6D6D),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
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
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Builder(
                        builder: (BuildContext scaffoldContext) {
                          return Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.menu),
                                onPressed: () {
                                  Scaffold.of(scaffoldContext).openDrawer();
                                },
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Admin Dashboard',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1C1C1C),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                  // Content Area - Shows different content based on selected item
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(),
                      child: _buildContent(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      // Mobile Sidebar Drawer
      drawer: isMobile
          ? Drawer(
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
