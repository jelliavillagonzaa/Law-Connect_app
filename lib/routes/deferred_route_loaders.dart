import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common/brand_logo.dart';
import '../screens/client/notifications_screen_web.dart' as web_notifications;

import '../pages/admin/admin_dashboard.dart' as admin_dashboard;
import '../pages/attorney/attorney_dashboard.dart' as attorney_dashboard;
import '../pages/staff/staff_dashboard.dart' as staff_dashboard;
import '../screens/client/dashboard_screen_with_nav.dart' as client_dashboard;
import '../screens/client/notifications_screen_mobile.dart' as notif_mobile;

/// Start downloading a deferred dashboard library (no-op since routes are bundled).
void prefetchPortalDashboard(String portalRole) {}

/// Warm all portal dashboards during login (no-op since routes are bundled).
void prefetchAllPortalDashboards() {}

/// Branded shell while a dashboard loads.
class RouteLoadingScaffold extends StatelessWidget {
  const RouteLoadingScaffold({super.key, this.message = ''});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogo(size: 72),
            const SizedBox(height: 28),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTheme.white,
              ),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(
                  color: AppTheme.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DeferredAdminDashboard extends StatelessWidget {
  const DeferredAdminDashboard({super.key});

  static Future<void> prefetch() => Future<void>.value();

  @override
  Widget build(BuildContext context) {
    return admin_dashboard.AdminDashboard();
  }
}

class DeferredAttorneyDashboard extends StatelessWidget {
  const DeferredAttorneyDashboard({super.key});

  static Future<void> prefetch() => Future<void>.value();

  @override
  Widget build(BuildContext context) {
    return attorney_dashboard.AttorneyDashboard();
  }
}

class DeferredStaffDashboard extends StatelessWidget {
  const DeferredStaffDashboard({super.key});

  static Future<void> prefetch() => Future<void>.value();

  @override
  Widget build(BuildContext context) {
    return staff_dashboard.StaffDashboard();
  }
}

class DeferredClientDashboard extends StatelessWidget {
  const DeferredClientDashboard({super.key});

  static Future<void> prefetch() => Future<void>.value();

  @override
  Widget build(BuildContext context) {
    return const client_dashboard.DashboardScreenWithNav();
  }
}

class DeferredClientNotificationsScreen extends StatelessWidget {
  const DeferredClientNotificationsScreen({super.key});

  static Future<void> prefetch() => Future<void>.value();

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const web_notifications.NotificationsScreen();
    }
    return notif_mobile.NotificationsScreen();
  }
}

