import 'package:flutter/material.dart';

/// "+N" slot inside a month day cell. Tap opens the full day list.
class CalendarOverflowPill extends StatelessWidget {
  const CalendarOverflowPill({
    super.key,
    required this.hiddenCount,
    required this.onTap,
    this.color = const Color.fromARGB(255, 46, 109, 192),
  });

  final int hiddenCount;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE4EAF6),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '+$hiddenCount',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                height: 1,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed 6×7 month grid — faster than [GridView] for month navigation (no scroll).
class CalendarMonthGrid extends StatelessWidget {
  const CalendarMonthGrid({
    super.key,
    required this.viewDate,
    required this.cellBuilder,
    this.isCompact = false,
    this.sundayFirst = false,
  });

  final DateTime viewDate;
  final bool isCompact;

  /// Website attorney calendar labels are S–S. The app grid stays Monday-first.
  final bool sundayFirst;
  final Widget Function(
    BuildContext context,
    DateTime day,
    bool isCurrentMonth,
    bool isToday,
  ) cellBuilder;

  static List<DateTime> computeDays(
    DateTime viewDate, {
    bool sundayFirst = false,
  }) {
    final firstDayOfMonth = DateTime(viewDate.year, viewDate.month, 1);
    final lastDayOfMonth = DateTime(viewDate.year, viewDate.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    // DateTime.weekday: Monday = 1 … Sunday = 7.
    final leading = sundayFirst
        ? firstDayOfMonth.weekday % 7
        : firstDayOfMonth.weekday - 1;

    final days = <DateTime>[];
    for (var i = leading; i > 0; i--) {
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
    final days = computeDays(viewDate, sundayFirst: sundayFirst);
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
