import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/attorney_availability_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/office_time_slots.dart';

/// Month grid plus office-hour chips. Busy times stay unlabeled:
/// a hearing, a booking, and a scheduled notary visit look the same.
class AttorneySlotPicker extends StatefulWidget {
  const AttorneySlotPicker({
    super.key,
    required this.attorneyId,
    required this.selectedSlot,
    required this.onSlotChanged,
  });

  final String attorneyId;
  final DateTime? selectedSlot;
  final ValueChanged<DateTime?> onSlotChanged;

  @override
  State<AttorneySlotPicker> createState() => _AttorneySlotPickerState();
}

class _AttorneySlotPickerState extends State<AttorneySlotPicker> {
  late DateTime _visibleMonth;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final seed = widget.selectedSlot ?? DateTime.now();
    _visibleMonth = DateTime(seed.year, seed.month);
    _selectedDay = widget.selectedSlot == null
        ? null
        : OfficeTimeSlots.dateOnly(widget.selectedSlot!);
  }

  @override
  void didUpdateWidget(AttorneySlotPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final slot = widget.selectedSlot;
    if (slot == null) return;
    _selectedDay = OfficeTimeSlots.dateOnly(slot);
    _visibleMonth = DateTime(slot.year, slot.month);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DateTime>>(
      stream: AttorneyAvailabilityService().watchBusyStarts(widget.attorneyId),
      builder: (context, snapshot) {
        final busy = snapshot.data ?? const <DateTime>[];
        final now = DateTime.now();
        final lastDate = OfficeTimeSlots.dateOnly(
          now.add(const Duration(days: OfficeTimeSlots.bookingHorizonDays)),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Open times are available. Gray times are already taken, including hearings. Names and case details are not shown.',
              style: TextStyle(fontSize: 13, height: 1.35, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            _monthHeader(now, lastDate),
            const SizedBox(height: 8),
            _weekdayRow(),
            const SizedBox(height: 4),
            _monthGrid(now, lastDate, busy),
            const SizedBox(height: 16),
            const Text(
              'Time',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _timeChips(now, busy),
          ],
        );
      },
    );
  }

  Widget _monthHeader(DateTime now, DateTime lastDate) {
    final firstMonth = DateTime(now.year, now.month);
    final lastMonth = DateTime(lastDate.year, lastDate.month);
    final canBack = _visibleMonth.isAfter(firstMonth);
    final canForward = _visibleMonth.isBefore(lastMonth);
    return Row(
      children: [
        IconButton(
          onPressed: canBack
              ? () => setState(() {
                  _visibleMonth = DateTime(
                    _visibleMonth.year,
                    _visibleMonth.month - 1,
                  );
                })
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            DateFormat('MMMM yyyy').format(_visibleMonth),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          onPressed: canForward
              ? () => setState(() {
                  _visibleMonth = DateTime(
                    _visibleMonth.year,
                    _visibleMonth.month + 1,
                  );
                })
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _weekdayRow() {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: label == 'Sun' ? const Color(0xFFC0392B) : Colors.grey[600],
              ),
            ),
          ),
      ],
    );
  }

  Widget _monthGrid(DateTime now, DateTime lastDate, List<DateTime> busy) {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month);
    final leading = first.weekday - DateTime.monday;
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();
    return Column(
      children: [
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _dayCell(
                    index: row * 7 + col,
                    leading: leading,
                    daysInMonth: daysInMonth,
                    now: now,
                    lastDate: lastDate,
                    busy: busy,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _dayCell({
    required int index,
    required int leading,
    required int daysInMonth,
    required DateTime now,
    required DateTime lastDate,
    required List<DateTime> busy,
  }) {
    final dayNumber = index - leading + 1;
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 44);
    }
    final day = DateTime(_visibleMonth.year, _visibleMonth.month, dayNumber);
    final bookable = OfficeTimeSlots.dayIsBookable(
      day: day,
      now: now,
      busyStarts: busy,
      lastDate: lastDate,
    );
    final full = OfficeTimeSlots.dayIsFull(day: day, now: now, busyStarts: busy);
    final selected = _selectedDay != null &&
        OfficeTimeSlots.dateOnly(_selectedDay!) == OfficeTimeSlots.dateOnly(day);
    final Color bg;
    final Color fg;
    if (selected) {
      bg = AppTheme.royalBlue;
      fg = Colors.white;
    } else if (full) {
      bg = const Color(0xFFF2F2F2);
      fg = Colors.grey;
    } else if (!bookable) {
      bg = Colors.transparent;
      fg = Colors.grey;
    } else {
      bg = Colors.transparent;
      fg = Colors.black87;
    }
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: bookable
              ? () {
                  setState(() => _selectedDay = day);
                  if (widget.selectedSlot != null &&
                      OfficeTimeSlots.dateOnly(widget.selectedSlot!) !=
                          OfficeTimeSlots.dateOnly(day)) {
                    widget.onSlotChanged(null);
                  }
                }
              : null,
          child: SizedBox(
            height: 46,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$dayNumber',
                  style: TextStyle(
                    color: fg,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (full && !selected)
                  const Text(
                    'Full',
                    style: TextStyle(fontSize: 8, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeChips(DateTime now, List<DateTime> busy) {
    final day = _selectedDay;
    if (day == null) {
      return Text(
        'Choose a date to see open times.',
        style: TextStyle(color: Colors.grey[600]),
      );
    }
    final slots = OfficeTimeSlots.slotsForDay(day);
    if (slots.isEmpty) {
      return Text(
        'The office is closed that day.',
        style: TextStyle(color: Colors.grey[600]),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final slot in slots)
          _chip(
            slot: slot,
            past: OfficeTimeSlots.isPastSlot(slot, now),
            busy: OfficeTimeSlots.slotIsBusy(slot, busy),
          ),
      ],
    );
  }

  Widget _chip({
    required DateTime slot,
    required bool past,
    required bool busy,
  }) {
    final selected = widget.selectedSlot != null &&
        OfficeTimeSlots.windowStart(widget.selectedSlot!) == slot;
    final disabled = past || busy;
    final label = DateFormat('h:mm a').format(slot);
    final Color bg;
    final Color fg;
    final BorderSide side;
    if (selected && !disabled) {
      bg = AppTheme.royalBlue;
      fg = Colors.white;
      side = const BorderSide(color: AppTheme.royalBlue);
    } else if (busy) {
      bg = const Color(0xFFF2F2F2);
      fg = Colors.grey;
      side = const BorderSide(color: Color(0xFFE0E0E0));
    } else if (past) {
      bg = Colors.transparent;
      fg = Colors.grey.shade400;
      side = BorderSide(color: Colors.grey.shade300);
    } else {
      bg = Colors.white;
      fg = AppTheme.royalBlue;
      side = const BorderSide(color: AppTheme.royalBlue);
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: disabled ? null : () => widget.onSlotChanged(slot),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.fromBorderSide(side),
          ),
          child: Text(
            busy ? '$label  Busy' : label,
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
