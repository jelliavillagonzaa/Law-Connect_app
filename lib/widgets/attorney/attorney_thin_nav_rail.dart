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

  const AttorneyThinNavRail({
    super.key,
    required this.activeItem,
    required this.onItemSelected,
    required this.onLogout,
    required this.isAvailable,
    required this.onAvailabilityChanged,
    this.messageUnreadCount = 0,
  });

  @override
  State<AttorneyThinNavRail> createState() => _AttorneyThinNavRailState();
}

class _AttorneyThinNavRailState extends State<AttorneyThinNavRail> {
  static const double _collapsedWidth = 72;
  static const double _wideLayoutMin = 176;

  UserModel? _currentUser;
  bool _isExpanded = true;
  String? _hoveredKey;

  @override
  void initState() {
    super.initState();
    _loadUserData();
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
      'icon': Icons.dashboard_outlined,
      'key': 'dashboard',
      'badge': null,
    },
    {
      'title': 'My Cases',
      'icon': Icons.folder_outlined,
      'key': 'cases',
      'badge': null,
    },
    {
      'title': 'Closed Cases',
      'icon': Icons.folder_off_outlined,
      'key': 'closed_cases',
      'badge': null,
    },
    {
      'title': 'Create Case',
      'icon': Icons.add,
      'key': 'case_requests',
      'badge': null,
    },
    {
      'title': 'Pending Appointments',
      'icon': Icons.pending_outlined,
      'key': 'pending',
      'badge': null,
    },
    {
      'title': 'Staff Tasks',
      'icon': Icons.task_outlined,
      'key': 'tasks',
      'badge': null,
    },
    {
      'title': 'Messages',
      'icon': Icons.message_outlined,
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
                      Text(
                        'Attorney Portal',
                        textDirection: TextDirection.ltr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xB3FFFFFF),
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
      return const SizedBox.shrink();
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
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProfilePictureWidget(
                  photoUrl: _currentUser!.photoUrl,
                  userName: _currentUser!.name.isNotEmpty
                      ? _currentUser!.name
                      : 'Attorney',
                  size: 32,
                  isEditable: false,
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentUser!.name,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currentUser!.email,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildLogoutButton(),
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
    final hovered = _hoveredKey == itemKey;
    final iconColor = isActive ? AttorneyUi.primary : Colors.white;
    return SizedBox(
      key: ValueKey<String>('nav-$itemKey'),
      height: 44,
      width: double.infinity,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredKey = itemKey),
        onExit: (_) => setState(() => _hoveredKey = null),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 10 : 0,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white
                  : (hovered
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(20),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: wide
                ? Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isActive
                              ? AttorneyUi.primary.withValues(alpha: 0.10)
                              : Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _ltrIcon(icon, size: 18, color: iconColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight:
                                isActive ? FontWeight.w700 : FontWeight.w500,
                            color: iconColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badge != null && badge > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AttorneyUi.danger,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$badge',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  )
                : Center(
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: isActive
                            ? AttorneyUi.primary.withValues(alpha: 0.10)
                            : Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _ltrIcon(icon, size: 18, color: iconColor),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

