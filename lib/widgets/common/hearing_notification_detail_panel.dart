import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../services/hearing_calendar_fields.dart';
import '../../utils/hearing_notification_formatter.dart';

final Map<String, Future<Map<String, dynamic>>> _enrichedHearingFutures =
    <String, Future<Map<String, dynamic>>>{};

/// Structured hearing details (all Firestore fields, labeled rows).
Future<Map<String, dynamic>> _loadEnrichedHearing(
  String hearingDocId,
  Map<String, dynamic> seed, {
  List<Map<String, dynamic>> siblingRows = const [],
}) async {
  try {
    Map<String, dynamic> hd = <String, dynamic>{};
    final snap = await FirebaseFirestore.instance
        .collection('hearings')
        .doc(hearingDocId)
        .get();
    if (snap.exists && snap.data() != null) {
      hd = snap.data()!;
    } else if (seed.isNotEmpty) {
      hd = Map<String, dynamic>.from(seed);
    }

    final seedCaseNo = (seed['caseNo'] as String?)?.trim() ?? '';
    if (seedCaseNo.isNotEmpty) {
      hd['caseNo'] = seedCaseNo;
    }
    final seedClient = (seed['clientName'] as String?)?.trim() ?? '';
    if (seedClient.isNotEmpty) {
      hd['clientName'] = seedClient;
    }

    final caseMaps = await HearingCalendarFields.loadCaseMapsForHearing(hd);
    final merged = await HearingCalendarFields.loadMergedHearingForDisplay(
      hearingDocId: hearingDocId,
      hearingData: hd,
      caseMaps: caseMaps,
      siblingRows: siblingRows,
    );
    if (merged.isNotEmpty) return merged;
    final prepared =
        await HearingCalendarFields.prepareForNotificationDisplayAsync(hd);
    return prepared;
  } catch (_) {
    final fallback = await FirebaseFirestore.instance
        .collection('hearings')
        .doc(hearingDocId)
        .get();
    if (fallback.exists && fallback.data() != null) {
      return HearingCalendarFields.prepareForNotificationDisplayAsync(
        fallback.data()!,
      );
    }
    return HearingCalendarFields.mergeHearingSources(
      [if (seed.isNotEmpty) seed, ...siblingRows],
    );
  }
}

Future<Map<String, dynamic>> _cachedEnrichedHearing(
  String hearingDocId,
  Map<String, dynamic> seed, {
  List<Map<String, dynamic>> siblingRows = const [],
}) {
  return _enrichedHearingFutures.putIfAbsent(
    hearingDocId,
    () => _loadEnrichedHearing(hearingDocId, seed, siblingRows: siblingRows),
  );
}

class HearingNotificationDetailPanel extends StatelessWidget {
  const HearingNotificationDetailPanel({
    super.key,
    required this.data,
    this.hearingDocId,
    this.calendarOnly = false,
    this.siblingRows = const [],
  });

  final Map<String, dynamic> data;
  final String? hearingDocId;

  /// When true, only [HearingNotificationFormatter.calendarHearingKeys] are shown.
  final bool calendarOnly;

  /// Overlay / inbox rows with the same [caseNo] (avoids broad `hearings` scans).
  final List<Map<String, dynamic>> siblingRows;

  List<MapEntry<String, String>> _fieldsFrom(Map<String, dynamic> hearing) {
    return calendarOnly
        ? HearingNotificationFormatter.fieldsForCalendarHearing(hearing)
        : HearingNotificationFormatter.fieldsForHearingNotificationDetail(
            hearing,
          );
  }

  @override
  Widget build(BuildContext context) {
    final hid = (hearingDocId ?? data['hearingDocId'] as String?)?.trim();
    final seedFields = calendarOnly
        ? HearingNotificationFormatter.fieldsForCalendarHearing(data)
        : HearingNotificationFormatter.fieldsFromNotificationData(data);

    if (hid == null || hid.isEmpty) {
      return _FieldsList(fields: seedFields);
    }

    // Web reminders: notification row already has display fields — skip extra Firestore reads.
    if (kIsWeb && seedFields.isNotEmpty) {
      return _FieldsList(fields: seedFields);
    }

    if (seedFields.length >= 3) {
      return FutureBuilder<Map<String, dynamic>>(
        future: _cachedEnrichedHearing(hid, data, siblingRows: siblingRows),
        builder: (context, snap) {
          final fields = (snap.hasData && snap.data!.isNotEmpty)
              ? _fieldsFrom(snap.data!)
              : seedFields;
          return _FieldsList(fields: fields);
        },
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _cachedEnrichedHearing(hid, data, siblingRows: siblingRows),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snap.hasData && snap.data!.isNotEmpty) {
          return _FieldsList(fields: _fieldsFrom(snap.data!));
        }
        return _FieldsList(fields: seedFields);
      },
    );
  }
}

class _FieldsList extends StatelessWidget {
  const _FieldsList({required this.fields});

  final List<MapEntry<String, String>> fields;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
      return Text(
        'No hearing details available.',
        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
      );
    }

    final regular = <MapEntry<String, String>>[];
    String? fullText;

    for (final row in fields) {
      if (row.key == 'Order / full text') {
        fullText = row.value;
      } else {
        regular.add(row);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...regular.map((row) => _DetailRow(label: row.key, value: row.value)),
        if (fullText != null && fullText.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Order / full text',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.royalBlue,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(
              child: SelectableText(
                fullText,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Colors.grey[850],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Colors.grey[900],
            ),
          ),
        ],
      ),
    );
  }
}
