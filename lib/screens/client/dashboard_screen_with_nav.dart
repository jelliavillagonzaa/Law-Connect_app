import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/bottom_navigation_bar_5tabs.dart';
import '../../services/case_service.dart';
import '../../services/chat_service.dart';
import '../../services/profile_service.dart';
import '../../models/user_model.dart';
import 'profile_screen.dart';
import 'conversations_list_screen.dart';
import 'appointments_screen.dart';
import 'notifications_screen.dart';
import 'notary_portal_screen.dart';
import 'chat_screen.dart';
import 'cases_list_screen.dart';
import 'attorney_selection_screen.dart';
import '../../screens/client/send_request_screen.dart';
import '../../pages/client/client_landing_page.dart';
import '../../pages/admin/admin_dashboard.dart';
import '../../utils/safe_network_image.dart';
import '../../widgets/common/safe_network_avatar.dart';
import '../../pages/attorney/attorney_dashboard.dart';
import '../../pages/staff/staff_dashboard.dart';
import '../../services/auth_service.dart';
import '../../services/hearing_notification_fanout_service.dart';

class DashboardScreenWithNav extends StatefulWidget {
  const DashboardScreenWithNav({super.key});

  @override
  State<DashboardScreenWithNav> createState() => _DashboardScreenWithNavState();
}

class _DashboardScreenWithNavState extends State<DashboardScreenWithNav> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CaseService _caseService = CaseService();
  final ChatService _chatService = ChatService();
  final ProfileService _profileService = ProfileService();

  // Stream subscriptions to dispose properly
  StreamSubscription? _appointmentStreamSubscription;
  StreamSubscription? _unreadCountStreamSubscription;
  StreamSubscription? _caseCountStreamSubscription;
  StreamSubscription? _notificationCountStreamSubscription;
  StreamSubscription<User?>? _authStreamSubscription;
  Timer? _unreadCountRefreshTimer;

  int _currentIndex = 0;
  UserModel? _currentUser;
  String? _localImageBase64;
  int _caseCount = 0;
  int _appointmentCount = 0;
  int _unreadMessageCount = 0;
  int _unreadNotificationCount = 0; // Separate count for notifications
  bool _isLoading = true;

  // Color palette aligned with AppTheme
  static const Color primaryColor = AppTheme.royalBlue;
  static const Color goldColor = AppTheme.gold;
  static const Color backgroundColor = AppTheme.lightGray;

  @override
  void initState() {
    super.initState();

    // IMPORTANT: Set loading to false immediately so UI shows right away
    // Don't wait for Firestore data - use Firebase Auth data as fallback
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
    } else {
      // User is logged in - show UI immediately, load data in background
      setState(() => _isLoading = false);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadUserData();
        _loadCaseCount();
        _loadAppointmentCount();
        _loadUnreadCount();
        _loadNotificationCount();
        _loadLocalImage();
      });
    }

    _authStreamSubscription = FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) {
      if (!mounted) return;
      if (user == null) {
        Get.offAll(() => const ClientLandingPage());
      }
    });
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final email = user.email ?? '';
      await AuthService().syncStaffRoleFromStaffApplication(
        uid: user.uid,
        email: email,
      );
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && mounted) {
        final data = Map<String, dynamic>.from(userDoc.data()!);
        final storedRole = (data['role'] as String?)?.toLowerCase() ?? 'client';
        final portalRole = AuthService.resolvePortalRole(
          email.isNotEmpty ? email : (data['email'] as String? ?? ''),
          firestoreRole: storedRole,
        );

        await AuthService().repairPortalRoleIfNeeded(
          uid: user.uid,
          email: email.isNotEmpty ? email : (data['email'] as String? ?? ''),
          firestoreRole: storedRole,
        );

        if (portalRole != 'client' && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            switch (portalRole) {
              case 'admin':
                Get.offAll(() => const AdminDashboard());
                break;
              case 'attorney':
                Get.offAll(() => const AttorneyDashboard());
                break;
              case 'staff':
                Get.offAll(() => const StaffDashboard());
                break;
            }
          });
          return;
        }

        data['role'] = portalRole;
        setState(() {
          _currentUser = UserModel.fromFirestore(data, user.uid);
          _isLoading = false;
        });
        // Always try to load local image - it will check if needed
        // This ensures we have the image even if photoUrl isn't set yet
        _loadLocalImage();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadLocalImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    // Always try to load local image - same as ProfileCard does
    // This ensures dashboard shows the same profile picture as Profile screen
    try {
      final localImage = await _profileService.getLocalProfilePicture(user.uid);

      if (mounted) {
        setState(() {
          // Always update if we got a valid image - don't check photoUrl here
          // The image provider will decide whether to show it
          if (localImage != null && localImage.isNotEmpty) {
            _localImageBase64 = localImage;
            print(
              '✅ Local profile image loaded in dashboard: ${localImage.length} bytes',
            );
          } else {
            print('ℹ️ No local profile image found in dashboard');
            // Don't clear existing image - keep what we have
          }
        });
      }
    } catch (e, stackTrace) {
      print('❌ Error loading local profile image in dashboard: $e');
      print('Stack trace: $stackTrace');
      // Don't clear existing image on error - keep what we have
    }
  }

  Future<void> _loadCaseCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _caseCount = 0;
          });
        }
        return;
      }

      // Cancel previous subscription if exists
      await _caseCountStreamSubscription?.cancel();

      // Get case count from stream with proper subscription
      _caseCountStreamSubscription = _caseService
          .getCasesForUser(user.uid, 'client')
          .listen(
            (cases) {
              if (mounted) {
                setState(() {
                  _caseCount = cases.length;
                  print('Case count updated: $_caseCount'); // Debug log
                });
              }
            },
            onError: (error) {
              print('Error loading case count: $error');
              if (mounted) {
                setState(() {
                  _caseCount = 0;
                });
              }
            },
          );
    } catch (e) {
      print('Error in _loadCaseCount: $e');
      if (mounted) {
        setState(() {
          _caseCount = 0;
        });
      }
    }
  }

  Future<void> _loadAppointmentCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _appointmentCount = 0;
          });
        }
        return;
      }

      // Cancel previous subscription if exists
      await _appointmentStreamSubscription?.cancel();

      // Query all appointments for this client
      _appointmentStreamSubscription = _firestore
          .collection('appointments')
          .where('clientId', isEqualTo: user.uid)
          .snapshots()
          .listen(
            (snapshot) {
              if (mounted) {
                setState(() {
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);

                  // Count only today's appointments that are not completed
                  // This matches what the "Today" tab shows in appointments screen
                  _appointmentCount = snapshot.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>?;
                    if (data == null) return false;

                    final status = data['status'] as String?;
                    // Skip cancelled or completed appointments
                    if (status == 'cancelled' || status == 'completed') {
                      return false;
                    }

                    // Check if appointment is today
                    final appointmentDateTime = data['appointmentDateTime'];
                    if (appointmentDateTime == null) return false;

                    DateTime aptDate;
                    if (appointmentDateTime is DateTime) {
                      aptDate = appointmentDateTime;
                    } else if (appointmentDateTime is Timestamp) {
                      aptDate = appointmentDateTime.toDate();
                    } else {
                      return false;
                    }

                    final aptDateOnly = DateTime(
                      aptDate.year,
                      aptDate.month,
                      aptDate.day,
                    );

                    return aptDateOnly == today;
                  }).length;

                  print(
                    'Today\'s appointment count updated: $_appointmentCount',
                  ); // Debug log
                });
              }
            },
            onError: (error) {
              print('Error loading appointment count: $error');
              if (mounted) {
                setState(() {
                  _appointmentCount = 0;
                });
              }
            },
          );
    } catch (e) {
      print('Error in _loadAppointmentCount: $e');
      if (mounted) {
        setState(() {
          _appointmentCount = 0;
        });
      }
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _unreadCountStreamSubscription?.cancel();
      _unreadCountRefreshTimer?.cancel();
      _unreadCountRefreshTimer = null;

      var refreshInFlight = false;

      Future<void> refreshUnreadCount() async {
        if (refreshInFlight || !mounted) return;
        refreshInFlight = true;
        try {
          final count = await _chatService.getUnreadCount(user.uid);
          if (!mounted) return;
          if (count != _unreadMessageCount) {
            setState(() => _unreadMessageCount = count);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Error refreshing unread count: $e');
          if (mounted && _unreadMessageCount != 0) {
            setState(() => _unreadMessageCount = 0);
          }
        } finally {
          refreshInFlight = false;
        }
      }

      void scheduleUnreadRefresh() {
        _unreadCountRefreshTimer?.cancel();
        _unreadCountRefreshTimer = Timer(
          const Duration(milliseconds: 500),
          () => unawaited(refreshUnreadCount()),
        );
      }

      await refreshUnreadCount();

      _unreadCountStreamSubscription = _firestore
          .collection('messages')
          .where('participants', arrayContains: user.uid)
          .snapshots()
          .listen(
            (_) => scheduleUnreadRefresh(),
            onError: (error) {
              if (kDebugMode) {
                debugPrint('Error in unread count stream: $error');
              }
              if (mounted && _unreadMessageCount != 0) {
                setState(() => _unreadMessageCount = 0);
              }
            },
          );
    } catch (e) {
      if (kDebugMode) debugPrint('Error in _loadUnreadCount: $e');
      if (mounted && _unreadMessageCount != 0) {
        setState(() => _unreadMessageCount = 0);
      }
    }
  }

  Future<void> _loadNotificationCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _notificationCountStreamSubscription?.cancel();

      final fanout = HearingNotificationFanoutService.instance;
      fanout.attach();
      fanout.warmInbox(
        user.uid,
        includeGlobalHearingsFallback: false,
        hearingsOnly: true,
      );
      _notificationCountStreamSubscription = fanout
          .watchClientNotificationBadgeCount(user.uid)
          .listen(
            (count) {
              if (mounted) {
                setState(() => _unreadNotificationCount = count);
              }
            },
            onError: (error) {
              if (kDebugMode) {
                debugPrint('Client notification badge stream: $error');
              }
              if (mounted) setState(() => _unreadNotificationCount = 0);
            },
          );

      unawaited(() async {
        await fanout.purgeClientCourtEmailNotices(user.uid);
        await fanout.syncClientHearingNotifications(force: true);
        final count = await fanout.countClientNotificationBadge(user.uid);
        if (mounted) setState(() => _unreadNotificationCount = count);
      }());
    } catch (e) {
      if (kDebugMode) debugPrint('Error in _loadNotificationCount: $e');
      if (mounted) setState(() => _unreadNotificationCount = 0);
    }
  }

  @override
  void dispose() {
    _authStreamSubscription?.cancel();
    _caseCountStreamSubscription?.cancel();
    _appointmentStreamSubscription?.cancel();
    _unreadCountStreamSubscription?.cancel();
    _notificationCountStreamSubscription?.cancel();
    HearingNotificationFanoutService.instance.detach();
    _unreadCountRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _openMessageStaffForm() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Get or create chat with staff using email identifier
      // This will create a chat that staff can access via their email
      final chatId = await _chatService.getOrCreateChatByStaffEmail(
        clientId: user.uid,
        staffEmail: 'staff@gmail.com',
      );

      // Navigate directly to chat screen (message form)
      Get.to(
        () => ChatScreen(
          conversationId: chatId,
          otherUserId: 'staff@gmail.com', // Use email as identifier
          otherUserName: 'Staff',
        ),
      );
    } catch (e) {
      // On any error, navigate to Messages tab
      setState(() => _currentIndex = 3);
    }
  }

  Future<void> _refreshData() async {
    await Future.wait([
      _loadUserData(),
      _loadCaseCount(),
      _loadAppointmentCount(),
      _loadUnreadCount(),
      _loadNotificationCount(),
    ]);
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });

    // Refresh profile picture when returning to dashboard tab
    if (index == 0) {
      _loadUserData();
      // Also reload local image when returning to dashboard
      _loadLocalImage();

      // Refresh unread counts when returning to dashboard
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Refresh unread message count
        _chatService
            .getUnreadCount(user.uid)
            .then((count) {
              if (mounted) {
                setState(() {
                  _unreadMessageCount = count;
                });
              }
            })
            .catchError((e) {
              print('Error refreshing unread count: $e');
            });

        // Refresh notification count
        _loadNotificationCount();
      }
    }
  }

  Widget _buildHomeScreen() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return EmptyState(
        icon: Icons.person_off_outlined,
        title: 'Not Logged In',
        message: 'Please log in to access your dashboard',
        actionLabel: 'Go to Login',
        onAction: () {
          Get.offAll(() => const ClientLandingPage());
        },
      );
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refreshData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Header Card
              _buildUserHeaderCard(user),
              const SizedBox(height: 24),

              // Overview Section
              Text(
                'Overview',
                style: AppTheme.heading3.copyWith(
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildSummarySection(context),
              const SizedBox(height: 24),

              // Quick Actions Section
              Text(
                'Quick Actions',
                style: AppTheme.heading4.copyWith(
                  color: primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _buildQuickActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserHeaderCard(User user) {
    // Always show Firebase Auth data immediately - update when Firestore loads
    String displayName =
        _currentUser?.fullName ??
        _currentUser?.name ??
        user.displayName ??
        'Client';

    // If still default, try to create name from email
    if (displayName == 'Client' && user.email != null) {
      final emailName = user.email!.split('@')[0];
      final nameParts = emailName.replaceAll('.', ' ').split(' ');
      displayName = nameParts
          .map((word) {
            if (word.isEmpty) return '';
            return word[0].toUpperCase() +
                (word.length > 1 ? word.substring(1) : '');
          })
          .join(' ');
      if (displayName.isEmpty) displayName = emailName;
    }

    final displayEmail = _currentUser?.email ?? user.email ?? 'No email';
    final photoUrl = _currentUser?.photoUrl ?? user.photoURL;
    final isVerified = _currentUser?.isVerified ?? false;

    // Get first letter for avatar - always show something
    String firstLetter = 'U';
    if (displayName.isNotEmpty) {
      firstLetter = displayName.substring(0, 1).toUpperCase();
    } else if (user.email != null && user.email!.isNotEmpty) {
      firstLetter = user.email!.substring(0, 1).toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Photo - Always show initials immediately
          Builder(
            builder: (context) {
              final memoryProvider = _buildProfileImageProvider(photoUrl);
              if (memoryProvider != null) {
                return CircleAvatar(
                  radius: 32,
                  backgroundColor: primaryColor.withOpacity(0.1),
                  backgroundImage: memoryProvider,
                );
              }
              if (isValidNetworkImageUrl(photoUrl)) {
                return SafeNetworkAvatar(
                  photoUrl: photoUrl,
                  radius: 32,
                  fallbackLetter: firstLetter,
                  backgroundColor: primaryColor.withOpacity(0.1),
                  foregroundColor: primaryColor,
                );
              }
              return CircleAvatar(
                radius: 32,
                backgroundColor: primaryColor.withOpacity(0.1),
                child: Text(
                  firstLetter,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 16),

          // User Info + View Profile
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: AppTheme.heading4.copyWith(
                                    color: primaryColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isVerified)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.verified,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            displayEmail,
                            style: AppTheme.bodyMedium.copyWith(
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: goldColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: goldColor.withOpacity(0.4),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        (_currentUser?.role ?? 'client').toUpperCase(),
                        style: AppTheme.caption.copyWith(
                          color: goldColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _currentIndex = 4; // Profile tab
                        });
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'View Profile',
                        style: AppTheme.bodySmall.copyWith(
                          color: primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection(BuildContext context) {
    // Original design: 3 cards in a row
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.0,
      children: [
        _buildSummaryCard(
          icon: Icons.folder_copy_rounded,
          label: 'Active Cases',
          count: _caseCount,
          color: primaryColor,
          onTap: () {
            setState(() => _currentIndex = 1); // Navigate to Cases tab
          },
        ),
        _buildSummaryCard(
          icon: Icons.calendar_today_rounded,
          label: 'Appointments',
          count: _appointmentCount,
          color: goldColor,
          onTap: () {
            setState(() => _currentIndex = 2);
          },
        ),
        _buildSummaryCard(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Unread Messages',
          count: _unreadMessageCount,
          color: Colors.green,
          onTap: () {
            setState(() => _currentIndex = 3);
          },
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Row 1: Request Appointment + Contact Staff
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  // Step 1 of appointment flow: select attorney
                  Get.to(() => const AttorneySelectionScreen());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.calendar_today_rounded),
                label: const Text(
                  'Request Appointment',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  // Open message form to contact staff
                  await _openMessageStaffForm();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.mail_outline_rounded),
                label: const Text(
                  'Contact Staff',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Row 2: Send Request + Notary Portal
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Get.to(() => const SendRequestScreen());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                icon: const Icon(Icons.help_outline_rounded),
                label: const Text(
                  'Send Request',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  Get.to(() => const NotaryPortalScreen());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: primaryColor.withOpacity(0.15)),
                  ),
                  elevation: 1,
                ),
                icon: const Icon(Icons.gavel_outlined),
                label: const Text(
                  'Notary Portal',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black.withOpacity(0.05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2), width: 1),
          ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 12),
            Text(
              '$count',
              style: AppTheme.heading3.copyWith(
                color: primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTheme.bodySmall.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return _buildHomeScreen();
      case 1:
        return const CasesListScreen();
      case 2:
        return const AppointmentsScreen();
      case 3:
        return const ConversationsListScreen();
      case 4:
        return const ProfileScreen();
      default:
        return _buildHomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: EmptyState(
          icon: Icons.person_off_outlined,
          title: 'Not Logged In',
          message: 'Please log in to access your dashboard',
          actionLabel: 'Go to Login',
          onAction: () {
            Get.offAll(() => const ClientLandingPage());
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      // Only show AppBar for Home screen, other screens have their own
      appBar: _currentIndex == 0
          ? AppBar(
              backgroundColor: primaryColor,
              title: const Text('Dashboard'),
              actions: [
                IconButton(
                  icon: Stack(
                    children: [
                      const Icon(Icons.notifications_outlined),
                      if (_unreadNotificationCount > 0)
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
                              minWidth: 18,
                              minHeight: 18,
                            ),
                            child: Text(
                              _unreadNotificationCount > 99
                                  ? '99+'
                                  : _unreadNotificationCount > 9
                                  ? '9+'
                                  : '$_unreadNotificationCount',
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
                    Get.to(() => const NotificationsScreen());
                  },
                ),
              ],
            )
          : null,
      body: _buildCurrentScreen(),
      bottomNavigationBar: CustomBottomNavigationBar5Tabs(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }

  ImageProvider? _buildProfileImageProvider(String? photoUrl) {
    // Always check for local storage image first - if it exists, show it
    // This ensures dashboard shows the same profile picture as Profile screen
    if (_localImageBase64 != null && _localImageBase64!.isNotEmpty) {
      try {
        final decodedImage = base64Decode(_localImageBase64!);
        print('✅ Displaying local profile image in dashboard');
        return MemoryImage(decodedImage);
      } catch (e) {
        print('❌ Error decoding local image in dashboard: $e');
      }
    }

    // Return null — network photos use SafeNetworkAvatar in the header UI.
    return null;
  }
}
