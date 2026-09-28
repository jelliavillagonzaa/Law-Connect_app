import 'package:flutter/material.dart';

/// Fixed 6×7 month grid — faster than [GridView] for month navigation (no scroll).
class CalendarMonthGrid extends StatelessWidget {
  const CalendarMonthGrid({
    super.key,
    required this.viewDate,
    required this.cellBuilder,
    this.isCompact = false,
  });

  final DateTime viewDate;
  final bool isCompact;
  final Widget Function(
    BuildContext context,
    DateTime day,
    bool isCurrentMonth,
    bool isToday,
  ) cellBuilder;

  static List<DateTime> computeDays(DateTime viewDate) {
    final firstDayOfMonth = DateTime(viewDate.year, viewDate.month, 1);
    final lastDayOfMonth = DateTime(viewDate.year, viewDate.month + 1, 0);
    final firstDayWeekday = firstDayOfMonth.weekday;
    final daysInMonth = lastDayOfMonth.day;

    final days = <DateTime>[];
    for (var i = firstDayWeekday - 1; i > 0; i--) {
      days.add(firstDayOfMonth.subtract(Duration(days: i)));
    }
    for (var i = 1; i <= daysInMonth; i++) {
      days.add(DateTime(viewDate.year, viewDate.month, i));
    }
    final remainingDays = 42 - days.length;
    for (var i = 1; i <= remainingDays; i++) {
      days.add(DateTime(viewDate.year, viewDate.month + 1, i));
    }
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final days = computeDays(viewDate);
    final now = DateTime.now();
    final viewMonth = viewDate.month;
    final pad = isCompact ? 8.0 : 16.0;
    final gap = isCompact ? 4.0 : 8.0;

    return Padding(
      padding: EdgeInsets.all(pad),
      child: Column(
        children: List.generate(6, (week) {
          return Expanded(
            child: RepaintBoundary(
              child: Padding(
                padding: EdgeInsets.only(bottom: week < 5 ? gap : 0),
                child: Row(
                  children: List.generate(7, (col) {
                    final day = days[week * 7 + col];
                    final isCurrentMonth = day.month == viewMonth;
                    final isToday =
                        day.year == now.year &&
                        day.month == now.month &&
                        day.day == now.day;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: col < 6 ? gap : 0),
                        child: SizedBox.expand(
                          child: cellBuilder(
                            context,
                            day,
                            isCurrentMonth,
                            isToday,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
