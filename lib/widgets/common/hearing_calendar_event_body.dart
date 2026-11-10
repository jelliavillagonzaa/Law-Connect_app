import 'package:flutter/material.dart';

import '../../services/hearing_calendar_fields.dart';
import '../../utils/hearing_notification_formatter.dart';

/// Compact labeled rows for calendar day lists (attorney / staff).
class HearingCalendarEventBody extends StatelessWidget {
  const HearingCalendarEventBody({
    super.key,
    required this.data,
    this.maxLines = 8,
    this.dense = false,
  });

  final Map<String, dynamic> data;
  final int maxLines;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final rows = HearingNotificationFormatter.calendarPreviewLines(
      data,
      maxLines: maxLines,
    );
    if (rows.isEmpty) {
      return Text(
        'No hearing details',
        style: TextStyle(
          fontSize: dense ? 12 : 13,
          color: Colors.grey[600],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: dense ? 4 : 6),
          _LabeledValue(
            label: rows[i].key,
            value: rows[i].value,
            dense: dense,
          ),
        ],
      ],
    );
  }
}

class _LabeledValue extends StatelessWidget {
  const _LabeledValue({
    required this.label,
    required this.value,
    required this.dense,
  });

  final String label;
  final String value;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: dense ? 100 : 112,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: dense ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
              height: 1.3,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: dense ? 12 : 13,
              color: Colors.grey[900],
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// AI SCHD badge used on synced hearing calendar rows.
class HearingAiSchedBadge extends StatelessWidget {
  const HearingAiSchedBadge({super.key, this.compact = false});

  final bool compact;

  static const String label = 'AI SCHD';
  static const Color gold = Color(0xFFF4C10F);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: gold,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w800,
          color: Colors.black87,
        ),
      ),
    );
  }
}

/// Dialog / app bar title: case number, then client, then case caption.
String hearingCalendarDisplayTitle(Map<String, dynamic> ev) {
  final rawCaseNo = HearingCalendarFields.asDisplayString(ev['caseNo']).isNotEmpty
      ? HearingCalendarFields.asDisplayString(ev['caseNo'])
      : HearingCalendarFields.asDisplayString(ev['caseNumber']);
  final cleanNo = HearingCalendarFields.cleanCaseDocketNo(rawCaseNo);
  if (cleanNo.isNotEmpty &&
      !HearingCalendarFields.isPlaceholderCaseNo(cleanNo)) {
    return cleanNo;
  }
  final client = HearingCalendarFields.resolveClientForDisplay(ev);
  if (client.isNotEmpty) return client;
  final caseTitle = HearingCalendarFields.asDisplayString(ev['caseTitle']);
  if (caseTitle.isNotEmpty &&
      !HearingCalendarFields.isLowQualityCaseTitle(caseTitle)) {
    return caseTitle;
  }
  if (cleanNo.isNotEmpty) return cleanNo;
  if (rawCaseNo.isNotEmpty) return rawCaseNo;
  final t = HearingCalendarFields.asDisplayString(ev['title']);
  if (t.isNotEmpty) {
    return t.replaceFirst(RegExp(r'^\[AI\]\s*'), '');
  }
  return 'Hearing';
}

bool isAiSyncedCalendarEvent(Map<String, dynamic> ev) {
  const aiSources = {
    'email_ingest',
    'hearings_sync',
    'legal_assistant',
  };
  return aiSources.contains(ev['source'] as String?) ||
      (ev['readOnly'] == true &&
          (ev['hearingDocId'] as String?)?.isNotEmpty == true);
}

/// `calendar_events` copy of a hearing — use live `hearings` overlay instead.
bool isFirestoreSyncedHearingCalendarRow(Map<String, dynamic> ev) {
  if ((ev['hearingDocId'] as String?)?.trim().isNotEmpty == true) {
    return true;
  }
  return isAiSyncedCalendarEvent(ev);
}

bool isManualAttorneyCalendarHearing(Map<String, dynamic> ev) {
  if ((ev['source'] as String?) == 'attorney_manual') return true;
  return (ev['appointmentId'] as String?)?.trim().isNotEmpty == true;
}

/// Stale or synced court hearing row in `calendar_events` — never render on grid.
/// The calendar must show court hearings from the live `hearings` collection only.
bool isMirroredCourtHearingCalendarEvent(Map<String, dynamic> ev) {
  if ((ev['eventType'] as String?)?.toLowerCase() != 'hearing') {
    return false;
  }
  return !isManualAttorneyCalendarHearing(ev);
}
