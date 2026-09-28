import '../widgets/common/hearing_calendar_event_body.dart';

/// Banner / month-link hearing index (attorney + staff calendars).
abstract final class CalendarHearingNav {
  static String fingerprint(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '0';
    var hash = rows.length;
    for (var i = 0; i < rows.length; i++) {
      if (i == 0 || i == rows.length - 1 || i % 17 == 0) {
        hash = Object.hash(
          hash,
          rows[i]['hearingDocId'],
          rows[i]['eventDate'],
        );
      }
    }
    return hash.toString();
  }

  static bool isHearingRow(Map<String, dynamic> ev) {
    if ((ev['hearingDocId'] as String?)?.trim().isNotEmpty == true) {
      return true;
    }
    if (isFirestoreSyncedHearingCalendarRow(ev)) return true;
    return (ev['eventType'] as String?)?.toLowerCase() == 'hearing';
  }

  /// Rows that belong on the month grid: client appointments + court hearings only.
  static bool isGridDisplayEvent(Map<String, dynamic> ev) {
    final type = (ev['eventType'] as String?)?.trim().toLowerCase() ?? '';
    if (type == 'appointment') return true;
    return isHearingRow(ev);
  }

  /// Merges `calendar_events` hearing rows with a lightweight hearings fetch.
  static List<Map<String, dynamic>> mergeSources({
    required List<Map<String, dynamic>> calendarEvents,
    required List<Map<String, dynamic>> overlayRows,
  }) {
    final out = <Map<String, dynamic>>[];
    final indexByKey = <String, int>{};

    void add(Map<String, dynamic> ev, {bool prefer = false}) {
      if (!isHearingRow(ev)) return;
      final hid = (ev['hearingDocId'] as String?)?.trim() ?? '';
      final id = (ev['id'] as String?)?.trim() ?? '';
      final key = hid.isNotEmpty ? 'h:$hid' : 'e:$id';
      if (key == 'e:') return;
      final existing = indexByKey[key];
      if (existing == null) {
        indexByKey[key] = out.length;
        out.add(ev);
        return;
      }
      if (prefer) {
        out[existing] = ev;
      }
    }

    for (final ev in calendarEvents) {
      add(ev);
    }
    for (final ev in overlayRows) {
      add(ev, prefer: true);
    }
    return out;
  }

  static List<DateTime> monthsOutsideView({
    required List<Map<String, dynamic>> hearingRows,
    required DateTime viewDate,
    DateTime? Function(dynamic raw)? parseDate,
  }) {
    final readDate = parseDate ?? _defaultParseDate;
    final seen = <String>{};
    final out = <DateTime>[];
    for (final ev in hearingRows) {
      final d = readDate(ev['eventDate']);
      if (d == null) continue;
      if (d.year == viewDate.year && d.month == viewDate.month) continue;
      final key = '${d.year}-${d.month}';
      if (seen.add(key)) {
        out.add(DateTime(d.year, d.month));
      }
    }
    out.sort((a, b) {
      final c = a.year.compareTo(b.year);
      return c != 0 ? c : a.month.compareTo(b.month);
    });
    return out;
  }

  static Set<String> hearingDayKeys(
    List<Map<String, dynamic>> rows,
    DateTime? Function(dynamic raw) parseDate,
  ) {
    final keys = <String>{};
    for (final row in rows) {
      final d = parseDate(row['eventDate']);
      if (d == null) continue;
      keys.add('${d.year}-${d.month}-${d.day}');
    }
    return keys;
  }

  static String hearingIdentity(Map<String, dynamic> ev) {
    final hid = (ev['hearingDocId'] as String?)?.trim() ?? '';
    if (hid.isNotEmpty) return hid;
    final id = (ev['id'] as String?)?.trim() ?? '';
    if (id.startsWith('hearing_cal_')) {
      return id.substring('hearing_cal_'.length);
    }
    if (id.startsWith('live_hearing_')) {
      return id.substring('live_hearing_'.length);
    }
    if (isHearingRow(ev) && id.isNotEmpty) return id;
    return '';
  }

  static void collectHearingIds(
    List<Map<String, dynamic>> rows,
    Set<String> seen,
  ) {
    for (final ev in rows) {
      final id = hearingIdentity(ev);
      if (id.isNotEmpty) seen.add(id);
    }
  }

  /// Latest event date among hearings not yet in [seen]. Those ids are added to [seen].
  static DateTime? newestUnseenHearingDate(
    List<Map<String, dynamic>> rows,
    Set<String> seen, {
    DateTime? Function(dynamic raw)? parseDate,
  }) {
    final readDate = parseDate ?? _defaultParseDate;
    DateTime? bestEvent;
    DateTime? bestCreated;
    for (final ev in rows) {
      final id = hearingIdentity(ev);
      if (id.isEmpty || !seen.add(id)) continue;
      final event = readDate(ev['eventDate']);
      if (event == null) continue;
      final created = readDate(ev['createdAt']);
      if (bestEvent == null ||
          (created != null &&
              (bestCreated == null || created.isAfter(bestCreated))) ||
          (created == null &&
              bestCreated == null &&
              event.isAfter(bestEvent))) {
        bestEvent = event;
        bestCreated = created ?? bestCreated;
      }
    }
    return bestEvent;
  }

  static DateTime? _defaultParseDate(dynamic raw) {
    if (raw is DateTime) return raw;
    return null;
  }
}
