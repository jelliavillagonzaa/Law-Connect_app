import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hearing_notification_fanout_service.dart';

/// Single source of truth for attorney Reminders unread + dashboard bell.
///
/// Mark read persists row keys (not timestamps). Appointment dates in the
/// future must not become unread again after Mark read.
class AttorneyInboxReadStore {
  AttorneyInboxReadStore._();
  static final AttorneyInboxReadStore instance = AttorneyInboxReadStore._();

  static const _prefsPrefix = 'attorney_read_keys_v1_';
  static const _maxKeys = 800;

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);
  final Set<String> _keys = <String>{};
  String? _uid;
  bool _loaded = false;
  bool _serverLoaded = false;

  Future<void> ensureLoaded(String userId, {bool server = true}) async {
    if (userId.isEmpty) return;
    final userChanged = _uid != userId;
    if (userChanged) {
      _serverLoaded = false;
    }
    _uid = userId;
    if (!_loaded || userChanged) {
      _keys.clear();
      try {
        final prefs = await SharedPreferences.getInstance();
        _keys.addAll(prefs.getStringList('$_prefsPrefix$userId') ?? const []);
      } catch (_) {}
      _loaded = true;
    }
    if (!server || (_serverLoaded && !userChanged)) return;
    _serverLoaded = true;
    // Load read keys from Firestore once to survive logout/login and new sessions
    try {
      final doc = await FirebaseFirestore.instance
          .collection('notifications')
          .doc('attorney_read_keys_$userId')
          .get()
          .timeout(const Duration(seconds: 4));
      final raw = doc.data()?['keys'];
      if (raw is List) {
        for (final k in raw) {
          final s = '$k'.trim();
          if (s.isNotEmpty) _keys.add(s);
        }
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('$_prefsPrefix$userId', _keys.toList());
        } catch (_) {}
      }
    } catch (_) {}
  }

  bool isRead(HearingInboxRow row) {
    if (row.data['isRead'] == true) return true;
    if (_keys.contains(row.rowKey)) return true;
    if (row.rowKey.startsWith('hearing_')) {
      final stripped = row.rowKey.substring('hearing_'.length);
      if (_keys.contains(stripped)) return true;
    }
    if (row.rowKey.startsWith('hn_')) {
      final stripped = row.rowKey.substring('hn_'.length);
      if (_keys.contains(stripped)) return true;
    }
    if (row.rowKey.startsWith('appt_')) {
      final stripped = row.rowKey.substring('appt_'.length);
      if (_keys.contains(stripped)) return true;
    }
    final nid = row.notificationDocId?.trim() ?? '';
    if (nid.isNotEmpty && _keys.contains(nid)) return true;
    final hid = (row.data['hearingDocId'] as String?)?.trim() ?? '';
    if (hid.isNotEmpty &&
        (_keys.contains(hid) || _keys.contains('hearing_$hid'))) {
      return true;
    }
    return false;
  }

  HearingInboxRow withReadFlag(HearingInboxRow row) {
    if (!row.isUnread || !isRead(row)) return row;
    return HearingInboxRow(
      rowKey: row.rowKey,
      notificationDocId: row.notificationDocId,
      data: {...row.data, 'isRead': true},
      sortTime: row.sortTime,
    );
  }

  void remember(HearingInboxRow row) {
    _addKey(row.rowKey);
    final nid = row.notificationDocId?.trim() ?? '';
    if (nid.isNotEmpty) _addKey(nid);
    final hid = (row.data['hearingDocId'] as String?)?.trim() ?? '';
    if (hid.isNotEmpty) {
      _addKey(hid);
      _addKey('hearing_$hid');
    }
  }

  void syncFromRows(List<HearingInboxRow> rows) {
    final n = rows.where((r) => !isRead(r)).length;
    if (unreadCount.value != n) unreadCount.value = n;
  }

  Future<void> markAll(String userId, List<HearingInboxRow> rows) async {
    await ensureLoaded(userId);
    for (final row in rows) {
      remember(row);
    }
    unreadCount.value = 0;
    await _persist(userId);
  }

  Future<void> markOne(String userId, HearingInboxRow row) async {
    await ensureLoaded(userId);
    remember(row);
    await _persist(userId);
  }

  void _addKey(String key) {
    final k = key.trim();
    if (k.isEmpty) return;
    _keys.add(k);
  }

  Future<void> _persist(String userId) async {
    final list = _keys.take(_maxKeys).toList(growable: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('$_prefsPrefix$userId', list);
    } catch (_) {}
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc('attorney_read_keys_$userId')
          .set({
            'userId': userId,
            'type': 'attorney_read_keys',
            'isRead': true,
            'keys': list,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {}
  }
}
