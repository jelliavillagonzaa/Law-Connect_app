import 'dart:async';

import '../../../utils/screen_debug_probe.dart';

/// Web / stub — notification badge is loaded when the user opens notifications.
class DashboardNotificationBadgeController {
  StreamSubscription<int>? _sub;

  Future<void> start(
    String userId,
    void Function(int count) onCount, {
    ScreenDebugProbe? debugProbe,
  }) async {}

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
