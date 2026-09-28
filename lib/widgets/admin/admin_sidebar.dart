import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import 'admin_ui_theme.dart';
import 'profile_card.dart';
import 'sidebar_item.dart';
import '../common/brand_logo.dart';

class AdminSidebar extends StatefulWidget {
  final String activeItem;
  final Function(String) onItemSelected;
  final VoidCallback onLogout;

  const AdminSidebar({
    super.key,
    required this.activeItem,
    required this.onItemSelected,
    required this.onLogout,
  });

  @override
  State<AdminSidebar> createState() => _AdminSidebarState();
}

class _AdminSidebarState extends State<AdminSidebar> {
  UserModel? _currentUser;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      _loadUserData();
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

  Widget _logoutButton() {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: widget.onLogout,
        style: TextButton.styleFrom(
          backgroundColor: const Color(0xFF16325C),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          ),
        ),
        icon: const Icon(Icons.logout_rounded, size: 14, color: Colors.white),
        label: const Text(
          'Logout',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  final List<Map<String, dynamic>> _menuItems = [
    {
      'title': 'Dashboard',
      'icon': Icons.dashboard_outlined,
      'key': 'dashboard',
    },
    {'title': 'User Management', 'icon': Icons.people_outlined, 'key': 'users'},
    {'title': 'Case Oversight', 'icon': Icons.folder_outlined, 'key': 'cases'},
    {'title': 'System Logs', 'icon': Icons.description_outlined, 'key': 'logs'},
    {
      'title': 'Reports & Analytics',
      'icon': Icons.analytics_outlined,
      'key': 'reports',
    },
    {
      'title': 'System Settings',
      'icon': Icons.settings_outlined,
      'key': 'settings',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AdminUi.sidebarWidth,
      decoration: const BoxDecoration(
        gradient: AdminUi.navyGradient,
        boxShadow: [
          BoxShadow(
            color: Color(0x40122A54),
            blurRadius: 28,
            offset: Offset(8, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                const BrandLogo(size: 32),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Law Connect',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.1,
                          height: 1.15,
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        'Admin Console',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Color(0xB3FFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
            child: Column(
              children: [
                for (final item in _menuItems)
                  SidebarItem(
                    title: item['title'] as String,
                    icon: item['icon'] as IconData,
                    isActive: widget.activeItem == item['key'],
                    onTap: () => widget.onItemSelected(item['key'] as String),
                  ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                      child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_currentUser != null)
                            ProfileCard(
                              user: _currentUser!,
                              onLogout: widget.onLogout,
                            )
                          else
                            _logoutButton(),
                          const SizedBox(height: 8),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.balance,
                                size: 12,
                                color: Color(0xB3FFFFFF),
                              ),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '"Justice Within Reach"',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    fontStyle: FontStyle.italic,
                                    color: Color(0xB3FFFFFF),
                                  ),
                                ),
                              ),
                            ],
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
        ],
        ),
      ),
    );
  }
}
