import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/hearing_calendar_fields.dart';
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
    this.caseNo,
  });

  final String rowKey;
  final String type;
  final String title;
  final String subtitle;
  final DateTime sortTime;
  final bool isRead;
  final String? notificationDocId;
  final String? hearingDocId;
  final String? caseNo;

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
        caseNo: caseNo,
      );

  LightweightReminderItem asUnread() => LightweightReminderItem(
        rowKey: rowKey,
        type: type,
        title: title,
        subtitle: subtitle,
        sortTime: sortTime,
        isRead: false,
        notificationDocId: notificationDocId,
        hearingDocId: hearingDocId,
        caseNo: caseNo,
      );

  /// Same court order saved twice a few minutes apart (two OCR pages).
  String? get duplicateCaseKey {
    if (!isHearing) return null;
    final stored = (caseNo ?? '').trim();
    final source = stored.isNotEmpty ? stored : title;
    final numbers = RegExp(r'\d{2,}').allMatches(source);
    if (numbers.isEmpty) return null;
    return numbers.last.group(0);
  }

  static const Duration duplicateWindow = Duration(minutes: 30);

  /// Keeps the newest row when the same case arrives more than once.
  static List<LightweightReminderItem> collapseSameCase(
    List<LightweightReminderItem> items,
  ) {
    final sorted = List<LightweightReminderItem>.from(items)
      ..sort((a, b) => b.sortTime.compareTo(a.sortTime));
    final kept = <LightweightReminderItem>[];
    for (final item in sorted) {
      final key = item.duplicateCaseKey;
      if (key == null) {
        kept.add(item);
        continue;
      }
      final twinIndex = kept.indexWhere((other) {
        if (other.duplicateCaseKey != key) return false;
        return other.sortTime.difference(item.sortTime).abs() <= duplicateWindow;
      });
      if (twinIndex < 0) {
        kept.add(item);
        continue;
      }
      if (!item.isRead && kept[twinIndex].isRead) {
        kept[twinIndex] = kept[twinIndex].asUnread();
      }
    }
    return kept;
  }

  static String truncate(String? text, [int max = 140]) {
    final t = text?.trim() ?? '';
    if (t.isEmpty) return '';
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1)}…';
  }

  static String subtitleFromMap(Map<String, dynamic> data) {
    final summary = HearingCalendarFields.asDisplayString(data['summary']);
    if (summary.isNotEmpty) return truncate(summary);
    final message = HearingCalendarFields.asDisplayString(data['message']);
    if (message.isNotEmpty) return truncate(message);
    final caseNo = HearingCalendarFields.asDisplayString(data['caseNo']);
    if (caseNo.isNotEmpty) return 'Case $caseNo';
    final activity = HearingCalendarFields.asDisplayString(data['activityType']);
    if (activity.isNotEmpty) return truncate(activity);
    return '';
  }

  static LightweightReminderItem? fromNotificationDoc(
    String id,
    Map<String, dynamic> data,
  ) {
    final fsType = HearingCalendarFields.asDisplayString(data['type']).toLowerCase();
    final ts = (data['createdAt'] as Timestamp?)?.toDate() ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final storedTitle = HearingCalendarFields.asDisplayString(data['title']);
    return LightweightReminderItem(
      rowKey: id,
      notificationDocId: id,
      hearingDocId: HearingCalendarFields.asDisplayString(data['hearingDocId']),
      caseNo: HearingCalendarFields.asDisplayString(data['caseNo']),
      type: fsType,
      title: storedTitle.isNotEmpty ? storedTitle : 'Reminder',
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
    final caseNo = HearingCalendarFields.asDisplayString(hd['caseNo']);
    final ts = (hd['createdAt'] as Timestamp?)?.toDate() ??
        (hd['updatedAt'] as Timestamp?)?.toDate() ??
        DateTime.now();
    return LightweightReminderItem(
      rowKey: 'hearing_$hearingId',
      hearingDocId: hearingId,
      caseNo: caseNo,
      type: 'hearing_activity',
      title: caseNo.isNotEmpty ? 'Court hearing — $caseNo' : 'Court hearing / order',
      subtitle: subtitleFromMap(hd),
      sortTime: ts,
      isRead: isRead,
    );
  }

  static LightweightReminderItem? fromHearingStub(Map<String, dynamic> stub) {
    final hearingId = HearingCalendarFields.asDisplayString(stub['id']);
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
