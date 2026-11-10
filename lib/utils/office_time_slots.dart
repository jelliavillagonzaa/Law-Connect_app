/// Client booking grid. Monday to Friday, 8:00 AM through 4:30 PM,
/// every 30 minutes. A hearing at 10:17 occupies the 10:00 slot.
class OfficeTimeSlots {
  static const int openHour = 8;
  static const int closeHour = 17;
  static const int stepMinutes = 30;
  static const int bookingHorizonDays = 90;

  static bool isWeekend(DateTime day) {
    return day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
  }

  static DateTime dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  /// Start of the 30-minute office slot that contains [when].
  /// Null when the time is outside office hours or on a weekend.
  static DateTime? windowStart(DateTime when) {
    if (isWeekend(when)) return null;
    final minutes = when.hour * 60 + when.minute;
    final open = openHour * 60;
    final close = closeHour * 60;
    if (minutes < open || minutes >= close) return null;
    final floored = minutes - (minutes % stepMinutes);
    return DateTime(when.year, when.month, when.day, floored ~/ 60, floored % 60);
  }

  static List<DateTime> slotsForDay(DateTime day) {
    if (isWeekend(day)) return const [];
    final date = dateOnly(day);
    final slots = <DateTime>[];
    var cursor = DateTime(date.year, date.month, date.day, openHour);
    final close = DateTime(date.year, date.month, date.day, closeHour);
    while (cursor.isBefore(close)) {
      slots.add(cursor);
      cursor = cursor.add(const Duration(minutes: stepMinutes));
    }
    return slots;
  }

  static bool isPastSlot(DateTime slotStart, DateTime now) {
    return !slotStart.isAfter(now);
  }

  /// True when [eventStart] falls inside the slot that begins at [slotStart].
  static bool occupies(DateTime slotStart, DateTime eventStart) {
    final end = slotStart.add(const Duration(minutes: stepMinutes));
    return !eventStart.isBefore(slotStart) && eventStart.isBefore(end);
  }

  static bool slotIsBusy(DateTime slotStart, Iterable<DateTime> busyStarts) {
    for (final start in busyStarts) {
      if (occupies(slotStart, start)) return true;
    }
    return false;
  }

  /// Open slots still ahead of [now]. Busy ones are left out.
  static List<DateTime> openSlots({
    required DateTime day,
    required DateTime now,
    required Iterable<DateTime> busyStarts,
  }) {
    return [
      for (final slot in slotsForDay(day))
        if (!isPastSlot(slot, now) && !slotIsBusy(slot, busyStarts)) slot,
    ];
  }

  /// A weekday with no remaining open slot. Past days and weekends are not full.
  static bool dayIsFull({
    required DateTime day,
    required DateTime now,
    required Iterable<DateTime> busyStarts,
  }) {
    if (isWeekend(day)) return false;
    final today = dateOnly(now);
    final date = dateOnly(day);
    if (date.isBefore(today)) return false;
    final future = slotsForDay(day).where((slot) => !isPastSlot(slot, now));
    if (future.isEmpty) return false;
    return future.every((slot) => slotIsBusy(slot, busyStarts));
  }

  static bool dayIsBookable({
    required DateTime day,
    required DateTime now,
    required Iterable<DateTime> busyStarts,
    DateTime? lastDate,
  }) {
    final today = dateOnly(now);
    final date = dateOnly(day);
    if (date.isBefore(today)) return false;
    final horizon = dateOnly(lastDate ?? now.add(const Duration(days: bookingHorizonDays)));
    if (date.isAfter(horizon)) return false;
    if (isWeekend(day)) return false;
    return openSlots(day: day, now: now, busyStarts: busyStarts).isNotEmpty;
  }
}
