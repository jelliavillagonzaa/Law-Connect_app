import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/lightweight_reminder_item.dart';
import 'hearing_notification_fanout_service.dart';

/// Shared staff/attorney reminders loader — notifications first, then global hearings.
class LightweightRemindersInboxService {
  LightweightRemindersInboxService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const int inboxLimit = 35;

  static bool _isCourtEmailSpam(Map<String, dynamic> data) {
    return clientCourtEmailSpamNotification(data);
  }

  static String _stringFrom(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    if (value is String) return value;
    return value.toString();
  }

  static Future<List<LightweightReminderItem>> loadNotificationReminders(
    String userId,
  ) async {
    if (userId.isEmpty) return const [];

    Query<Map<String, dynamic>> query =
        _firestore.collection('notifications').where('userId', isEqualTo: userId);

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await query
          .orderBy('createdAt', descending: true)
          .limit(inboxLimit)
          .get();
    } catch (_) {
      snap = await query.limit(inboxLimit).get();
    }

    final reminders = <LightweightReminderItem>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final fsType = _stringFrom(data['type']).toLowerCase();
      if (_isCourtEmailSpam(data)) continue;
      if (!hearingOrAppointmentBellType(fsType)) continue;
      final item = LightweightReminderItem.fromNotificationDoc(doc.id, data);
      if (item != null) reminders.add(item);
    }
    reminders.sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return reminders;
  }

  static Future<List<LightweightReminderItem>> mergeGlobalHearings(
    String userId,
    List<LightweightReminderItem> existing, {
    int? hearingsLimit,
  }) async {
    if (userId.isEmpty) return existing;

    final limit = hearingsLimit ?? (kIsWeb ? 10 : 5);

    final covered = <String>{
      for (final item in existing)
        if (item.hearingDocId != null && item.hearingDocId!.isNotEmpty)
          item.hearingDocId!,
    };
    final readIds =
        await HearingNotificationFanoutService.instance.staffReadHearingIds(
      userId,
    );

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _firestore
          .collection('hearings')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get()
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      snap = await _firestore
          .collection('hearings')
          .limit(limit)
          .get()
          .timeout(const Duration(seconds: 8));
    }

    final stubs = <Map<String, dynamic>>[];
    for (var i = 0; i < snap.docs.length; i++) {
      final doc = snap.docs[i];
      if (covered.contains(doc.id)) continue;
      final hd = doc.data();
      if (!HearingNotificationFanoutService.isDisplayableHearingRow(hd)) {
        continue;
      }
      unawaited(
        HearingNotificationFanoutService.instance.queueDevicePushIfMissing(
          doc.id,
          hd,
        ),
      );
      stubs.add({
        'id': doc.id,
        'caseNo': hd['caseNo'],
        'summary': hd['summary'],
        'activityType': hd['activityType'],
        'caseId': hd['caseId'],
        'clientName': hd['clientName'],
        'createdAtMs': hd['createdAt'] is Timestamp
            ? (hd['createdAt'] as Timestamp).millisecondsSinceEpoch
            : DateTime.tryParse('${hd['createdAt'] ?? ''}')?.millisecondsSinceEpoch,
        'updatedAtMs': hd['updatedAt'] is Timestamp
            ? (hd['updatedAt'] as Timestamp).millisecondsSinceEpoch
            : DateTime.tryParse('${hd['updatedAt'] ?? ''}')?.millisecondsSinceEpoch,
        'isRead': readIds.contains(doc.id),
      });
      if (i.isOdd) await Future<void>.delayed(Duration.zero);
    }

    final keys = existing.map((r) => r.rowKey).toSet();
    final merged = List<LightweightReminderItem>.from(existing);
    for (final stub in stubs) {
      final item = LightweightReminderItem.fromHearingStub(stub);
      if (item != null && keys.add(item.rowKey)) merged.add(item);
    }
    merged.sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return merged;
  }

  /// Unread inbox rows from notification docs already loaded.
  /// Same-case hearings inside 30 minutes count once.
  static int unreadCountFromNotificationDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final reminders = <LightweightReminderItem>[];
    var otherUnread = 0;
    for (final doc in docs) {
      final data = doc.data();
      final fsType = _stringFrom(data['type']).toLowerCase();
      if (_isCourtEmailSpam(data)) continue;
      if (fsType == 'court_email_ingest' || fsType.startsWith('court_')) {
        continue;
      }
      if (hearingOrAppointmentBellType(fsType)) {
        final item = LightweightReminderItem.fromNotificationDoc(doc.id, data);
        if (item != null) reminders.add(item);
      } else if (data['isRead'] != true) {
        otherUnread++;
      }
    }
    return otherUnread + reminders.where((item) => !item.isRead).length;
  }

  /// Unread notices for the staff bell. Notification docs only — a slow
  /// hearings scan must not leave the badge at zero.
  static Future<int> countUnreadReminders(String userId) async {
    if (userId.isEmpty) return 0;
    final query = _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId);
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await query
          .orderBy('createdAt', descending: true)
          .limit(60)
          .get()
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      snap = await query.limit(60).get().timeout(const Duration(seconds: 6));
    }
    return unreadCountFromNotificationDocs(snap.docs);
  }
}
