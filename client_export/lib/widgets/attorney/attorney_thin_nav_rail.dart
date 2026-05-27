import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../../models/user_model.dart';
import '../../widgets/common/profile_picture_widget.dart';
import '../../widgets/common/law_connect_logo.dart';

class AttorneyThinNavRail extends StatefulWidget {
  final String activeItem;
  final Function(String) onItemSelected;
  final VoidCallback onLogout;
  final bool isAvailable;
  final ValueChanged<bool> onAvailabilityChanged;

  const AttorneyThinNavRail({
    super.key,
    required this.activeItem,
    required this.onItemSelected,
    required this.onLogout,
    required this.isAvailable,
    required this.onAvailabilityChanged,
  });

  @override
  State<AttorneyThinNavRail> createState() => _AttorneyThinNavRailState();
}

class _AttorneyThinNavRailState extends State<AttorneyThinNavRail>
    with SingleTickerProviderStateMixin {
  UserModel? _currentUser;
  bool _isLoading = true;
  bool _isExpanded = false;
  late AnimationController _expandController;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && mounted) {
        setState(() {
          _currentUser = UserModel.fromFirestore(userDoc.data()!, user.uid);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
      'title': 'Case Requests',
      'icon': Icons.inbox_outlined,
      'key': 'case_requests',
      'badge': null,
    },
    {
      'title': 'Pending Cases',
      'icon': Icons.pending_outlined,
      'key': 'pending',
      'badge': null,
    },
    {
      'title': 'Tasks',
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
    return MouseRegion(
      onEnter: (_) {
        // Hover no longer auto-expands/collapses; use the toggle button instead
      },
      onExit: (_) {
        // Do not auto-collapse on exit if the user has it expanded;
        // leave collapse to the toggle button for better control.
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: _isExpanded ? 240 : 72,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(right: BorderSide(color: Colors.grey[200]!, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(2, 0),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Logo/Branding Section
              _buildLogoSection(),

              const Divider(height: 1),

              // Navigation Items
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.only(
                    top: 12,
                    bottom: 8,
                    left: _isExpanded ? 12 : 0,
                    right: _isExpanded ? 12 : 0,
                  ),
                  shrinkWrap: true,
                  itemCount: _menuItems.length,
                  itemBuilder: (context, index) {
                    final item = _menuItems[index];
                    final isActive = widget.activeItem == item['key'];

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _NavRailItem(
                        title: item['title'],
                        icon: item['icon'],
                        isActive: isActive,
                        isExpanded: _isExpanded,
                        badge: item['badge'],
                        onTap: () => widget.onItemSelected(item['key']),
                      ),
                    );
                  },
                ),
              ),

              const Divider(height: 1),

              // Profile & Actions Section pinned to the very bottom
              _buildProfileActionsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    return Container(
      padding: EdgeInsets.all(_isExpanded ? 20 : 16),
      child: _isExpanded
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.royalBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: LawConnectLogo(
                        size: 28,
                        color: AppTheme.royalBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Law Connect',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkText,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Attorney Portal',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.mutedText,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Collapse / expand toggle icon (hamburger with arrow style)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.royalBlue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.menu_open_rounded,
                        size: 20,
                        color: AppTheme.royalBlue,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.royalBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: LawConnectLogo(size: 28, color: AppTheme.royalBlue),
                  ),
                ),
                const SizedBox(height: 12),
                // Compact toggle icon to match the “menu with arrow” feel
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.royalBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.menu_rounded,
                      size: 18,
                      color: AppTheme.royalBlue,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildProfileActionsSection() {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_currentUser == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.all(_isExpanded ? 16 : 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.royalBlue, AppTheme.deepNavy],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      // Make the bottom profile/actions area scrollable so it never overflows
      child: SingleChildScrollView(
        child: _isExpanded
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Profile Info (wrapped to avoid any horizontal overflow)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        ProfilePictureWidget(
                          photoUrl: _currentUser!.photoUrl,
                          userName: _currentUser!.name.isNotEmpty
                              ? _currentUser!.name
                              : 'Attorney',
                          size: 40,
                          isEditable: false,
                        ),
                        const SizedBox(width: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentUser!.name,
                                style: TextStyle(
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
                  // Logout Button
                  _buildLogoutButton(),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: ProfilePictureWidget(
                      photoUrl: _currentUser!.photoUrl,
                      userName: _currentUser!.name.isNotEmpty
                          ? _currentUser!.name
                          : 'Attorney',
                      size: 40,
                      isEditable: false,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Logout Button (compact)
                  _buildLogoutButton(),
                ],
              ),
      ),
    );
  }

  // Unused method - kept for potential future use
  // ignore: unused_element
  Widget _buildAvailabilityToggle() {
    return _isExpanded
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: widget.isAvailable
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFFF9800),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              // Wrap status text in Flexible so it can shrink and avoid overflow
              Flexible(
                child: Text(
                  widget.isAvailable ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Transform.scale(
                scale: 0.7,
                child: Switch(
                  value: widget.isAvailable,
                  onChanged: widget.onAvailabilityChanged,
                  activeColor: const Color(0xFF4CAF50),
                  activeTrackColor: const Color(0xFF4CAF50).withOpacity(0.4),
                  inactiveThumbColor: Colors.grey[300],
                  inactiveTrackColor: Colors.grey[700]!.withOpacity(0.3),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          )
        : Tooltip(
            message: widget.isAvailable ? 'Online' : 'Offline',
            child: GestureDetector(
              onTap: () => widget.onAvailabilityChanged(!widget.isAvailable),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: widget.isAvailable
                      ? const Color(0xFF4CAF50).withOpacity(0.1)
                      : const Color(0xFFFF9800).withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.isAvailable
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFFF9800),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: widget.isAvailable
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFFF9800),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
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
    return _isExpanded
        ? SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _showLogoutConfirmation,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.royalBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.logout_rounded, size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Logout',
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
          )
        : Tooltip(
            message: 'Logout',
            child: InkWell(
              onTap: _showLogoutConfirmation,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC3545).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFDC3545).withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          );
  }
}

class _NavRailItem extends StatefulWidget {
  final String title;
  final IconData icon;
  final bool isActive;
  final bool isExpanded;
  final int? badge;
  final VoidCallback onTap;

  const _NavRailItem({
    required this.title,
    required this.icon,
    required this.isActive,
    required this.isExpanded,
    this.badge,
    required this.onTap,
  });

  @override
  State<_NavRailItem> createState() => _NavRailItemState();
}

class _NavRailItemState extends State<_NavRailItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.isExpanded ? '' : widget.title,
        preferBelow: false,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: EdgeInsets.symmetric(
              horizontal: widget.isExpanded ? 12 : 0,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? AppTheme.royalBlue.withOpacity(0.1)
                  : (_isHovered
                        ? AppTheme.royalBlue.withOpacity(0.05)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
              border: widget.isActive
                  ? Border.all(
                      color: AppTheme.royalBlue.withOpacity(0.3),
                      width: 1,
                    )
                  : null,
            ),
            child: widget.isExpanded
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Icon(
                          widget.icon,
                          size: 20,
                          color: widget.isActive
                              ? AppTheme.royalBlue
                              : (_isHovered
                                    ? AppTheme.royalBlue.withOpacity(0.7)
                                    : AppTheme.mutedText),
                        ),
                        const SizedBox(width: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: widget.isActive
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: widget.isActive
                                  ? AppTheme.royalBlue
                                  : (_isHovered
                                        ? AppTheme.royalBlue.withOpacity(0.8)
                                        : AppTheme.mutedText),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                        if (widget.badge != null && widget.badge! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC3545),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${widget.badge}',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          widget.icon,
                          size: 22,
                          color: widget.isActive
                              ? AppTheme.royalBlue
                              : (_isHovered
                                    ? AppTheme.royalBlue.withOpacity(0.7)
                                    : AppTheme.mutedText),
                        ),
                        if (widget.badge != null && widget.badge! > 0)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFFDC3545),
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              child: Center(
                                child: Text(
                                  '${widget.badge}',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
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
