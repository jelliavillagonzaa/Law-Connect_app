import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common/brand_logo.dart';
import '../screens/client/client_dashboard_web_shell.dart';
import '../screens/client/notifications_screen_web.dart' as web_notifications;
import '../screens/portal/portal_web_shells.dart';

import '../pages/admin/admin_dashboard.dart' deferred as admin_dashboard;
import '../pages/attorney/attorney_dashboard.dart' deferred as attorney_dashboard;
import '../pages/staff/staff_dashboard.dart' deferred as staff_dashboard;
import '../screens/client/dashboard_screen_with_nav.dart' deferred as client_dashboard;
import '../screens/client/notifications_screen_mobile.dart' deferred as notif_mobile;

/// Flutter web (especially after hot reload) can return `null`/`undefined` from
/// deferred `loadLibrary()`. Calling `.catchError` on that crashes login.
Future<void> _wrapLoadLibrary(Future<void> Function() loadLibrary) {
  return Future<void>(() async {
    await loadLibrary();
  });
}

void _safeUnawaited(Future<void>? future, String label) {
  unawaited(() async {
    try {
      if (future != null) {
        await future;
      }
    } catch (e, st) {
      // Avoid crashing the app due to unhandled deferred-load errors.
      debugPrint('⚠️ Deferred load failed ($label): $e');
      debugPrint('$st');
    }
  }());
}

/// Start downloading a deferred dashboard library (safe to call multiple times).
void prefetchPortalDashboard(String portalRole) {
  switch (portalRole.toLowerCase()) {
    case 'admin':
      _safeUnawaited(DeferredAdminDashboard.prefetch(), 'admin_dashboard');
    case 'attorney':
      _safeUnawaited(DeferredAttorneyDashboard.prefetch(), 'attorney_dashboard');
    case 'staff':
      _safeUnawaited(DeferredStaffDashboard.prefetch(), 'staff_dashboard');
    default:
      _safeUnawaited(DeferredClientDashboard.prefetch(), 'client_dashboard');
  }
}

/// Warm all portal dashboards during login so role routing feels instant.
void prefetchAllPortalDashboards() {
  _safeUnawaited(DeferredClientDashboard.prefetch(), 'client_dashboard');
  _safeUnawaited(
    DeferredClientNotificationsScreen.prefetch(),
    'client_notifications',
  );
  _safeUnawaited(DeferredAttorneyDashboard.prefetch(), 'attorney_dashboard');
  _safeUnawaited(DeferredStaffDashboard.prefetch(), 'staff_dashboard');
  _safeUnawaited(DeferredAdminDashboard.prefetch(), 'admin_dashboard');
}

/// Branded shell while a deferred dashboard library loads.
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

class _DeferredRouteHost extends StatefulWidget {
  const _DeferredRouteHost({
    required this.loadFuture,
    required this.pageBuilder,
    required this.loadingMessage,
    this.loadingWidget,
  });

  final Future<void> loadFuture;
  final Widget Function() pageBuilder;
  final String loadingMessage;
  final Widget? loadingWidget;

  @override
  State<_DeferredRouteHost> createState() => _DeferredRouteHostState();
}

class _DeferredRouteHostState extends State<_DeferredRouteHost> {
  Widget? _readyPage;

  @override
  Widget build(BuildContext context) {
    if (_readyPage != null) return _readyPage!;
    return FutureBuilder<void>(
      future: widget.loadFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Failed to load page: ${snapshot.error}'),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.done) {
          _readyPage = widget.pageBuilder();
          return _readyPage!;
        }
        return widget.loadingWidget ??
            RouteLoadingScaffold(message: widget.loadingMessage);
      },
    );
  }
}

class DeferredAdminDashboard extends StatelessWidget {
  const DeferredAdminDashboard({super.key});

  static Future<void>? _load;

  static Future<void> prefetch() => _ensureLoaded();

  static Future<void> _ensureLoaded() {
    return _load ??= _wrapLoadLibrary(() => admin_dashboard.loadLibrary());
  }

  @override
  Widget build(BuildContext context) {
    return _DeferredRouteHost(
      loadFuture: _ensureLoaded(),
      loadingMessage: 'Loading admin dashboard…',
      loadingWidget: kIsWeb ? const AdminPortalWebShell() : null,
      pageBuilder: () => admin_dashboard.AdminDashboard(),
    );
  }
}

class DeferredAttorneyDashboard extends StatelessWidget {
  const DeferredAttorneyDashboard({super.key});

  static Future<void>? _load;

  static Future<void> prefetch() => _ensureLoaded();

  static Future<void> _ensureLoaded() {
    return _load ??= _wrapLoadLibrary(() => attorney_dashboard.loadLibrary());
  }

  @override
  Widget build(BuildContext context) {
    return _DeferredRouteHost(
      loadFuture: _ensureLoaded(),
      loadingMessage: 'Loading attorney dashboard…',
      loadingWidget: kIsWeb ? const AttorneyPortalWebShell() : null,
      pageBuilder: () => attorney_dashboard.AttorneyDashboard(),
    );
  }
}

class DeferredStaffDashboard extends StatelessWidget {
  const DeferredStaffDashboard({super.key});

  static Future<void>? _load;

  static Future<void> prefetch() => _ensureLoaded();

  static Future<void> _ensureLoaded() {
    return _load ??= _wrapLoadLibrary(() => staff_dashboard.loadLibrary());
  }

  @override
  Widget build(BuildContext context) {
    return _DeferredRouteHost(
      loadFuture: _ensureLoaded(),
      loadingMessage: 'Loading staff dashboard…',
      loadingWidget: kIsWeb ? const StaffPortalWebShell() : null,
      pageBuilder: () => staff_dashboard.StaffDashboard(),
    );
  }
}

class DeferredClientDashboard extends StatelessWidget {
  const DeferredClientDashboard({super.key});

  static Future<void>? _load;

  static Future<void> prefetch() => _ensureLoaded();

  static Future<void> _ensureLoaded() {
    return _load ??= _wrapLoadLibrary(() => client_dashboard.loadLibrary());
  }

  @override
  Widget build(BuildContext context) {
    return _DeferredRouteHost(
      loadFuture: _ensureLoaded(),
      loadingMessage: 'Loading client dashboard…',
      loadingWidget: kIsWeb ? const ClientDashboardWebShell() : null,
      pageBuilder: () => client_dashboard.DashboardScreenWithNav(),
    );
  }
}

class DeferredClientNotificationsScreen extends StatelessWidget {
  const DeferredClientNotificationsScreen({super.key});

  static Future<void> prefetch() {
    if (kIsWeb) return Future<void>.value();
    return _wrapLoadLibrary(() => notif_mobile.loadLibrary());
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const web_notifications.NotificationsScreen();
    }
    return _DeferredRouteHost(
      loadFuture: _wrapLoadLibrary(() => notif_mobile.loadLibrary()),
      loadingMessage: 'Loading notifications…',
      pageBuilder: () => notif_mobile.NotificationsScreen(),
    );
  }
}
