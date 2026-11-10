import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../utils/hearing_notification_formatter.dart';
import '../utils/out_of_system_notice.dart';
import 'court_notice_rule_extractor.dart';
import 'hearing_notification_fanout_service.dart';
import 'hearing_party_names.dart';

/// Maps a Firestore `hearings` document into calendar UI / `calendar_events` fields.
class HearingCalendarFields {
  /// n8n / Firestore may store `caseNo` as int (5297). Never `as String?`.
  static String asDisplayString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v.trim();
    if (v is num) return v.toString();
    if (v is bool) return v.toString();
    if (v is Timestamp) {
      return DateFormat('MMMM d, yyyy').format(v.toDate());
    }
    if (v is DateTime) return DateFormat('MMMM d, yyyy').format(v);
    return v.toString().trim();
  }

  /// Coerces Firestore `hearingDate` / `hearingTime` (String or Timestamp) for parsing.
  static String hearingFieldAsString(Map<String, dynamic> hd, String key) {
    final v = hd[key];
    if (v is String) return v.trim();
    if (v is num) return v.toString();
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

    final caseNo = fieldAsDisplayString(hd, 'caseNo');
    if (caseNo.isNotEmpty) {
      final parsedInt = int.tryParse(caseNo);
      final queryValues = <Object>[
        caseNo,
        if (parsedInt != null) parsedInt,
      ];
      for (final field in [
        'caseNumber',
        'caseNo',
        'docketNumber',
        'criminalCaseNo',
      ]) {
        for (final qVal in queryValues) {
          try {
            final q = await FirebaseFirestore.instance
                .collection('cases')
                .where(field, isEqualTo: qVal)
                .limit(5)
                .get();
            for (final doc in q.docs) {
              addCase(doc.id, doc.data());
            }
          } catch (_) {}
        }
      }
    }

    return caseMaps;
  }

  /// Other `hearings` rows with the same [caseNo] (fuller captions / fields).
  static List<Map<String, dynamic>> siblingSourcesByCaseNo(
    Map<String, dynamic> hd,
    List<Map<String, dynamic>> pool,
  ) {
    final caseNo = fieldAsDisplayString(hd, 'caseNo');
    if (caseNo.isEmpty) return const [];
    final norm = _normalizeCaseNo(caseNo);
    final out = <Map<String, dynamic>>[];
    for (final row in pool) {
      final rowNo = fieldAsDisplayString(row, 'caseNo');
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

  static String _capExtractBlob(String text, [int max = 12000]) {
    if (text.length <= max) return text;
    return text.substring(0, max);
  }

  static String _caseTitleFromOrderText(Map<String, dynamic> hd) {
    final blob = _capExtractBlob([
      (hd['fullText'] as String?)?.trim() ?? '',
      (hd['message'] as String?)?.trim() ?? '',
      (hd['summary'] as String?)?.trim() ?? '',
    ].join('\n'), 4000);
    if (blob.isEmpty) return '';

    // 1. Philippine court caption style:
    // [Plaintiff(s)]
    // Plaintiff,
    // -versus -
    // [Civil Case No. ...]
    // [For: ...]
    // [Defendant(s)]
    // Defendants.
    final lines = blob
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final vsIdx = lines.indexWhere((l) =>
        RegExp(r'^[-–—]?\s*(?:versus|vs\.?)\s*[-–—]?$', caseSensitive: false)
            .hasMatch(l) ||
        RegExp(r'[-–—]\s*versus\s*[-–—]', caseSensitive: false).hasMatch(l));
    if (vsIdx != -1) {
      final plaintiffLines = <String>[];
      for (var i = vsIdx - 1; i >= 0; i--) {
        final line = lines[i];
        if (RegExp(
          r'^(?:Republic|REGIONAL|MUNICIPAL|METROPOLITAN|10th|\d+(?:st|nd|rd|th)\s+Judicial|BRANCH|Email|Contact)',
          caseSensitive: false,
        ).hasMatch(line)) {
          break;
        }
        if (RegExp(r'^Plaintiffs?,?$', caseSensitive: false).hasMatch(line)) {
          continue;
        }
        plaintiffLines.insert(0, line);
      }
      final plaintiff = plaintiffLines.join(' ');
      final mainPlaintiff = plaintiff
          .split(RegExp(r',\s*Namely:', caseSensitive: false))
          .first
          .split(RegExp(r'Namely:', caseSensitive: false))
          .first
          .trim();

      final defLines = <String>[];
      for (var i = vsIdx + 1; i < lines.length; i++) {
        final line = lines[i];
        if (RegExp(r'^(?:Civil|Criminal|Special|Spec\.?)\s*Case',
                caseSensitive: false)
            .hasMatch(line)) {
          continue;
        }
        if (RegExp(r'^\d{3,}', caseSensitive: false).hasMatch(line)) continue;
        if (RegExp(r'^(?:For\s*:|Recovery of|Ownership|Possession|Damages|Injunction)',
                caseSensitive: false)
            .hasMatch(line)) {
          continue;
        }
        if (RegExp(r'^[xX]\s*[-–—]+\s*[xX]$').hasMatch(line) ||
            RegExp(r'^ORDER$', caseSensitive: false).hasMatch(line)) {
          break;
        }
        if (RegExp(r'Defendants?,?\.?$', caseSensitive: false).hasMatch(line)) {
          final cleaned = line
              .replaceFirst(
                RegExp(r',?\s*Defendants?,?\.?$', caseSensitive: false),
                '',
              )
              .trim();
          if (cleaned.isNotEmpty) defLines.add(cleaned);
          break;
        }
        defLines.add(line);
      }
      var defendants = defLines
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceFirst(
            RegExp(r',?\s*Defendants?,?\.?$', caseSensitive: false),
            '',
          )
          .trim();
      while (defendants.endsWith(',')) {
        defendants = defendants.substring(0, defendants.length - 1).trim();
      }
      if (mainPlaintiff.length >= 3 && defendants.length >= 3) {
        return '$mainPlaintiff vs. $defendants';
      }
    }

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
    final caseNo = fieldAsDisplayString(hd, 'caseNo');
    if (caseNo.isNotEmpty) {
      for (final c in caseMaps) {
        if (HearingNotificationFanoutService.caseMapMatchesHearing(
          c,
          caseNo,
          hd,
        )) {
          return c;
        }
      }
    }

    final clientName = fieldAsDisplayString(hd, 'clientName');
    if (clientName.isNotEmpty) {
      final target = clientName.toLowerCase();
      for (final c in caseMaps) {
        for (final field in ['clientName', 'clientFullName']) {
          final stored = fieldAsDisplayString(c, field);
          if (stored.isNotEmpty && stored.toLowerCase() == target) {
            return c;
          }
        }
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
    if (v is num) return v.toString();
    if (v is Timestamp) return hearingFieldAsString(m, key);
    if (v is DateTime) {
      if (key == 'hearingTime') {
        return DateFormat('h:mm a').format(v);
      }
      return DateFormat('MMMM d, yyyy').format(v);
    }
    return asDisplayString(v);
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

  /// True when [raw] is only a branch number/keyword without city, RTC, or courthouse name.
  /// Example: 'BRANCH 12' or 'Branch 12' -> true. 'BRANCH 12 - OROQUIETA CITY' -> false.
  static bool isBareLocation(String? raw) {
    if (raw == null) return true;
    final t = raw.trim();
    if (t.isEmpty) return true;
    if (RegExp(r'^(?:branch\s*\d*|\d+)[\s,.]*$', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    final hasSeparator = t.contains('-') ||
        t.contains('–') ||
        t.contains('—') ||
        t.contains(',');
    final hasDetails = RegExp(
      r'\b(city|province|hall of justice|rtc|mtc|mtcc|municipal|regional|court|judicial)\b',
      caseSensitive: false,
    ).hasMatch(t);
    return !hasSeparator && !hasDetails;
  }

  /// True when [raw] is a test/placeholder token (e.g. 'SAMPLE', 'TEST', 'N/A') rather
  /// than an authentic court docket number.
  static bool isPlaceholderCaseNo(String? raw) {
    if (raw == null) return true;
    final t = raw.trim();
    if (t.isEmpty) return true;
    final lower = t.toLowerCase();
    const placeholders = {
      'sample',
      'test',
      'court order',
      'court hearing',
      'hearing',
      'order',
      'n/a',
      'na',
      'none',
      'unknown',
      'pending',
      'tbd',
      'case no. sample',
      'case no sample',
      'civil case no. sample',
      'civil case no sample',
      'criminal case no. sample',
      'criminal case no sample',
      'spec. case no. sample',
      'special case no. sample',
    };
    if (placeholders.contains(lower)) return true;
    final stripped = lower
        .replaceFirst(
          RegExp(
            r'^(?:civil|criminal|special|spec\.?)?\s*case\s*(?:no\.?|#)?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (stripped == 'sample' || stripped == 'test') return true;
    return false;
  }

  /// Strips prefixes like "Civil Case No.", "Criminal Case No.", "Case No." to return clean docket number.
  static String cleanCaseDocketNo(dynamic raw) {
    if (raw == null) return '';
    var s = asDisplayString(raw).trim();
    if (s.isEmpty) return '';
    if (isPlaceholderCaseNo(s)) return s;
    final stripped = s.replaceFirst(
      RegExp(
        r'^(?:civil|criminal|special(?:\s+proceedings)?|spec\.?\s*proc\.?|spec\.?)?\s*case\s*(?:no\.?|#)?\s*[:\-]?\s*',
        caseSensitive: false,
      ),
      '',
    ).trim();
    if (stripped.isNotEmpty) {
      return stripped;
    }
    return s;
  }

  /// Cleans compound venue strings like "Branch 12 - OROQUIETA CITY" to just the city (e.g. "Oroquieta City").
  static String cleanVenueCity(String venue) {
    var v = venue.trim();
    if (v.isEmpty) return '';
    final m = RegExp(
      r'^(?:branch\s*\d+\s*[-–—,]\s*)([A-Za-z\s.]+City|[A-Za-z\s.]+)',
      caseSensitive: false,
    ).firstMatch(v);
    if (m != null) {
      final city = m.group(1)!.trim();
      if (city.toLowerCase().contains('city')) {
        return _titleCase(city);
      }
    }
    if (v.toUpperCase() == v && v.length > 3) {
      return _titleCase(v);
    }
    return v;
  }

  static String _titleCase(String text) {
    return text.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Resolves the authentic client name for display.
  /// If the current client name points to the opposing plaintiff (e.g. "HEIRS OF ..."),
  /// but answering defendants are represented, resolves to the defendants.
  static String resolveClientForDisplay(Map<String, dynamic> hd) {
    final client = fieldAsDisplayString(hd, 'clientName').trim();
    final title = resolveCaseTitleForDisplay(hd);
    final vsParts = title.split(RegExp(r'\s+vs\.?\s+', caseSensitive: false));
    final vsLeft = vsParts.isNotEmpty ? vsParts[0].trim() : '';
    final vsRight = vsParts.length > 1 ? vsParts[1].trim() : '';

    if (vsRight.isNotEmpty &&
        (client.isEmpty ||
            client.toLowerCase().startsWith('heirs of') ||
            (vsLeft.isNotEmpty && client.toLowerCase() == vsLeft.toLowerCase()))) {
      return sanitizePartyDisplayName(vsRight);
    }

    if (client.isNotEmpty && !client.toLowerCase().startsWith('heirs of')) {
      return sanitizePartyDisplayName(client);
    }

    final fromText = extractClientFromOrderText(_extractOrderBlob(hd), title);
    if (fromText.isNotEmpty) return fromText;
    if (vsRight.isNotEmpty) return sanitizePartyDisplayName(vsRight);
    return client;
  }

  static String _extractOrderBlob(Map<String, dynamic> d) {
    return _capExtractBlob([
      d['fullText'],
      d['orderText'],
      d['message'],
      d['summary'],
      d['description'],
      d['body'],
    ].whereType<Object>().map((e) => '$e').join('\n').trim());
  }

  /// Full venue: court/branch + city (longest complete text wins).
  static String resolveVenueForDisplay(Map<String, dynamic> d) {
    var loc = (d['location'] as String?)?.trim() ?? '';
    var court = (d['courtBranch'] as String?)?.trim() ?? '';
    if (loc.isEmpty) {
      loc = (d['venue'] as String?)?.trim() ?? '';
    }
    if (court.isEmpty) {
      court = (d['court'] as String?)?.trim() ??
          (d['court_branch'] as String?)?.trim() ??
          '';
    }

    if (isBareLocation(loc) && !isBareLocation(court)) loc = court;
    if (isBareLocation(court) && !isBareLocation(loc)) court = loc;

    if (isBareLocation(loc) || isBareLocation(court)) {
      final blob = _extractOrderBlob(d);
      if (blob.isNotEmpty) {
        final extracted = extractLocationFromOrderText(
          blob,
          loc.isNotEmpty ? loc : court,
        );
        if (extracted.isNotEmpty && !isBareLocation(extracted)) {
          if (isBareLocation(loc)) loc = extracted;
          if (isBareLocation(court)) court = extracted;
        }
      }
    }

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

    final anchor = Map<String, dynamic>.from(rawList.first);
    final out = Map<String, dynamic>.from(anchor);
    for (final key in HearingNotificationFormatter.calendarHearingKeys.keys) {
      if (key == 'caseTitle') continue;
      final best = _pickBestString(key, rawList);
      if (best.isNotEmpty) out[key] = best;
    }
    out.remove('caseTitle');

    if (linked != null) {
      final linkedNo = fieldAsDisplayString(linked, 'caseNo');
      final cn = linkedNo.isNotEmpty
          ? linkedNo
          : fieldAsDisplayString(linked, 'caseNumber');
      if (cn.isNotEmpty &&
          (fieldAsDisplayString(anchor, 'caseNo').isEmpty ||
              isPlaceholderCaseNo(fieldAsDisplayString(anchor, 'caseNo')))) {
        out['caseNo'] = cn;
      }
      final client = (linked['clientName'] as String?)?.trim() ??
          (linked['clientFullName'] as String?)?.trim();
      if (client != null &&
          client.isNotEmpty &&
          fieldAsDisplayString(anchor, 'clientName').isEmpty) {
        out['clientName'] = client;
      }
      final branch = (linked['courtBranch'] as String?)?.trim();
      if (branch != null &&
          branch.isNotEmpty &&
          (fieldAsDisplayString(anchor, 'courtBranch').isEmpty ||
              isBareLocation(fieldAsDisplayString(anchor, 'courtBranch')))) {
        out['courtBranch'] = branch;
      }
    }

    for (final key in [
      'caseNo',
      'clientName',
      'hearingDate',
      'hearingTime',
    ]) {
      final v = fieldAsDisplayString(anchor, key);
      if (v.isNotEmpty) {
        if (key == 'caseNo' &&
            isPlaceholderCaseNo(v) &&
            fieldAsDisplayString(out, 'caseNo').isNotEmpty &&
            !isPlaceholderCaseNo(fieldAsDisplayString(out, 'caseNo'))) {
          // Keep authentic case number from linked case or best candidate
        } else {
          out[key] = v;
        }
      }
    }

    applyResolvedCaseTitle(
      out,
      linkedCase: linked,
      caseMaps: caseMaps,
      sources: rawList,
    );

    final venue = resolveVenueForDisplay(out);
    if (venue.isNotEmpty) out['location'] = venue;

    fillStructuredFieldsFromOrderText(out);
    return out;
  }

  /// Fills Case No, title, client, time, location, date, summary from OCR / order text.
  /// Sanitize party / alert fields so SMS, push, and inbox match the PDF caption.
  static Map<String, dynamic> enrichForAlerts(Map<String, dynamic> raw) {
    final out = Map<String, dynamic>.from(raw);
    fillStructuredFieldsFromOrderText(out);

    // Prefer resolved schedule when AI left hearingDate empty.
    if (fieldAsDisplayString(out, 'hearingDate').isEmpty) {
      final when = resolveEventDate(out) ??
          resolveEventDateFromHearingDateField(out);
      if (when != null) {
        out['hearingDate'] = DateFormat('MMMM d, yyyy').format(when);
        if (fieldAsDisplayString(out, 'hearingTime').isEmpty) {
          out['hearingTime'] = DateFormat('h:mm a').format(when);
        }
      }
    }

    final client = sanitizePartyDisplayName(fieldAsDisplayString(out, 'clientName'));
    if (client.isNotEmpty) {
      out['clientName'] = client;
    } else {
      out.remove('clientName');
    }
    final title = sanitizePartyDisplayName(fieldAsDisplayString(out, 'caseTitle'));
    if (title.isNotEmpty) out['caseTitle'] = title;

    if (fieldAsDisplayString(out, 'location').isEmpty) {
      final branch = fieldAsDisplayString(out, 'courtBranch');
      if (branch.isNotEmpty) out['location'] = branch;
    }
    return out;
  }

  /// Strip court emails / SAMPLE noise from a party or caption string.
  static String sanitizePartyDisplayName(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    s = s.replaceAll(
      RegExp(r'[\w.+-]+@,?\s*[\w.-]+\.\w{2,}', caseSensitive: false),
      ' ',
    );
    s = s.replaceAll(
      RegExp(
        r'SAMPLE\s*[-–—]?\s*NOT AN OFFICIAL COURT DOCUMENT\.?',
        caseSensitive: false,
      ),
      ' ',
    );
    s = s.replaceAll(
      RegExp(r'Sample document layout only\.?', caseSensitive: false),
      ' ',
    );
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static void fillStructuredFieldsFromOrderText(Map<String, dynamic> out) {
    // Always scrub email-in-name even when other fields look complete.
    final existingClient = fieldAsDisplayString(out, 'clientName');
    if (existingClient.isNotEmpty) {
      final clean = sanitizePartyDisplayName(existingClient);
      if (clean != existingClient) {
        if (clean.isEmpty) {
          out.remove('clientName');
        } else {
          out['clientName'] = clean;
        }
      }
    }

    final summaryNow = fieldAsDisplayString(out, 'summary');
    if (fieldAsDisplayString(out, 'caseNo').isNotEmpty &&
        fieldAsDisplayString(out, 'clientName').isNotEmpty &&
        fieldAsDisplayString(out, 'hearingDate').isNotEmpty &&
        summaryNow.isNotEmpty &&
        !summaryLooksCutOff(summaryNow) &&
        fieldAsDisplayString(out, 'fullText').isNotEmpty &&
        !isBareLocation(fieldAsDisplayString(out, 'location'))) {
      return;
    }

    final blob = _capExtractBlob([
      out['fullText'],
      out['message'],
      out['summary'],
      out['description'],
      out['body'],
    ].whereType<Object>().map((e) => '$e').join('\n').trim());
    if (blob.length < 40) return;

    if ((out['fullText'] as String?)?.trim().isEmpty != false) {
      if (_isCourtOrderText(blob)) out['fullText'] = blob;
    }

    void putIfEmpty(String key, String value) {
      final v = value.trim();
      if (v.isEmpty) return;
      if (fieldAsDisplayString(out, key).isEmpty) out[key] = v;
    }

    final existingCaseNo = fieldAsDisplayString(out, 'caseNo');
    if (existingCaseNo.isEmpty || isPlaceholderCaseNo(existingCaseNo)) {
      final extracted = extractCaseNoFromOrderText(blob);
      if (extracted.isNotEmpty && !isPlaceholderCaseNo(extracted)) {
        out['caseNo'] = extracted;
      }
    }
    if (fieldAsDisplayString(out, 'caseTitle').isEmpty) {
      putIfEmpty('caseTitle', extractCaseTitleFromOrderText(blob));
    }
    if (fieldAsDisplayString(out, 'clientName').isEmpty) {
      putIfEmpty(
        'clientName',
        extractClientFromOrderText(
          blob,
          fieldAsDisplayString(out, 'caseTitle'),
        ),
      );
    }
    if (fieldAsDisplayString(out, 'hearingDate').isEmpty) {
      putIfEmpty('hearingDate', extractHearingDateFromOrderText(blob));
    }
    if (fieldAsDisplayString(out, 'hearingTime').isEmpty) {
      putIfEmpty('hearingTime', extractHearingTimeFromOrderText(blob));
    }
    final currentLoc = fieldAsDisplayString(out, 'location');
    if (currentLoc.isEmpty || isBareLocation(currentLoc)) {
      final extracted = extractLocationFromOrderText(
        blob,
        fieldAsDisplayString(out, 'courtBranch'),
      );
      if (extracted.isNotEmpty && !isBareLocation(extracted)) {
        out['location'] = extracted;
        out['courtBranch'] = extracted;
      } else if (currentLoc.isEmpty) {
        putIfEmpty('location', extracted);
      }
    }
    putIfEmpty('courtBranch', fieldAsDisplayString(out, 'location'));

    final existingSummary = fieldAsDisplayString(out, 'summary');
    final ft = fieldAsDisplayString(out, 'fullText');
    if (existingSummary.isEmpty ||
        existingSummary.length > 420 ||
        summaryLooksCutOff(existingSummary) ||
        (ft.isNotEmpty && existingSummary == ft)) {
      final summary = extractSummaryFromOrderText(blob);
      if (summary.isNotEmpty) out['summary'] = summary;
    }
  }

  static String extractCaseNoFromOrderText(String text) {
    final patterns = [
      RegExp(
        r'((?:spec(?:ial)?\.?\s*case\s*no\.?\s*)[A-Za-z0-9\-_/]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'(civil\s*case\s*no\.?\s*[A-Za-z0-9\-_/]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'(criminal\s*case\s*no\.?\s*[A-Za-z0-9\-_/]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'case\s*(?:no\.?|number|#)\s*[:\s]*([A-Za-z0-9\-_/]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(\d{2,4}-\d{3,}(?:-[A-Za-z0-9]+)?)\b',
        caseSensitive: false,
      ),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(text);
      if (m != null) {
        final raw = (m.group(1) ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (raw.isNotEmpty) {
          if (isPlaceholderCaseNo(raw)) continue;
          if (raw.toLowerCase().startsWith('spec') ||
              raw.toLowerCase().contains('case')) {
            return raw;
          }
          return 'Case No. $raw';
        }
      }
    }
    return '';
  }

  static String extractCaseTitleFromOrderText(String text) {
    text = _capExtractBlob(text);
    final fromLines = _caseTitleFromOrderText({'fullText': text});
    if (fromLines.isNotEmpty) return fromLines;
    final vs = RegExp(
      r"([A-Z][A-Za-z0-9.,'’&\-\s]{3,80}?)\s+(?:vs\.?|versus)\s+([A-Z][A-Za-z0-9.,'’&\-\s]{3,120})",
    ).firstMatch(text);
    if (vs != null) {
      final right = vs.group(2)!.trim().replaceAll(RegExp(r'[.,;]+$'), '');
      return '${vs.group(1)!.trim()} vs. $right';
    }
    final heirs = RegExp(
      r'(HEIRS OF [A-Z][A-Z\s.,\-]+?)(?:\n|Namely|Plaintiff)',
      caseSensitive: false,
    ).firstMatch(text);
    if (heirs != null) {
      return heirs.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    final phCaption = RegExp(
      r'([A-Z][A-Za-z0-9.,\s\-]+?)\s*,?\s*Plaintiffs?\s*,?\s*[-–]?\s*versus',
      caseSensitive: false,
    ).firstMatch(text);
    if (phCaption != null) {
      return phCaption.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return '';
  }

  /// Splits OCR / court `clientName` blobs into individual party names.
  static List<String> splitHearingPartyNames(String raw) =>
      HearingPartyNames.split(raw);

  static String extractClientFromOrderText(String text, String caseTitle) {
    final vsParts = caseTitle.split(RegExp(r'\s+vs\.?\s+', caseSensitive: false));
    final vsLeft = vsParts.isNotEmpty ? vsParts[0].trim() : '';
    final vsRight = vsParts.length > 1 ? vsParts[1].trim() : '';

    final representsDefendants = RegExp(
      r'(?:appeared\s+in\s+court\s+for|counsel\s+for)\s+(?:the\s+)?(?:answering\s+)?defendants',
      caseSensitive: false,
    ).hasMatch(text);

    if ((representsDefendants || vsRight.isNotEmpty) && vsRight.length > 3) {
      return sanitizePartyDisplayName(vsRight);
    }

    final petitioner = RegExp(
      r'(?:petitioner|plaintiff|applicant)\s*[:\-]\s*([^\n]{3,400})',
      caseSensitive: false,
    ).firstMatch(text);
    final petitionerText = petitioner?.group(1)?.trim() ?? '';
    final heirs = RegExp(
      r'(HEIRS OF [A-Z][A-Z\s.,&\-]+?)(?:\n|Namely|Plaintiff)',
      caseSensitive: false,
    ).firstMatch(text);
    final heirsText =
        heirs?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

    String pickRichest(List<String> candidates) {
      var best = '';
      for (final c in candidates) {
        final t = sanitizePartyDisplayName(c);
        if (t.isEmpty) continue;
        if (splitHearingPartyNames(t).length > splitHearingPartyNames(best).length) {
          best = t;
          continue;
        }
        if (best.isEmpty || t.length > best.length) best = t;
      }
      return best;
    }

    return pickRichest([heirsText, petitionerText, vsLeft]);
  }

  static String extractHearingDateFromOrderText(String text) {
    final reset = RegExp(
      '(?:reset|set|schedul\\w*|next hearing)\\b[^\\n.]{0,80}?\\bon\\s+'
      '(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec)\\.?\\s+'
      r'(\d{1,2})\s*,?\s+(\d{4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (reset != null) {
      return _monthPhrase(reset.group(1)!, reset.group(2)!, reset.group(3)!);
    }
    final m = RegExp(
      r'(?:on\s+)?(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2})\s*,?\s+(\d{4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return '';
    return '${m.group(1)} ${m.group(2)}, ${m.group(3)}';
  }

  static String extractHearingTimeFromOrderText(String text) {
    final clock = RegExp(
      r"(\d{1,2}:\d{2})\s*(?:o['’]?clock\s+)?(?:in the morning|in the afternoon|a\.?m\.?|p\.?m\.?)",
      caseSensitive: false,
    ).firstMatch(text);
    if (clock != null) return clock.group(0)!.replaceAll(RegExp(r'\s+'), ' ').trim();
    final at = RegExp(
      r'at\s+(\d{1,2}:\d{2}\s*(?:a\.?m\.?|p\.?m\.?)?)',
      caseSensitive: false,
    ).firstMatch(text);
    return at?.group(1)?.trim() ?? '';
  }

  static String extractLocationFromOrderText(String text, String fallback) {
    // 1. Check for full branch with city/suffix: e.g. "BRANCH 12 - OROQUIETA CITY" or "BRANCH 12, OROQUIETA CITY"
    final branchFull = RegExp(
      r'branch\s*(\d+)(?:\s*[-–—]\s*([^\r\n]+)|,\s*([^\r\n]+))',
      caseSensitive: false,
    ).firstMatch(text);
    if (branchFull != null) {
      final bNum = branchFull.group(1);
      var city = (branchFull.group(2) ?? branchFull.group(3) ?? '').trim();
      city = city.replaceAll(RegExp(r'[\r\n]+'), ' ').replaceAll(RegExp(r'[.,\s]+$'), '').trim();
      if (city.isNotEmpty) {
        return 'Branch $bNum - $city';
      }
    }

    // 2. Check for city before branch, e.g. "QUEZON CITY, BRANCH 45" or "QUEZON CITY - BRANCH 45"
    final cityBeforeBranch = RegExp(
      r'([A-Za-z\s.]+City|[A-Za-z\s.]+Province)\s*[,–—-]\s*branch\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (cityBeforeBranch != null) {
      final cityPre = cityBeforeBranch.group(1)!.trim();
      final bNum = cityBeforeBranch.group(2)!.trim();
      return 'Branch $bNum - $cityPre';
    }

    final branch = RegExp(
      r'branch\s*(\d+)(?:\s*[-–—]\s*([A-Za-z .]+))?',
      caseSensitive: false,
    ).firstMatch(text);
    final rtc = RegExp(
      r'((?:regional|municipal|metropolitan)\s+trial\s+court[^\n,]{0,80})',
      caseSensitive: false,
    ).firstMatch(text);
    final region = RegExp(
      r'(\d+(?:st|nd|rd|th)\s+judicial region)',
      caseSensitive: false,
    ).firstMatch(text);
    var city = branch?.group(2)?.trim() ?? '';
    if (city.isEmpty) {
      final nextLineCity = RegExp(
        r'branch\s*\d+\s*[\r\n]+\s*([A-Za-z\s.]+City|[A-Za-z\s.]+Province|Hall of Justice[^\r\n]*)',
        caseSensitive: false,
      ).firstMatch(text);
      if (nextLineCity != null) {
        city = nextLineCity.group(1)!.replaceAll(RegExp(r'[.,\s]+$'), '').trim();
      }
    }
    if (city.isEmpty) {
      final cityInOrder = RegExp(
        r'\b([A-Za-z\s.]+City|Hall of Justice[^\r\n,]*)\b',
        caseSensitive: false,
      ).firstMatch(text);
      if (cityInOrder != null) {
        city = cityInOrder.group(1)!.replaceAll(RegExp(r'[.,\s]+$'), '').trim();
      }
    }
    final parts = <String>[];
    if (branch != null) parts.add('Branch ${branch.group(1)}');
    if (rtc != null) {
      var court = rtc.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (region != null && !court.toLowerCase().contains('judicial')) {
        court = '$court, ${region.group(1)}';
      }
      if (city.isNotEmpty && !court.toLowerCase().contains(city.toLowerCase())) {
        court = '$court, $city';
      }
      if (parts.isNotEmpty) return '${parts.first} — $court';
      return court;
    }
    if (parts.isNotEmpty) {
      if (city.isNotEmpty) return '${parts.first} — $city';
      return fallback.isNotEmpty ? fallback : parts.first;
    }
    return fallback;
  }

  /// True when a stored summary was sliced mid-word (`…` / `...`).
  static String extractProceedingFromOrderText(String text) {
    if (text.isEmpty) return '';
    final m = RegExp(
      r'(?:for\s+|hearing\s+for\s+|stage\s+of\s+)?\b('
      r'arraignment\s+and\s+pre-trial\s+conference|'
      r'arraignment\s+and\s+pre-trial|'
      r'pre-trial\s+conference|'
      r'pre-trial|'
      r'arraignment|'
      r'promulgation\s+of\s+judgment|'
      r'promulgation|'
      r'initial\s+presentation\s+of\s+evidence|'
      r'presentation\s+of\s+evidence|'
      r'continuation\s+of\s+(?:the\s+)?proceedings|'
      r'continuation\s+of\s+hearing|'
      r'bail\s+hearing|'
      r'clarificatory\s+hearing'
      r')\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (m != null) {
      final raw = m.group(1)!.trim();
      return raw.split(' ').map((w) {
        if (w.toLowerCase() == 'and' || w.toLowerCase() == 'of' || w.toLowerCase() == 'the') {
          return w.toLowerCase();
        }
        return w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
      }).join(' ');
    }
    return '';
  }

  static String cleanSummaryText(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'\s+,'), ',');
    s = s.replaceAll(RegExp(r'\s+\.'), '.');
    // Remove trailing cutoffs like " a...", " a.", "...", dangling prepositions
    s = s.replaceAll(RegExp(r'\s+(?:a|p)\.{0,3}$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s+(?:on|at|for|the|and|or|in)\s*\.{0,3}$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'[,;:\s–—]+$'), '').trim();
    if (s.isNotEmpty && !s.endsWith('.') && !s.endsWith('!') && !s.endsWith('?')) {
      s = '$s.';
    }
    if (s.isNotEmpty && s[0].toLowerCase() == s[0]) {
      s = '${s[0].toUpperCase()}${s.substring(1)}';
    }
    return s;
  }

  /// Detects the legal role/capacity of an involved party (e.g. Accused, Defendant, Petitioner, Plaintiff).
  static String detectPartyRole({
    String? clientName,
    String? caseTitle,
    String? fullText,
  }) {
    final cn = (clientName ?? '').trim();
    if (cn.isEmpty) return '';

    final ct = (caseTitle ?? '').trim().toLowerCase();
    final ft = (fullText ?? '').toLowerCase();
    final cnLower = cn.toLowerCase();

    if (ct.contains('people of the philippines') || ft.contains('people of the philippines')) {
      if (ct.contains(cnLower) || ft.contains(cnLower) || ft.contains('accused')) {
        return 'Accused / Defendant';
      }
    }
    if (ft.contains('accused $cnLower') ||
        ft.contains('$cnLower, accused') ||
        ft.contains('$cnLower (accused)') ||
        ft.contains('accused: $cnLower')) {
      return 'Accused';
    }
    if (ft.contains('defendant $cnLower') ||
        ft.contains('$cnLower, defendant') ||
        ft.contains('defendant: $cnLower')) {
      return 'Defendant';
    }
    if (ft.contains('petitioner $cnLower') ||
        ft.contains('$cnLower, petitioner') ||
        ft.contains('petitioner: $cnLower')) {
      return 'Petitioner';
    }
    if (ft.contains('respondent $cnLower') ||
        ft.contains('$cnLower, respondent') ||
        ft.contains('respondent: $cnLower')) {
      return 'Respondent';
    }
    if (ct.contains(' vs.') || ct.contains(' versus ')) {
      final parts = ct.split(RegExp(r'\s+(?:vs\.?|versus)\s+'));
      if (parts.length > 1) {
        if (parts[1].contains(cnLower)) return 'Defendant / Respondent';
        if (parts[0].contains(cnLower)) return 'Plaintiff / Petitioner';
      }
    }
    return 'Named Involved Party';
  }

  /// True when a stored summary was sliced mid-word (`…` / `...` / `a...`).
  static bool summaryLooksCutOff(String summary) {
    final t = summary.trim();
    if (t.endsWith('…') || t.endsWith('...') || t.endsWith('..')) return true;
    return RegExp(r'\s+(?:a|p)\.{0,3}$', caseSensitive: false).hasMatch(t) ||
        RegExp(r'\s+(?:on|at|for|the|and|or|in)\s*$', caseSensitive: false).hasMatch(t);
  }

  static String extractSummaryFromOrderText(String text) {
    final wherefore = RegExp(r'WHEREFORE\b', caseSensitive: false).firstMatch(text);
    if (wherefore != null) {
      var chunk = text.substring(wherefore.start);
      final stop = RegExp(
        r'\b(?:SO ORDERED|Page\s+\d+)\b',
        caseSensitive: false,
      ).firstMatch(chunk);
      if (stop != null && stop.start > 15) {
        chunk = chunk.substring(0, stop.start);
      }
      chunk = cleanSummaryText(chunk);
      const max = 420;
      if (chunk.length > max) {
        final dot = chunk.lastIndexOf('.', max);
        if (dot >= 40) chunk = chunk.substring(0, dot + 1).trim();
      }
      return cleanSummaryText(chunk);
    }
    final reset = RegExp(
      r'(?:hearing\s+of\s+the\s+above-entitled\s+case|the\s+continuation\s+of\s+(?:the\s+)?proceedings|the\s+court\s+hereby\s+sets|reset|set|scheduled)[\s\S]{10,400}?(?:morning|afternoon|a\.?m\.?|p\.?m\.?|o[\x27\u2019]?clock)',
      caseSensitive: false,
    ).firstMatch(text);
    if (reset != null) {
      var s = reset.group(0)!;
      final rest = text.substring(reset.start);
      final sentenceEnd = RegExp(r'^[\s\S]+?\.\s+').firstMatch(rest);
      if (sentenceEnd != null && sentenceEnd.group(0)!.length <= 420) {
        s = sentenceEnd.group(0)!;
      }
      return cleanSummaryText(s);
    }
    return '';
  }

  static String? _groupKeyForRow(Map<String, dynamic> r) {
    final cn = fieldAsDisplayString(r, 'caseNo');
    if (cn.isNotEmpty) return 'no:$cn';
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
    final caseNo = fieldAsDisplayString(hearingData, 'caseNo');
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

    var effectiveCaseMaps = caseMaps;
    if (effectiveCaseMaps.isEmpty) {
      try {
        effectiveCaseMaps = await loadCaseMapsForHearing(hearingData);
      } catch (_) {}
    }

    final merged = mergeHearingSources(sources, caseMaps: effectiveCaseMaps);

    // Keep identity fields from the selected hearing record stable when authentic.
    // When anchor is a placeholder like "SAMPLE", preserve richer case number from linked cases.
    final anchorCaseNo = fieldAsDisplayString(hearingData, 'caseNo');
    if (anchorCaseNo.isNotEmpty && !isPlaceholderCaseNo(anchorCaseNo)) {
      merged['caseNo'] = anchorCaseNo;
    } else if (isPlaceholderCaseNo(fieldAsDisplayString(merged, 'caseNo'))) {
      for (final cm in effectiveCaseMaps) {
        final cn = fieldAsDisplayString(cm, 'caseNumber').isNotEmpty
            ? fieldAsDisplayString(cm, 'caseNumber')
            : fieldAsDisplayString(cm, 'caseNo');
        if (cn.isNotEmpty && !isPlaceholderCaseNo(cn)) {
          merged['caseNo'] = cn;
          break;
        }
      }
    }
    final anchorClient = fieldAsDisplayString(hearingData, 'clientName');
    if (anchorClient.isNotEmpty) {
      merged['clientName'] = anchorClient;
    }

    merged['hearingDocId'] = hearingDocId;
    merged['eventType'] = 'hearing';
    applyResolvedCaseTitle(
      merged,
      linkedCase: findLinkedCase(merged, effectiveCaseMaps),
      caseMaps: effectiveCaseMaps,
    );
    final when =
        resolveEventDate(merged) ?? resolveEventDate(hearingData);
    if (when != null) {
      merged['eventDate'] = when;
    }
    final venue = resolveVenueForDisplay(merged);
    if (venue.isNotEmpty) {
      merged['location'] = venue;
    }
    return merged;
  }

  static HearingCalendarFields fromHearingDoc(
    Map<String, dynamic> hd, {
    List<Map<String, dynamic>> caseMaps = const [],
  }) {
    final enriched = enrichHearingData(hd, caseMaps: caseMaps);
    final clientName = fieldAsDisplayString(enriched, 'clientName');
    final caseNo = fieldAsDisplayString(enriched, 'caseNo');
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
      final venue = resolveVenueForDisplay(merged);
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
        if (venue.isNotEmpty) 'location': venue,
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

  static const _monthNumbers = {
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sept': 9,
    'sep': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  static String _monthPhrase(String month, String day, String year) {
    final n = _monthNumbers[month.toLowerCase().replaceAll('.', '')];
    const names = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (n == null) return '$month $day, $year';
    return '${names[n]} $day, $year';
  }

  static const _monthToken =
      r'(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec)';

  /// Year for OCR lines that say "October 28" with no year.
  static DateTime _yearHint(Map<String, dynamic> hd) {
    final created = hd['createdAt'];
    if (created is Timestamp) return created.toDate();
    if (created is DateTime) return created;
    final updated = hd['updatedAt'];
    if (updated is Timestamp) return updated.toDate();
    if (updated is DateTime) return updated;
    return DateTime.now();
  }

  static DateTime _dayWithHint(int month, int day, DateTime hint) {
    var candidate = DateTime(hint.year, month, day);
    if (candidate.isBefore(hint.subtract(const Duration(days: 60)))) {
      candidate = DateTime(hint.year + 1, month, day);
    }
    return candidate;
  }

  /// Date the order actually sets ("reset the pre-trial on October 28"),
  /// not the signing line ("Done in open court this 8th day of September").
  static DateTime? nextSetHearingDate(Map<String, dynamic> hd) {
    final blobs = <String>[
      hearingFieldAsString(hd, 'hearingDate'),
      hearingFieldAsString(hd, 'fullText'),
      hearingFieldAsString(hd, 'message'),
      hearingFieldAsString(hd, 'summary'),
      hearingFieldAsString(hd, 'hearingTime'),
    ];
    final withYear = RegExp(
      '(?:reset|set|schedul\\w*|next hearing)\\b[^\\n.]{0,80}?\\bon\\s+'
      '$_monthToken\\.?\\s+'
      r'(\d{1,2}),?\s+(\d{4})',
      caseSensitive: false,
    );
    final withoutYear = RegExp(
      '(?:reset|set|schedul\\w*|next hearing|hearing)\\b[^\\n.]{0,80}?\\bon\\s+'
      '$_monthToken\\.?\\s+'
      r'(\d{1,2})(?!\s*,?\s*\d{4})',
      caseSensitive: false,
    );
    final hint = _yearHint(hd);
    for (final blob in blobs) {
      if (blob.isEmpty) continue;
      final dated = withYear.firstMatch(blob);
      if (dated != null) {
        final phrase = _monthPhrase(dated.group(1)!, dated.group(2)!, dated.group(3)!);
        final day = _parseHearingDateString(phrase);
        if (day != null) {
          final window = blob.substring(
            dated.end,
            (dated.end + 48) > blob.length ? blob.length : dated.end + 48,
          );
          return _clockOnDay(day, window);
        }
      }
      final loose = withoutYear.firstMatch(blob);
      if (loose != null) {
        final month = _monthNumbers[loose.group(1)!.toLowerCase().replaceAll('.', '')];
        final dayNum = int.tryParse(loose.group(2)!);
        if (month != null && dayNum != null) {
          final day = _dayWithHint(month, dayNum, hint);
          final window = blob.substring(
            loose.end,
            (loose.end + 48) > blob.length ? blob.length : loose.end + 48,
          );
          return _clockOnDay(day, window);
        }
      }
    }
    return null;
  }

  static DateTime _clockOnDay(DateTime day, String window) {
    final lower = window.toLowerCase();
    final match = RegExp(r'(\d{1,2})(?::(\d{2}))?').firstMatch(lower);
    if (match == null) {
      return DateTime(day.year, day.month, day.day, 8, 30);
    }
    var hour = int.tryParse(match.group(1)!) ?? 8;
    final minute = int.tryParse(match.group(2) ?? '') ?? 0;
    final afternoon = lower.contains('pm') ||
        lower.contains('afternoon') ||
        lower.contains('evening');
    final morning = lower.contains('am') || lower.contains('morning');
    if (afternoon && hour < 12) hour += 12;
    if (morning && hour == 12) hour = 0;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  /// "{branch} · Hearing {Month D, YYYY}". Calendar helpers only; the push uses the SMS text.
  static String pushHearingWhenLine(Map<String, dynamic> hd) {
    final branch = hearingFieldAsString(hd, 'courtBranch');
    final when = nextSetHearingDate(hd);
    final dateLabel = when != null
        ? DateFormat('MMMM d, yyyy').format(when)
        : hearingFieldAsString(hd, 'hearingDate');
    final kind = _hearingKindLabel(hd);
    final whenText = dateLabel.isEmpty ? '' : '$kind $dateLabel';
    return [
      if (branch.isNotEmpty) branch,
      if (whenText.isNotEmpty) whenText,
    ].join(' · ');
  }

  /// Same body as the hearing SMS and the phone push.
  static String pushHearingContext(Map<String, dynamic> hd) {
    return HearingNotificationFormatter.buildPopupBody(hd);
  }

  static String _hearingKindLabel(Map<String, dynamic> hd) {
    final blob = [
      hearingFieldAsString(hd, 'fullText'),
      hearingFieldAsString(hd, 'summary'),
      hearingFieldAsString(hd, 'hearingTime'),
    ].join(' ').toLowerCase();
    if (blob.contains('pre-trial') || blob.contains('pretrial')) {
      return 'Pre-trial';
    }
    if (blob.contains('arraignment')) return 'Arraignment';
    if (blob.contains('mediation')) return 'Mediation';
    return 'Hearing';
  }

  /// Calendar cell date: prefer AI `hearingDate` / `hearingTime` (e.g. April 22 → day 22),
  /// not upload `createdAt` or stale `hearingDateTime`.
  ///
  /// The structured AI fields are checked first so a new automated hearing
  /// can land on the grid without scanning the full court-order text.
  static DateTime? resolveEventDate(Map<String, dynamic> hd) {
    try {
      final normalized = normalizeHearingDoc(hd);
      final fromFields = _scheduleFromHearingFields(normalized);
      if (fromFields != null) return fromFields;

      final reset = nextSetHearingDate(hd);
      if (reset != null) return reset;

      // Stored hearing timestamp wins over the first date in the OCR blob
      // (signing lines like "this 8th day of September" used to move rows).
      final hts = normalized['hearingDateTime'] ??
          hd['hearingDateTime'] ??
          hd['eventDate'];
      if (hts is Timestamp) return hts.toDate();
      if (hts is DateTime) return hts;

      final fromOrderText = _dateFromHearingOrderText(normalized);
      if (fromOrderText != null) return fromOrderText;

      final fullText = (hd['fullText'] as String?)?.trim() ?? '';
      if (fullText.isNotEmpty) {
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

      // Do not abort when hearingDate string failed earlier — keep trying
      // caseTitle / summary blobs (SAMPLE orders often put the date there).
      for (final key in const ['caseTitle', 'title', 'summary', 'clientName']) {
        final blob = hearingFieldAsString(normalized, key);
        if (blob.isEmpty) continue;
        final fromBlob = _dateFromHearingOrderText({'hearingDate': blob});
        if (fromBlob != null) return fromBlob;
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
    day ??= _parseMonthDayNoYear(dateStr, _yearHint(hd));
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
    final minuteMatch = RegExp(r'(\d{1,2})\s*:\s*(\d{2})').firstMatch(lower);
    final minute = int.tryParse(minuteMatch?.group(2) ?? '') ?? 30;
    final afternoon = lower.contains('pm') ||
        lower.contains('afternoon') ||
        lower.contains('evening');
    final morning = lower.contains('am') || lower.contains('morning');
    if (afternoon && hour < 12) hour += 12;
    if (morning && hour == 12) hour = 0;
    return DateTime(day.year, day.month, day.day, hour, minute);
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
      r'(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2})\s*,?\s+(\d{4})',
      caseSensitive: false,
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

  static DateTime? _parseMonthDayNoYear(String dateStr, DateTime hint) {
    final m = RegExp(
      r'(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec)\.?\s+(\d{1,2})\b',
      caseSensitive: false,
    ).firstMatch(dateStr.replaceAll(RegExp(r'\s+'), ' ').trim());
    if (m == null) return null;
    final month = _monthNumbers[m.group(1)!.toLowerCase().replaceAll('.', '')];
    final day = int.tryParse(m.group(2)!);
    if (month == null || day == null) return null;
    return _dayWithHint(month, day, hint);
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
      r'(?:on\s+)?(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2})\s*,?\s+(\d{4})',
      caseSensitive: false,
    );
    final yearless = RegExp(
      r'(?:on\s+)?(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2})\b(?!\s*,?\s*\d{4})',
      caseSensitive: false,
    );
    final hint = _yearHint(hd);
    for (final blob in blobs) {
      if (blob.isEmpty) continue;
      final m = re.firstMatch(blob);
      if (m != null) {
        final phrase = '${m.group(1)} ${m.group(2)}, ${m.group(3)}';
        final day = _parseHearingDateString(phrase);
        if (day != null) {
          return _scheduleFromHearingFields({
            ...hd,
            'hearingDate': phrase,
          });
        }
      }
      final loose = yearless.firstMatch(blob);
      if (loose != null) {
        final month = _monthNumbers[loose.group(1)!.toLowerCase()];
        final dayNum = int.tryParse(loose.group(2)!);
        if (month != null && dayNum != null) {
          final day = _dayWithHint(month, dayNum, hint);
          return _scheduleFromHearingFields({
            ...hd,
            'hearingDate': DateFormat('MMMM d, yyyy').format(day),
          });
        }
      }
    }
    return null;
  }

  static bool isCourtImportRow(Map<String, dynamic> hd) {
    final cn = asDisplayString(hd['caseNo']);
    final ft = asDisplayString(hd['fullText']);
    return cn.isNotEmpty && ft.isNotEmpty;
  }

  static final _legalNoticeToken = RegExp(
    r'(hearing|court|trial|arraignment|mediation|conference|motion|'
    r'order|versus|\bvs\b|branch|people|appointment|reminder|calendar|'
    r'pre-?trial|promulgation|status|inquest|bail|plea|wherefore|'
    r'spec(?:ial)?\.?\s*case|crim(?:inal)?\.?\s*case)',
    caseSensitive: false,
  );

  static final _noticeStopword = RegExp(
    r'^(hearing|scheduled|updated|message|notice|court|order|event|'
    r'reminder|calendar|activity|new)$',
    caseSensitive: false,
  );

  /// Keyboard-mash / test titles (e.g. sbajshsahxsax) — not a real hearing notice.
  static bool isGibberishNoticeText(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    if (_legalNoticeToken.hasMatch(t)) return false;
    final words = t
        .split(RegExp(r'[^a-zA-Z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return false;
    if (words.length == 1 && _isGibberishToken(words.first)) return true;
    final significant = words
        .where((w) => w.length >= 8 && !_noticeStopword.hasMatch(w))
        .toList();
    if (significant.isEmpty) return false;
    return significant.every(_isGibberishToken);
  }

  static bool _isGibberishToken(String raw) {
    if (RegExp(r'\d').hasMatch(raw)) return false;
    final s = raw.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (s.length < 8) return false;
    if (_legalNoticeToken.hasMatch(s)) return false;
    if (RegExp(r'(.)\1{2,}').hasMatch(s)) return true;
    if (RegExp(r'(.{2,5})\1').hasMatch(s)) return true;
    if (!RegExp(r'[aeiou]').hasMatch(s)) return true;
    if (RegExp(r'[^aeiou]{4,}').hasMatch(s)) return true;
    return false;
  }

  /// Head and tail only. Reminders loads dozens of hearings on the UI thread;
  /// joining an entire court-order `fullText` for each one freezes Android
  /// ("Law Connect isn't responding"). Promo and closing lines stay visible.
  static String _forSpamScan(dynamic value) {
    if (value == null) return '';
    final raw = value is String ? value : value.toString();
    if (raw.isEmpty) return '';
    const head = 1800;
    const tail = 500;
    final clipped = raw.length <= head + tail
        ? raw
        : '${raw.substring(0, head)} ${raw.substring(raw.length - tail)}';
    return clipped.toLowerCase();
  }

  static String _spamBlob(Map<String, dynamic> d, List<String> keys) {
    final parts = <String>[];
    for (final key in keys) {
      final piece = _forSpamScan(d[key]);
      if (piece.isNotEmpty) parts.add(piece);
    }
    return parts.join(' ');
  }

  /// First non-empty field, clipped before [String.trim] so a court order
  /// is not copied in full on the UI thread.
  static String _firstClippedField(Map<String, dynamic> d, List<String> keys) {
    for (final key in keys) {
      final value = d[key];
      if (!hasNonEmptyText(value)) continue;
      return _forSpamScan(value).trim();
    }
    return '';
  }

  /// True when [value] has a non-whitespace character, without copying a long order.
  static bool hasNonEmptyText(dynamic value) {
    if (value == null) return false;
    if (value is String) {
      for (var i = 0; i < value.length; i++) {
        final c = value.codeUnitAt(i);
        if (c != 32 && c != 9 && c != 10 && c != 13) return true;
      }
      return false;
    }
    return value.toString().trim().isNotEmpty;
  }

  /// Promotional / test / misclassified rows (not a court order).
  static bool isNonCourtHearingSpam(Map<String, dynamic> d) {
    if (isEatingHearingJunk(d)) return true;
    if (isOutOfSystemPumpedNotice(d)) return true;
    final source = '${d['source'] ?? ''}'.toLowerCase();
    final activity = '${d['activityType'] ?? ''}'.toLowerCase();
    final fromN8n = source == 'n8n' ||
        activity == 'court_import' ||
        source.contains('n8n');
    final blob = _spamBlob(d, const [
      'title',
      'caseTitle',
      'summary',
      'fullText',
      'message',
      'subject',
      'description',
      'activityType',
      'body',
      'notes',
    ]);
    final compact = blob.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    if (blob.contains('blasttv') ||
        blob.contains('voucher code') ||
        blob.contains('voucher redemption') ||
        blob.contains('enjoy your 30-day') ||
        blob.contains('[ai hearing (eating)]') ||
        blob.contains('hearing (eating)') ||
        compact.contains('ai hearing eating') ||
        compact.contains('hearing eating') ||
        blob.contains('cursor.com') ||
        blob.contains('cursor.sh') ||
        blob.contains('cursor team') ||
        blob.contains('anysphere') ||
        blob.contains('browser layout editor') ||
        blob.contains('browser-based layout editor') ||
        blob.contains('writing and fixing code faster') ||
        blob.contains('try debug mode') ||
        blob.contains('changelog/2-2') ||
        blob.contains('dear developer') ||
        blob.contains('firebase.google.com')) {
      return true;
    }
    final caseNo = asDisplayString(d['caseNo']);
    final caseNoKey = caseNo.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final placeholderCaseNo = caseNoKey.isEmpty ||
        caseNoKey == 'court order' ||
        caseNoKey == 'court hearing' ||
        caseNoKey == 'hearing' ||
        caseNoKey == 'order' ||
        caseNoKey == 'n/a' ||
        caseNoKey == 'none';
    final importedText = hasNonEmptyText(d['fullText'])
        ? _forSpamScan(d['fullText'])
        : _forSpamScan(d['message']);
    final importedCourtRow =
        !placeholderCaseNo && caseNo.isNotEmpty && importedText.isNotEmpty;
    // Real n8n / court-order import — show unless promo junk above.
    if (fromN8n) return false;
    if (importedCourtRow || importedText.isNotEmpty) return false;
    if (_isCourtOrderText(blob) ||
        blob.contains('regional trial court') ||
        blob.contains('wherefore') ||
        blob.contains('so ordered') ||
        blob.contains('people of the philippines') ||
        blob.contains('in open court') ||
        blob.contains('sample')) {
      return false;
    }
    if (placeholderCaseNo) return true;
    if (compact.contains('eating') &&
        !compact.contains('court') &&
        !compact.contains('branch') &&
        !compact.contains('versus')) {
      return true;
    }
    final fullText = _forSpamScan(d['fullText']);
    if (fullText.length > 160 && _isCourtOrderText(fullText)) {
      return false;
    }
    final title = _firstClippedField(d, const ['title', 'caseTitle']);
    final body = _firstClippedField(
      d,
      const ['description', 'message', 'summary', 'body'],
    );
    if (title.isNotEmpty && isGibberishNoticeText(title)) return true;
    if (body.isNotEmpty && isGibberishNoticeText(body)) return true;
    return false;
  }

  /// Test mash like "[AI] Hearing (eating)" — never a real court order.
  static bool isEatingHearingJunk(Map<String, dynamic> d) {
    final blob = _spamBlob(d, const [
      'title',
      'caseTitle',
      'action',
      'details',
      'summary',
      'fullText',
      'message',
      'subject',
      'description',
      'activityType',
      'body',
      'notes',
    ]);
    final compact = blob.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    if (blob.contains('[ai hearing (eating)]') ||
        blob.contains('hearing (eating)') ||
        compact.contains('ai hearing eating') ||
        compact.contains('hearing eating')) {
      return true;
    }
    return compact.contains('eating') &&
        compact.contains('hearing') &&
        !compact.contains('court') &&
        !compact.contains('branch') &&
        !compact.contains('versus');
  }

  /// Staff work diary: hide email-ingest test hearings.
  static bool isJunkWorkLog(Map<String, dynamic> log) =>
      isEatingHearingJunk(log);

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
    final blob = '$fullText\n$message'.toLowerCase();
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

    final parties = splitHearingPartyNames(clientName);
    if (parties.isEmpty) {
      add(clientName);
    } else {
      for (final p in parties) {
        add(p);
      }
    }
    add(caseTitle);
    add(courtBranch);
    add(senderName);
    add(fieldAsDisplayString(hd, 'caseNo'));

    return parts;
  }
}
