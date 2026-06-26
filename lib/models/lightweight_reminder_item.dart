import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/hearing_notification_fanout_service.dart';

/// Small reminder row for staff/attorney inbox lists — no OCR blobs in memory.
class LightweightReminderItem {
  const LightweightReminderItem({
    required this.rowKey,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.sortTime,
    required this.isRead,
    this.notificationDocId,
    this.hearingDocId,
  });

  final String rowKey;
  final String type;
  final String title;
  final String subtitle;
  final DateTime sortTime;
  final bool isRead;
  final String? notificationDocId;
  final String? hearingDocId;

  bool get isHearing =>
      type.contains('hearing') ||
      (hearingDocId != null && hearingDocId!.isNotEmpty);

  LightweightReminderItem markRead() => LightweightReminderItem(
        rowKey: rowKey,
        type: type,
        title: title,
        subtitle: subtitle,
        sortTime: sortTime,
        isRead: true,
        notificationDocId: notificationDocId,
        hearingDocId: hearingDocId,
      );

  static String truncate(String? text, [int max = 140]) {
    final t = text?.trim() ?? '';
    if (t.isEmpty) return '';
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1)}…';
  }

  static String subtitleFromMap(Map<String, dynamic> data) {
    final summary = (data['summary'] as String?)?.trim();
    if (summary != null && summary.isNotEmpty) return truncate(summary);
    final caseNo = (data['caseNo'] as String?)?.trim();
    if (caseNo != null && caseNo.isNotEmpty) return 'Case $caseNo';
    final activity = (data['activityType'] as String?)?.trim();
    if (activity != null && activity.isNotEmpty) return truncate(activity);
    return '';
  }

  static LightweightReminderItem? fromNotificationDoc(
    String id,
    Map<String, dynamic> data,
  ) {
    final fsType = (data['type'] as String? ?? '').toLowerCase();
    final ts = (data['createdAt'] as Timestamp?)?.toDate() ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return LightweightReminderItem(
      rowKey: id,
      notificationDocId: id,
      hearingDocId: (data['hearingDocId'] as String?)?.trim(),
      type: fsType,
      title: ((data['title'] as String?)?.trim().isNotEmpty == true)
          ? (data['title'] as String).trim()
          : 'Reminder',
      subtitle: subtitleFromMap(data),
      sortTime: ts,
      isRead: data['isRead'] == true,
    );
  }

  static LightweightReminderItem? fromHearingDoc(
    String hearingId,
    Map<String, dynamic> hd, {
    required bool isRead,
  }) {
    if (!HearingNotificationFanoutService.isDisplayableHearingRow(hd)) {
      return null;
    }
    final caseNo = (hd['caseNo'] as String?)?.trim() ?? '';
    final ts = (hd['createdAt'] as Timestamp?)?.toDate() ??
        (hd['updatedAt'] as Timestamp?)?.toDate() ??
        DateTime.now();
    return LightweightReminderItem(
      rowKey: 'hearing_$hearingId',
      hearingDocId: hearingId,
      type: 'hearing_activity',
      title: caseNo.isNotEmpty ? 'Court hearing — $caseNo' : 'Court hearing / order',
      subtitle: subtitleFromMap(hd),
      sortTime: ts,
      isRead: isRead,
    );
  }

  static LightweightReminderItem? fromHearingStub(Map<String, dynamic> stub) {
    final hearingId = stub['id'] as String? ?? '';
    if (hearingId.isEmpty) return null;
    final hd = <String, dynamic>{
      if (stub['caseNo'] != null) 'caseNo': stub['caseNo'],
      if (stub['summary'] != null) 'summary': stub['summary'],
      if (stub['activityType'] != null) 'activityType': stub['activityType'],
      if (stub['caseId'] != null) 'caseId': stub['caseId'],
      if (stub['clientName'] != null) 'clientName': stub['clientName'],
      if (stub['createdAtMs'] != null)
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(
          stub['createdAtMs'] as int,
        ),
      if (stub['updatedAtMs'] != null)
        'updatedAt': Timestamp.fromMillisecondsSinceEpoch(
          stub['updatedAtMs'] as int,
        ),
    };
    return fromHearingDoc(
      hearingId,
      hd,
      isRead: stub['isRead'] == true,
    );
  }

  /// Minimal [HearingInboxRow] for attorney reminders UI (detail loads on expand).
  HearingInboxRow toInboxRow() {
    return HearingInboxRow(
      rowKey: rowKey,
      notificationDocId: notificationDocId,
      data: {
        'type': type,
        'title': title,
        'summary': subtitle,
        'message': '',
        if (hearingDocId != null) 'hearingDocId': hearingDocId,
        'isRead': isRead,
        'createdAt': Timestamp.fromDate(sortTime),
        '_lightweight': true,
      },
      sortTime: sortTime,
    );
  }
}
