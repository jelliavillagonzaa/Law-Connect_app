import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common/brand_logo.dart';

/// Instant chrome shown on web while a deferred portal library finishes
/// downloading. Looks like the real dashboard — no spinner, no "Loading…" copy.
class AdminPortalWebShell extends StatelessWidget {
  const AdminPortalWebShell({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Row(
        children: [
          if (!isMobile) const _AdminSidebarChrome(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isMobile)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    color: Colors.white,
                    child: const Text(
                      'Admin Dashboard',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1C1C1C),
                      ),
                    ),
                  ),
                const Expanded(child: _DashboardBodyChrome(title: 'Overview')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AttorneyPortalWebShell extends StatelessWidget {
  const AttorneyPortalWebShell({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 800;
    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      appBar: isDesktop
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: AppTheme.royalBlue,
              title: const Text('Dashboard'),
            ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isDesktop)
            Container(
              width: 72,
              color: Colors.white,
              child: const Column(
                children: [
                  SizedBox(height: 16),
                  BrandLogo(size: 36),
                ],
              ),
            ),
          const Expanded(child: _DashboardBodyChrome(title: 'Dashboard')),
        ],
      ),
    );
  }
}

class StaffPortalWebShell extends StatelessWidget {
  const StaffPortalWebShell({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 800;
    if (!isDesktop) {
      return Scaffold(
        backgroundColor: AppTheme.lightGray,
        appBar: AppBar(automaticallyImplyLeading: false),
        body: const _DashboardBodyChrome(title: 'Dashboard'),
        bottomNavigationBar: const _StubBottomBar(),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 250,
            color: Colors.white,
            child: const Column(
              children: [
                SizedBox(height: 24),
                BrandLogo(size: 48),
                SizedBox(height: 8),
                Text(
                  'Staff',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.royalBlue,
                  ),
                ),
              ],
            ),
          ),
          const Expanded(child: _DashboardBodyChrome(title: 'Overview')),
        ],
      ),
    );
  }
}

class _AdminSidebarChrome extends StatelessWidget {
  const _AdminSidebarChrome();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF122A54), Color(0xFF183B73), Color(0xFF274C8E)],
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Row(
          children: [
            BrandLogo(size: 48),
            SizedBox(width: 12),
            Text(
              'Law Connect',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardBodyChrome extends StatelessWidget {
  const _DashboardBodyChrome({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.royalBlue,
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: _StatPlaceholder()),
              SizedBox(width: 12),
              Expanded(child: _StatPlaceholder()),
              SizedBox(width: 12),
              Expanded(child: _StatPlaceholder()),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPlaceholder extends StatelessWidget {
  const _StatPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
    );
  }
}

class _StubBottomBar extends StatelessWidget {
  const _StubBottomBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      color: Colors.white,
      alignment: Alignment.center,
      child: const Icon(Icons.dashboard, color: AppTheme.gold),
    );
  }
}
