import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../services/hearing_calendar_fields.dart';

/// Builds readable notification text and field lists from `hearings` documents.
class HearingNotificationFormatter {
  HearingNotificationFormatter._();

  static const _orderedKeys = <String, String>{
    'caseNo': 'Case No.',
    'caseTitle': 'Case title',
    'clientName': 'Client',
    'courtBranch': 'Court / Branch',
    'documentType': 'Document type',
    'hearingDate': 'Hearing date',
    'hearingTime': 'Hearing time',
    'hearingDateTime': 'Hearing date & time',
    'location': 'Location',
    'judgeName': 'Judge',
    'summary': 'Summary',
    'activityType': 'Activity',
    'senderName': 'From',
    'message': 'Message',
    'fullText': 'Order / full text',
    'createdAt': 'Recorded',
    'updatedAt': 'Last updated',
  };

  static const _skipKeys = <String>{
    'clientFanoutComplete',
    'involvedClientIds',
    'matchedClientIds',
    'ownerClientId',
    'notifyUserIds',
    'staffId',
    'staffAssigned',
  };

  /// Fields shown on attorney/staff hybrid calendar (from `hearings` only).
  static const calendarHearingKeys = <String, String>{
    'caseNo': 'Case No.',
    'caseTitle': 'Case title',
    'clientName': 'Client',
    'hearingTime': 'Hearing time',
    'location': 'Location',
  };

  /// Subset of a hearing / calendar row for UI (no id, title, description, etc.).
  static String _calendarFieldText(Map<String, dynamic> source, String key) {
    final v = source[key];
    if (v is String) return v.trim();
    if (v is Timestamp) {
      final d = v.toDate();
      if (key == 'hearingTime') return DateFormat('h:mm a').format(d);
      return DateFormat('MMMM d, yyyy').format(d);
    }
    if (v is DateTime) {
      if (key == 'hearingTime') return DateFormat('h:mm a').format(v);
      return DateFormat('MMMM d, yyyy').format(v);
    }
    return '';
  }

  static Map<String, dynamic> pickCalendarHearingFields(
    Map<String, dynamic> source,
  ) {
    final out = <String, dynamic>{};
    for (final key in calendarHearingKeys.keys) {
      final text = _calendarFieldText(source, key);
      if (text.isNotEmpty) out[key] = text;
    }
    return out;
  }

  /// Labeled rows for calendar cards and detail dialogs.
  static List<MapEntry<String, String>> fieldsForCalendarHearing(
    Map<String, dynamic> data,
  ) {
    final rows = <MapEntry<String, String>>[];
    for (final entry in calendarHearingKeys.entries) {
      final text = _formatValue(entry.key, data[entry.key]);
      if (text == null || text.isEmpty) continue;
      rows.add(MapEntry(entry.value, text));
    }
    return rows;
  }

  /// Copies hearing fields onto a `notifications` document for structured UI.
  static Map<String, dynamic> copyHearingFieldsForNotification(
    Map<String, dynamic> hearing, {
    List<Map<String, dynamic>> caseMaps = const [],
  }) {
    final rawTitle = (hearing['caseTitle'] as String?)?.trim() ?? '';
    final seed = Map<String, dynamic>.from(hearing);
    if (rawTitle.isEmpty ||
        HearingCalendarFields.isLowQualityCaseTitle(rawTitle)) {
      seed.remove('caseTitle');
    }
    final prepared = HearingCalendarFields.prepareForNotificationDisplay(
      seed,
      caseMaps: caseMaps,
    );
    final out = <String, dynamic>{};
    for (final key in _orderedKeys.keys) {
      if (_skipKeys.contains(key)) continue;
      final v = prepared[key] ?? (key == 'caseTitle' ? null : hearing[key]);
      if (v == null) continue;
      if (v is Timestamp) {
        out[key] = v;
      } else if (v is String && v.trim().isNotEmpty) {
        out[key] = v.trim();
      } else if (v is num || v is bool) {
        out[key] = v;
      }
    }
    final title = HearingCalendarFields.fieldAsDisplayString(
      prepared,
      'caseTitle',
    );
    if (title.isNotEmpty &&
        !HearingCalendarFields.isLowQualityCaseTitle(title)) {
      out['caseTitle'] = title;
    }
    return out;
  }

  /// Label + value rows for detail panels (ordered, de-duplicated).
  static List<MapEntry<String, String>> fieldsFromMap(Map<String, dynamic> data) {
    final used = <String>{};
    final rows = <MapEntry<String, String>>[];

    void add(String key, String label) {
      if (_skipKeys.contains(key) || used.contains(key)) return;
      final text = _formatValue(key, data[key]);
      if (text == null || text.isEmpty) return;
      used.add(key);
      rows.add(MapEntry(label, text));
    }

    final hasHearingDate = _formatValue('hearingDate', data['hearingDate']) != null;
    final hasHearingTime = _formatValue('hearingTime', data['hearingTime']) != null;

    for (final entry in _orderedKeys.entries) {
      if (entry.key == 'hearingDateTime' && (hasHearingDate || hasHearingTime)) {
        continue;
      }
      add(entry.key, entry.value);
    }

    // Any other primitive fields from Firestore (future-proof).
    for (final key in data.keys) {
      if (used.contains(key) || _skipKeys.contains(key)) continue;
      if (_orderedKeys.containsKey(key)) continue;
      final v = data[key];
      if (v is Map || v is List) continue;
      final text = _formatValue(key, v);
      if (text == null || text.isEmpty) continue;
      used.add(key);
      rows.add(MapEntry(_humanizeKey(key), text));
    }

    return rows;
  }

  /// Labeled rows for hearing notification detail (no duplicate Message wall).
  static List<MapEntry<String, String>> fieldsForHearingNotificationDetail(
    Map<String, dynamic> data,
  ) {
    final prepared = Map<String, dynamic>.from(data);
    final rawTitle = HearingCalendarFields.fieldAsDisplayString(
      prepared,
      'caseTitle',
    );
    if (rawTitle.isEmpty ||
        HearingCalendarFields.isLowQualityCaseTitle(rawTitle)) {
      prepared.remove('caseTitle');
    }
    var title = HearingCalendarFields.fieldAsDisplayString(prepared, 'caseTitle');
    if (title.isEmpty || HearingCalendarFields.isLowQualityCaseTitle(title)) {
      HearingCalendarFields.applyResolvedCaseTitle(prepared);
      title = HearingCalendarFields.fieldAsDisplayString(prepared, 'caseTitle');
    }
    if (title.isEmpty || HearingCalendarFields.isLowQualityCaseTitle(title)) {
      final reprepared = HearingCalendarFields.prepareForNotificationDisplay(
        Map<String, dynamic>.from(data)..remove('caseTitle'),
      );
      for (final key in calendarHearingKeys.keys) {
        final v = HearingCalendarFields.fieldAsDisplayString(reprepared, key);
        if (v.isNotEmpty) prepared[key] = v;
      }
    }

    final rows = <MapEntry<String, String>>[];
    final used = <String>{};

    void add(String key, String label) {
      if (used.contains(label)) return;
      var text = _formatValue(key, prepared[key]);
      if ((text == null || text.isEmpty) && key != 'caseTitle') {
        text = _formatValue(key, data[key]);
      }
      if (text == null || text.isEmpty) return;
      if (key == 'caseTitle' &&
          HearingCalendarFields.isLowQualityCaseTitle(text)) {
        return;
      }
      used.add(label);
      rows.add(MapEntry(label, text));
    }

    for (final entry in calendarHearingKeys.entries) {
      add(entry.key, entry.value);
    }
    add('hearingDate', 'Hearing date');
    add('summary', 'Summary');
    add('documentType', 'Document type');
    add('senderName', 'From');

    final fullText = _formatValue('fullText', prepared['fullText'] ?? data['fullText']);
    if (fullText != null && fullText.isNotEmpty) {
      rows.add(MapEntry('Order / full text', fullText));
    }

    if (rows.isNotEmpty) return rows;

    final merged = Map<String, dynamic>.from(prepared);
    final fromMessage = _parseLegacyMessage(data['message'] as String?);
    for (final e in fromMessage.entries) {
      merged.putIfAbsent(e.key, () => e.value);
    }
    return fieldsFromMap(merged)
        .where((r) => r.key != 'Message')
        .toList();
  }

  /// Merges notification doc fields; falls back to parsing legacy `message` text.
  static List<MapEntry<String, String>> fieldsFromNotificationData(
    Map<String, dynamic> data,
  ) {
    final hearingDocId = (data['hearingDocId'] as String?)?.trim() ?? '';
    final type = (data['type'] as String?)?.toLowerCase() ?? '';
    if (hearingDocId.isNotEmpty || type.contains('hearing')) {
      return fieldsForHearingNotificationDetail(data);
    }

    final merged = Map<String, dynamic>.from(data);
    final fromMessage = _parseLegacyMessage(data['message'] as String?);
    for (final e in fromMessage.entries) {
      merged.putIfAbsent(e.key, () => e.value);
    }
    return fieldsFromMap(merged);
  }

  /// Short subtitle for list rows.
  static String buildSummary(Map<String, dynamic> d) {
    final summary = (d['summary'] as String?)?.trim();
    if (summary != null && summary.isNotEmpty) return summary;

    final parts = <String>[];
    final loc = (d['location'] as String?)?.trim();
    final hd = _formatValue('hearingDate', d['hearingDate']);
    final ht = _formatValue('hearingTime', d['hearingTime']);
    final cl = (d['clientName'] as String?)?.trim();
    final cn = (d['caseNo'] as String?)?.trim();
    final br = (d['courtBranch'] as String?)?.trim();

    if (loc != null && loc.isNotEmpty) parts.add(loc);
    if (hd != null && hd.isNotEmpty) {
      parts.add(ht != null && ht.isNotEmpty ? '$hd · $ht' : hd);
    }
    if (cl != null && cl.isNotEmpty) parts.add(cl);
    if (br != null && br.isNotEmpty) parts.add(br);
    if (cn != null && cn.isNotEmpty && !parts.contains(cn)) parts.add(cn);

    if (parts.isNotEmpty) return parts.take(4).join(' • ');

    final msg = (d['message'] as String?)?.trim() ?? '';
    if (msg.isNotEmpty) {
      final first = msg.split('\n').first.trim();
      if (first.length > 100) return '${first.substring(0, 97)}...';
      return first;
    }
    return (d['caseTitle'] as String?)?.trim() ??
        cn ??
        'Court hearing notice';
  }

  /// Rows shown on calendar day cards (`hearings` fields only).
  static List<MapEntry<String, String>> calendarPreviewLines(
    Map<String, dynamic> data, {
    int maxLines = 8,
  }) {
    final rows = fieldsForCalendarHearing(data);
    if (rows.length <= maxLines) return rows;
    return rows.sublist(0, maxLines);
  }

  static String buildBody(Map<String, dynamic> d) {
    final rows = fieldsFromMap(d);
    if (rows.isEmpty) return 'Court hearing notice';

    final buffer = StringBuffer();
    for (final row in rows) {
      if (row.key == 'Order / full text') {
        buffer.writeln();
        buffer.writeln('${row.key}:');
        buffer.writeln(row.value);
      } else {
        buffer.writeln('${row.key}: ${row.value}');
      }
    }
    var text = buffer.toString().trim();
    if (text.length > 12000) {
      text = '${text.substring(0, 11997)}...';
    }
    return text;
  }

  static String? _formatValue(String key, dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) {
      if (key == 'hearingDateTime' &&
          value.toDate().millisecondsSinceEpoch == 0) {
        return null;
      }
      return DateFormat('MMMM dd, yyyy • hh:mm a').format(value.toDate());
    }
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is num) return value.toString();
    if (value is! String) return null;
    final t = value.trim();
    if (t.isEmpty) return null;
    return t;
  }

  static String _humanizeKey(String key) {
    if (key.isEmpty) return key;
    final spaced = key
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}')
        .replaceAll('_', ' ')
        .trim();
    if (spaced.isEmpty) return key;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  static Map<String, String> _parseLegacyMessage(String? message) {
    final out = <String, String>{};
    if (message == null || message.trim().isEmpty) return out;

    const labelToKey = {
      'Case No.': 'caseNo',
      'Client': 'clientName',
      'Court / Branch': 'courtBranch',
      'Location': 'location',
      'Summary': 'summary',
      'Hearing date': 'hearingDate',
      'Hearing time': 'hearingTime',
      'Judge': 'judgeName',
    };

    for (final line in message.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed == 'Order / notice:') continue;
      final colon = trimmed.indexOf(':');
      if (colon <= 0) continue;
      final label = trimmed.substring(0, colon).trim();
      final val = trimmed.substring(colon + 1).trim();
      if (val.isEmpty) continue;
      final key = labelToKey[label];
      if (key != null) out[key] = val;
    }
    return out;
  }
}
