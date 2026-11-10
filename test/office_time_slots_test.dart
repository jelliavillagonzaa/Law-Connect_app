import 'package:flutter_test/flutter_test.dart';
import 'package:law_connect4/utils/office_time_slots.dart';

void main() {
  test('10:17 occupies the 10:00 office slot', () {
    final window = OfficeTimeSlots.windowStart(DateTime(2026, 9, 30, 10, 17));
    expect(window, DateTime(2026, 9, 30, 10, 0));
    expect(
      OfficeTimeSlots.occupies(window!, DateTime(2026, 9, 30, 10, 17)),
      isTrue,
    );
    expect(
      OfficeTimeSlots.slotIsBusy(window, [DateTime(2026, 9, 30, 10, 17)]),
      isTrue,
    );
    expect(
      OfficeTimeSlots.slotIsBusy(
        DateTime(2026, 9, 30, 10, 30),
        [DateTime(2026, 9, 30, 10, 17)],
      ),
      isFalse,
    );
  });

  test('weekends and hours outside 8:00 to 5:00 are not bookable slots', () {
    expect(OfficeTimeSlots.windowStart(DateTime(2026, 10, 3, 10)), isNull);
    expect(OfficeTimeSlots.windowStart(DateTime(2026, 9, 30, 7, 45)), isNull);
    expect(OfficeTimeSlots.windowStart(DateTime(2026, 9, 30, 17)), isNull);
    expect(
      OfficeTimeSlots.windowStart(DateTime(2026, 9, 30, 16, 30)),
      DateTime(2026, 9, 30, 16, 30),
    );
    expect(OfficeTimeSlots.slotsForDay(DateTime(2026, 9, 30)).length, 18);
  });

  test('a day is full only when every remaining slot is busy', () {
    final now = DateTime(2026, 9, 30, 8);
    final day = DateTime(2026, 9, 30);
    final allBusy = OfficeTimeSlots.slotsForDay(day);
    expect(
      OfficeTimeSlots.dayIsFull(day: day, now: now, busyStarts: allBusy),
      isTrue,
    );
    expect(
      OfficeTimeSlots.dayIsBookable(day: day, now: now, busyStarts: allBusy),
      isFalse,
    );
    final open = OfficeTimeSlots.openSlots(
      day: day,
      now: now,
      busyStarts: [DateTime(2026, 9, 30, 10)],
    );
    expect(open.contains(DateTime(2026, 9, 30, 10)), isFalse);
    expect(open.contains(DateTime(2026, 9, 30, 10, 30)), isTrue);
  });
}
