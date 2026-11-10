/// Turns OCR court-order text into blocks that can be laid out like a pleading.
///
/// The stored string is unchanged. Line breaks from the scan are joined back
/// into headings, the party caption, and paragraphs.
class CourtOrderPartyLine {
  const CourtOrderPartyLine(this.text, {this.centered = false});

  final String text;
  final bool centered;
}

class CourtOrderDisplay {
  const CourtOrderDisplay({
    required this.isPleading,
    required this.header,
    required this.parties,
    required this.caseMeta,
    required this.heading,
    required this.paragraphs,
    required this.soOrdered,
    required this.closing,
    required this.signature,
    required this.footnotes,
  });

  final bool isPleading;
  final List<String> header;
  final List<CourtOrderPartyLine> parties;
  final List<String> caseMeta;
  final String? heading;
  final List<String> paragraphs;
  final bool soOrdered;
  final String? closing;
  final List<String> signature;
  final List<String> footnotes;

  factory CourtOrderDisplay.parse(String raw) {
    final lines = _preprocessLines(_lines(raw));
    if (lines.isEmpty) {
      return const CourtOrderDisplay(
        isPleading: false,
        header: [],
        parties: [],
        caseMeta: [],
        heading: null,
        paragraphs: [],
        soOrdered: false,
        closing: null,
        signature: [],
        footnotes: [],
      );
    }

    final header = <String>[];
    final partiesRaw = <CourtOrderPartyLine>[];
    final caseMeta = <String>[];
    String? heading;
    var i = 0;

    while (i < lines.length && (_isNoise(lines[i]) || _isInboxNoise(lines[i]))) {
      i++;
    }
    while (i < lines.length && _isHeaderLine(lines[i])) {
      final cleaned = _cleanHeaderLine(lines[i]);
      if (cleaned.isNotEmpty) header.add(cleaned);
      i++;
    }

    while (i < lines.length && !_isBodyStart(lines[i])) {
      final line = lines[i];
      if (_isNoise(line) ||
          _isRunningFooter(line) ||
          _isInboxNoise(line) ||
          _isSampleWatermark(line)) {
        i++;
        continue;
      }
      if (_isOrderHeading(line)) break;
      if (_isCaseMetaStart(line)) {
        var meta = line;
        i++;
        while (i < lines.length && _isCaseMetaContinuation(lines[i])) {
          meta = _append(meta, lines[i]);
          i++;
        }
        var cleanedMeta = _tidy(meta);
        // If versus was mashed onto case number (e.g. "Civil Case No. 5297 versus -")
        if (RegExp(r'\s+versus\s*[-–—]?$', caseSensitive: false).hasMatch(cleanedMeta)) {
          cleanedMeta = cleanedMeta.replaceAll(RegExp(r'\s+versus\s*[-–—]?$', caseSensitive: false), '').trim();
          partiesRaw.add(const CourtOrderPartyLine('- versus -', centered: true));
        }
        caseMeta.add(cleanedMeta);
        continue;
      }
      if (_isRole(line)) {
        partiesRaw.add(CourtOrderPartyLine(_tidyRole(line), centered: true));
        i++;
        continue;
      }
      var names = line;
      i++;
      while (i < lines.length && _isNameContinuation(lines[i])) {
        names = _append(names, lines[i]);
        i++;
      }
      var rawTidy = _stripEmailsFromPartyText(_tidy(names));
      // Peel accidental OCR column leak like "Possession" inside name: "AXEL JOSEPH Possession L. BINAORO"
      final tidy = rawTidy.replaceAll(RegExp(r'\bPossession\s+', caseSensitive: false), '');
      if (tidy.isNotEmpty &&
          !_isSampleWatermark(tidy) &&
          !_isJunkPartyName(tidy) &&
          !_isEmailContactLine(tidy)) {
        partiesRaw.add(CourtOrderPartyLine(tidy));
      }
    }

    if (i < lines.length && _isOrderHeading(lines[i])) {
      heading = _tidyHeading(lines[i]);
      i++;
    }

    final body = <String>[];
    var soOrdered = false;
    while (i < lines.length) {
      final line = lines[i];
      if (_isNoise(line) ||
          _isRunningFooter(line) ||
          _isOrderHeading(line) ||
          _isInboxNoise(line) ||
          _isSampleWatermark(line) ||
          (_isCaseMetaStart(line) && line.length < 48)) {
        i++;
        continue;
      }
      if (_isSoOrdered(line)) {
        soOrdered = true;
        i++;
        break;
      }
      body.add(line);
      i++;
    }

    final paragraphs = _reflowParagraphs(body);
    String? closing;
    final signature = <String>[];
    final footnotes = <String>[];

    while (i < lines.length) {
      final line = lines[i];
      if (_isNoise(line) ||
          _isRunningFooter(line) ||
          _isOrderHeading(line) ||
          _isInboxNoise(line) ||
          _isSampleWatermark(line)) {
        i++;
        continue;
      }
      if (_isSoOrdered(line)) {
        soOrdered = true;
        i++;
        continue;
      }
      if (_isCaseMetaStart(line)) {
        i++;
        while (i < lines.length && _isCaseMetaContinuation(lines[i])) {
          i++;
        }
        continue;
      }
      final lower = line.toLowerCase();
      if (lower.startsWith('cc:') ||
          lower.startsWith('cc ') ||
          (footnotes.isNotEmpty && lower.startsWith('atty'))) {
        footnotes.add(_tidy(line));
        i++;
        continue;
      }
      if (closing == null && lower.startsWith('done in')) {
        var done = line;
        i++;
        while (i < lines.length && _isClosingContinuation(lines[i])) {
          done = _append(done, lines[i]);
          i++;
        }
        closing = _tidy(done);
        continue;
      }
      if (lower.contains('presiding judge') || _looksLikeJudgeName(line)) {
        signature.add(_tidy(line));
        i++;
        continue;
      }
      if (signature.isNotEmpty && line.length < 42 && !_isCaseMetaStart(line)) {
        signature.add(_tidy(line));
        i++;
        continue;
      }
      paragraphs.add(_tidy(line));
      i++;
    }

    final parties = _normalizePartyCaption(partiesRaw);

    // If heading was omitted by OCR, default to 'ORDER' when it contains court order hallmarks
    heading ??= (soOrdered || paragraphs.any((p) => p.toUpperCase().contains('WHEREFORE')))
        ? 'ORDER'
        : null;

    for (var m = 0; m < caseMeta.length; m++) {
      var item = caseMeta[m];
      if (item.toLowerCase().endsWith('with') ||
          (item.toLowerCase().contains('recovery of ownership') &&
              !item.toLowerCase().contains('possession'))) {
        caseMeta[m] = '$item Possession'.replaceAll(RegExp(r'\s+'), ' ').trim();
      }
    }

    final pleading = header.length >= 2 ||
        heading != null ||
        (caseMeta.isNotEmpty && parties.isNotEmpty) ||
        paragraphs.any((p) => p.toUpperCase().contains('WHEREFORE'));

    if (!pleading) {
      return CourtOrderDisplay(
        isPleading: false,
        header: const [],
        parties: const [],
        caseMeta: const [],
        heading: null,
        paragraphs: _reflowParagraphs(lines.where((l) => !_isNoise(l)).toList()),
        soOrdered: false,
        closing: null,
        signature: const [],
        footnotes: const [],
      );
    }

    return CourtOrderDisplay(
      isPleading: true,
      header: header,
      parties: parties,
      caseMeta: caseMeta,
      heading: heading,
      paragraphs: paragraphs,
      soOrdered: soOrdered,
      closing: closing,
      signature: signature,
      footnotes: footnotes,
    );
  }
}

/// Expand mashed SAMPLE/OCR lines and strip watermarks before caption parse.
List<String> _preprocessLines(List<String> raw) {
  final out = <String>[];
  for (final original in raw) {
    final line = original.trim();
    if (line.isEmpty) continue;
    // Expand first — SAMPLE banner is often mashed onto the court header.
    final pieces = _expandMashedLine(line);
    if (pieces.isEmpty && _isPureSampleWatermark(line)) continue;

    for (final piece in pieces) {
      final cleaned = _stripSampleDecorations(piece).trim();
      if (cleaned.isEmpty) continue;
      if (_isPureSampleWatermark(cleaned)) continue;
      if (_isInboxNoise(cleaned)) continue;
      out.add(cleaned);
    }
  }
  return out;
}

List<String> _expandMashedLine(String line) {
  final lower = line.toLowerCase();
  final hasCourt = lower.contains('republic of the philippines') ||
      lower.contains('regional trial court') ||
      lower.contains('municipal trial court') ||
      lower.contains('judicial region') ||
      RegExp(r'\bbranch\s+\d+', caseSensitive: false).hasMatch(line);

  if (!hasCourt || line.length < 40) {
    // "Sample document layout only JOREN LIMPAHAN" → name only.
    final sampleOnly = RegExp(
      r'^sample\s+document\s+layout\s+only\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (sampleOnly != null) {
      final name = sampleOnly.group(1)!.trim();
      return name.isEmpty ? const [] : [name];
    }
    return [line];
  }

  // Peel known court phrases out of one mashed header line.
  final markers = <RegExp>[
    RegExp(r'Republic of the Philippines', caseSensitive: false),
    RegExp(r'REGIONAL TRIAL COURT', caseSensitive: false),
    RegExp(r'MUNICIPAL TRIAL COURT[^\n]*', caseSensitive: false),
    RegExp(r'METROPOLITAN TRIAL COURT[^\n]*', caseSensitive: false),
    RegExp(r'\d+(?:st|nd|rd|th)\s+Judicial Region', caseSensitive: false),
    RegExp(r'BRANCH\s+\d+[^\n]*', caseSensitive: false),
  ];

  final hits = <({int start, int end, String text})>[];
  for (final re in markers) {
    for (final m in re.allMatches(line)) {
      hits.add((start: m.start, end: m.end, text: m.group(0)!.trim()));
    }
  }
  if (hits.isEmpty) return [line];

  hits.sort((a, b) => a.start.compareTo(b.start));
  final pieces = <String>[];
  var cursor = 0;
  for (final hit in hits) {
    if (hit.start < cursor) continue;
    final before = line.substring(cursor, hit.start).trim();
    final leftover = _stripSampleDecorations(before).trim();
    if (leftover.isNotEmpty &&
        !_isPureSampleWatermark(leftover) &&
        !_looksLikeCourtFragment(leftover)) {
      // Orphan name stuck before court header (e.g. after SAMPLE banner).
      if (_looksLikePartyName(leftover)) pieces.add(leftover);
    }
    pieces.add(_tidy(hit.text));
    cursor = hit.end;
  }
  final tail = _stripSampleDecorations(line.substring(cursor)).trim();
  if (tail.isNotEmpty &&
      !_isPureSampleWatermark(tail) &&
      _looksLikePartyName(tail)) {
    pieces.add(tail);
  }
  return pieces.isEmpty ? [line] : pieces;
}

String _stripSampleDecorations(String line) {
  var s = line.trim();
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
  s = s.replaceAll(
    RegExp(r'\bNOT AN OFFICIAL COURT DOCUMENT\b\.?', caseSensitive: false),
    ' ',
  );
  s = s.replaceAll(RegExp(r'^[-\s•]+'), '');
  return s.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
}

String _cleanHeaderLine(String line) => _stripSampleDecorations(line);

bool _isPureSampleWatermark(String line) {
  final lower = line.toLowerCase().trim();
  if (lower.isEmpty) return true;
  if (lower == 'sample') return true;
  if (lower == 'sample document layout only') return true;
  if (lower == 'not an official court document') return true;
  // Whole line is only the SAMPLE disclaimer (no court/party leftover).
  final stripped = _stripSampleDecorations(line);
  if (stripped.isEmpty) return true;
  final strippedLower = stripped.toLowerCase();
  if (strippedLower.startsWith('sample - not an official') ||
      strippedLower.startsWith('sample – not an official')) {
    // Still only watermark text after strip failed to peel court phrases.
    return !strippedLower.contains('republic') &&
        !strippedLower.contains('trial court') &&
        !strippedLower.contains('branch');
  }
  return false;
}

bool _isSampleWatermark(String line) {
  final lower = line.toLowerCase().trim();
  return lower.contains('not an official court document') ||
      lower.contains('sample document layout only') ||
      (lower.startsWith('sample') && lower.contains('official'));
}

bool _isJunkPartyName(String line) {
  final lower = line.toLowerCase().trim();
  if (lower.isEmpty) return true;
  if (_isSampleWatermark(line) || _isPureSampleWatermark(line)) return true;
  if (lower == 'sample' || lower == 'sample case') return true;
  if (lower.startsWith('for: sample')) return true;
  return false;
}

bool _looksLikeCourtFragment(String line) {
  final lower = line.toLowerCase();
  return lower.contains('republic') ||
      lower.contains('trial court') ||
      lower.contains('judicial') ||
      lower.startsWith('branch');
}

bool _looksLikePartyName(String line) {
  if (line.length < 3 || line.length > 120) return false;
  if (_isRole(line) || _isCaseMetaStart(line) || _isOrderHeading(line)) {
    return false;
  }
  if (_isSampleWatermark(line) || _isJunkPartyName(line)) return false;
  final lower = line.toLowerCase();
  if (lower.contains('republic of the philippines') ||
      lower.contains('trial court') ||
      lower.contains('judicial region') ||
      lower.startsWith('branch ') ||
      lower.startsWith('email') ||
      lower.startsWith('contact')) {
    return false;
  }
  final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (letters.length < 3) return false;
  return RegExp(r'[A-Za-z]').hasMatch(line);
}

/// Force caption order: names → Plaintiff, → -versus- → names → Defendant.
List<CourtOrderPartyLine> _normalizePartyCaption(
  List<CourtOrderPartyLine> raw,
) {
  if (raw.isEmpty) return raw;

  final beforeVersus = <String>[];
  final afterVersus = <String>[];
  String? plaintiffRole;
  String? defendantRole;
  var versus = '- versus -';
  var sawVersus = false;

  for (final line in raw) {
    final text = _stripEmailsFromPartyText(line.text.trim());
    if (text.isEmpty ||
        _isJunkPartyName(text) ||
        _isEmailContactLine(text)) {
      continue;
    }
    final role = _roleKind(text);
    if (role == _RoleKind.versus) {
      sawVersus = true;
      versus = _tidyRole(text);
      continue;
    }
    if (role == _RoleKind.plaintiff) {
      plaintiffRole = _canonicalRole(text, plaintiff: true);
      continue;
    }
    if (role == _RoleKind.defendant) {
      defendantRole = _canonicalRole(text, plaintiff: false);
      continue;
    }
    if (!sawVersus) {
      beforeVersus.add(text);
    } else {
      afterVersus.add(text);
    }
  }

  // Role-first OCR (Plaintiff, / name) left names empty on one side — keep as-is
  // only when we still have names.
  if (beforeVersus.isEmpty && afterVersus.isEmpty) return raw;

  // If afterVersus is empty (OCR put defendant names before versus), split beforeVersus:
  if (afterVersus.isEmpty && beforeVersus.length >= 2) {
    var splitIdx = -1;
    for (var k = 1; k < beforeVersus.length; k++) {
      final entry = beforeVersus[k].trim();
      if (!entry.toLowerCase().startsWith('namely') &&
          !entry.toLowerCase().startsWith('and ') &&
          !entry.toLowerCase().startsWith('& ')) {
        splitIdx = k;
        break;
      }
    }
    if (splitIdx != -1) {
      final defs = beforeVersus.sublist(splitIdx);
      beforeVersus.removeRange(splitIdx, beforeVersus.length);
      afterVersus.addAll(defs);
    } else {
      final last = beforeVersus.removeLast();
      afterVersus.add(last);
    }
  }

  plaintiffRole ??= beforeVersus.isNotEmpty ? 'Plaintiff,' : null;
  defendantRole ??= afterVersus.isNotEmpty ? 'Defendants.' : null;

  final out = <CourtOrderPartyLine>[];
  for (final name in beforeVersus) {
    out.add(CourtOrderPartyLine(name));
  }
  if (plaintiffRole != null) {
    out.add(CourtOrderPartyLine(plaintiffRole, centered: true));
  }
  out.add(CourtOrderPartyLine(versus, centered: true));
  for (final name in afterVersus) {
    out.add(CourtOrderPartyLine(name));
  }
  if (defendantRole != null) {
    out.add(CourtOrderPartyLine(defendantRole, centered: true));
  }
  return out;
}

enum _RoleKind { plaintiff, defendant, versus }

_RoleKind? _roleKind(String line) {
  if (!_isRole(line) && !_isLooseRole(line)) return null;
  final letters = line.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  if (letters == 'versus' || letters == 'vs') return _RoleKind.versus;
  if (letters.startsWith('plaintiff') ||
      letters.startsWith('petitioner')) {
    return _RoleKind.plaintiff;
  }
  if (letters.startsWith('defendant') ||
      letters.startsWith('respondent') ||
      letters == 'accused') {
    return _RoleKind.defendant;
  }
  return null;
}

bool _isLooseRole(String line) {
  final letters = line.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  return letters == 'plaintiff' ||
      letters == 'plaintiffs' ||
      letters == 'defendant' ||
      letters == 'defendants' ||
      letters == 'petitioner' ||
      letters == 'petitioners' ||
      letters == 'respondent' ||
      letters == 'respondents' ||
      letters == 'versus' ||
      letters == 'accused';
}

String _canonicalRole(String line, {required bool plaintiff}) {
  final letters = line.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  if (plaintiff) {
    if (letters.startsWith('petitioners')) return 'Petitioners,';
    if (letters.startsWith('petitioner')) return 'Petitioner,';
    if (letters.startsWith('plaintiffs')) return 'Plaintiffs,';
    return 'Plaintiff,';
  }
  if (letters.startsWith('respondents')) return 'Respondents.';
  if (letters.startsWith('respondent')) return 'Respondent.';
  if (letters.startsWith('defendants')) return 'Defendants.';
  if (letters == 'accused') return 'Accused.';
  return 'Defendant.';
}

List<String> _lines(String raw) {
  return raw
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

String _tidy(String value) {
  return value
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .trim();
}

String _append(String prev, String next) {
  if (RegExp(r'[A-Za-z]-$').hasMatch(prev) &&
      RegExp(r'^[a-z]').hasMatch(next)) {
    return prev.substring(0, prev.length - 1) + next;
  }
  if (next.toLowerCase().startsWith('namely')) return '$prev\n$next';
  return '$prev $next';
}

bool _isInboxNoise(String line) {
  final lower = line.toLowerCase().trim();
  return lower.startsWith('case no.:') ||
      lower.startsWith('case no:') ||
      lower.startsWith('client:') ||
      lower.startsWith('court / branch:') ||
      lower.startsWith('order / notice') ||
      lower.startsWith('hearing date/time') ||
      lower.startsWith('matter:') ||
      lower.startsWith('case record id');
}

bool _isNoise(String line) {
  if (RegExp(r'^page\s+\d+\s+of\s+\d+$', caseSensitive: false).hasMatch(line)) {
    return true;
  }
  if (RegExp(r'^[xX\-\._=\s*•]+$').hasMatch(line)) return true;
  if (RegExp(r'^/+\w+$').hasMatch(line)) return true;
  return line.length <= 1;
}

bool _isRunningFooter(String line) {
  if (_compactLetters(line) == 'PRETRIALORDER') return true;
  return RegExp(
    r'^(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}$',
    caseSensitive: false,
  ).hasMatch(line);
}

bool _isEmailContactLine(String line) {
  final t = line.trim();
  if (t.isEmpty) return false;
  final lower = t.toLowerCase();
  if (lower.startsWith('email address') ||
      lower.startsWith('email:') ||
      lower.startsWith('e-mail')) {
    return true;
  }
  // Bare court contact email under BRANCH (PDF header).
  return RegExp(
    r'^[\w.+-]+@,?\s*[\w.-]+\.\w{2,}$',
    caseSensitive: false,
  ).hasMatch(t);
}

/// Strip emails mashed into a party name line.
String _stripEmailsFromPartyText(String line) {
  var s = line.replaceAll(
    RegExp(r'[\w.+-]+@,?\s*[\w.-]+\.\w{2,}', caseSensitive: false),
    ' ',
  );
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  return s;
}

bool _isHeaderLine(String line) {
  final cleaned = _stripSampleDecorations(line);
  final lower = cleaned.toLowerCase();
  if (_isEmailContactLine(cleaned)) return true;
  // Pure party name must not be treated as court header.
  if (_looksLikePartyName(cleaned) &&
      !lower.contains('republic') &&
      !lower.contains('trial court') &&
      !lower.contains('judicial') &&
      !lower.startsWith('branch ') &&
      !lower.startsWith('email') &&
      !lower.startsWith('contact') &&
      !lower.startsWith('tel')) {
    return false;
  }
  return lower.contains('republic of the philippines') ||
      lower.contains('regional trial court') ||
      lower.contains('municipal trial court') ||
      lower.contains('metropolitan trial court') ||
      lower.contains('judicial region') ||
      lower.startsWith('branch ') ||
      lower.startsWith('email address') ||
      lower.startsWith('contact number') ||
      lower.startsWith('tel.') ||
      lower.startsWith('tel ') ||
      lower.startsWith('telephone');
}

bool _isCaseMetaStart(String line) {
  final lower = line.toLowerCase();
  return lower.startsWith('civil case') ||
      lower.startsWith('criminal case') ||
      lower.startsWith('special civil') ||
      lower.startsWith('for:') ||
      lower.startsWith('for :');
}

bool _isCaseMetaContinuation(String line) {
  if (_isNoise(line) ||
      _isRunningFooter(line) ||
      _isRole(line) ||
      _isCaseMetaStart(line) ||
      _isOrderHeading(line) ||
      _isBodyStart(line) ||
      _mostlyUpper(line)) {
    return false;
  }
  final words = _words(line);
  return line.length <= 42 && words.isNotEmpty && words.length <= 6;
}

bool _isRole(String line) {
  if (line.length > 40) return false;
  final letters = line.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  const roles = {
    'plaintiff',
    'plaintiffs',
    'defendant',
    'defendants',
    'petitioner',
    'petitioners',
    'respondent',
    'respondents',
    'versus',
    'accused',
  };
  return roles.contains(letters);
}

bool _isOrderHeading(String line) {
  if (line.length > 40) return false;
  final compact = _compactLetters(line);
  return compact == 'ORDER' || compact == 'PRETRIALORDER';
}

bool _isSoOrdered(String line) {
  if (line.length > 24) return false;
  return _compactLetters(line) == 'SOORDERED';
}

bool _isBodyStart(String line) {
  if (_isOrderHeading(line) || _isSoOrdered(line)) return true;
  if (_words(line).length < 8 || !_hasLower(line)) return false;
  return RegExp(
    r'^(when|in view|wherefore|this case|the court|before this|accordingly|the plaintiffs|the defendants|parties|this page is a sample)\b',
    caseSensitive: false,
  ).hasMatch(line);
}

bool _isNameContinuation(String line) {
  if (_isNoise(line) ||
      _isRunningFooter(line) ||
      _isRole(line) ||
      _isCaseMetaStart(line) ||
      _isOrderHeading(line) ||
      _isBodyStart(line) ||
      _isSampleWatermark(line) ||
      _isHeaderLine(line)) {
    return false;
  }
  return _words(line).length < 14;
}

bool _isClosingContinuation(String line) {
  if (_isNoise(line) || _isRunningFooter(line) || _isSoOrdered(line)) {
    return false;
  }
  final lower = line.toLowerCase();
  if (lower.startsWith('cc:') || lower.startsWith('cc ')) return false;
  if (lower.contains('presiding judge')) return false;
  if (_looksLikeJudgeName(line)) return false;
  return line.length < 80;
}

bool _looksLikeJudgeName(String line) {
  if (line.length > 48 || !_mostlyUpper(line)) return false;
  final words = _words(line);
  return words.length >= 2 && words.length <= 6;
}

String _tidyRole(String line) {
  final letters = line.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  if (letters == 'versus' || letters == 'vs') return '- versus -';
  return _tidy(line);
}

String _tidyHeading(String line) {
  final compact = _compactLetters(line);
  if (compact == 'ORDER') return 'ORDER';
  if (compact == 'PRETRIALORDER') return 'PRE-TRIAL ORDER';
  return _tidy(line);
}

List<String> _reflowParagraphs(List<String> lines) {
  if (lines.isEmpty) return const [];
  final lengths = lines.map((line) => line.length).toList()..sort();
  final wrap = lengths[(lengths.length * 3 / 4).floor()];
  final out = <String>[];
  var buf = lines.first;
  for (var i = 1; i < lines.length; i++) {
    final next = lines[i];
    if (_shouldBreak(buf, next, wrap)) {
      final tidy = _tidy(buf);
      if (tidy.isNotEmpty) out.add(tidy);
      buf = next;
    } else {
      buf = _append(buf, next);
    }
  }
  final last = _tidy(buf);
  if (last.isNotEmpty) out.add(last);
  return out;
}

bool _shouldBreak(String prev, String next, int wrap) {
  final end = prev.trimRight();
  if (!_endsSentence(end)) return false;
  if (RegExp(r'^[a-z]').hasMatch(next.trimLeft())) return false;
  if (end.length >= wrap - 6 && !_startsNewParagraph(next)) return false;
  return true;
}

bool _endsSentence(String line) {
  if (!RegExp(r'[.!?]$').hasMatch(line)) return false;
  if (RegExp(
    r'\b(Atty|Jr|Sr|Mr|Mrs|Ms|Dr|No|Nos|St|Inc|Ltd|Hon|Rep|Corp)\.$',
    caseSensitive: false,
  ).hasMatch(line)) {
    return false;
  }
  if (RegExp(r'\b[A-Z]\.$').hasMatch(line)) return false;
  return true;
}

bool _startsNewParagraph(String line) {
  return RegExp(
    r'^(WHEREFORE|SO ORDERED|In view\b|The plaintiffs\b|The defendants\b|When this\b|Accordingly\b|Parties\b|Notify\b|Let them\b|Let it\b|Done in\b|Atty\.|This page is a sample)',
    caseSensitive: false,
  ).hasMatch(line.trimLeft());
}

bool _mostlyUpper(String line) {
  final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (letters.length < 3) return false;
  final upper = letters.replaceAll(RegExp(r'[^A-Z]'), '').length;
  return upper / letters.length >= 0.7;
}

bool _hasLower(String line) => RegExp(r'[a-z]').hasMatch(line);

List<String> _words(String line) =>
    line.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();

String _compactLetters(String line) =>
    line.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');

/// Picks the complete order when page 2 is stored in another field or row.
class CourtOrderTextSources {
  static const _keys = [
    'fullText',
    'message',
    'rawText',
    'ocrText',
    'extractedText',
    'orderText',
    'pdfText',
    'text',
    'content',
    'body',
    'emailBody',
    'description',
  ];

  static String combine(Map<String, dynamic> data) {
    final parts = <String>[];
    void add(dynamic value) {
      if (value is String) {
        final text = value.trim();
        if (text.length >= 80) parts.add(text);
      } else if (value is Iterable) {
        for (final item in value) {
          add(item);
        }
      }
    }

    for (final key in _keys) {
      final v = data[key];
      if (v is String && _isInboxWrapper(v) && !_norm(v).contains('republic of the philippines') && !_norm(v).contains('regional trial court')) continue;
      add(v);
    }
    return joinPieces(parts.map(_unwrapInbox).toList());
  }

  static String joinPieces(List<String> parts) {
    final cleaned = parts
        .map(_unwrapInbox)
        .map((part) => part.trim())
        .where((part) => part.length >= 80 && !_isInboxWrapper(part))
        .toList();
    if (cleaned.isEmpty) return '';
    cleaned.sort((a, b) => b.length.compareTo(a.length));
    var best = cleaned.first;
    for (final part in cleaned.skip(1)) {
      final bestNorm = _norm(best);
      final partNorm = _norm(part);
      if (partNorm.isEmpty || bestNorm.contains(partNorm)) continue;
      if (partNorm.contains(bestNorm)) {
        best = part;
        continue;
      }
      if (!_hasClosing(best) && _hasClosing(part)) {
        best = '$best\n\n$part';
        continue;
      }
      if (_hasClosing(best) &&
          !_hasClosing(part) &&
          _looksLikeOrderOpening(part)) {
        best = '$part\n\n$best';
      }
    }
    return best.trim();
  }

  static bool hasClosing(String text) => _hasClosing(text);
  static bool isInboxWrapper(String text) => _isInboxWrapper(text);
}

String _norm(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

bool _hasClosing(String text) {
  final norm = _norm(text);
  return norm.contains('so ordered') || norm.contains('presiding judge');
}

String _unwrapInbox(String text) {
  final trimmed = text.trim();
  // If the text contains the authentic court heading anywhere, unwrap it directly!
  final courtHeading = RegExp(
    r'\b(?:REPUBLIC OF THE PHILIPPINES|REGIONAL TRIAL COURT|MUNICIPAL TRIAL COURT|METROPOLITAN TRIAL COURT)\b',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (courtHeading != null) {
    var orderBody = trimmed.substring(courtHeading.start).trim();
    final end = RegExp(
      r'\n\s*(?:Hearing date/time:|Matter:|Case record ID:|Case No\.:|Client:)',
      caseSensitive: false,
    ).firstMatch(orderBody);
    if (end != null) orderBody = orderBody.substring(0, end.start).trim();
    return orderBody;
  }

  if (!_isInboxWrapper(trimmed)) return trimmed;
  final start = RegExp(
    r'order\s*/\s*notice\s*:',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (start == null) return '';
  var body = trimmed.substring(start.end).trim();
  final end = RegExp(
    r'\n\s*(?:Hearing date/time:|Matter:|Case record ID:|Case No\.:|Client:)',
    caseSensitive: false,
  ).firstMatch(body);
  if (end != null) body = body.substring(0, end.start).trim();
  return body;
}

bool _isInboxWrapper(String text) {
  final norm = _norm(text);
  if (norm.contains('republic of the philippines') ||
      norm.contains('regional trial court') ||
      norm.contains('municipal trial court') ||
      norm.contains('metropolitan trial court')) {
    return false;
  }
  if (norm.contains('order / notice') ||
      norm.contains('hearing date/time') ||
      norm.contains('case record id')) {
    return true;
  }
  if ((norm.contains('case title:') || norm.contains('case no:')) &&
      (norm.contains('hearing time:') || norm.contains('location:'))) {
    return true;
  }
  if (norm.contains('hearing time:') &&
      norm.contains('location:') &&
      norm.contains('summary:')) {
    return true;
  }
  if (norm.startsWith('case title:') ||
      norm.startsWith('new notice court hearings') ||
      norm.startsWith('court hearing notice') ||
      norm.startsWith('notice of court hearing')) {
    return true;
  }
  return false;
}

bool _looksLikeOrderOpening(String text) {
  final norm = _norm(text);
  return norm.contains('republic of the philippines') ||
      norm.contains('regional trial court') ||
      norm.contains('municipal trial court');
}
