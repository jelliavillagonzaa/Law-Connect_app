import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../services/hearing_notification_fanout_service.dart';
import '../../../utils/screen_debug_probe.dart';

/// Live unread count for the client notification bell (app + web).
///
/// Counts `notifications` where `isRead` is not true for this user
/// (`userId` or `clientId`). New docs increment the badge; marking read
/// decrements it.
class DashboardNotificationBadgeController {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subs =
      [];
  Timer? _pollTimer;
  bool _stopped = false;
  String? _userId;
  void Function(int count)? _onCount;

  final Map<String, bool> _fromUserId = {};
  final Map<String, bool> _fromClientId = {};
  bool _gotUserSnap = false;
  bool _gotClientSnap = false;
  int _cachedPeek = 0;

  Future<void> start(
    String userId,
    void Function(int count) onCount, {
    ScreenDebugProbe? debugProbe,
  }) async {
    stop();
    _stopped = false;
    _userId = userId;
    _onCount = onCount;
    _fromUserId.clear();
    _fromClientId.clear();
    _gotUserSnap = false;
    _gotClientSnap = false;

    final fanout = HearingNotificationFanoutService.instance;
    try {
      await fanout.prepareBellCount(userId);
    } catch (_) {}
    if (_stopped) return;

    _cachedPeek = fanout.peekInboxBellCount(
      userId,
      includeGlobalHearingsFallback: false,
      hearingsOnly: true,
    );
    _emit();
    debugProbe?.event('badge.start', detail: 'peek=$_cachedPeek');

    // Poll only — dual live snapshots freeze the client isolate on Android.
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_stopped) return;
      unawaited(_refreshOnce());
    });
    unawaited(_refreshOnce());
  }

  Future<void> refresh() => _refreshOnce();

  Query<Map<String, dynamic>> _unreadQuery(String field, String userId) {
    return _db
        .collection('notifications')
        .where(field, isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .limit(99);
  }

  Query<Map<String, dynamic>> _recentQuery(String field, String userId) {
    return _db
        .collection('notifications')
        .where(field, isEqualTo: userId)
        .limit(80);
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _getUnreadOrRecent(
    String field,
    String userId,
  ) async {
    try {
      return await _unreadQuery(
        field,
        userId,
      ).get().timeout(const Duration(seconds: 1));
    } catch (_) {
      return _recentQuery(
        field,
        userId,
      ).get().timeout(const Duration(seconds: 1));
    }
  }

  Future<void> _refreshOnce() async {
    final userId = _userId;
    if (userId == null || _stopped) return;
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _unreadQuery('userId', userId)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 1));
        if (snap.docs.isEmpty) {
          snap = await _getUnreadOrRecent('userId', userId);
        }
      } catch (_) {
        snap = await _getUnreadOrRecent('userId', userId);
      }
      if (_stopped) return;
      _ingest(snap, isUserIdQuery: true);
    } catch (_) {}
  }

  void _ingest(
    QuerySnapshot<Map<String, dynamic>> snap, {
    required bool isUserIdQuery,
  }) {
    final next = <String, bool>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final type = (data['type'] as String? ?? '').toLowerCase();
      if (type == 'court_email_ingest') continue;
      if (type.startsWith('court_') && !type.contains('hearing')) continue;
      final queue =
          ((data['queueDocId'] ?? data['queuedDocId']) as String? ?? '')
              .toLowerCase();
      if (queue.contains('imap')) continue;
      next[doc.id] = data['isRead'] == true;
    }
    if (isUserIdQuery) {
      _fromUserId
        ..clear()
        ..addAll(next);
      _gotUserSnap = true;
    } else {
      _fromClientId
        ..clear()
        ..addAll(next);
      _gotClientSnap = true;
    }
    _emit();
  }

  void _emit() {
    final onCount = _onCount;
    if (_stopped || onCount == null) return;

    final merged = <String, bool>{..._fromUserId, ..._fromClientId};
    final unread = merged.values.where((isRead) => !isRead).length;
    if (_gotUserSnap || _gotClientSnap) {
      onCount(unread);
    } else {
      onCount(unread > 0 ? unread : _cachedPeek);
    }
  }

  void stop() {
    _stopped = true;
    _onCount = null;
    _userId = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
  }
}
