import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../theme/app_theme.dart';

/// Custom bottom navigation bar with 3 tabs (Home, Appointments, Profile)
/// in an iPhone-form floating frosted glass capsule dock.
class CustomBottomNavigationBar4Tabs extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomNavigationBar4Tabs({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final navItems = [
      (
        icon: Icons.home_rounded,
        unselectedIcon: Icons.home_outlined,
        label: 'Home',
      ),
      (
        icon: Icons.calendar_month_rounded,
        unselectedIcon: Icons.calendar_today_outlined,
        label: 'Appts',
      ),
      (
        icon: Icons.person_rounded,
        unselectedIcon: Icons.person_outline_rounded,
        label: 'Profile',
      ),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                children: List.generate(navItems.length, (index) {
                  final item = navItems[index];
                  final isSelected = currentIndex == index;

                  return Expanded(
                    child: _ClientIphoneNav4Button(
                      isSelected: isSelected,
                      icon: item.icon,
                      unselectedIcon: item.unselectedIcon,
                      label: item.label,
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

class _ClientIphoneNav4Button extends StatefulWidget {
  final bool isSelected;
  final IconData icon;
  final IconData unselectedIcon;
  final String label;
  final VoidCallback onTap;

  const _ClientIphoneNav4Button({
    required this.isSelected,
    required this.icon,
    required this.unselectedIcon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ClientIphoneNav4Button> createState() =>
      _ClientIphoneNav4ButtonState();
}

class _ClientIphoneNav4ButtonState extends State<_ClientIphoneNav4Button> {
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
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  widget.isSelected ? widget.icon : widget.unselectedIcon,
                  key: ValueKey<bool>(widget.isSelected),
                  size: 22,
                  color: widget.isSelected ? activeColor : inactiveColor,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 10.5,
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
