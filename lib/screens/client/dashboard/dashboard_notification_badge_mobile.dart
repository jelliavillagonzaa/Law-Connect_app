import 'dart:async';

import '../../../services/hearing_notification_fanout_service.dart';
import '../../../utils/screen_debug_probe.dart';

/// Mobile — badge from cache only on dashboard open (no live Firestore listeners).
class DashboardNotificationBadgeController {
  StreamSubscription<int>? _sub;
  bool _stopped = false;

  Future<void> start(
    String userId,
    void Function(int count) onCount, {
    ScreenDebugProbe? debugProbe,
  }) async {
    _stopped = false;
    final fanout = HearingNotificationFanoutService.instance;

    try {
      await fanout.prepareBellCount(userId);
    } catch (_) {}

    if (_stopped) return;
    onCount(
      fanout.peekInboxBellCount(
        userId,
        includeGlobalHearingsFallback: false,
        hearingsOnly: true,
      ),
    );
    debugProbe?.event('badge.peek', detail: 'cache only — no live listeners');
  }

  void stop() {
    _stopped = true;
    _sub?.cancel();
    _sub = null;
  }
}
