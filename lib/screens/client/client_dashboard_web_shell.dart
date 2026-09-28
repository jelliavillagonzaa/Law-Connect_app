import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/bottom_navigation_bar_5tabs.dart';
import '../../widgets/client/client_notification_bell_button.dart';

/// Lightweight placeholder while the full client dashboard library loads on web.
class ClientDashboardWebShell extends StatelessWidget {
  const ClientDashboardWebShell({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!
        : (user?.email?.split('@').first ?? 'Client');

    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      appBar: AppBar(
        backgroundColor: AppTheme.royalBlue,
        title: const Text('Dashboard'),
        actions: const [
          ClientNotificationBellButton(),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonCard(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'C',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.email ?? '',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Overview',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.royalBlue,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: const [
                  Expanded(child: _SkeletonStatBox()),
                  SizedBox(width: 12),
                  Expanded(child: _SkeletonStatBox()),
                  SizedBox(width: 12),
                  Expanded(child: _SkeletonStatBox()),
                ],
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const CustomBottomNavigationBar5Tabs(
        currentIndex: 0,
        onTap: _noopTap,
      ),
    );
  }

  static void _noopTap(int _) {}
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.royalBlue,
            AppTheme.royalBlue.withValues(alpha: 0.88),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _SkeletonStatBox extends StatelessWidget {
  const _SkeletonStatBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Container(
          width: 32,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }
}
