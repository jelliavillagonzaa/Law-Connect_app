import 'package:flutter_test/flutter_test.dart';

List<DateTime> computeDaysForMonth(DateTime monthDate) {
  final firstDay = DateTime(monthDate.year, monthDate.month, 1);
  final leading = firstDay.weekday % 7; // Sunday is 0
  final start = firstDay.subtract(Duration(days: leading));
  final days = <DateTime>[];
  for (int i = 0; i < 42; i++) {
    days.add(DateTime(start.year, start.month, start.day + i));
  }
  if (days.length == 42 && days[35].month != monthDate.month) {
    return days.sublist(0, 35);
  }
  return days;
}

void main() {
  group('Admin Dashboard Calendar Unit Tests', () {
    test('Sunday-first month computation aligns leading days correctly', () {
      // March 2017 (mockup reference in user image)
      // March 1, 2017 was a Wednesday (weekday = 3).
      // Sunday is 0, so leading = 3 days (Feb 26, 27, 28).
      final days = computeDaysForMonth(DateTime(2017, 3, 1));
      expect(days.first.year, 2017);
      expect(days.first.month, 2);
      expect(days.first.day, 26); // Exactly matches Image 1 row 1: 26 27 28 01 02 03 04!

      // 4th day is March 1
      expect(days[3].month, 3);
      expect(days[3].day, 1);
    });

    test('Two digit day formatting formats 01 to 09 with leading zeros', () {
      for (int d = 1; d <= 9; d++) {
        final formatted = d.toString().padLeft(2, '0');
        expect(formatted.length, 2);
        expect(formatted.startsWith('0'), isTrue);
      }
      expect(10.toString().padLeft(2, '0'), '10');
      expect(31.toString().padLeft(2, '0'), '31');
    });

    test('Trims 6th row when month fits in 35 days (5 weeks)', () {
      // February 2026 starts on Sunday (Feb 1, 2026 is Sunday), 28 days
      final febDays = computeDaysForMonth(DateTime(2026, 2, 1));
      expect(febDays.length, 35);
    });

    test('Retains 42 days when month spans 6 weeks', () {
      // May 2026 starts on Friday (May 1), 31 days -> spans 6 calendar rows
      final mayDays = computeDaysForMonth(DateTime(2026, 5, 1));
      expect(mayDays.length, 42);
    });
  });
}
