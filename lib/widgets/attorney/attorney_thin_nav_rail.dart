import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../../models/user_model.dart';
import '../../widgets/common/profile_picture_widget.dart';
import '../../widgets/common/brand_logo.dart';
import 'attorney_ui_theme.dart';

class AttorneyThinNavRail extends StatefulWidget {
  final String activeItem;
  final Function(String) onItemSelected;
  final VoidCallback onLogout;
  final bool isAvailable;
  final ValueChanged<bool> onAvailabilityChanged;
  final int messageUnreadCount;
  final int pendingRequestsCount;

  const AttorneyThinNavRail({
    super.key,
    required this.activeItem,
    required this.onItemSelected,
    required this.onLogout,
    required this.isAvailable,
    required this.onAvailabilityChanged,
    this.messageUnreadCount = 0,
    this.pendingRequestsCount = 0,
  });

  @override
  State<AttorneyThinNavRail> createState() => _AttorneyThinNavRailState();
}

class _AttorneyThinNavRailState extends State<AttorneyThinNavRail> {
  static const double _collapsedWidth = 72;
  static const double _wideLayoutMin = 176;

  UserModel? _currentUser;
  bool _isExpanded = true;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _loadUserData();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && mounted) {
        setState(() {
          _currentUser = UserModel.fromFirestore(userDoc.data()!, user.uid);
        });
      }
    } catch (_) {}
  }

  final List<Map<String, dynamic>> _menuItems = [
    {
      'title': 'Dashboard',
      'icon': Icons.grid_view_rounded,
      'key': 'dashboard',
      'badge': null,
    },
    {
      'title': 'Cases',
      'icon': Icons.folder_outlined,
      'key': 'cases',
      'badge': null,
    },
    {
      'title': 'Closed Cases',
      'icon': Icons.assignment_turned_in_outlined,
      'key': 'closed_cases',
      'badge': null,
    },
    {
      'title': 'Create Case',
      'icon': Icons.add_circle_outline,
      'key': 'case_requests',
      'badge': null,
    },
    {
      'title': 'Staff Tasks',
      'icon': Icons.checklist_rounded,
      'key': 'tasks',
      'badge': null,
    },
    {
      'title': 'Payment History',
      'icon': Icons.receipt_long_rounded,
      'key': 'payment_history',
      'badge': null,
    },
    {
      'title': 'Messages',
      'icon': Icons.chat_bubble_outline_rounded,
      'key': 'messages',
      'badge': null,
    },
    {
      'title': 'Calendar',
      'icon': Icons.calendar_today_outlined,
      'key': 'calendar',
      'badge': null,
    },
    {
      'title': 'Settings',
      'icon': Icons.settings_outlined,
      'key': 'settings',
      'badge': null,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: double.infinity,
        child: AnimatedContainer(
          duration: AttorneyUi.anim,
          curve: Curves.easeInOut,
          width: _isExpanded ? AttorneyUi.sidebarWidth : _collapsedWidth,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            gradient: AttorneyUi.sidebarGradient,
            boxShadow: [
              BoxShadow(
                color: AttorneyUi.primary.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(8, 0),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            right: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= _wideLayoutMin;
                return ClipRect(
                  child: Column(
                    children: [
                      _buildLogoSection(wide),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: wide ? 20 : 10,
                        ),
                        child: Container(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.only(
                            top: 8,
                            bottom: 6,
                            left: wide ? 8 : 0,
                            right: wide ? 8 : 0,
                          ),
                          child: Column(
                            children: [
                              for (final item in _menuItems)
                                _buildNavItem(
                                  title: item['title'] as String,
                                  icon: item['icon'] as IconData,
                                  itemKey: item['key'] as String,
                                  isActive: widget.activeItem == item['key'],
                                  wide: wide,
                                  badge: item['key'] == 'messages'
                                      ? (widget.messageUnreadCount > 0
                                          ? widget.messageUnreadCount
                                          : null)
                                      : item['badge'] as int?,
                                  onTap: () => widget.onItemSelected(
                                    item['key'] as String,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: wide ? 16 : 10,
                        ),
                        child: Container(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      _buildProfileActionsSection(wide),
                      if (wide) _buildWatermark(),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Icon _ltrIcon(IconData icon, {required double size, required Color color}) {
    return Icon(
      icon,
      size: size,
      color: color,
      textDirection: TextDirection.ltr,
    );
  }

  Widget _menuToggle() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: _ltrIcon(
          _isExpanded ? Icons.menu_open_rounded : Icons.menu_rounded,
          size: 20,
          color: Colors.white70,
        ),
      ),
    );
  }

  Widget _buildLogoSection(bool wide) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        wide ? 12 : 8,
        12,
        wide ? 12 : 8,
        10,
      ),
      child: wide
          ? Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const BrandLogo(size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Law Connect',
                        textDirection: TextDirection.ltr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                _menuToggle(),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const BrandLogo(size: 22),
                ),
                const SizedBox(height: 6),
                _menuToggle(),
              ],
            ),
    );
  }

  Widget _buildProfileActionsSection(bool wide) {
    if (_currentUser == null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(wide ? 12 : 6, 8, wide ? 12 : 6, 16),
        child: wide
            ? _buildLogoutButton()
            : Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _showLogoutConfirmation,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: Colors.white70,
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                ),
              ),
      );
    }

    if (!wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProfilePictureWidget(
              photoUrl: _currentUser!.photoUrl,
              userName: _currentUser!.name.isNotEmpty
                  ? _currentUser!.name
                  : 'Attorney',
              size: 24,
              isEditable: false,
            ),
            const SizedBox(height: 4),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _showLogoutConfirmation,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.logout_rounded,
                  size: 16,
                  color: Colors.white70,
                  textDirection: TextDirection.ltr,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F264A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProfilePictureWidget(
                photoUrl: _currentUser!.photoUrl,
                userName: _currentUser!.name.isNotEmpty
                    ? _currentUser!.name
                    : 'Attorney',
                size: 34,
                isEditable: false,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _currentUser!.name.isNotEmpty
                          ? _currentUser!.name
                          : 'Attorney',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _currentUser!.email.isNotEmpty
                          ? _currentUser!.email
                          : 'attorney@gmail.com',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: 0.65),
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
          _buildLogoutButton(),
        ],
      ),
    );
  }

  Widget _buildWatermark() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.balance_rounded,
            size: 26,
            color: Colors.white.withValues(alpha: 0.16),
          ),
          const SizedBox(height: 4),
          Text(
            'Justice • Integrity • Professionalism',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
              color: Colors.white.withValues(alpha: 0.35),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _showLogoutConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Logout',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.darkText,
            ),
          ),
          content: Text(
            'Do you want to log out?',
            style: TextStyle(fontSize: 15, color: AppTheme.mutedText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.mutedText,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: Text(
                'No',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.royalBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Text(
                'Yes',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      widget.onLogout();
    }
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _showLogoutConfirmation,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.12),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 12,
          ),
          minimumSize: const Size(0, 36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ltrIcon(
              Icons.logout_rounded,
              size: 16,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            const Flexible(
              child: Text(
                'Logout',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required String title,
    required IconData icon,
    required String itemKey,
    required bool isActive,
    required bool wide,
    required int? badge,
    required VoidCallback onTap,
  }) {
    final iconColor =
        isActive ? Colors.white : Colors.white.withValues(alpha: 0.75);
    final textColor =
        isActive ? Colors.white : Colors.white.withValues(alpha: 0.85);

    return Container(
      key: ValueKey<String>('nav-$itemKey'),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF1E6BFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: const Color(0xFF1E6BFF).withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.white.withValues(alpha: 0.08),
          splashColor: Colors.white.withValues(alpha: 0.14),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 14 : 0,
              vertical: 10,
            ),
            child: wide
                ? Row(
                    children: [
                      Icon(icon, size: 20, color: iconColor),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight:
                                isActive ? FontWeight.w700 : FontWeight.w500,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badge != null && badge > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            badge > 99 ? '99+' : '$badge',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  )
                : Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(icon, size: 20, color: iconColor),
                        if (badge != null && badge > 0)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

