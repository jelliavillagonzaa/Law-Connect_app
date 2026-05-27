import '../models/court_message_extraction.dart';

/// Heuristic extraction for English-language court notices (extend patterns later).
class CourtNoticeRuleExtractor {
  CourtMessageExtraction extract(String raw) {
    final text = raw.replaceAll(RegExp(r'\r\n'), '\n').trim();
    if (text.isEmpty) {
      return const CourtMessageExtraction();
    }

    final hearingAt = _parseHearingDateTime(text);
    final caseNo = _firstMatch(text, [
      RegExp(
        r'case\s*(?:no\.?|number|#)\s*[:\s]*([A-Za-z0-9\-_/]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:docket|civil|cv|cr)[\s#:No.]*([A-Za-z0-9\-_/]+)',
        caseSensitive: false,
      ),
    ]);
    final court = _lineAfterLabels(text, [
      'court',
      'in the court',
      'before the court',
    ]);
    final judge = _lineAfterLabels(text, [
      'judge',
      'honorable',
      'hon.',
      'presiding',
    ]);
    final room = _firstMatch(text, [
      RegExp(
        r'(?:courtroom|room|branch)\s*[:\s#]*([A-Za-z0-9\s\-]+)',
        caseSensitive: false,
      ),
    ]);

    String? plaintiff;
    String? defendant;
    final pv = RegExp(
      r'plaintiff[s]?\s*[:\s]+(.+?)(?:\n|defendant|$)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    if (pv != null) {
      plaintiff = pv.group(1)?.trim().split('\n').first.trim();
    }
    final dv = RegExp(
      r'defendant[s]?\s*[:\s]+(.+?)(?:\n|plaintiff|hearing|date|$)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(text);
    if (dv != null) {
      defendant = dv.group(1)?.trim().split('\n').first.trim();
    }

    final attorney = _lineAfterLabels(text, [
      'attorney for',
      'counsel for',
      'represented by',
      'law offices of',
    ]);
    final client = _lineAfterLabels(text, [
      'petitioner',
      'applicant',
      'respondent',
    ]);

    final summary = text.length > 400 ? '${text.substring(0, 400)}…' : text;

    return CourtMessageExtraction(
      hearingDateTime: hearingAt,
      courtName: court,
      judge: judge,
      caseNumber: caseNo,
      plaintiff: plaintiff,
      defendant: defendant,
      attorneyMentioned: attorney,
      clientMentioned: client,
      roomOrBranch: room,
      summaryNotes: summary,
    );
  }

  DateTime? _parseHearingDateTime(String text) {
    // ISO-like
    final iso = RegExp(
      r'(20\d{2})-(\d{2})-(\d{2})[T\s](\d{1,2}):(\d{2})',
    ).firstMatch(text);
    if (iso != null) {
      final y = int.tryParse(iso.group(1)!);
      final mo = int.tryParse(iso.group(2)!);
      final d = int.tryParse(iso.group(3)!);
      final h = int.tryParse(iso.group(4)!);
      final mi = int.tryParse(iso.group(5)!);
      if (y != null && mo != null && d != null && h != null && mi != null) {
        return DateTime(y, mo, d, h, mi);
      }
    }

    // "January 5, 2026 at 9:00 AM"
    final long = RegExp(
      r'(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2}),?\s+(20\d{2})\s*(?:at\s*)?(\d{1,2}):(\d{2})\s*(am|pm)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (long != null) {
      final month = _monthIndex(long.group(1)!);
      final day = int.tryParse(long.group(2)!);
      final year = int.tryParse(long.group(3)!);
      var hour = int.tryParse(long.group(4)!);
      final minute = int.tryParse(long.group(5)!);
      final ap = long.group(6)?.toLowerCase();
      if (month != null && day != null && year != null && hour != null) {
        final min = minute ?? 0;
        if (ap == 'pm' && hour < 12) hour += 12;
        if (ap == 'am' && hour == 12) hour = 0;
        return DateTime(year, month, day, hour, min);
      }
    }

    // mm/dd/yyyy with optional time
    final us = RegExp(
      r'(\d{1,2})/(\d{1,2})/(20\d{2})\s*(\d{1,2}):(\d{2})\s*(am|pm)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (us != null) {
      final m = int.tryParse(us.group(1)!);
      final d = int.tryParse(us.group(2)!);
      final y = int.tryParse(us.group(3)!);
      var hour = int.tryParse(us.group(4)!);
      final minute = int.tryParse(us.group(5)!);
      final ap = us.group(6)?.toLowerCase();
      if (m != null && d != null && y != null && hour != null) {
        if (ap == 'pm' && hour < 12) hour += 12;
        if (ap == 'am' && hour == 12) hour = 0;
        return DateTime(y, m, d, hour, minute ?? 0);
      }
    }

    // Date only mm/dd/yyyy → default 9:00
    final usDate = RegExp(r'(\d{1,2})/(\d{1,2})/(20\d{2})').firstMatch(text);
    if (usDate != null) {
      final m = int.tryParse(usDate.group(1)!);
      final d = int.tryParse(usDate.group(2)!);
      final y = int.tryParse(usDate.group(3)!);
      if (m != null && d != null && y != null) {
        return DateTime(y, m, d, 9, 0);
      }
    }

    return null;
  }

  int? _monthIndex(String name) {
    const months = [
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
    ];
    final i = months.indexOf(name.toLowerCase());
    return i < 0 ? null : i + 1;
  }

  String? _firstMatch(String text, List<RegExp> patterns) {
    for (final re in patterns) {
      final m = re.firstMatch(text);
      if (m != null && m.groupCount >= 1) {
        final s = m.group(1)?.trim();
        if (s != null && s.isNotEmpty) return s;
      }
    }
    return null;
  }

  String? _lineAfterLabels(String text, List<String> labels) {
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].trim();
      final low = l.toLowerCase();
      for (final label in labels) {
        if (low.contains(label) && low.length < 120) {
          if (l.contains(':')) {
            final part = l.split(':').skip(1).join(':').trim();
            if (part.isNotEmpty) return part;
          }
          if (i + 1 < lines.length) {
            final next = lines[i + 1].trim();
            if (next.isNotEmpty) return next;
          }
        }
      }
    }
    return null;
  }
}
