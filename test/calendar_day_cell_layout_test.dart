import 'package:flutter_test/flutter_test.dart';
import 'package:law_connect4/utils/calendar_perf.dart';

void main() {
  const chip = CalendarPerf.monthCellChipHeight;
  const pill = CalendarPerf.monthCellMoreRowHeight;

  test('one to three items show every name and no pill', () {
    for (final total in [1, 2, 3]) {
      final layout = CalendarPerf.layoutDayCellEntries(
        bodyHeight: chip * 3,
        totalEntries: total,
      );
      expect(layout.shown, total, reason: 'total=$total');
      expect(layout.showMore, isFalse, reason: 'total=$total');
    }
  });

  test('more than three keeps two names and a +N pill', () {
    final layout = CalendarPerf.layoutDayCellEntries(
      bodyHeight: chip * 2 + pill,
      totalEntries: 45,
    );
    expect(layout.shown, 2);
    expect(layout.showMore, isTrue);
    expect(45 - layout.shown, 43);
  });

  test('five items in a tall cell still use the +N slot', () {
    final layout = CalendarPerf.layoutDayCellEntries(
      bodyHeight: 80,
      totalEntries: 5,
    );
    expect(layout.shown, 2);
    expect(layout.showMore, isTrue);
  });

  test('a short cell drops a name so the pill still fits', () {
    final layout = CalendarPerf.layoutDayCellEntries(
      bodyHeight: chip + pill,
      totalEntries: 3,
    );
    expect(layout.shown, 1);
    expect(layout.showMore, isTrue);
    expect(layout.shown * chip + pill, lessThanOrEqualTo(chip + pill + 0.5));
  });

  test('chips and pill never exceed the body height', () {
    for (final height in [16.0, 32.0, 48.0, 60.0]) {
      for (final total in [1, 2, 3, 4, 45]) {
        final layout = CalendarPerf.layoutDayCellEntries(
          bodyHeight: height,
          totalEntries: total,
        );
        final used = layout.shown * layout.chipHeight +
            (layout.showMore ? pill : 0);
        expect(used, lessThanOrEqualTo(height + 0.5),
            reason: 'height=$height total=$total');
        expect(layout.shown, lessThanOrEqualTo(3));
        if (total > 3 && layout.shown > 0) {
          expect(layout.shown, lessThanOrEqualTo(2));
          expect(layout.showMore, isTrue);
        }
      }
    }
  });
}
