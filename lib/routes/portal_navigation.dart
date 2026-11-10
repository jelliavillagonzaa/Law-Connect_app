import 'package:get/get.dart';

import 'deferred_route_loaders.dart';

export 'deferred_route_loaders.dart'
    show prefetchAllPortalDashboards, prefetchPortalDashboard;

/// After logout, open the firm-portal login screen. The public landing
/// page at `/` stays as-is.
void navigateAfterLogout() {
  Get.offAllNamed('/LoginPage');
}

/// Central post-login navigation — always uses deferred GetX routes so heavy
/// dashboards are not compiled into the login/OTP libraries.
void navigateToPortalDashboard(String portalRole) {
  try {
    prefetchPortalDashboard(portalRole);
  } catch (_) {
    // Prefetch is optional — never block a successful login.
  }
  final route = switch (portalRole.toLowerCase()) {
    'admin' || 'staff' => '/StaffDashboard',
    'attorney' => '/AttorneyDashboard',
    _ => '/ClientDashboard',
  };
  Get.offAllNamed(
    route,
    arguments: portalRole.toLowerCase() == 'admin' ? {'initialItem': 'admin_dashboard'} : null,
  );
}
