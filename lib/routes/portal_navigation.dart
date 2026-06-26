import 'package:get/get.dart';

import 'deferred_route_loaders.dart';

export 'deferred_route_loaders.dart'
    show prefetchAllPortalDashboards, prefetchPortalDashboard;

/// Central post-login navigation — always uses deferred GetX routes so heavy
/// dashboards are not compiled into the login/OTP libraries.
void navigateToPortalDashboard(String portalRole) {
  prefetchPortalDashboard(portalRole);
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
