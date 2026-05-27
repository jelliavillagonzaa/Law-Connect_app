import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../utils/hearing_notification_formatter.dart';
import 'court_notice_rule_extractor.dart';

/// Maps a Firestore `hearings` document into calendar UI / `calendar_events` fields.
class HearingCalendarFields {
  /// Coerces Firestore `hearingDate` / `hearingTime` (String or Timestamp) for parsing.
  static String hearingFieldAsString(Map<String, dynamic> hd, String key) {
    final v = hd[key];
    if (v is String) return v.trim();
    if (v is Timestamp) {
      if (key == 'hearingTime') {
        return DateFormat('h:mm a').format(v.toDate());
      }
      return DateFormat('MMMM d, yyyy').format(v.toDate());
    }
    if (v is DateTime) {
      if (key == 'hearingTime') {
        return DateFormat('h:mm a').format(v);
      }
      return DateFormat('MMMM d, yyyy').format(v);
    }
    return '';
  }

  /// Normalizes hearing docs so date resolution never casts Timestamp as String.
  static Map<String, dynamic> normalizeHearingDoc(Map<String, dynamic> hd) {
    final out = Map<String, dynamic>.from(hd);
    final dateStr = hearingFieldAsString(hd, 'hearingDate');
    if (dateStr.isNotEmpty) out['hearingDate'] = dateStr;
    final timeStr = hearingFieldAsString(hd, 'hearingTime');
    if (timeStr.isNotEmpty) out['hearingTime'] = timeStr;
    return out;
  }

  HearingCalendarFields({
    required this.title,
    required this.description,
    required this.eventDate,
    required this.clientName,
    required this.caseNo,
    required this.courtBranch,
    required this.hearingPurpose,
    required this.involvedParties,
    required this.orderExcerpt,
    this.caseId,
    this.caseTitle,
    this.senderName,
    this.activityType,
    this.hearingDate = '',
    this.hearingTime = '',
    this.location = '',
    this.judgeName = '',
    this.summary = '',
    this.documentType = '',
  });

  final String title;
  final String description;
  final DateTime? eventDate;
  final String clientName;
  final String caseNo;
  final String courtBranch;
  final String hearingPurpose;
  final List<String> involvedParties;
  final String orderExcerpt;
  final String? caseId;
  final String? caseTitle;
  final String? senderName;
  final String? activityType;
  final String hearingDate;
  final String hearingTime;
  final String location;
  final String judgeName;
  final String summary;
  final String documentType;

  /// True when [title] looks like a party-vs-party or in re caption.
  static bool hasCaseCaptionMarker(String title) {
    final lower = title.trim().toLowerCase();
    if (lower.isEmpty) return false;
    if (lower.contains(' versus ')) return true;
    if (RegExp(r'\bvs\.?\b').hasMatch(lower)) return true;
    if (RegExp(r'\bv\.?\s+s\.?\b').hasMatch(lower)) return true;
    return false;
  }

  /// Placeholder / OCR noise — not a real case caption.
  static bool isLowQualityCaseTitle(String title) {
    final t = title.trim();
    if (t.isEmpty) return true;
    if (hasCaseCaptionMarker(t)) return false;
    final lower = t.toLowerCase();
    if (lower.startsWith('in re:')) return false;
    if (t.contains(' ') && t.contains('.')) return false;
    // Single-token placeholders (e.g. "gugyugyyyu") from bad OCR / test data.
    if (!t.contains(' ') && t.length <= 32) return true;
    if (t.length < 10) return true;
    return false;
  }

  static String _normalizeCaption(String title) =>
      title.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Best display title: court-order caption, linked `cases`, then hearing field.
  static String resolveCaseTitleForDisplay(
    Map<String, dynamic> hd, {
    Map<String, dynamic>? linkedCase,
  }) {
    final fromHearing =
        _normalizeCaption(fieldAsDisplayString(hd, 'caseTitle'));
    final fromCase =
        _normalizeCaption((linkedCase?['caseTitle'] as String?) ?? '');
    final fromText = _caseTitleFromOrderText(hd);

    final candidates = <String>[
      if (fromText.isNotEmpty) fromText,
      if (fromCase.isNotEmpty && !isLowQualityCaseTitle(fromCase)) fromCase,
      if (fromHearing.isNotEmpty && !isLowQualityCaseTitle(fromHearing))
        fromHearing,
    ];
    if (candidates.isEmpty) return '';

    candidates.sort(
      (a, b) => _caseTitleDisplayScore(b).compareTo(_caseTitleDisplayScore(a)),
    );
    return candidates.first;
  }

  /// Sets [out]['caseTitle'] from hearing + linked case + order text.
  static void applyResolvedCaseTitle(
    Map<String, dynamic> out, {
    Map<String, dynamic>? linkedCase,
    List<Map<String, dynamic>> caseMaps = const [],
    Iterable<Map<String, dynamic>> sources = const [],
  }) {
    final linked = linkedCase ?? findLinkedCase(out, caseMaps);
    final candidates = <String>[];

    void consider(Map<String, dynamic> m) {
      final t = resolveCaseTitleForDisplay(m, linkedCase: linked);
      if (t.isNotEmpty) candidates.add(t);
      final direct = _normalizeCaption(fieldAsDisplayString(m, 'caseTitle'));
      if (direct.isNotEmpty &&
          !isLowQualityCaseTitle(direct) &&
          !candidates.contains(direct)) {
        candidates.add(direct);
      }
    }

    consider(out);
    for (final s in sources) {
      consider(s);
    }

    if (candidates.isEmpty) {
      out.remove('caseTitle');
      return;
    }
    candidates.sort(
      (a, b) => _caseTitleDisplayScore(b).compareTo(_caseTitleDisplayScore(a)),
    );
    out['caseTitle'] = candidates.first;
  }

  /// Async enrichment for detail panels (loads linked `cases` first).
  static Future<Map<String, dynamic>> prepareForNotificationDisplayAsync(
    Map<String, dynamic> raw,
  ) async {
    final caseMaps = await loadCaseMapsForHearing(raw);
    return prepareForNotificationDisplay(raw, caseMaps: caseMaps);
  }

  /// Linked `cases` rows for notification/calendar enrichment.
  static Future<List<Map<String, dynamic>>> loadCaseMapsForHearing(
    Map<String, dynamic> hd,
  ) async {
    final caseMaps = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addCase(String id, Map<String, dynamic> data) {
      if (id.isEmpty || !seen.add(id)) return;
      caseMaps.add({'id': id, ...data});
    }

    final caseId = (hd['caseId'] as String?)?.trim() ?? '';
    if (caseId.isNotEmpty) {
      try {
        final snap =
            await FirebaseFirestore.instance.collection('cases').doc(caseId).get();
        if (snap.exists && snap.data() != null) {
          addCase(snap.id, snap.data()!);
        }
      } catch (_) {}
    }

    final caseNo = (hd['caseNo'] as String?)?.trim() ?? '';
    if (caseNo.isNotEmpty) {
      for (final field in [
        'caseNumber',
        'caseNo',
        'docketNumber',
        'criminalCaseNo',
      ]) {
        try {
          final q = await FirebaseFirestore.instance
              .collection('cases')
              .where(field, isEqualTo: caseNo)
              .limit(5)
              .get();
          for (final doc in q.docs) {
            addCase(doc.id, doc.data());
          }
        } catch (_) {}
      }
    }

    return caseMaps;
  }

  /// Other `hearings` rows with the same [caseNo] (fuller captions / fields).
  static List<Map<String, dynamic>> siblingSourcesByCaseNo(
    Map<String, dynamic> hd,
    List<Map<String, dynamic>> pool,
  ) {
    final caseNo = (hd['caseNo'] as String?)?.trim() ?? '';
    if (caseNo.isEmpty) return const [];
    final norm = _normalizeCaseNo(caseNo);
    final out = <Map<String, dynamic>>[];
    for (final row in pool) {
      final rowNo = (row['caseNo'] as String?)?.trim() ?? '';
      if (rowNo.isEmpty) continue;
      if (_normalizeCaseNo(rowNo) != norm) continue;
      out.add(row);
    }
    return out;
  }

  /// Merged hearing map with the best [caseTitle] for UI / notifications.
  static Map<String, dynamic> prepareForNotificationDisplay(
    Map<String, dynamic> raw, {
    List<Map<String, dynamic>> caseMaps = const [],
    Iterable<Map<String, dynamic>> extraSources = const [],
  }) {
    final sources = <Map<String, dynamic>>[
      normalizeHearingDoc(raw),
      ...extraSources.map(
        (s) => normalizeHearingDoc(Map<String, dynamic>.from(s)),
      ),
    ];
    return mergeHearingSources(sources, caseMaps: caseMaps);
  }

  static int _caseTitleDisplayScore(String title) {
    final t = title.toLowerCase();
    var score = title.length;
    if (hasCaseCaptionMarker(title)) score += 800;
    if (t.startsWith('in re:')) score -= 120;
    return score;
  }

  /// Scans all long string fields (summary, message, etc.) for a vs. caption.
  static String _caseTitleFromAnyTextField(Map<String, dynamic> hd) {
    const skip = {
      'hearingDate',
      'hearingTime',
      'hearingDateTime',
      'caseNo',
      'clientName',
      'location',
      'courtBranch',
      'judgeName',
      'senderName',
      'activityType',
      'documentType',
    };
    String? best;
    var bestScore = -1;
    for (final entry in hd.entries) {
      if (skip.contains(entry.key)) continue;
      final text = fieldAsDisplayString(hd, entry.key);
      if (text.length < 24 || !hasCaseCaptionMarker(text)) continue;
      final score = _caseTitleDisplayScore(text);
      if (score > bestScore) {
        bestScore = score;
        best = _normalizeCaption(text);
      }
    }
    return best ?? '';
  }

  static String _caseTitleFromOrderText(Map<String, dynamic> hd) {
    final blob = [
      (hd['fullText'] as String?)?.trim() ?? '',
      (hd['message'] as String?)?.trim() ?? '',
      (hd['summary'] as String?)?.trim() ?? '',
    ].join('\n');
    if (blob.isEmpty) return '';

    for (final line in blob.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.length < 12) continue;
      if (!hasCaseCaptionMarker(trimmed)) continue;
      final cleaned = trimmed
          .replaceFirst(
            RegExp(
              r'^(?:case\s*(?:no\.?|number|title|caption)\s*[:\-]?\s*)',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      if (cleaned.length >= 12 && hasCaseCaptionMarker(cleaned)) {
        return _normalizeCaption(cleaned);
      }
    }

    final vs = RegExp(
      r"([A-Z][A-Za-z0-9.'\-]+(?:\s+(?:[A-Z][A-Za-z0-9.'\-]+|of|the|and|&)\s*)*)\s+v\.?\s*s\.?\s+(.+?)(?:\n\n|\n[A-Z]{2,}|\.\s+(?:COMES|WHEREAS|WHEREFORE|ORDER)|$)",
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(blob);
    if (vs != null) {
      final left = _normalizeCaption(vs.group(1)!);
      final right = _normalizeCaption(vs.group(2)!);
      if (left.length >= 3 && right.length >= 5) {
        return '$left vs. $right';
      }
    }
    return '';
  }

  static Map<String, dynamic>? findLinkedCase(
    Map<String, dynamic> hd,
    List<Map<String, dynamic>> caseMaps,
  ) {
    if (caseMaps.isEmpty) return null;
    final caseId = (hd['caseId'] as String?)?.trim() ?? '';
    if (caseId.isNotEmpty) {
      for (final c in caseMaps) {
        if ((c['id'] as String?) == caseId) return c;
      }
    }
    final caseNo = (hd['caseNo'] as String?)?.trim() ?? '';
    if (caseNo.isEmpty) return null;
    final norm = caseNo.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    for (final c in caseMaps) {
      for (final field in [
        'caseNumber',
        'caseNo',
        'docketNumber',
        'criminalCaseNo',
      ]) {
        final raw = (c[field] as String?)?.trim() ?? '';
        if (raw.isEmpty) continue;
        final v = raw.toLowerCase().replaceAll(RegExp(r'\s+'), '');
        if (v == norm || v.contains(norm) || norm.contains(v)) return c;
      }
    }
    return null;
  }

  static int _fieldPickScore(String fieldKey, String value) {
    var score = value.length;
    final lower = value.toLowerCase();
    if (fieldKey == 'caseTitle') {
      score += _caseTitleDisplayScore(value);
    }
    if (fieldKey == 'location' || fieldKey == 'courtBranch') {
      if (lower.contains('regional trial court') ||
          lower.contains('branch')) {
        score += 200;
      }
    }
    if (fieldKey == 'hearingDate' && RegExp(r'\d{4}').hasMatch(value)) {
      score += 100;
    }
    return score;
  }

  /// Firestore may store date/time as String, Timestamp, or DateTime.
  static String fieldAsDisplayString(Map<String, dynamic> m, String key) {
    if (key == 'hearingDate' ||
        key == 'hearingTime' ||
        key == 'hearingDateTime') {
      return hearingFieldAsString(m, key);
    }
    final v = m[key];
    if (v is String) return v.trim();
    if (v is Timestamp) return hearingFieldAsString(m, key);
    if (v is DateTime) {
      if (key == 'hearingTime') {
        return DateFormat('h:mm a').format(v);
      }
      return DateFormat('MMMM d, yyyy').format(v);
    }
    return '';
  }

  static String _pickBestString(
    String fieldKey,
    Iterable<Map<String, dynamic>> maps,
  ) {
    String? best;
    var bestScore = -1;
    for (final m in maps) {
      final v = fieldAsDisplayString(m, fieldKey);
      if (v.isEmpty) continue;
      if (fieldKey == 'caseTitle' && isLowQualityCaseTitle(v)) continue;
      final s = _fieldPickScore(fieldKey, v);
      if (s > bestScore) {
        bestScore = s;
        best = v;
      }
    }
    return best ?? '';
  }

  /// Full venue: court/branch + city (longest complete text wins).
  static String resolveVenueForDisplay(Map<String, dynamic> d) {
    final loc = (d['location'] as String?)?.trim() ?? '';
    final court = (d['courtBranch'] as String?)?.trim() ?? '';
    if (loc.isEmpty) return court;
    if (court.isEmpty) return loc;
    final ll = loc.toLowerCase();
    final cl = court.toLowerCase();
    if (ll.contains(cl) || cl.contains(ll)) return loc.length >= court.length ? loc : court;
    return '$court — $loc';
  }

  /// Merges `cases` + order text into hearing map before calendar/notifications UI.
  static Map<String, dynamic> enrichHearingData(
    Map<String, dynamic> hd, {
    List<Map<String, dynamic>> caseMaps = const [],
  }) {
    return mergeHearingSources([hd], caseMaps: caseMaps);
  }

  /// Combines multiple `hearings` rows (same case) + linked `cases` into one complete map.
  static Map<String, dynamic> mergeHearingSources(
    Iterable<Map<String, dynamic>> sources, {
    List<Map<String, dynamic>> caseMaps = const [],
  }) {
    final rawList = sources
        .map((s) => normalizeHearingDoc(Map<String, dynamic>.from(s)))
        .toList();
    if (rawList.isEmpty) return {};

    final linked = findLinkedCase(rawList.first, caseMaps);
    if (linked != null) {
      rawList.add(linked);
    }

    final out = Map<String, dynamic>.from(rawList.first);
    for (final key in HearingNotificationFormatter.calendarHearingKeys.keys) {
      if (key == 'caseTitle') continue;
      final best = _pickBestString(key, rawList);
      if (best.isNotEmpty) out[key] = best;
    }
    out.remove('caseTitle');

    if (linked != null) {
      final cn = (linked['caseNo'] as String?)?.trim() ??
          (linked['caseNumber'] as String?)?.trim();
      if (cn != null && cn.isNotEmpty) out['caseNo'] = cn;
      final client = (linked['clientName'] as String?)?.trim() ??
          (linked['clientFullName'] as String?)?.trim();
      if (client != null && client.isNotEmpty) out['clientName'] = client;
      final branch = (linked['courtBranch'] as String?)?.trim();
      if (branch != null && branch.isNotEmpty) out['courtBranch'] = branch;
    }

    applyResolvedCaseTitle(
      out,
      linkedCase: linked,
      caseMaps: caseMaps,
      sources: rawList,
    );

    final venue = resolveVenueForDisplay(out);
    if (venue.isNotEmpty) out['location'] = venue;

    return out;
  }

  static String? _groupKeyForRow(Map<String, dynamic> r) {
    final cn = (r['caseNo'] as String?)?.trim();
    if (cn != null && cn.isNotEmpty) return 'no:$cn';
    final cid = (r['caseId'] as String?)?.trim();
    if (cid != null && cid.isNotEmpty) return 'id:$cid';
    return null;
  }

  /// Same case on one calendar day → every row gets the fullest field set.
  static void unifyHearingRecordsForCalendar(List<Map<String, dynamic>> rows) {
    final byGroup = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final g = _groupKeyForRow(r);
      if (g == null) continue;
      byGroup.putIfAbsent(g, () => []).add(r);
    }

    for (final group in byGroup.values) {
      final merged = mergeHearingSources(group);
      for (final r in group) {
        for (final entry in HearingNotificationFormatter.calendarHearingKeys.entries) {
          final v = merged[entry.key];
          if (v is String && v.trim().isNotEmpty) {
            r[entry.key] = v.trim();
          }
        }
      }
    }
  }

  @Deprecated('Use unifyHearingRecordsForCalendar')
  static void unifyCaseTitlesForCalendar(List<Map<String, dynamic>> rows) =>
      unifyHearingRecordsForCalendar(rows);

  static String _normalizeCaseNo(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Full detail map: this hearing + all same [caseNo] rows in `hearings` + `cases`.
  static Future<Map<String, dynamic>> loadMergedHearingForDisplay({
    required String hearingDocId,
    required Map<String, dynamic> hearingData,
    List<Map<String, dynamic>> caseMaps = const [],
    List<Map<String, dynamic>> siblingRows = const [],
  }) async {
    final sources = <Map<String, dynamic>>[
      hearingData,
      ...siblingRows,
    ];
    final caseNo = (hearingData['caseNo'] as String?)?.trim() ?? '';
    if (caseNo.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('hearings')
            .where('caseNo', isEqualTo: caseNo)
            .limit(50)
            .get();
        for (final d in snap.docs) {
          if (d.id == hearingDocId) continue;
          sources.add(d.data());
        }
      } catch (_) {
        /* keep hearingData + siblings */
      }
    }

    final merged = mergeHearingSources(sources, caseMaps: caseMaps);

    // Keep identity fields from the selected hearing record stable.
    // Without this, same-case merges can occasionally pull a client name from
    // another row and make card preview vs detail dialog inconsistent.
    final anchorCaseNo = fieldAsDisplayString(hearingData, 'caseNo');
    if (anchorCaseNo.isNotEmpty) {
      merged['caseNo'] = anchorCaseNo;
    }
    final anchorClient = fieldAsDisplayString(hearingData, 'clientName');
    if (anchorClient.isNotEmpty) {
      merged['clientName'] = anchorClient;
    }

    merged['hearingDocId'] = hearingDocId;
    merged['eventType'] = 'hearing';
    applyResolvedCaseTitle(
      merged,
      linkedCase: findLinkedCase(merged, caseMaps),
      caseMaps: caseMaps,
    );
    final when =
        resolveEventDate(merged) ?? resolveEventDate(hearingData);
    if (when != null) {
      merged['eventDate'] = when;
    }
    return merged;
  }

  static HearingCalendarFields fromHearingDoc(
    Map<String, dynamic> hd, {
    List<Map<String, dynamic>> caseMaps = const [],
  }) {
    final enriched = enrichHearingData(hd, caseMaps: caseMaps);
    final clientName = (enriched['clientName'] as String?)?.trim() ?? '';
    final caseNo = (enriched['caseNo'] as String?)?.trim() ?? '';
    final courtBranch = (enriched['courtBranch'] as String?)?.trim() ?? '';
    final caseTitle = (enriched['caseTitle'] as String?)?.trim();
    final caseId = (enriched['caseId'] as String?)?.trim();
    final senderName = (enriched['senderName'] as String?)?.trim();
    final activityType = (enriched['activityType'] as String?)?.trim();
    final message = (enriched['message'] as String?)?.trim() ?? '';
    final fullText = (enriched['fullText'] as String?)?.trim() ?? '';

    final purpose = _hearingPurpose(enriched, fullText, message, activityType);
    final when = resolveEventDate(enriched);
    final excerpt = _orderExcerpt(fullText, message);

    final title = _buildTitle(
      purpose: purpose,
      clientName: clientName,
      caseNo: caseNo,
      caseTitle: caseTitle,
    );

    return HearingCalendarFields(
      title: title,
      description: _buildDescription(
        clientName: clientName,
        caseNo: caseNo,
        courtBranch: courtBranch,
        purpose: purpose,
        excerpt: excerpt,
        message: message,
        when: when,
      ),
      eventDate: when,
      clientName: clientName,
      caseNo: caseNo,
      courtBranch: courtBranch,
      hearingPurpose: purpose,
      involvedParties: _involvedParties(
        enriched,
        clientName: clientName,
        courtBranch: courtBranch,
        caseTitle: caseTitle,
        senderName: senderName,
      ),
      orderExcerpt: excerpt,
      caseId: caseId?.isNotEmpty == true ? caseId : null,
      caseTitle: caseTitle?.isNotEmpty == true ? caseTitle : null,
      senderName: senderName?.isNotEmpty == true ? senderName : null,
      activityType: activityType?.isNotEmpty == true ? activityType : null,
      hearingDate: hearingFieldAsString(enriched, 'hearingDate'),
      hearingTime: hearingFieldAsString(enriched, 'hearingTime'),
      location: resolveVenueForDisplay(enriched),
      judgeName: (enriched['judgeName'] as String?)?.trim() ?? '',
      summary: (enriched['summary'] as String?)?.trim() ?? '',
      documentType: (enriched['documentType'] as String?)?.trim() ?? '',
    );
  }

  /// Live overlay row for hybrid calendar UI (`hearings` fields only).
  Map<String, dynamic> toCalendarDisplayMap(String hearingDocId) {
    final display = mergeHearingSources([
      {
        'caseNo': caseNo,
        'caseTitle': caseTitle ?? '',
        'clientName': clientName,
        'hearingDate': hearingDate,
        'hearingTime': hearingTime,
        'courtBranch': courtBranch,
        'location': location,
        'judgeName': judgeName,
      },
    ]);
    return {
      'hearingDocId': hearingDocId,
      'eventType': 'hearing',
      'readOnly': true,
      'title': calendarListTitle(),
      if (eventDate != null) 'eventDate': eventDate,
      if (caseId != null) 'caseId': caseId,
      ...HearingNotificationFormatter.pickCalendarHearingFields(display),
    };
  }

  String calendarListTitle() {
    if (caseNo.isNotEmpty) return caseNo;
    if (clientName.isNotEmpty) return clientName;
    final ct = caseTitle?.trim();
    if (ct != null && ct.isNotEmpty) {
      return ct.length > 48 ? '${ct.substring(0, 45)}...' : ct;
    }
    return 'Hearing';
  }

  /// Crash-safe calendar cell row (no [fromHearingDoc] / court OCR parsing).
  static Map<String, dynamic>? toCalendarOverlayRow({
    required Map<String, dynamic> raw,
    required String hearingDocId,
    required String attorneyId,
    required DateTime when,
    List<Map<String, dynamic>> caseMaps = const [],
  }) {
    try {
      final merged = mergeHearingSources([raw], caseMaps: caseMaps);
      final caseNo = fieldAsDisplayString(merged, 'caseNo');
      final clientName = fieldAsDisplayString(merged, 'clientName');
      final caseTitle = fieldAsDisplayString(merged, 'caseTitle');
      var title = caseNo.isNotEmpty
          ? caseNo
          : (clientName.isNotEmpty
              ? clientName
              : (caseTitle.isNotEmpty ? caseTitle : 'Hearing'));
      return {
        'hearingDocId': hearingDocId,
        'eventType': 'hearing',
        'readOnly': true,
        'source': 'hearings_sync',
        'assignedTo': attorneyId,
        'eventDate': when,
        'title': title,
        'hearingDate': fieldAsDisplayString(merged, 'hearingDate'),
        'hearingTime': fieldAsDisplayString(merged, 'hearingTime'),
        ...HearingNotificationFormatter.pickCalendarHearingFields(merged),
      };
    } catch (_) {
      return null;
    }
  }

  /// Legacy alias; prefer [toCalendarDisplayMap] for calendar overlay.
  Map<String, dynamic> toDisplayMap(String hearingDocId) =>
      toCalendarDisplayMap(hearingDocId);

  Map<String, dynamic> toCalendarEventPayload() {
    return {
      'title': title,
      'description': description,
      if (eventDate != null) 'eventDate': Timestamp.fromDate(eventDate!),
      if (clientName.isNotEmpty) 'clientName': clientName,
      if (caseNo.isNotEmpty) 'caseNo': caseNo,
      if (courtBranch.isNotEmpty) 'courtBranch': courtBranch,
      if (hearingPurpose.isNotEmpty) 'hearingPurpose': hearingPurpose,
      'involvedParties': involvedParties,
      if (orderExcerpt.isNotEmpty) 'hearingOrderExcerpt': orderExcerpt,
      if (caseId != null) 'caseId': caseId,
      if (caseTitle != null) 'caseTitle': caseTitle,
      if (senderName != null) 'senderName': senderName,
      if (activityType != null) 'activityType': activityType,
      if (hearingDate.isNotEmpty) 'hearingDate': hearingDate,
      if (hearingTime.isNotEmpty) 'hearingTime': hearingTime,
      if (location.isNotEmpty) 'location': location,
      if (judgeName.isNotEmpty) 'judgeName': judgeName,
      if (summary.isNotEmpty) 'summary': summary,
      if (documentType.isNotEmpty) 'documentType': documentType,
    };
  }

  /// Calendar cell date: prefer AI `hearingDate` / `hearingTime` (e.g. April 22 → day 22),
  /// not upload `createdAt` or stale `hearingDateTime`.
  static DateTime? resolveEventDate(Map<String, dynamic> hd) {
    try {
      final normalized = normalizeHearingDoc(hd);
      final hearingDateStr = hearingFieldAsString(normalized, 'hearingDate');

      final fromFields = _scheduleFromHearingFields(normalized);
      if (fromFields != null) return fromFields;

      final fromOrderText = _dateFromHearingOrderText(normalized);
      if (fromOrderText != null) return fromOrderText;

      // Do not fall back to createdAt when a hearing date string exists but failed parse.
      if (hearingDateStr.isNotEmpty) return null;

      final hts = normalized['hearingDateTime'];
      if (hts is Timestamp) return hts.toDate();
      if (hts is DateTime) return hts;

      final fullText = (hd['fullText'] as String?)?.trim() ?? '';
      if (fullText.isNotEmpty && _isCourtOrderText(fullText)) {
        final parsed =
            CourtNoticeRuleExtractor().extract(fullText).hearingDateTime;
        if (parsed != null) return parsed;
      }

      final message = (hd['message'] as String?)?.trim() ?? '';
      if (message.isNotEmpty) {
        final parsed =
            CourtNoticeRuleExtractor().extract(message).hearingDateTime;
        if (parsed != null) return parsed;
      }

      if (isCourtImportRow(hd)) {
        final created = hd['createdAt'];
        if (created is Timestamp) return created.toDate();
        if (created is DateTime) return created;
      }

      final caseId = (hd['caseId'] as String?)?.trim() ?? '';
      if (caseId.isNotEmpty) {
        final created = hd['createdAt'];
        if (created is Timestamp) return created.toDate();
        if (created is DateTime) return created;
      }

      return null;
    } catch (_) {
      return resolveEventDateFromHearingDateField(hd);
    }
  }

  static DateTime? _scheduleFromHearingFields(Map<String, dynamic> hd) {
    final dateStr = hearingFieldAsString(hd, 'hearingDate');
    if (dateStr.isEmpty) return null;

    DateTime? day = _parseHearingDateString(dateStr);
    if (day == null) return null;

    final timeStr = hearingFieldAsString(hd, 'hearingTime');
    if (timeStr.isEmpty) {
      return DateTime(day.year, day.month, day.day, 8, 30);
    }

    final lower = timeStr.toLowerCase();
    final match = RegExp(r'(\d{1,2})').firstMatch(lower);
    if (match == null) {
      return DateTime(day.year, day.month, day.day, 8, 30);
    }
    var hour = int.tryParse(match.group(1)!) ?? 8;
    if (lower.contains('pm') && hour < 12) hour += 12;
    if (lower.contains('am') && hour == 12) hour = 0;
    return DateTime(day.year, day.month, day.day, hour, 30);
  }

  /// Fallback when [resolveEventDate] misses but `hearingDate` string is set.
  static DateTime? resolveEventDateFromHearingDateField(Map<String, dynamic> hd) {
    final normalized = normalizeHearingDoc(hd);
    final dateStr = hearingFieldAsString(normalized, 'hearingDate');
    if (dateStr.isEmpty) return null;
    return _scheduleFromHearingFields(normalized);
  }

  static DateTime? _parseHearingDateString(String dateStr) {
    var normalized = dateStr.replaceAll(RegExp(r'\s+'), ' ').trim();
    normalized = normalized
        .replaceAll(RegExp(r'[\u2018\u2019\u201C\u201D]'), '')
        .trim();
    for (final pattern in [
      'MMMM dd, yyyy',
      'MMMM d, yyyy',
      'MMM dd, yyyy',
      'MMM d, yyyy',
      'MMMM dd yyyy',
      'MMMM d yyyy',
      'dd MMMM yyyy',
      'd MMMM yyyy',
      'yyyy-MM-dd',
      'MM/dd/yyyy',
      'M/d/yyyy',
    ]) {
      try {
        return DateFormat(pattern, 'en_US').parse(normalized);
      } catch (_) {}
      try {
        return DateFormat(pattern).parse(normalized);
      } catch (_) {}
    }
    final iso = DateTime.tryParse(normalized);
    if (iso != null) return iso;
    final mdy = RegExp(
      r'(?i)(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2}),?\s+(\d{4})',
    ).firstMatch(normalized);
    if (mdy != null) {
      final monthName = mdy.group(1)!;
      final dayNum = int.tryParse(mdy.group(2)!);
      final yearNum = int.tryParse(mdy.group(3)!);
      if (dayNum != null && yearNum != null) {
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
        final month = months[monthName.toLowerCase()];
        if (month != null) {
          return DateTime(yearNum, month, dayNum);
        }
      }
    }
    return null;
  }

  /// Parses "on April 22, 2026" style lines from court order OCR text.
  static DateTime? _dateFromHearingOrderText(Map<String, dynamic> hd) {
    final blobs = <String>[
      hearingFieldAsString(hd, 'hearingDate'),
      (hd['fullText'] as String?)?.trim() ?? '',
      (hd['message'] as String?)?.trim() ?? '',
      (hd['summary'] as String?)?.trim() ?? '',
    ];
    final re = RegExp(
      r'(?i)(?:on\s+)?(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2}),?\s+(\d{4})',
    );
    for (final blob in blobs) {
      if (blob.isEmpty) continue;
      final m = re.firstMatch(blob);
      if (m == null) continue;
      final phrase = '${m.group(1)} ${m.group(2)}, ${m.group(3)}';
      final day = _parseHearingDateString(phrase);
      if (day == null) continue;
      return _scheduleFromHearingFields({
        ...hd,
        'hearingDate': phrase,
      });
    }
    return null;
  }

  static bool isCourtImportRow(Map<String, dynamic> hd) {
    final cn = (hd['caseNo'] as String?)?.trim() ?? '';
    final ft = (hd['fullText'] as String?)?.trim() ?? '';
    return cn.isNotEmpty && ft.isNotEmpty;
  }

  static bool _isCourtOrderText(String text) {
    final t = text.toLowerCase();
    if (t.contains('firebase') && t.contains('google')) return false;
    if (t.contains('project') &&
        (t.contains('shut down') || t.contains('shutdown')) &&
        !t.contains('court')) {
      return false;
    }
    if (t.contains('dear developer') && !t.contains('court')) return false;
    return t.contains('court') ||
        t.contains('hearing') ||
        t.contains('arraignment') ||
        t.contains('branch') ||
        t.contains(' versus ') ||
        t.contains(' vs ') ||
        t.contains('people of the philippines');
  }

  static String _hearingPurpose(
    Map<String, dynamic> hd,
    String fullText,
    String message,
    String? activityType,
  ) {
    final blob = '${fullText}\n$message'.toLowerCase();
    for (final phrase in [
      'arraignment and pre-trial',
      'pre-trial conference',
      'arraignment',
      'pre-trial',
      'trial',
      'mediation',
      'status conference',
      'hearing',
    ]) {
      if (blob.contains(phrase)) {
        return phrase[0].toUpperCase() + phrase.substring(1);
      }
    }
    if (activityType != null && activityType.isNotEmpty) {
      if (activityType == 'schedule') return 'Hearing scheduled';
      return activityType[0].toUpperCase() + activityType.substring(1);
    }
    if (isCourtImportRow(hd)) return 'Court hearing';
    return 'Hearing';
  }

  static String _buildTitle({
    required String purpose,
    required String clientName,
    required String caseNo,
    String? caseTitle,
  }) {
    final label = purpose.isNotEmpty ? purpose : 'Hearing';
    if (clientName.isNotEmpty) {
      return '[AI] $label — $clientName';
    }
    if (caseTitle != null && caseTitle.isNotEmpty) {
      return '[AI] $label — $caseTitle';
    }
    if (caseNo.isNotEmpty) {
      return '[AI] $label — $caseNo';
    }
    return '[AI] $label';
  }

  static String _buildDescription({
    required String clientName,
    required String caseNo,
    required String courtBranch,
    required String purpose,
    required String excerpt,
    required String message,
    DateTime? when,
  }) {
    final lines = <String>[];
    if (clientName.isNotEmpty) lines.add('Client: $clientName');
    if (caseNo.isNotEmpty) lines.add('Case No.: $caseNo');
    if (courtBranch.isNotEmpty) lines.add('Court / Branch: $courtBranch');
    if (purpose.isNotEmpty) lines.add('Purpose: $purpose');
    if (when != null) {
      lines.add(
        'Schedule: ${when.month}/${when.day}/${when.year} '
        '${when.hour.toString().padLeft(2, '0')}:'
        '${when.minute.toString().padLeft(2, '0')}',
      );
    }
    if (message.isNotEmpty && !_isCourtOrderText(message)) {
      lines.add('Note: $message');
    }
    if (excerpt.isNotEmpty) {
      lines.add('');
      lines.add('Court order:');
      lines.add(excerpt);
    }
    return lines.join('\n');
  }

  static String _orderExcerpt(String fullText, String message) {
    final src = fullText.isNotEmpty && _isCourtOrderText(fullText)
        ? fullText
        : (message.isNotEmpty && _isCourtOrderText(message) ? message : '');
    if (src.isEmpty) return '';
    return src.length > 1200 ? '${src.substring(0, 1197)}...' : src;
  }

  static List<String> _involvedParties(
    Map<String, dynamic> hd, {
    required String clientName,
    required String courtBranch,
    String? caseTitle,
    String? senderName,
  }) {
    final parts = <String>[];
    void add(String? s) {
      final t = s?.trim();
      if (t == null || t.isEmpty || parts.contains(t)) return;
      parts.add(t);
    }

    add(clientName);
    add(caseTitle);
    add(courtBranch);
    add(senderName);
    add((hd['caseNo'] as String?)?.trim());

    return parts;
  }
}
