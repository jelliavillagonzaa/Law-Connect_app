import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../services/staff_service.dart';
import '../../services/task_service.dart';
import '../../services/chat_service.dart';
import '../../services/staff_auth_service.dart';
import '../../models/staff_model.dart';
import '../../models/task_model.dart';
import '../../models/case_model.dart';
import '../../widgets/admin/stat_card.dart';
import '../../theme/app_theme.dart';
import '../../screens/staff/staff_cases_screen.dart';
import '../../screens/staff/staff_tasks_screen.dart';
import '../../screens/staff/staff_calendar_screen.dart';
import '../../screens/staff/staff_clients_screen.dart';
import '../../screens/staff/staff_communication_screen.dart';
import '../../screens/staff/staff_reports_screen.dart';
import '../../screens/staff/staff_notifications_screen.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../../screens/staff/staff_create_case_draft_screen.dart';
import '../../screens/client/chat_screen.dart';
import '../../pages/staff/staff_profile_page.dart';
import '../../widgets/common/profile_picture_widget.dart';
import '../auth/login_page.dart';

class StaffDashboard extends StatefulWidget {
  const StaffDashboard({super.key});

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  final StaffService _staffService = StaffService();
  final TaskService _taskService = TaskService();
  final ChatService _chatService = ChatService();
  final StaffAuthService _staffAuthService = StaffAuthService();

  StaffModel? _currentStaff;
  String? _assignedAttorneyId;
  String _activeItem = 'dashboard';
  int _selectedBottomNavIndex = 0;
  int _unreadCount = 0;
  bool _isLoading = true;

  Map<String, dynamic> _stats = {};
  List<TaskModel> _myTasks = [];
  List<CaseModel> _assignedCases = [];
  List<Map<String, dynamic>> _upcomingDeadlines = [];
  List<Map<String, dynamic>> _hearingNotifications = [];

  static int _safeInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUnreadCount();
    _loadDashboardData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      HearingNotificationFanoutService.instance.attach();
      HearingNotificationFanoutService.instance.warmInbox(user.uid);
      unawaited(
        HearingNotificationFanoutService.instance
            .syncStaffHearingNotifications(force: true),
      );
      unawaited(
        HearingNotificationFanoutService.instance.syncRecentHearingsForInbox(),
      );
    });
  }

  Future<void> _loadUserData() async {
    final staff = await _staffAuthService.getCurrentStaff();
    if (mounted && staff != null) {
      setState(() {
        _currentStaff = staff;
        _assignedAttorneyId = staff.assignedAttorneyId;
      });
    }
  }

  Future<void> _openChatWithAttorney() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Get.snackbar(
        'Error',
        'You must be logged in to send messages',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    if (_assignedAttorneyId == null || _assignedAttorneyId!.isEmpty) {
      Get.snackbar(
        'No Attorney Assigned',
        'You are not assigned to an attorney yet',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    try {
      // Get attorney info
      final attorneyDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_assignedAttorneyId!)
          .get();

      if (!attorneyDoc.exists) {
        Get.snackbar(
          'Error',
          'Attorney not found',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      final attorneyData = attorneyDoc.data()!;
      final attorneyName =
          attorneyData['fullName'] ?? attorneyData['name'] ?? 'Attorney';

      // Create or get chat with attorney
      final chatId = await _chatService.getOrCreateChat(
        user.uid,
        _assignedAttorneyId!,
      );

      // Navigate to chat
      Get.to(
        () => ChatScreen(
          conversationId: chatId,
          otherUserId: _assignedAttorneyId!,
          otherUserName: attorneyName,
        ),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to open chat: ${e.toString()}',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    }
  }

  Future<void> _loadUnreadCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      int totalCount = 0;

      // Count unread messages
      final messageCount = await _chatService.getUnreadCount(user.uid);
      totalCount += messageCount;

      // Count unread Firestore notifications (include missing isRead)
      final notificationsSnapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .get();
      totalCount += notificationsSnapshot.docs
          .where((d) => d.data()['isRead'] != true)
          .length;

      // Count pending tasks
      final tasks = await _taskService.getStaffTasks(user.uid).first;
      final pendingTasks = tasks.where((t) => t.status == 'pending').length;
      if (pendingTasks > 0)
        totalCount += 1; // Add 1 for pending tasks notification

      // Count upcoming deadlines (within 7 days)
      if (_assignedAttorneyId != null) {
        final now = DateTime.now();
        final sevenDaysLater = now.add(const Duration(days: 7));
        final deadlinesSnapshot = await FirebaseFirestore.instance
            .collection('calendar_events')
            .where('assignedTo', isEqualTo: _assignedAttorneyId)
            .where('eventDate', isGreaterThan: Timestamp.fromDate(now))
            .where('eventDate', isLessThan: Timestamp.fromDate(sevenDaysLater))
            .get();
        if (deadlinesSnapshot.docs.isNotEmpty)
          totalCount += 1; // Add 1 for upcoming deadlines
      }

      if (mounted) {
        setState(() => _unreadCount = totalCount);
      }
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Load tasks
      _taskService.getStaffTasks(user.uid).listen((tasks) {
        if (mounted) {
          setState(() {
            _myTasks = tasks;
            _updateStats();
          });
        }
      });

      // Load assigned cases (for quick access)
      _staffService.getAssignedCases(user.uid).listen((cases) {
        if (mounted) {
          setState(() {
            _assignedCases = cases;
            _updateStats();
          });
        }
      });

      // Also load all attorney cases for full view
      if (_assignedAttorneyId != null) {
        _staffService.getAttorneyCases(_assignedAttorneyId!).listen((allCases) {
          if (mounted) {
            // Update stats with all cases, not just assigned ones
            setState(() {
              _updateStats();
            });
          }
        });
      }

      // Load upcoming deadlines/calendar events
      if (_assignedAttorneyId != null) {
        _staffService.getCalendarEvents(_assignedAttorneyId!).listen((events) {
          if (mounted) {
            final now = DateTime.now();
            setState(() {
              _upcomingDeadlines = events
                  .where(
                    (e) =>
                        e['eventDate'] != null &&
                        (e['eventDate'] as DateTime).isAfter(now),
                  )
                  .take(5)
                  .toList();
              _updateStats();
            });
          }
        });

        // Load hearing notifications (2 days before)
        _staffService
            .getUpcomingHearingNotifications(_assignedAttorneyId!)
            .listen((notifications) {
              if (mounted) {
                setState(() {
                  _hearingNotifications = notifications;
                });
              }
            });
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _updateStats() {
    final totalTasks = _myTasks.length;
    final pendingTasks = _myTasks.where((t) => t.status == 'pending').length;
    final inProgressTasks = _myTasks
        .where((t) => t.status == 'in_progress')
        .length;
    final completedTasks = _myTasks
        .where((t) => t.status == 'completed')
        .length;
    final activeCases = _assignedCases
        .where((c) => c.status == 'in_progress' || c.status == 'accepted')
        .length;
    final upcomingDeadlines = _upcomingDeadlines.length;

    setState(() {
      _stats = {
        'totalTasks': totalTasks,
        'pendingTasks': pendingTasks,
        'inProgressTasks': inProgressTasks,
        'completedTasks': completedTasks,
        'activeCases': activeCases,
        'upcomingDeadlines': upcomingDeadlines,
      };
    });
  }

  void _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Get.offAll(() => const LoginPage());
      }
    }
  }

  /// Bell in AppBar: unread count from Firestore `notifications` (matches notification inbox).
  Widget _buildNotificationBellIconButton() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return IconButton(
        icon: const Icon(Icons.notifications_active),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const StaffNotificationsScreen(),
            ),
          );
        },
        tooltip: 'Notifications',
      );
    }

    final badgeStream = HearingNotificationFanoutService.instance
        .watchStaffNotificationBadgeCount(user.uid)
        .map(_safeInt)
        .handleError((Object e, StackTrace st) {
          debugPrint('Error loading notification badge: $e');
        });

    return StreamBuilder(
      initialData: 0,
      stream: badgeStream,
      builder: (context, snapshot) {
        final unreadCount = _safeInt(snapshot.data ?? 0);
        final showBadge = unreadCount > 0;
        final labelText =
            unreadCount > 99 ? '99+' : unreadCount > 9 ? '9+' : '$unreadCount';

        return IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_active),
              if (showBadge)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      labelText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const StaffNotificationsScreen(),
              ),
            );
          },
          tooltip: showBadge
              ? 'Notifications ($unreadCount unread)'
              : 'Notifications',
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    if (!isDesktop) {
      return Scaffold(
        drawer: _buildMobileDrawer(),
        appBar: AppBar(
          title: const Text(''),
          automaticallyImplyLeading: false,
          actions: [
            _buildNotificationBellIconButton(),
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const StaffProfilePage(),
                  ),
                );
              },
              tooltip: 'Profile',
            ),
          ],
        ),
        body: _buildContent(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const StaffCreateCaseDraftScreen(),
              ),
            ).then((created) {
              if (created == true) {
                _loadDashboardData(); // Refresh dashboard
                // Reset to dashboard view after successful creation
                if (mounted) {
                  setState(() {
                    _selectedBottomNavIndex = 0;
                    _activeItem = 'dashboard';
                  });
                }
              }
            });
          },
          backgroundColor: AppTheme.royalBlue,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.edit_document),
          label: const Text('Create Draft'),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedBottomNavIndex,
          onTap: (index) {
            if (index == 2) {
              // Navigate to create draft screen instead of showing it directly
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StaffCreateCaseDraftScreen(),
                ),
              ).then((created) {
                if (created == true) {
                  _loadDashboardData(); // Refresh dashboard
                  if (mounted) {
                    setState(() {
                      _selectedBottomNavIndex = 0; // Return to dashboard
                    });
                  }
                } else if (mounted) {
                  // Keep current index if cancelled
                  setState(() {
                    _selectedBottomNavIndex = _selectedBottomNavIndex;
                  });
                }
              });
            } else {
              setState(() => _selectedBottomNavIndex = index);
            }
          },
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Cases'),
            BottomNavigationBarItem(
              icon: Icon(Icons.edit_document),
              label: 'Draft',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.task), label: 'Tasks'),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today),
              label: 'Calendar',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.message),
              label: 'Messages',
            ),
          ],
        ),
      );
    } else {
      return Scaffold(
        appBar: AppBar(
          title: const Text(''),
          automaticallyImplyLeading: false,
          actions: [
            _buildNotificationBellIconButton(),
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const StaffProfilePage(),
                  ),
                );
              },
              tooltip: 'Profile',
            ),
          ],
        ),
        body: Row(
          children: [
            _buildSidebar(),
            Expanded(child: _buildContent()),
          ],
        ),
      );
    }
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      color: AppTheme.deepNavy,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                ProfilePictureWidget(
                  photoUrl: _currentStaff?.photoUrl,
                  userName: _currentStaff?.name ?? 'Staff',
                  size: 60,
                  isEditable: false,
                  onUpdated: () {
                    // Reload staff data when profile picture is updated
                    _loadUserData();
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  _currentStaff?.name ?? 'Staff Member',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.cleanWhite,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  'Paralegal / Legal Assistant',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.cleanWhite.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: ListView(
              children: [
                _buildSidebarItem('dashboard', 'Dashboard', Icons.dashboard),
                _buildSidebarItem('cases', 'Cases', Icons.folder),
                _buildSidebarItem(
                  'draft_cases',
                  'Create Draft Case',
                  Icons.edit_document,
                ),
                _buildSidebarItem('tasks', 'Tasks', Icons.task),
                _buildSidebarItem('clients', 'Clients', Icons.people),
                _buildSidebarItem('calendar', 'Calendar', Icons.calendar_today),
                _buildSidebarItem(
                  'communication',
                  'Messages',
                  Icons.message,
                  badge: _unreadCount,
                ),
                _buildSidebarItem(
                  'reports',
                  'Reports & Logs',
                  Icons.assessment,
                ),
                _buildSidebarItem('profile', 'Profile', Icons.person),
              ],
              // Add Create Draft Case button at the bottom of sidebar
              // This will be added after the list
            ),
          ),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white70),
            title: Text('Logout', style: TextStyle(color: Colors.white70)),
            onTap: _handleLogout,
          ),
        ],
      ),
    );
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: AppTheme.royalBlue),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ProfilePictureWidget(
                  photoUrl: _currentStaff?.photoUrl,
                  userName: _currentStaff?.name ?? 'Staff',
                  size: 60,
                  isEditable: false,
                  onUpdated: () {
                    // Reload staff data when profile picture is updated
                    _loadUserData();
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  _currentStaff?.name ?? 'Staff Member',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.cleanWhite,
                  ),
                ),
                Text(
                  'Paralegal / Legal Assistant',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.cleanWhite.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 0);
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('Cases'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 1);
            },
          ),
          ListTile(
            leading: const Icon(Icons.task),
            title: const Text('Tasks'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 2);
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Calendar'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 3);
            },
          ),
          ListTile(
            leading: Stack(
              children: [
                const Icon(Icons.message),
                if (_unreadCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '${_unreadCount > 9 ? '9+' : _unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            title: const Text('Messages'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedBottomNavIndex = 4);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profile'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StaffProfilePage(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () {
              Navigator.pop(context);
              _handleLogout();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(
    String item,
    String label,
    IconData icon, {
    int badge = 0,
  }) {
    final isActive = _activeItem == item;
    return ListTile(
      leading: Stack(
        children: [
          Icon(icon, color: isActive ? AppTheme.gold : Colors.white70),
          if (badge > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  '${badge > 9 ? '9+' : badge}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isActive ? AppTheme.gold : Colors.white70,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isActive,
      selectedTileColor: Colors.white.withOpacity(0.1),
      onTap: () {
        if (item == 'draft_cases') {
          // Navigate to create draft case screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const StaffCreateCaseDraftScreen(),
            ),
          ).then((created) {
            if (created == true) {
              _loadDashboardData(); // Refresh dashboard
              // Reset to dashboard view after successful creation
              if (mounted) {
                setState(() {
                  _selectedBottomNavIndex = 0;
                  _activeItem = 'dashboard';
                });
              }
            }
          });
        } else {
          setState(() => _activeItem = item);
        }
      },
    );
  }

  Widget _buildContent() {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    if (!isDesktop) {
      // Mobile: Show based on bottom nav index
      switch (_selectedBottomNavIndex) {
        case 0:
          return _buildDashboardView();
        case 1:
          return const StaffCasesScreen();
        case 2:
          // Don't show create screen directly in bottom nav
          // It should only be accessed via navigation (FAB or menu item)
          // Return to dashboard if somehow index 2 is selected
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _selectedBottomNavIndex = 0;
              });
            }
          });
          return _buildDashboardView();
        case 3:
          return const StaffTasksScreen();
        case 4:
          return const StaffCalendarScreen();
        case 5:
          return const StaffCommunicationScreen();
        default:
          return _buildDashboardView();
      }
    } else {
      // Desktop: Show based on active item
      switch (_activeItem) {
        case 'cases':
          return const StaffCasesScreen();
        case 'draft_cases':
          return const StaffCreateCaseDraftScreen();
        case 'tasks':
          return const StaffTasksScreen();
        case 'clients':
          return const StaffClientsScreen();
        case 'calendar':
          return const StaffCalendarScreen();
        case 'communication':
          return const StaffCommunicationScreen();
        case 'reports':
          return const StaffReportsScreen();
        case 'profile':
          return const StaffProfilePage();
        default:
          return _buildDashboardView();
      }
    }
  }

  Widget _buildDashboardView() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isDesktop = MediaQuery.of(context).size.width >= 800;
    final crossAxisCount = isDesktop ? 4 : 2;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dark Blue Header Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.deepNavy,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${_currentStaff?.name ?? 'Staff'}!',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.cleanWhite,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Here\'s your overview for today',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.cleanWhite.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          // Content Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // Hearing Notifications (2 days before)
                if (_hearingNotifications.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.notifications_active,
                              color: Colors.blue.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Hearing Reminders',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._hearingNotifications.map((notification) {
                          final hearingDate =
                              notification['hearingDate'] as DateTime?;
                          final daysUntil = hearingDate != null
                              ? hearingDate.difference(DateTime.now()).inDays
                              : 0;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: Colors.white,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue.shade100,
                                child: Icon(
                                  Icons.gavel,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              title: Text(
                                notification['title'] ?? 'Hearing',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (hearingDate != null)
                                    Text(
                                      'Hearing Date: ${DateFormat('EEEE, MMMM dd, yyyy • hh:mm a').format(hearingDate)}',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: daysUntil <= 2
                                          ? Colors.orange.shade100
                                          : Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      daysUntil == 0
                                          ? 'Today!'
                                          : daysUntil == 1
                                          ? 'Tomorrow'
                                          : '$daysUntil days remaining',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: daysUntil <= 2
                                            ? Colors.orange.shade900
                                            : Colors.green.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Quick Actions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.royalBlue,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const StaffCreateCaseDraftScreen(),
                                  ),
                                ).then((created) {
                                  if (created == true) {
                                    _loadDashboardData(); // Refresh dashboard
                                  }
                                });
                              },
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('Create Draft Case'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.royalBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          if (_assignedAttorneyId != null) ...[
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: _openChatWithAttorney,
                              icon: const Icon(Icons.message),
                              label: const Text('Message Attorney'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.gold,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_upcomingDeadlines.isNotEmpty) ...[
                  Text(
                    'Upcoming Deadlines',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.royalBlue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._upcomingDeadlines.map(
                    (deadline) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          Icons.event,
                          color: _getDeadlineColor(
                            deadline['eventDate'] as DateTime,
                          ),
                        ),
                        title: Text(deadline['title'] ?? 'Event'),
                        subtitle: Text(
                          DateFormat(
                            'MMM dd, yyyy • hh:mm a',
                          ).format(deadline['eventDate'] as DateTime),
                        ),
                        trailing: Chip(
                          label: Text(deadline['eventType'] ?? 'event'),
                          backgroundColor: AppTheme.lightGray,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Stats Grid
                Text(
                  'Overview',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.royalBlue,
                  ),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.1,
                  children: [
                    StatCard(
                      title: 'Total Tasks',
                      value: '${_stats['totalTasks'] ?? 0}',
                      description: 'All assigned tasks',
                      icon: Icons.task_outlined,
                      iconColor: AppTheme.royalBlue,
                    ),
                    StatCard(
                      title: 'Pending Tasks',
                      value: '${_stats['pendingTasks'] ?? 0}',
                      description: 'Awaiting action',
                      icon: Icons.pending_outlined,
                      iconColor: const Color(0xFFF56565),
                    ),
                    StatCard(
                      title: 'In Progress',
                      value: '${_stats['inProgressTasks'] ?? 0}',
                      description: 'Currently working',
                      icon: Icons.work_outline,
                      iconColor: const Color(0xFF48BB78),
                    ),
                    StatCard(
                      title: 'Active Cases',
                      value: '${_stats['activeCases'] ?? 0}',
                      description: 'Assigned cases',
                      icon: Icons.folder_outlined,
                      iconColor: const Color(0xFF764BA2),
                    ),
                    StatCard(
                      title: 'Completed Tasks',
                      value: '${_stats['completedTasks'] ?? 0}',
                      description: 'Finished tasks',
                      icon: Icons.check_circle_outline,
                      iconColor: const Color(0xFFED8936),
                    ),
                    StatCard(
                      title: 'Upcoming Deadlines',
                      value: '${_stats['upcomingDeadlines'] ?? 0}',
                      description: 'Hearings & deadlines',
                      icon: Icons.event_outlined,
                      iconColor: const Color(0xFFF56565),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Active Cases Quick Access
                if (_assignedCases.isNotEmpty) ...[
                  Text(
                    'Active Cases',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.royalBlue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _assignedCases.take(5).length,
                      itemBuilder: (context, index) {
                        final caseModel = _assignedCases[index];
                        return Container(
                          width: 200,
                          margin: const EdgeInsets.only(right: 12),
                          child: Card(
                            child: InkWell(
                              onTap: () {
                                setState(() => _activeItem = 'cases');
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      caseModel.caseTitle,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Chip(
                                      label: Text(
                                        caseModel.status.toUpperCase(),
                                        style: TextStyle(fontSize: 10),
                                      ),
                                      backgroundColor: _getCaseStatusColor(
                                        caseModel.status,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Recent Tasks
                Text(
                  'Recent Tasks',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.royalBlue,
                  ),
                ),
                const SizedBox(height: 12),
                if (_myTasks.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.task_outlined,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No tasks assigned yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ..._myTasks
                      .take(5)
                      .map(
                        (task) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: _getTaskStatusIcon(task.status),
                            title: Text(task.title),
                            subtitle: Text(task.description),
                            trailing: Chip(
                              label: Text(
                                task.status.replaceAll('_', ' ').toUpperCase(),
                              ),
                              backgroundColor: _getTaskStatusColor(task.status),
                            ),
                            onTap: () {
                              Get.to(() => const StaffTasksScreen());
                            },
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getDeadlineColor(DateTime deadline) {
    final daysUntil = deadline.difference(DateTime.now()).inDays;
    if (daysUntil < 0) return Colors.red;
    if (daysUntil <= 1) return Colors.orange;
    if (daysUntil <= 3) return Colors.amber;
    return Colors.blue;
  }

  Widget _getTaskStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return const Icon(Icons.pending, color: Colors.orange);
      case 'in_progress':
        return const Icon(Icons.work, color: Colors.blue);
      case 'completed':
        return const Icon(Icons.check_circle, color: Colors.green);
      default:
        return const Icon(Icons.task, color: Colors.grey);
    }
  }

  Color _getTaskStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange.withOpacity(0.2);
      case 'in_progress':
        return Colors.blue.withOpacity(0.2);
      case 'completed':
        return Colors.green.withOpacity(0.2);
      default:
        return Colors.grey.withOpacity(0.2);
    }
  }

  Color _getCaseStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange.withOpacity(0.2);
      case 'accepted':
      case 'in_progress':
        return Colors.blue.withOpacity(0.2);
      case 'completed':
        return Colors.green.withOpacity(0.2);
      default:
        return Colors.grey.withOpacity(0.2);
    }
  }

  @override
  void dispose() {
    HearingNotificationFanoutService.instance.detach();
    super.dispose();
  }
}
