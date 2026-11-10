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
import '../../widgets/client/client_ui_theme.dart';
import '../../models/case_model.dart';
import '../../models/appointment_model.dart';
import '../../pages/case/case_detail_page.dart';
import 'package:intl/intl.dart';
import '../../services/chat_service.dart';
import '../../services/fcm_service.dart';
import '../../services/profile_service.dart';
import '../../models/user_model.dart';
import '../../routes/portal_navigation.dart';
import 'dashboard/client_dashboard_tabs.dart' as dashboard_tabs;
import 'dashboard/client_dashboard_nav.dart' as dashboard_nav;
import '../../utils/safe_network_image.dart';
import '../../utils/quiet_console.dart';
import '../../utils/screen_debug_probe.dart';
import '../../utils/case_status_filter.dart';
import '../../widgets/common/safe_network_avatar.dart';
import '../../widgets/common/brand_logo.dart';
import '../../widgets/common/instant_async.dart';
import '../../widgets/common/lazy_indexed_stack.dart';
import '../../widgets/client/client_notification_bell_button.dart';
import 'help_center_screen.dart';
import '../../services/auth_service.dart';
import '../../services/hearing_notification_fanout_service.dart';

class DashboardScreenWithNav extends StatefulWidget {
  const DashboardScreenWithNav({super.key});

  @override
  State<DashboardScreenWithNav> createState() => _DashboardScreenWithNavState();
}

class _DashboardScreenWithNavState extends State<DashboardScreenWithNav> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatService _chatService = ChatService();
  final ProfileService _profileService = ProfileService();

  // Stream subscriptions to dispose properly
  StreamSubscription? _appointmentStreamSubscription;
  StreamSubscription? _unreadCountStreamSubscription;
  StreamSubscription? _caseCountStreamSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _userProfileSubscription;
  final ScreenDebugProbe _probe = ScreenDebugProbe('client_dashboard');
  StreamSubscription<User?>? _authStreamSubscription;
  Timer? _unreadCountRefreshTimer;
  bool _redirectingToLanding = false;
  bool _fanoutAttached = false;

  int _currentIndex = 0;
  UserModel? _currentUser;
  String? _localImageBase64;
  int _caseCount = 0;
  int _appointmentCount = 0;
  int _unreadMessageCount = 0;
  List<CaseModel> _previewCases = const [];
  AppointmentModel? _nextAppointment;
  bool _isLoading = false;

  // Color palette aligned with AppTheme
  static const Color primaryColor = AppTheme.royalBlue;
  static const Color goldColor = AppTheme.gold;
  static const Color backgroundColor = AppTheme.lightGray;

  @override
  void initState() {
    super.initState();
    _probe.attach();
    _probe.event('initState');

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
        _probe.event('postFrame');
        _loadUserData();
        unawaited(_refreshSummaryCounts());
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          if (!mounted || _currentIndex != 0) return;
          unawaited(
            _refreshSummaryCounts().catchError((Object e, StackTrace st) {
              appLog('refreshSummaryCounts crashed: $e\n$st');
            }),
          );
        });
        final uid = user.uid;
        unawaited(FCMService().initialize().catchError((_) {}));
        unawaited(FCMService().saveTokenForUser(uid).catchError((_) {}));
        if (kIsWeb) {
          return;
        }
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          _probe.event('deferredLocalImage');
          unawaited(
            _loadLocalImage().catchError((Object e, StackTrace st) {
              appLog('loadLocalImage crashed: $e\n$st');
            }),
          );
        });
      });
    }

    _authStreamSubscription = FirebaseAuth.instance.authStateChanges().listen((
      user,
    ) {
      if (!mounted || _redirectingToLanding) return;
      if (user == null) {
        _redirectingToLanding = true;
        navigateAfterLogout();
      }
    });
  }

  Future<void> _loadUserData() => _probe.track('loadUserData', () async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final email = user.email ?? '';
      unawaited(
        AuthService().syncStaffRoleFromStaffApplication(
          uid: user.uid,
          email: email,
        ),
      );
      final userRef = _firestore.collection('users').doc(user.uid);
      DocumentSnapshot<Map<String, dynamic>> userDoc;
      try {
        userDoc = await userRef
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 1));
        if (!userDoc.exists) {
          userDoc = await userRef.get().timeout(const Duration(seconds: 1));
        }
      } catch (_) {
        userDoc = await userRef.get().timeout(const Duration(seconds: 1));
      }
      if (userDoc.exists && mounted) {
        final data = Map<String, dynamic>.from(userDoc.data()!);
        final storedRole = (data['role'] as String?)?.toLowerCase() ?? 'client';
        final portalRole = AuthService.resolvePortalRole(
          email.isNotEmpty ? email : (data['email'] as String? ?? ''),
          firestoreRole: storedRole,
        );

        unawaited(
          AuthService().repairPortalRoleIfNeeded(
            uid: user.uid,
            email: email.isNotEmpty ? email : (data['email'] as String? ?? ''),
            firestoreRole: storedRole,
          ),
        );

        if (portalRole != 'client' && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            switch (portalRole) {
              case 'admin':
                Get.offAllNamed('/AdminDashboard');
                break;
              case 'attorney':
                Get.offAllNamed('/AttorneyDashboard');
                break;
              case 'staff':
                Get.offAllNamed('/StaffDashboard');
                break;
            }
          });
          return;
        }

        data['role'] = portalRole;
        if (!_fanoutAttached) {
          _fanoutAttached = true;
          HearingNotificationFanoutService.instance.attach();
        }
        unawaited(
          HearingNotificationFanoutService.instance
              .syncClientHearingNotifications(),
        );
        setState(() {
          _currentUser = UserModel.fromFirestore(data, user.uid);
          _isLoading = false;
        });
        unawaited(_listenToUserProfile(user.uid));
        unawaited(_loadLocalImage());
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  });

  Future<void> _listenToUserProfile(String uid) async {
    await _userProfileSubscription?.cancel();
    _userProfileSubscription = _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      final data = doc.data();
      if (data == null) return;
      setState(() {
        _currentUser = UserModel.fromFirestore(data, uid);
      });
    });
  }

  Future<void> _loadLocalImage() => _probe.track('loadLocalImage', () async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      final localImage = await _profileService.getLocalProfilePicture(user.uid);

      if (mounted) {
        setState(() {
          if (localImage != null && localImage.isNotEmpty) {
            _localImageBase64 = localImage;
          }
        });
      }
    } catch (e, stackTrace) {
      appLog('Error loading local profile image in dashboard: $e\n$stackTrace');
    }
  });

  Future<void> _refreshSummaryCounts() => _probe.track('refreshSummaryCounts', () async {
    await _loadCaseCount();
    if (!mounted) return;
    await _loadAppointmentCount();
    if (!mounted) return;
    await _loadUnreadCount();
  });

  Future<void> _loadCaseCount() => _probe.track('loadCaseCount', () async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _caseCount = 0;
            _previewCases = const [];
          });
        }
        return;
      }

      await _caseCountStreamSubscription?.cancel();
      _caseCountStreamSubscription = null;

      try {
        final query = _firestore
            .collection('cases')
            .where('clientId', isEqualTo: user.uid)
            .limit(50);
        QuerySnapshot<Map<String, dynamic>> snapshot;
        try {
          snapshot = await query
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 2));
          if (snapshot.docs.isEmpty) {
            snapshot = await query.get().timeout(const Duration(seconds: 8));
          }
        } catch (_) {
          snapshot = await query.get().timeout(const Duration(seconds: 8));
        }
        if (!mounted) return;
        final visible = <CaseModel>[];
        for (final doc in snapshot.docs) {
          try {
            final c = CaseModel.fromFirestore(doc);
            if (CaseStatusFilter.visibleToClient(c)) visible.add(c);
          } catch (_) {}
        }
        visible.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        final active = visible
            .where((c) => !CaseStatusFilter.isCompleted(c.status))
            .toList();
        setState(() {
          _caseCount = active.isNotEmpty ? active.length : visible.length;
          _previewCases = (active.isNotEmpty ? active : visible).take(5).toList();
        });
      } catch (e) {
        appLog('Error in _loadCaseCount inner: $e');
      }
    } catch (e) {
      appLog('Error in _loadCaseCount: ${safeErrorString(e)}');
    }
  });

  Future<void> _loadAppointmentCount() => _probe.track('loadAppointmentCount', () async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _appointmentCount = 0;
            _nextAppointment = null;
          });
        }
        return;
      }

      // Cancel previous subscription if exists
      await _appointmentStreamSubscription?.cancel();
      _appointmentStreamSubscription = null;

      try {
        final query = _firestore
            .collection('appointments')
            .where('clientId', isEqualTo: user.uid)
            .limit(100);
        QuerySnapshot<Map<String, dynamic>> snapshot;
        try {
          snapshot = await query
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 2));
          if (snapshot.docs.isEmpty) {
            snapshot = await query.get().timeout(const Duration(seconds: 8));
          }
        } catch (_) {
          snapshot = await query.get().timeout(const Duration(seconds: 8));
        }
        if (!mounted) return;
        final now = DateTime.now();
        var upcomingCount = 0;
        AppointmentModel? next;
        for (final doc in snapshot.docs) {
          AppointmentModel apt;
          try {
            apt = AppointmentModel.fromFirestore(doc);
          } catch (_) {
            continue;
          }
          final status = apt.status.toLowerCase().trim();
          if (status == 'cancelled' || status == 'declined' || status == 'completed') {
            continue;
          }
          if (!apt.appointmentDateTime.isBefore(now)) {
            upcomingCount++;
            if (next == null ||
                apt.appointmentDateTime.isBefore(next.appointmentDateTime)) {
              next = apt;
            }
          }
        }
        setState(() {
          _appointmentCount = upcomingCount;
          _nextAppointment = next;
        });
      } catch (e) {
        appLog('Error in _loadAppointmentCount inner: $e');
      }
    } catch (e) {
      appLog('Error in _loadAppointmentCount: $e');
    }
  });

  Future<void> _loadUnreadCount() => _probe.track('loadUnreadCount', () async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _unreadCountStreamSubscription?.cancel();
      _unreadCountStreamSubscription = null;
      _unreadCountRefreshTimer?.cancel();
      _unreadCountRefreshTimer = null;

      try {
        final count = await _chatService
            .getUnreadCount(user.uid)
            .timeout(const Duration(seconds: 8));
        if (!mounted) return;
        if (count != _unreadMessageCount) {
          setState(() => _unreadMessageCount = count);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Error refreshing unread count: $e');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error in _loadUnreadCount: $e');
    }
  });


  @override
  void dispose() {
    _probe.event('dispose');
    _probe.detach();
    _authStreamSubscription?.cancel();
    _userProfileSubscription?.cancel();
    _caseCountStreamSubscription?.cancel();
    _appointmentStreamSubscription?.cancel();
    _unreadCountStreamSubscription?.cancel();
    _unreadCountRefreshTimer?.cancel();
    if (_fanoutAttached) {
      _fanoutAttached = false;
      HearingNotificationFanoutService.instance.detach();
    }
    super.dispose();
  }

  bool _openingCounselChat = false;

  Future<void> _openMessageStaffForm() async {
    if (_openingCounselChat) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _openingCounselChat = true);

    try {
      final result = await _chatService.getOrCreateClientOfficeChatWithCounterpart(user.uid);

      await dashboard_nav.openChat(
        conversationId: result.chatId,
        otherUserId: result.counterpart.id,
        otherUserName: result.counterpart.name,
        otherUserRole: result.counterpart.role,
      );
    } catch (e) {
      if (!mounted) return;
      Get.snackbar(
        'Messages',
        e.toString().replaceFirst('Exception: ', ''),
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      setState(() => _currentIndex = 3);
    } finally {
      if (mounted) {
        setState(() => _openingCounselChat = false);
      }
    }
  }

  Future<void> _refreshData() => _probe.track('pullToRefresh', () async {
    unawaited(
      HearingNotificationFanoutService.instance
          .syncClientHearingNotifications(force: true),
    );
    await _loadUserData();
    await _refreshSummaryCounts();
    if (!kIsWeb) {
      await _loadLocalImage();
    }
  });

  void _onTabTapped(int index) {
    _probe.event('tabTap', detail: 'index=$index');
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
    });
    if (index == 0) {
      unawaited(_refreshSummaryCounts());
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
          navigateAfterLogout();
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
              _buildUserHeaderCard(user),
              const SizedBox(height: 22),
              _buildSectionHeader(
                'Overview',
                onViewAll: () => setState(() => _currentIndex = 1),
              ),
              const SizedBox(height: 12),
              _buildSummarySection(context),
              const SizedBox(height: 22),
              _buildSectionHeader(
                'My Cases',
                onViewAll: () => setState(() => _currentIndex = 1),
              ),
              const SizedBox(height: 12),
              _buildMyCasesStrip(),
              if (_nextAppointment != null) ...[
                const SizedBox(height: 22),
                _buildUpcomingCallout(_nextAppointment!),
              ],
              const SizedBox(height: 22),
              Text('Quick Actions', style: ClientUi.heading),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ClientUi.navy,
        borderRadius: BorderRadius.circular(20),
        boxShadow: ClientUi.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Builder(
                builder: (context) {
                  if (isValidNetworkImageUrl(photoUrl)) {
                    return SafeNetworkAvatar(
                      photoUrl: photoUrl,
                      radius: 30,
                      fallbackLetter: firstLetter,
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                      foregroundColor: Colors.white,
                    );
                  }
                  final memoryProvider = _buildProfileImageProvider(photoUrl);
                  if (memoryProvider != null) {
                    return CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                      backgroundImage: memoryProvider,
                    );
                  }
                  return CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    child: Text(
                      firstLetter,
                      style: TextStyle(fontFamily: AppTheme.fontFamily,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: AppTheme.fontFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayEmail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: AppTheme.fontFamily,
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _pill(
                          (_currentUser?.role ?? 'client').toUpperCase(),
                          ClientUi.gold,
                          ClientUi.navy,
                        ),
                        if (isVerified)
                          _pill('Verified', Colors.white, ClientUi.navy),
                      ],
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _currentIndex = 4;
                  });
                },
                child: Text(
                  'View Profile  >',
                  style: TextStyle(fontFamily: AppTheme.fontFamily,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Good day, ${displayName.split(' ').first}!',
            style: TextStyle(fontFamily: AppTheme.fontFamily,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Here's your overview and latest updates.",
            style: TextStyle(fontFamily: AppTheme.fontFamily,
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection(BuildContext context) {
    return SizedBox(
      height: 122,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildSummaryCard(
              icon: Icons.folder_copy_rounded,
              label: 'Cases',
              subtitle: _caseCount > 0 ? "Cases on record." : "No cases yet.",
              count: _caseCount,
              color: primaryColor,
              onTap: () {
                setState(() => _currentIndex = 1);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSummaryCard(
              icon: Icons.calendar_today_rounded,
              label: 'Appointments',
              subtitle: "Upcoming schedule.",
              count: _appointmentCount,
              color: goldColor,
              onTap: () {
                setState(() => _currentIndex = 2);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSummaryCard(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Unread Messages',
              subtitle: _unreadMessageCount > 0 ? "New messages." : "All caught up.",
              count: _unreadMessageCount,
              color: Colors.green,
              onTap: () {
                setState(() => _currentIndex = 3);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionTile(
                icon: Icons.calendar_month_outlined,
                title: 'Request Appointment',
                subtitle: 'Book a consultation',
                filled: true,
                gold: false,
                onTap: () async {
                  await dashboard_nav.openAttorneySelection();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _actionTile(
                icon: Icons.chat_bubble_outline,
                title: 'Message with Counsel',
                subtitle: 'Chat with counsel',
                filled: true,
                gold: true,
                isLoading: _openingCounselChat,
                onTap: _openMessageStaffForm,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _actionTile(
                icon: Icons.help_outline_rounded,
                title: 'Send Request',
                subtitle: 'Ask for assistance',
                filled: false,
                gold: false,
                onTap: () async {
                  await dashboard_nav.openSendRequest();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _actionTile(
                icon: Icons.gavel_outlined,
                title: 'Notary Portal',
                subtitle: 'Notary services',
                filled: false,
                gold: false,
                onTap: () async {
                  await dashboard_nav.openNotaryPortal();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _actionTile(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Billing & Payments',
          subtitle: 'Balances and legal fees',
          filled: false,
          gold: false,
          onTap: () async {
            await dashboard_nav.openBilling();
          },
        ),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool filled,
    required bool gold,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    final bg = gold
        ? ClientUi.gold
        : filled
            ? ClientUi.navy
            : Colors.white;
    final fg = gold
        ? ClientUi.navy
        : filled
            ? Colors.white
            : ClientUi.navy;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: filled || gold
                ? null
                : Border.all(color: ClientUi.line),
            boxShadow: ClientUi.cardShadow,
          ),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: AppTheme.fontFamily,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: fg,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: AppTheme.fontFamily,
                        fontSize: 11,
                        color: fg.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(fg),
                  ),
                )
              else
                Icon(Icons.chevron_right, color: fg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: ClientUi.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 8),
              Text(
                '$count',
                style: TextStyle(fontFamily: AppTheme.fontFamily,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: ClientUi.navy,
                  height: 1.05,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: AppTheme.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ClientUi.text,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: AppTheme.fontFamily,fontSize: 10, color: ClientUi.muted),
              ),
              const Spacer(),
              Container(height: 3, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onViewAll}) {
    return Row(
      children: [
        Expanded(child: Text(title, style: ClientUi.heading)),
        if (onViewAll != null)
          TextButton(
            onPressed: onViewAll,
            child: Text(
              'View All  >',
              style: TextStyle(fontFamily: AppTheme.fontFamily,
                fontWeight: FontWeight.w700,
                color: ClientUi.navyMid,
              ),
            ),
          ),
      ],
    );
  }

  Widget _pill(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(fontFamily: AppTheme.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildMyCasesStrip() {
    if (_previewCases.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: ClientUi.cardShadow,
        ),
        child: Text(
          'No cases yet. Your filed cases will show here.',
          style: ClientUi.body,
          textAlign: TextAlign.center,
        ),
      );
    }

    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _previewCases.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final c = _previewCases[index];
          return _casePreviewCard(c);
        },
      ),
    );
  }

  Widget _casePreviewCard(CaseModel c) {
    final status = c.status.toLowerCase();
    final color = status == 'completed'
        ? ClientUi.green
        : status == 'in_progress' || status == 'accepted'
            ? ClientUi.navyMid
            : ClientUi.gold;
    final progress = status == 'completed'
        ? 1.0
        : status == 'in_progress'
            ? 0.7
            : status == 'accepted'
                ? 0.5
                : 0.35;
    final footer = c.hearingDate != null
        ? 'Hearing scheduled • ${DateFormat('MMM d, y').format(c.hearingDate!)}'
        : 'Case filed • ${DateFormat('MMM d, y').format(c.createdAt)}';

    return Container(
      width: 240,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ClientUi.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.balance, color: ClientUi.navyMid, size: 20),
              const Spacer(),
              _pill(
                CaseStatusFilter.statusLabel(c.status).toUpperCase(),
                color.withValues(alpha: 0.18),
                color,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            c.caseTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: AppTheme.fontFamily,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: ClientUi.navy,
            ),
          ),
          Text(
            c.caseType,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: AppTheme.fontFamily,fontSize: 12, color: ClientUi.muted),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              color: color,
              backgroundColor: ClientUi.line,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            footer,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: AppTheme.fontFamily,fontSize: 11, color: ClientUi.muted),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Get.to(() => CaseDetailPage(caseId: c.id));
              },
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('View Case  >'),
              style: FilledButton.styleFrom(
                backgroundColor: ClientUi.navy,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingCallout(AppointmentModel apt) {
    final days = apt.appointmentDateTime.difference(DateTime.now()).inDays;
    return Material(
      color: const Color(0xFFFFF6D8),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => setState(() => _currentIndex = 2),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: ClientUi.gold,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.calendar_today, color: ClientUi.navy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Upcoming Appointment',
                          style: TextStyle(fontFamily: AppTheme.fontFamily,
                            fontWeight: FontWeight.w800,
                            color: ClientUi.navy,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _pill(
                          days <= 0 ? 'TODAY' : 'IN $days DAYS',
                          ClientUi.gold,
                          ClientUi.navy,
                        ),
                      ],
                    ),
                    Text(
                      apt.caseTitle?.trim().isNotEmpty == true
                          ? apt.caseTitle!
                          : apt.appointmentType.replaceAll('_', ' '),
                      style: TextStyle(fontFamily: AppTheme.fontFamily,
                        fontSize: 13,
                        color: ClientUi.text,
                      ),
                    ),
                    Text(
                      [
                        DateFormat('MMM d, y • h:mm a')
                            .format(apt.appointmentDateTime),
                        if ((apt.attorneyName ?? '').trim().isNotEmpty)
                          apt.attorneyName!,
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: AppTheme.fontFamily,
                        fontSize: 12,
                        color: ClientUi.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: ClientUi.navy),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    return LazyIndexedStack(
      index: _currentIndex,
      activeTabRevision:
          _currentIndex == 0 ? _homeTabRevision : 'frozen-tabs',
      builders: [
        () => _buildHomeScreen(),
        () => dashboard_tabs.buildClientDashboardTab(1),
        () => dashboard_tabs.buildClientDashboardTab(2),
        () => dashboard_tabs.buildClientDashboardTab(3),
        () => dashboard_tabs.buildClientDashboardTab(4),
      ],
    );
  }

  Object get _homeTabRevision => Object.hash(
        _caseCount,
        _appointmentCount,
        _unreadMessageCount,
        _previewCases.length,
        _nextAppointment?.id,
        _currentUser?.id,
        _localImageBase64?.length,
      );


  @override
  Widget build(BuildContext context) {
    _probe.onBuild(detail: 'tab=$_currentIndex loading=$_isLoading');

    if (_isLoading) {
      return _probe.wrap(
        Scaffold(
          backgroundColor: backgroundColor,
          body: const InstantFill(),
        ),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _probe.wrap(
        Scaffold(
          backgroundColor: backgroundColor,
          body: EmptyState(
            icon: Icons.person_off_outlined,
            title: 'Not Logged In',
            message: 'Please log in to access your dashboard',
            actionLabel: 'Go to Login',
            onAction: () {
              navigateAfterLogout();
            },
          ),
        ),
      );
    }

    return _probe.wrap(
      Scaffold(
      backgroundColor: ClientUi.background,
      appBar: _currentIndex == 0
          ? AppBar(
              backgroundColor: ClientUi.navy,
              automaticallyImplyLeading: false,
              titleSpacing: 12,
              title: Row(
                children: [
                  const BrandLogo(size: 36),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'LawConnect',
                          style: TextStyle(fontFamily: AppTheme.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Connect • Consult • Resolve',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: AppTheme.fontFamily,
                            fontSize: 10,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Dashboard',
                    style: TextStyle(fontFamily: AppTheme.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Help Center',
                  icon: const Icon(Icons.help_outline),
                  onPressed: () => Get.to(() => const HelpCenterScreen()),
                ),
                const ClientNotificationBellButton(),
              ],
            )
          : null,
      body: _buildCurrentScreen(),
      bottomNavigationBar: CustomBottomNavigationBar5Tabs(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        messageUnreadCount: _unreadMessageCount,
      ),
      ),
    );
  }

  ImageProvider? _buildProfileImageProvider(String? photoUrl) {
    // Always check for local storage image first - if it exists, show it
    // This ensures dashboard shows the same profile picture as Profile screen
    if (_localImageBase64 != null && _localImageBase64!.isNotEmpty) {
      try {
        final decodedImage = base64Decode(_localImageBase64!);
        return MemoryImage(decodedImage);
      } catch (e) {
        appLog('Error decoding local image in dashboard: $e');
      }
    }

    // Return null — network photos use SafeNetworkAvatar in the header UI.
    return null;
  }
}
