import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../../models/user_model.dart';
import '../../widgets/common/profile_picture_widget.dart';

class AttorneySidebar extends StatefulWidget {
  final String activeItem;
  final Function(String) onItemSelected;
  final VoidCallback onLogout;
  final bool isAvailable;
  final ValueChanged<bool> onAvailabilityChanged;

  const AttorneySidebar({
    super.key,
    required this.activeItem,
    required this.onItemSelected,
    required this.onLogout,
    required this.isAvailable,
    required this.onAvailabilityChanged,
  });

  @override
  State<AttorneySidebar> createState() => _AttorneySidebarState();
}

class _AttorneySidebarState extends State<AttorneySidebar>
    with SingleTickerProviderStateMixin {
  UserModel? _currentUser;
  bool _isLoading = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
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

  Future<void> _onProfilePictureUpdated() async {
    await _loadUserData();
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
      'title': 'Pending Cases',
      'icon': Icons.pending_outlined,
      'key': 'pending',
      'badge': null,
    },
    {
      'title': 'Messages',
      'icon': Icons.message_outlined,
      'key': 'messages',
      'badge': null,
    },
    {
      'title': 'Calendar View',
      'icon': Icons.calendar_today_outlined,
      'key': 'calendar',
      'badge': null,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          // Sidebar background color for both web and mobile – match attorney UI
          color: const Color.fromARGB(255, 158, 182, 215),
          border: Border(right: BorderSide(color: Colors.grey[300]!, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(2, 0),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          children: [
            // Enhanced Profile Header
            _buildProfileHeader(),

            // Menu Items Section
            Expanded(child: _buildMenuSection()),
            // Logout moved to settings screen, so no logout button here
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      // Make header background transparent so only the circular profile image stands out
      decoration: const BoxDecoration(color: Colors.transparent),
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            )
          : _currentUser == null
          ? const SizedBox.shrink()
          : Column(
              children: [
                // Circular profile picture (no rectangular blue background)
                ProfilePictureWidget(
                  photoUrl: _currentUser!.photoUrl,
                  userName: (_currentUser!.fullName?.isNotEmpty ?? false)
                      ? _currentUser!.fullName!
                      : (_currentUser!.name.isNotEmpty
                            ? _currentUser!.name
                            : 'Attorney'),
                  size: 88,
                  isEditable: true,
                  onUpdated: _onProfilePictureUpdated,
                ),
                const SizedBox(height: 18),
                // Name
                Text(
                  _currentUser!.fullName ?? _currentUser!.name,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // Email
                Text(
                  _currentUser!.email,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 22),
              ],
            ),
    );
  }

  // Unused method - kept for potential future use
  // ignore: unused_element
  Widget _buildAvailabilityToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status Indicator with Professional Glow
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: widget.isAvailable
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFFFF9800),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color:
                      (widget.isAvailable
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFF9800))
                          .withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 1.5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          // Status Text
          Text(
            widget.isAvailable ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 14),
          // Professional Toggle Switch
          Transform.scale(
            scale: 0.88,
            child: Switch(
              value: widget.isAvailable,
              onChanged: widget.onAvailabilityChanged,
              activeColor: const Color(0xFF4CAF50),
              activeTrackColor: const Color(0xFF4CAF50).withOpacity(0.4),
              inactiveThumbColor: Colors.grey[400],
              inactiveTrackColor: Colors.grey[700]!.withOpacity(0.3),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuSection() {
    return Column(
      children: [
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            physics: const BouncingScrollPhysics(),
            itemCount: _menuItems.length,
            itemBuilder: (context, index) {
              final item = _menuItems[index];
              final isActive = widget.activeItem == item['key'];

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _MenuItem(
                  title: item['title'],
                  icon: item['icon'],
                  isActive: isActive,
                  badge: item['badge'],
                  onTap: () => widget.onItemSelected(item['key']),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Logout section removed – logout handled from settings screen.
}

class _MenuItem extends StatefulWidget {
  final String title;
  final IconData icon;
  final bool isActive;
  final int? badge;
  final VoidCallback onTap;

  const _MenuItem({
    required this.title,
    required this.icon,
    required this.isActive,
    this.badge,
    required this.onTap,
  });

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) {
          _controller.reverse();
          widget.onTap();
        },
        onTapCancel: () => _controller.reverse(),
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? AppTheme.royalBlue.withOpacity(0.1)
                  : (_isHovered
                        ? AppTheme.royalBlue.withOpacity(0.05)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(12),
              border: widget.isActive
                  ? Border.all(
                      color: AppTheme.royalBlue.withOpacity(0.3),
                      width: 1,
                    )
                  : (_isHovered
                        ? Border.all(
                            color: AppTheme.royalBlue.withOpacity(0.15),
                            width: 1,
                          )
                        : null),
            ),
            child: Row(
              children: [
                // Icon with professional styling
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: widget.isActive
                        ? AppTheme.royalBlue.withOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 21,
                    color: widget.isActive
                        ? AppTheme.royalBlue
                        : (_isHovered
                              ? AppTheme.royalBlue.withOpacity(0.75)
                              : AppTheme.mutedText),
                  ),
                ),
                const SizedBox(width: 14),
                // Title with professional typography
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: widget.isActive
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: widget.isActive
                          ? AppTheme.royalBlue
                          : (_isHovered
                                ? AppTheme.royalBlue.withOpacity(0.85)
                                : AppTheme.mutedText),
                      letterSpacing: 0.15,
                      height: 1.3,
                    ),
                  ),
                ),
                // Badge (if any) - Professional styling
                if (widget.badge != null && widget.badge! > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC3545),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFDC3545).withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      '${widget.badge}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                // Active Indicator - Professional design
                if (widget.isActive)
                  Container(
                    margin: const EdgeInsets.only(left: 10),
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppTheme.royalBlue,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.royalBlue.withOpacity(0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
