import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../theme/app_theme.dart';

/// Premium iPhone-style floating frosted glass capsule navigation dock with 5 tabs.
/// Features ultra-smooth spring compression, haptic feedback, glowing gold active pill,
/// and seamless icon transitions.
class CustomBottomNavigationBar5Tabs extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final int messageUnreadCount;

  const CustomBottomNavigationBar5Tabs({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.messageUnreadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final navItems = [
      (
        icon: Icons.grid_view_rounded,
        unselectedIcon: Icons.grid_view_outlined,
        label: 'Dashboard',
        badge: 0,
      ),
      (
        icon: Icons.folder_rounded,
        unselectedIcon: Icons.folder_outlined,
        label: 'Cases',
        badge: 0,
      ),
      (
        icon: Icons.calendar_month_rounded,
        unselectedIcon: Icons.calendar_today_outlined,
        label: 'Appointments',
        badge: 0,
      ),
      (
        icon: Icons.chat_bubble_rounded,
        unselectedIcon: Icons.chat_bubble_outline_rounded,
        label: 'Messages',
        badge: messageUnreadCount,
      ),
      (
        icon: Icons.person_rounded,
        unselectedIcon: Icons.person_outline_rounded,
        label: 'Profile',
        badge: 0,
      ),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 66,
              decoration: BoxDecoration(
                color: const Color(0xFF07152B).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF07152B).withValues(alpha: 0.50),
                    blurRadius: 26,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Row(
                children: List.generate(navItems.length, (index) {
                  final item = navItems[index];
                  final isSelected = currentIndex == index;

                  return Expanded(
                    child: _ClientIphoneNavButton(
                      isSelected: isSelected,
                      icon: item.icon,
                      unselectedIcon: item.unselectedIcon,
                      label: item.label,
                      badge: item.badge,
                      onTap: () => onTap(index),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientIphoneNavButton extends StatefulWidget {
  final bool isSelected;
  final IconData icon;
  final IconData unselectedIcon;
  final String label;
  final int badge;
  final VoidCallback onTap;

  const _ClientIphoneNavButton({
    required this.isSelected,
    required this.icon,
    required this.unselectedIcon,
    required this.label,
    required this.badge,
    required this.onTap,
  });

  @override
  State<_ClientIphoneNavButton> createState() => _ClientIphoneNavButtonState();
}

class _ClientIphoneNavButtonState extends State<_ClientIphoneNavButton> {
  bool _isDown = false;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFFFBBF24); // Warm legal gold
    final inactiveColor = Colors.white.withValues(alpha: 0.60);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isDown = true),
      onTapUp: (_) {
        setState(() => _isDown = false);
        unawaited(HapticFeedback.lightImpact());
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isDown = false),
      child: AnimatedScale(
        scale: _isDown ? 0.88 : (widget.isSelected ? 1.04 : 1.0),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? const Color(0xFFF59E0B).withValues(alpha: 0.20)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.isSelected
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                  : Colors.transparent,
              width: 1,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      widget.isSelected ? widget.icon : widget.unselectedIcon,
                      key: ValueKey<bool>(widget.isSelected),
                      size: 21,
                      color: widget.isSelected ? activeColor : inactiveColor,
                    ),
                  ),
                  if (widget.badge > 0)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4.5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF07152B),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  const Color(0xFFEF4444).withValues(alpha: 0.4),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          widget.badge > 99 ? '99+' : '${widget.badge}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 10,
                  fontWeight:
                      widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: widget.isSelected ? activeColor : inactiveColor,
                  letterSpacing: 0.1,
                ),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
