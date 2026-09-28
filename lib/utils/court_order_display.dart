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
    final lines = _lines(raw);
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
    final parties = <CourtOrderPartyLine>[];
    final caseMeta = <String>[];
    String? heading;
    var i = 0;

    while (i < lines.length && (_isNoise(lines[i]) || _isInboxNoise(lines[i]))) {
      i++;
    }
    while (i < lines.length && _isHeaderLine(lines[i])) {
      header.add(lines[i]);
      i++;
    }

    while (i < lines.length && !_isBodyStart(lines[i])) {
      final line = lines[i];
      if (_isNoise(line) || _isRunningFooter(line) || _isInboxNoise(line)) {
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
        caseMeta.add(_tidy(meta));
        continue;
      }
      if (_isRole(line)) {
        parties.add(CourtOrderPartyLine(_tidyRole(line), centered: true));
        i++;
        continue;
      }
      var names = line;
      i++;
      while (i < lines.length && _isNameContinuation(lines[i])) {
        names = _append(names, lines[i]);
        i++;
      }
      final tidy = _tidy(names);
      if (tidy.isNotEmpty) {
        parties.add(CourtOrderPartyLine(tidy));
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
          _isInboxNoise(line)) {
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

bool _isHeaderLine(String line) {
  final lower = line.toLowerCase();
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
    r'^(when|in view|wherefore|this case|the court|before this|accordingly|the plaintiffs|the defendants|parties)\b',
    caseSensitive: false,
  ).hasMatch(line);
}

bool _isNameContinuation(String line) {
  if (_isNoise(line) ||
      _isRunningFooter(line) ||
      _isRole(line) ||
      _isCaseMetaStart(line) ||
      _isOrderHeading(line) ||
      _isBodyStart(line)) {
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
  if (letters == 'versus') return '- versus -';
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
    r'^(WHEREFORE|SO ORDERED|In view\b|The plaintiffs\b|The defendants\b|When this\b|Accordingly\b|Parties\b|Notify\b|Let them\b|Let it\b|Done in\b|Atty\.)',
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
      add(data[key]);
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
}

String _norm(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

bool _hasClosing(String text) {
  final norm = _norm(text);
  return norm.contains('so ordered') || norm.contains('presiding judge');
}

String _unwrapInbox(String text) {
  final trimmed = text.trim();
  if (!_isInboxWrapper(trimmed)) return trimmed;
  final start = RegExp(
    r'order\s*/\s*notice\s*:',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (start == null) return '';
  var body = trimmed.substring(start.end).trim();
  final end = RegExp(
    r'\n\s*(Hearing date/time:|Matter:|Case record ID:)',
    caseSensitive: false,
  ).firstMatch(body);
  if (end != null) body = body.substring(0, end.start).trim();
  return body;
}

bool _isInboxWrapper(String text) {
  final norm = _norm(text);
  return norm.contains('order / notice') ||
      norm.contains('hearing date/time') ||
      norm.contains('case record id');
}

bool _looksLikeOrderOpening(String text) {
  final norm = _norm(text);
  return norm.contains('republic of the philippines') ||
      norm.contains('regional trial court') ||
      norm.contains('municipal trial court');
}
