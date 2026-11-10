import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/hearing_calendar_fields.dart';
import '../services/hearing_calendar_sync_service.dart';

/// Lightweight hearing → calendar grid row (same path as [calendar_events]).
abstract final class CalendarLiveHearingMap {
  static String _str(dynamic v) => HearingCalendarFields.asDisplayString(v);

  static DateTime? _asDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Map<String, dynamic>? fromHearingDoc(
    Map<String, dynamic> raw,
    String docId,
    String attorneyId, {
    bool fallbackToCreatedAt = true,
  }) {
    try {
      return _fromHearingDocImpl(
        raw,
        docId,
        attorneyId,
        fallbackToCreatedAt: fallbackToCreatedAt,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _fromHearingDocImpl(
    Map<String, dynamic> raw,
    String docId,
    String attorneyId, {
    required bool fallbackToCreatedAt,
  }) {
    final rawCaseNo = _firstStr(raw, const ['caseNo', 'caseNumber', 'case_number']);
    final cleanCaseNo = HearingCalendarFields.cleanCaseDocketNo(rawCaseNo);
    final caseNo = cleanCaseNo.isNotEmpty ? cleanCaseNo : rawCaseNo;
    var clientName = _firstStr(raw, const ['clientName', 'client_name']);
    final resolvedClient = HearingCalendarFields.resolveClientForDisplay(raw);
    if (resolvedClient.isNotEmpty) {
      clientName = resolvedClient;
    }
    var caseTitle = _firstStr(raw, const ['caseTitle', 'case_title']);
    if (!HearingCalendarFields.hasCaseCaptionMarker(caseTitle)) {
      final resolvedTitle = HearingCalendarFields.resolveCaseTitleForDisplay(raw);
      if (resolvedTitle.isNotEmpty && HearingCalendarFields.hasCaseCaptionMarker(resolvedTitle)) {
        caseTitle = resolvedTitle;
      }
    }
    final courtBranch = _firstStr(
      raw,
      const ['courtBranch', 'court_branch', 'court', 'location'],
    );
    final summary = _str(raw['summary']);
    final fullText = _str(raw['fullText']);
    final message = _str(raw['message']);
    final source = _str(raw['source']).toLowerCase();
    final activity = _str(raw['activityType']).toLowerCase();
    final hasIdentity = caseNo.isNotEmpty ||
        clientName.isNotEmpty ||
        caseTitle.isNotEmpty ||
        courtBranch.isNotEmpty ||
        summary.isNotEmpty ||
        fullText.isNotEmpty ||
        message.isNotEmpty ||
        source == 'n8n' ||
        activity == 'court_import';
    if (!hasIdentity) return null;

    // Prefer structured hearingDate / order text. Never drop a court row that
    // already has case identity — fall back to createdAt so it still paints.
    DateTime? when = parseHearingWhen(raw);
    if (when == null && fallbackToCreatedAt) {
      when = _asDate(raw['createdAt']) ?? _asDate(raw['updatedAt']);
      if (when != null) {
        when = DateTime(when.year, when.month, when.day, 8, 30);
      }
    }
    if (when == null && hasIdentity) {
      // Last resort: still show on the grid (upload day) so notify → calendar.
      when = DateTime.now();
      when = DateTime(when.year, when.month, when.day, 8, 30);
    }
    if (when == null) return null;

    final hearingTime = _firstStr(raw, const ['hearingTime', 'hearing_time']);
    final venue = HearingCalendarFields.resolveVenueForDisplay(raw);
    final createdAt = _asDate(raw['createdAt']) ?? _asDate(raw['updatedAt']);
    final updatedAt = _asDate(raw['updatedAt']);

    return gridRow(
      docId: docId,
      attorneyId: attorneyId,
      when: when,
      caseNo: caseNo,
      clientName: clientName,
      caseTitle: caseTitle,
      courtBranch: courtBranch,
      hearingTime: hearingTime,
      location: venue.isNotEmpty ? venue : courtBranch,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static String _firstStr(Map<String, dynamic> raw, List<String> keys) {
    for (final key in keys) {
      final s = _str(raw[key]);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static Map<String, dynamic> gridRow({
    required String docId,
    required String attorneyId,
    required DateTime when,
    String caseNo = '',
    String clientName = '',
    String caseTitle = '',
    String courtBranch = '',
    String hearingTime = '',
    String location = '',
    dynamic createdAt,
    dynamic updatedAt,
  }) {
    final cleanNo = HearingCalendarFields.cleanCaseDocketNo(caseNo);
    final title = (cleanNo.isNotEmpty &&
            !HearingCalendarFields.isPlaceholderCaseNo(cleanNo))
        ? cleanNo
        : (caseNo.isNotEmpty &&
                !HearingCalendarFields.isPlaceholderCaseNo(caseNo))
            ? caseNo
            : (clientName.isNotEmpty
                ? clientName
                : (caseTitle.isNotEmpty ? caseTitle : 'Hearing'));
    return {
      'id': 'live_hearing_$docId',
      'hearingDocId': docId,
      'eventType': 'hearing',
      'eventDate': when,
      'title': title,
      if (clientName.isNotEmpty) 'clientName': clientName,
      if (caseNo.isNotEmpty) 'caseNo': caseNo,
      if (caseTitle.isNotEmpty) 'caseTitle': caseTitle,
      if (courtBranch.isNotEmpty) 'courtBranch': courtBranch,
      if (hearingTime.isNotEmpty) 'hearingTime': hearingTime,
      if (location.isNotEmpty) 'location': location,
      if (createdAt != null) 'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
      'source': HearingCalendarSyncService.sourceTag,
      'assignedTo': attorneyId,
      'readOnly': true,
    };
  }

  static DateTime? parseHearingWhen(Map<String, dynamic> data) {
    final resolved = HearingCalendarFields.resolveEventDate(data);
    if (resolved != null) return resolved;

    final fromHearingField =
        HearingCalendarFields.resolveEventDateFromHearingDateField(data);
    if (fromHearingField != null) return fromHearingField;

    // Same display path as the notification detail panel.
    try {
      final prepared =
          HearingCalendarFields.prepareForNotificationDisplay(data);
      final fromPrepared = HearingCalendarFields.resolveEventDate(prepared) ??
          HearingCalendarFields.resolveEventDateFromHearingDateField(prepared);
      if (fromPrepared != null) return fromPrepared;
    } catch (_) {}

    final hearingDate = data['hearingDate'] ?? data['hearing_date'] ?? data['date'];
    final fromField = _asDate(hearingDate);
    if (fromField != null) {
      return DateTime(fromField.year, fromField.month, fromField.day, 8, 30);
    }
    if (hearingDate is String && hearingDate.trim().isNotEmpty) {
      final scraped = _scrapedMonthDayYear(hearingDate);
      if (scraped != null) return scraped;
    }

    // Pull "November 1, 2026" from title / summary / body when AI omitted hearingDate.
    for (final key in const [
      'caseTitle',
      'title',
      'summary',
      'message',
      'fullText',
      'clientName',
    ]) {
      final scraped = _scrapedMonthDayYear(_str(data[key]));
      if (scraped != null) return scraped;
    }

    final hearingDateTime = data['hearingDateTime'] ?? data['eventDate'];
    if (hearingDateTime is Timestamp) return hearingDateTime.toDate();
    if (hearingDateTime is DateTime) return hearingDateTime;
    return null;
  }

  static DateTime? _scrapedMonthDayYear(String raw) {
    if (raw.trim().isEmpty) return null;
    final m = RegExp(
      r'(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2})\s*,?\s+(\d{4})',
      caseSensitive: false,
    ).firstMatch(raw);
    if (m == null) return null;
    const months = {
      'january': 1,
      'february': 2,
      'march': 3,
      'april': 4,
      'may': 5,
      'june': 6,
      'july': 7,
      'august': 8,
      'september': 9,
      'october': 10,
      'november': 11,
      'december': 12,
    };
    final month = months[m.group(1)!.toLowerCase()];
    final day = int.tryParse(m.group(2)!);
    final year = int.tryParse(m.group(3)!);
    if (month == null || day == null || year == null) return null;
    return DateTime(year, month, day, 8, 30);
  }

  static List<Map<String, dynamic>> mapHearingDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String attorneyId, {
    bool fallbackToCreatedAt = true,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final row = fromHearingDoc(
        doc.data(),
        doc.id,
        attorneyId,
        fallbackToCreatedAt: fallbackToCreatedAt,
      );
      if (row != null) out.add(row);
    }
    return out;
  }

  static List<Map<String, dynamic>> mapHearingSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
    String attorneyId,
  ) => mapHearingDocs(snap.docs, attorneyId);

  static List<Map<String, dynamic>> mergeHearingRows(
    List<Map<String, dynamic>> base,
    List<Map<String, dynamic>> incoming,
  ) {
    if (incoming.isEmpty) return base;
    if (base.isEmpty) return incoming;
    final byId = <String, Map<String, dynamic>>{};
    for (final r in base) {
      final id = _str(r['hearingDocId']);
      if (id.isNotEmpty) byId[id] = r;
    }
    for (final r in incoming) {
      final id = _str(r['hearingDocId']);
      if (id.isNotEmpty) byId[id] = r;
    }
    final merged = byId.values.toList()
      ..sort((a, b) {
        final ad = a['eventDate'];
        final bd = b['eventDate'];
        if (ad is! DateTime || bd is! DateTime) return 0;
        return ad.compareTo(bd);
      });
    return merged;
  }

  /// Live `hearings` rows win when the same [hearingDocId] exists.
  static List<Map<String, dynamic>> mergeIntoCalendarEvents(
    List<Map<String, dynamic>> calendarEvents,
    List<Map<String, dynamic>> liveHearings,
  ) {
    if (liveHearings.isEmpty) return calendarEvents;

    final seen = <String>{
      for (final e in calendarEvents)
        if (_str(e['hearingDocId']).isNotEmpty) _str(e['hearingDocId']),
    };

    final out = List<Map<String, dynamic>>.from(calendarEvents);
    for (final h in liveHearings) {
      final hid = _str(h['hearingDocId']);
      if (hid.isEmpty) continue;
      final existingIdx = out.indexWhere((e) => _str(e['hearingDocId']) == hid);
      if (existingIdx >= 0) {
        out[existingIdx] = h;
        continue;
      }
      seen.add(hid);
      out.add(h);
    }

    out.sort((a, b) {
      final ad = a['eventDate'];
      final bd = b['eventDate'];
      if (ad is! DateTime || bd is! DateTime) return 0;
      return ad.compareTo(bd);
    });
    return out;
  }
}
