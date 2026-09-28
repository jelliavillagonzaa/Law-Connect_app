import 'case_sms_formatter.dart';

/// Professional SMS copy for attorney hearing alerts and reminders.
///
/// Formats Firestore hearing fields for PhilSMS / Semaphore. Does not change
/// stored case data.
class HearingSmsFormatter {
  HearingSmsFormatter._();

  static const String brand = 'LAWCONNECT HEARING REMINDER';
  static const int maxSmsLength = 1200;

  static const String scheduledClosing =
      'Please be reminded of your scheduled hearing.';
  static const String fiveDayLeadIn = 'Your hearing is in 5 days.';
  static const String fiveDayClosing =
      'Please prepare for your scheduled hearing.';
  static const String twoDayLeadIn = 'Your hearing is in 2 days.';
  static const String twoDayClosing =
      'Please be reminded of your upcoming hearing.';
  static const String hearingDayLeadIn = 'Your hearing is today.';
  static const String hearingDayClosing =
      'Please be reminded of your hearing today.';

  /// [reminderKind] is `d5`, `d2`, or `hearing_day`. Empty = new/updated hearing.
  static String build({
    String caseNo = '',
    String caseTitle = '',
    String clientName = '',
    String hearingDate = '',
    String hearingTime = '',
    String location = '',
    String reminderKind = '',
  }) {
    final lines = <String>[brand, ''];
    final kind = reminderKind.trim().toLowerCase();
    if (kind == 'd5') {
      lines.add(fiveDayLeadIn);
      lines.add('');
    } else if (kind == 'd2') {
      lines.add(twoDayLeadIn);
      lines.add('');
    } else if (kind == 'hearing_day' || kind == 'day_noon') {
      lines.add(hearingDayLeadIn);
      lines.add('');
    }

    final caseLine = formatCaseNumber(caseNo);
    if (caseLine.isNotEmpty) lines.add(caseLine);

    final caption = captionLines(caseTitle, clientName: clientName);
    lines.addAll(caption);

    if (kind.isEmpty) {
      lines.add('');
      lines.add('Hearing Details:');
    } else {
      lines.add('');
    }

    final date = hearingDate.trim();
    if (date.isNotEmpty) lines.add('Date: $date');
    final time = formatTime(hearingTime);
    if (time.isNotEmpty) lines.add('Time: $time');
    final loc = formatLocation(location);
    if (loc.isNotEmpty) lines.add('Location: $loc');

    lines.add('');
    if (kind == 'd5') {
      lines.add(fiveDayClosing);
    } else if (kind == 'd2') {
      lines.add(twoDayClosing);
    } else if (kind == 'hearing_day' || kind == 'day_noon') {
      lines.add(hearingDayClosing);
    } else {
      lines.add(scheduledClosing);
    }

    var text = lines.join('\n').trim();
    if (text.length > maxSmsLength) {
      final shortenedTitle = _etAlCaseTitle(caseTitle);
      if (shortenedTitle != caseTitle) {
        return build(
          caseNo: caseNo,
          caseTitle: shortenedTitle,
          clientName: clientName,
          hearingDate: hearingDate,
          hearingTime: hearingTime,
          location: location,
          reminderKind: reminderKind,
        );
      }
    }
    if (text.length > maxSmsLength) {
      text = '${text.substring(0, maxSmsLength - 3)}...';
    }
    return text;
  }

  static String formatCaseNumber(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return '';
    t = t.replaceFirst(
      RegExp(r'^(?:civil\s+)?(?:case\s*(?:no\.?|#|number)?\s*)', caseSensitive: false),
      '',
    ).trim();
    t = t.replaceFirst(RegExp(r'^#\s*'), '');
    if (t.isEmpty) return '';
    return 'Case #$t';
  }

  /// `8:30 in the morning` → `8:30 AM`. Leaves unknown strings unchanged.
  static String formatTime(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final clock = RegExp(r'(\d{1,2}):(\d{2})(?::\d{2})?').firstMatch(t);
    if (clock == null) return t;
    var hour = int.tryParse(clock.group(1)!) ?? -1;
    final minute = clock.group(2)!;
    if (hour < 0) return t;
    final lower = t.toLowerCase();
    final explicitPm = lower.contains('p.m') ||
        RegExp(r'\bpm\b').hasMatch(lower) ||
        lower.contains('afternoon') ||
        lower.contains('evening');
    final explicitAm = lower.contains('a.m') ||
        RegExp(r'\bam\b').hasMatch(lower) ||
        lower.contains('morning');

    if (hour > 12) {
      hour -= 12;
      return '$hour:$minute PM';
    }
    if (hour == 0) return '12:$minute AM';
    if (explicitPm) {
      return '$hour:$minute PM';
    }
    if (explicitAm) {
      return '$hour:$minute AM';
    }
    if (hour == 12) return '12:$minute PM';
    if (hour >= 1 && hour <= 11) return '$hour:$minute AM';
    return '$hour:$minute';
  }

  static String formatLocation(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    return t.replaceAllMapped(
      RegExp(r'\bbranch\b', caseSensitive: false),
      (_) => 'Branch',
    );
  }

  static List<String> captionLines(String caseTitle, {String clientName = ''}) {
    final title = caseTitle.trim();
    final client = clientName.trim();
    if (title.isEmpty) {
      return client.isEmpty ? const [] : [client];
    }

    final vs = RegExp(r'\s+(?:vs\.?|versus)\s+', caseSensitive: false);
    final match = vs.firstMatch(title);
    if (match == null) {
      final lines = <String>[title];
      if (client.isNotEmpty && !_containsIgnoreCase(title, client)) {
        lines.add(client);
      }
      return lines;
    }

    final left = title.substring(0, match.start).trim();
    final right = title.substring(match.end).trim();
    return [
      if (left.isNotEmpty) left,
      'vs.',
      if (right.isNotEmpty) right,
    ];
  }

  static bool _containsIgnoreCase(String haystack, String needle) {
    return haystack.toLowerCase().contains(needle.toLowerCase());
  }

  /// Last-resort SMS length trim only. Full party names are kept when they fit.
  static String _etAlCaseTitle(String caseTitle) =>
      CaseSmsFormatter.etAlCaseTitle(caseTitle);
}
