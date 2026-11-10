import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../services/hearing_calendar_fields.dart';
import 'court_order_display.dart';
import 'hearing_sms_formatter.dart';

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
    'remarks': 'Remarks',
    'notes': 'Notes / Remarks',
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
      if (key == 'location') {
        var venue = HearingCalendarFields.resolveVenueForDisplay(source);
        if (venue.isEmpty) {
          venue = _calendarFieldText(source, 'location');
        }
        if (venue.isEmpty) {
          venue = _calendarFieldText(source, 'courtBranch');
        }
        if (venue.isNotEmpty) out['location'] = venue;
      } else {
        final text = _calendarFieldText(source, key);
        if (text.isNotEmpty) out[key] = text;
      }
    }
    return out;
  }

  /// Labeled rows for calendar cards and detail dialogs.
  static List<MapEntry<String, String>> fieldsForCalendarHearing(
    Map<String, dynamic> data,
  ) {
    final rows = <MapEntry<String, String>>[];
    for (final entry in calendarHearingKeys.entries) {
      String? text;
      if (entry.key == 'caseNo') {
        final rawCase = HearingCalendarFields.asDisplayString(data['caseNo']).isNotEmpty
            ? HearingCalendarFields.asDisplayString(data['caseNo'])
            : HearingCalendarFields.asDisplayString(data['caseNumber']);
        final cleanCase = HearingCalendarFields.cleanCaseDocketNo(rawCase);
        text = cleanCase.isNotEmpty ? cleanCase : _formatValue(entry.key, data[entry.key]);
      } else if (entry.key == 'caseTitle') {
        var title = HearingCalendarFields.asDisplayString(data['caseTitle']);
        if (!HearingCalendarFields.hasCaseCaptionMarker(title)) {
          final resolved = HearingCalendarFields.resolveCaseTitleForDisplay(data);
          if (resolved.isNotEmpty && HearingCalendarFields.hasCaseCaptionMarker(resolved)) {
            title = resolved;
          }
        }
        text = title.isNotEmpty ? title : _formatValue(entry.key, data[entry.key]);
      } else if (entry.key == 'clientName') {
        final resolvedClient = HearingCalendarFields.resolveClientForDisplay(data);
        text = resolvedClient.isNotEmpty
            ? resolvedClient
            : _formatValue(entry.key, data[entry.key]);
      } else if (entry.key == 'location') {
        var venue = HearingCalendarFields.resolveVenueForDisplay(data);
        if (venue.isEmpty) {
          final rawLoc = _formatValue('location', data['location']) ??
              _formatValue('courtBranch', data['courtBranch']) ??
              _formatValue('court', data['court']) ??
              _formatValue('court_branch', data['court_branch']) ??
              _formatValue('venue', data['venue']);
          if (rawLoc != null && rawLoc.isNotEmpty) {
            venue = rawLoc;
          }
        }
        text = venue.isNotEmpty ? venue : null;
      } else {
        text = _formatValue(entry.key, data[entry.key]);
      }
      if (text == null || text.isEmpty) continue;
      rows.add(MapEntry(entry.value, text));
    }
    return rows;
  }

  static String _s(dynamic v) => HearingCalendarFields.asDisplayString(v);

  /// Copies hearing fields onto a `notifications` document for structured UI.
  static Map<String, dynamic> copyHearingFieldsForNotification(
    Map<String, dynamic> hearing, {
    List<Map<String, dynamic>> caseMaps = const [],
  }) {
    final rawTitle = _s(hearing['caseTitle']);
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
      } else if (v is num) {
        out[key] = v.toString();
      } else if (v is bool) {
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
  ///
  /// [parseOrderText] runs OCR/order regex. Inbox expand must pass false so
  /// the UI isolate is not blocked by court-order blobs.
  static List<MapEntry<String, String>> fieldsForHearingNotificationDetail(
    Map<String, dynamic> data, {
    bool parseOrderText = true,
  }) {
    final prepared = parseOrderText
        ? HearingCalendarFields.prepareForNotificationDisplay(data)
        : Map<String, dynamic>.from(data);
    if (parseOrderText) {
      HearingCalendarFields.fillStructuredFieldsFromOrderText(prepared);
    }
    final currentLoc =
        HearingCalendarFields.fieldAsDisplayString(prepared, 'location');
    if (currentLoc.isEmpty || HearingCalendarFields.isBareLocation(currentLoc)) {
      final venue = HearingCalendarFields.resolveVenueForDisplay(data);
      if (venue.isNotEmpty && !HearingCalendarFields.isBareLocation(venue)) {
        prepared['location'] = venue;
      }
    }

    final fullOrderText = CourtOrderTextSources.combine({...data, ...prepared});

    if (_formatValue('hearingDate', prepared['hearingDate'])?.isEmpty ?? true) {
      final extractedDate = HearingCalendarFields.extractHearingDateFromOrderText(fullOrderText);
      if (extractedDate.isNotEmpty) {
        prepared['hearingDate'] = extractedDate;
      }
    }

    if (_formatValue('hearingTime', prepared['hearingTime'])?.isEmpty ?? true) {
      final extractedTime = HearingCalendarFields.extractHearingTimeFromOrderText(fullOrderText);
      if (extractedTime.isNotEmpty) {
        prepared['hearingTime'] = extractedTime;
      }
    }

    final proceeding = HearingCalendarFields.extractProceedingFromOrderText(fullOrderText);

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
      if (entry.key == 'clientName') {
        var text = _formatValue(entry.key, prepared[entry.key]);
        if ((text == null || text.isEmpty)) {
          text = _formatValue(entry.key, data[entry.key]);
        }
        if (text == null || text.isEmpty) continue;
        final parties = HearingCalendarFields.splitHearingPartyNames(text);
        final label = parties.length > 1 ? 'Involved Parties' : 'Involved Party';
        if (!used.contains(label)) {
          used.add(label);
          rows.add(MapEntry(label, text));
        }

        final role = HearingCalendarFields.detectPartyRole(
          clientName: text,
          caseTitle: _formatValue('caseTitle', prepared['caseTitle']) ??
              _formatValue('caseTitle', data['caseTitle']),
          fullText: fullOrderText,
        );
        if (role.isNotEmpty && !used.contains('Your Role / Status')) {
          used.add('Your Role / Status');
          rows.add(MapEntry('Your Role / Status', role));
        }
        continue;
      }
      if (entry.key == 'hearingTime') {
        add('hearingDate', 'Hearing date');
        add('hearingTime', 'Hearing time');
        continue;
      }
      add(entry.key, entry.value);
    }
    add('hearingDate', 'Hearing date');

    if (proceeding.isNotEmpty && !used.contains('Proceeding / Purpose')) {
      used.add('Proceeding / Purpose');
      rows.add(MapEntry('Proceeding / Purpose', proceeding));
    }

    var rawSummary = _formatValue('summary', prepared['summary']) ??
        _formatValue('summary', data['summary']) ?? '';
    if (rawSummary.isNotEmpty) {
      rawSummary = HearingCalendarFields.cleanSummaryText(rawSummary);
      if (rawSummary.isNotEmpty && !used.contains('Summary')) {
        used.add('Summary');
        rows.add(MapEntry('Summary', rawSummary));
      }
    }

    add('documentType', 'Document type');
    add('senderName', 'From');
    add('remarks', 'Remarks');
    add('notes', 'Notes / Remarks');

    var fullText = fullOrderText;
    if (fullText.isEmpty) {
      fullText = _formatValue(
            'fullText',
            prepared['fullText'] ?? data['fullText'],
          ) ??
          '';
    }
    if (CourtOrderTextSources.isInboxWrapper(fullText)) {
      fullText = '';
    }
    if (fullText.isNotEmpty) {
      rows.add(MapEntry('Order / full text', fullText));
    }

    if (rows.isNotEmpty) return rows;

    final merged = Map<String, dynamic>.from(prepared);
    final fromMessage = _parseLegacyMessage(_s(data['message']));
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
    final hearingDocId = _s(data['hearingDocId']);
    final type = _s(data['type']).toLowerCase();
    if (hearingDocId.isNotEmpty || type.contains('hearing')) {
      return fieldsForHearingNotificationDetail(data, parseOrderText: false);
    }

    final merged = Map<String, dynamic>.from(data);
    final fromMessage = _parseLegacyMessage(_s(data['message']));
    for (final e in fromMessage.entries) {
      merged.putIfAbsent(e.key, () => e.value);
    }
    return fieldsFromMap(merged);
  }

  /// Short subtitle for list rows.
  static String buildSummary(Map<String, dynamic> d) {
    final enriched = HearingCalendarFields.enrichForAlerts(d);
    final fullOrderText = CourtOrderTextSources.combine(enriched);
    final proceeding = HearingCalendarFields.extractProceedingFromOrderText(fullOrderText);

    final parts = <String>[];
    final loc = _s(enriched['location']);
    final br = _s(enriched['courtBranch']);
    final venue = loc.isNotEmpty ? loc : br;
    final hd = _formatValue('hearingDate', enriched['hearingDate']) ??
        HearingCalendarFields.extractHearingDateFromOrderText(fullOrderText);
    final ht = _formatValue('hearingTime', enriched['hearingTime']) ??
        HearingCalendarFields.extractHearingTimeFromOrderText(fullOrderText);

    if (proceeding.isNotEmpty) {
      parts.add(proceeding);
    }
    if (hd.isNotEmpty) {
      parts.add(ht.isNotEmpty ? '$hd · $ht' : hd);
    } else if (ht.isNotEmpty) {
      parts.add(ht);
    }
    if (venue.isNotEmpty) {
      parts.add(venue);
    }

    if (parts.isNotEmpty) {
      return parts.take(3).join(' • ');
    }

    final rawSummary = _s(enriched['summary']);
    if (rawSummary.isNotEmpty) {
      final clean = HearingCalendarFields.cleanSummaryText(rawSummary);
      if (clean.length > 120) {
        final dot = clean.lastIndexOf('.', 120);
        if (dot >= 40) return clean.substring(0, dot + 1).trim();
        return '${clean.substring(0, 117)}...';
      }
      return clean;
    }

    final msg = _s(d['message']);
    if (msg.isNotEmpty) {
      final first = msg.split('\n').first.trim();
      if (first.length > 100) return '${first.substring(0, 97)}...';
      return first;
    }
    final title = _s(d['caseTitle']);
    if (title.isNotEmpty) return title;
    final cn = _s(enriched['caseNo']);
    if (cn.isNotEmpty) return cn;
    return 'Court hearing notice';
  }

  /// Phone push / in-app popup body. Date is always the first line when known.
  static String buildPopupBody(Map<String, dynamic> data) {
    final existing = _s(data['message']).isNotEmpty
        ? _s(data['message'])
        : _s(data['body']);

    final enriched = HearingCalendarFields.enrichForAlerts(data);
    final caseNo = _s(enriched['caseNo']);
    final caseTitle = _s(enriched['caseTitle']);
    final clientName = _s(enriched['clientName']);
    final hearingDate = HearingCalendarFields.hearingFieldAsString(
      enriched,
      'hearingDate',
    );
    final hearingTime = HearingCalendarFields.hearingFieldAsString(
      enriched,
      'hearingTime',
    );
    final venue = HearingCalendarFields.resolveVenueForDisplay(enriched);
    final location = (venue.isNotEmpty &&
            !HearingCalendarFields.isBareLocation(venue))
        ? venue
        : (_s(enriched['location']).isNotEmpty
            ? _s(enriched['location'])
            : _s(enriched['courtBranch']));
    final hasFacts = caseNo.isNotEmpty ||
        caseTitle.isNotEmpty ||
        clientName.isNotEmpty ||
        hearingDate.isNotEmpty ||
        hearingTime.isNotEmpty ||
        location.isNotEmpty;

    if (!hasFacts) return _trimPopupExtras(existing);

    // Same copy as PhilSMS / Semaphore hearing texts (includes Date: line).
    return HearingSmsFormatter.build(
      caseNo: caseNo,
      caseTitle: caseTitle,
      clientName: clientName,
      hearingDate: hearingDate,
      hearingTime: hearingTime,
      location: location,
      reminderKind: _reminderKind(enriched),
    );
  }

  /// Title with hearing date so collapsed trays still show when.
  static String buildPopupTitle(Map<String, dynamic> data, {String? fallback}) {
    final enriched = HearingCalendarFields.enrichForAlerts(data);
    final caseNo = _s(enriched['caseNo']);
    final hearingDate = HearingCalendarFields.hearingFieldAsString(
      enriched,
      'hearingDate',
    );
    final base = (fallback ?? '').trim().isNotEmpty
        ? fallback!.trim()
        : (caseNo.isNotEmpty
            ? 'Court hearing / order — $caseNo'
            : 'Court hearing / order');
    if (hearingDate.isEmpty) return base;
    if (base.contains(hearingDate)) return base;
    return '$base · $hearingDate';
  }

  static String _reminderKind(Map<String, dynamic> data) {
    for (final key in const ['reminderKind', 'hearingReminderKind']) {
      final kind = _s(data[key]).toLowerCase();
      if (kind == 'd5' ||
          kind == 'd2' ||
          kind == 'hearing_day' ||
          kind == 'day_noon') {
        return kind;
      }
    }
    final type = _s(data['type']).toLowerCase();
    if (type.contains('hearing_reminder_d5') || type.endsWith('_d5')) {
      return 'd5';
    }
    if (type.contains('hearing_reminder_d2') || type.endsWith('_d2')) {
      return 'd2';
    }
    if (type.contains('hearing_day') || type.contains('day_noon')) {
      return 'hearing_day';
    }
    return '';
  }

  static String _trimPopupExtras(String raw) {
    final matter = raw.indexOf('\nMatter:');
    if (matter > 0) return raw.substring(0, matter).trim();
    final hearingAt = raw.indexOf('\nHearing date/time:');
    if (hearingAt > 0) return raw.substring(0, hearingAt).trim();
    final caseId = raw.indexOf('\nCase record ID:');
    if (caseId > 0) return raw.substring(0, caseId).trim();
    return raw.trim();
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
