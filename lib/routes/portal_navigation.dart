import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';

import 'deferred_route_loaders.dart';

export 'deferred_route_loaders.dart'
    show prefetchAllPortalDashboards, prefetchPortalDashboard;

/// After logout: website stays on the firm-portal landing; the app goes
/// to the original white-card [LoginPage].
void navigateAfterLogout() {
  Get.offAllNamed(kIsWeb ? '/' : '/LoginPage');
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
    'admin' => '/AdminDashboard',
    'attorney' => '/AttorneyDashboard',
    'staff' => '/StaffDashboard',
    _ => '/ClientDashboard',
  };
  Get.offAllNamed(
    route,
    arguments: null,
  );
}
