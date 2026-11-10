/// Splits OCR / court `clientName` blobs into individual party names.
class HearingPartyNames {
  HearingPartyNames._();

  static final _partySeparators = RegExp(
    r'\s*(?:,|;|/|\band\b|&|\bvs\.?(?=\s|$)|\bversus\b|\bv\.(?=\s))\s*',
    caseSensitive: false,
  );
  static final _spsCouple = RegExp(
    r'\bSPS\.?\s+([A-Za-z][A-Za-z.\-]*)\s*&\s*([A-Za-z][A-Za-z.\-]*(?:\s+[A-Za-z][A-Za-z.\-]*)*)',
    caseSensitive: false,
  );
  static const _partySkipTokens = {
    'namely',
    'heirs',
    'of',
    'the',
    'and',
    'sps',
    'spouses',
    'et',
    'al',
    'vs',
    'versus',
    'plaintiff',
    'defendant',
    'petitioner',
    'respondent',
  };

  /// `"RUBEN MONTEJO, AXEL JOSEPH L. BINAORO, SPS. DANILO & PRESCILLA ARMINGOL"`
  /// → each person, including both spouses.
  static List<String> split(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return const [];

    final extras = <String>[];
    s = s.replaceAllMapped(_spsCouple, (m) {
      final first = (m.group(1) ?? '').trim();
      final rest = (m.group(2) ?? '').trim();
      final restParts = rest.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      final last = restParts.isEmpty ? rest : restParts.last;
      if (first.isNotEmpty && last.isNotEmpty) extras.add('$first $last');
      if (rest.isNotEmpty) extras.add(rest);
      return ', $rest, ';
    });
    s = s.replaceAll(RegExp(r'\bSPS\.?\s*', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'\bHEIRS OF\s+', caseSensitive: false), ' ');

    final out = <String>[];
    void add(String p) {
      p = p.replaceAll(RegExp(r'\s+'), ' ').trim();
      // Court contact emails belong in the header, not party captions.
      p = p
          .replaceAll(
            RegExp(r'[\w.+-]+@,?\s*[\w.-]+\.\w{2,}', caseSensitive: false),
            ' ',
          )
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      p = p.replaceAll(RegExp(r'^and\s+', caseSensitive: false), '').trim();
      p = p.replaceAll(RegExp(r'[.,;:]+$'), '').trim();
      if (p.length < 4) return;
      if (_partySkipTokens.contains(p.toLowerCase())) return;
      if (RegExp(r'^[\w.+-]+@').hasMatch(p)) return;
      if (out.any((e) => e.toLowerCase() == p.toLowerCase())) return;
      out.add(p);
    }

    for (final p in s.split(_partySeparators)) {
      add(p);
      final stripped = stripRoles(p);
      if (stripped.isNotEmpty && stripped != p) add(stripped);
    }
    for (final p in extras) {
      add(p);
      final stripped = stripRoles(p);
      if (stripped.isNotEmpty && stripped != p) add(stripped);
    }
    return out;
  }

  static String stripRoles(String raw) {
    var s = raw.trim();
    s = s.replaceAll(
      RegExp(
        r'\b(?:accused|defendant|petitioner|respondent|complainant|plaintiff|appellant|appellee|witness|victim)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    s = s.replaceAll(
      RegExp(
        r'\b(?:mr\.?|ms\.?|mrs\.?|atty\.?|atty|attorney|judge|hon\.?)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    s = s.replaceAll(RegExp(r'[()[\]{}]'), ' ');
    s = s.replaceAll(RegExp(r'[-–—]'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
