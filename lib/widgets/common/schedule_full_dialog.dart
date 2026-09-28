import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';

/// Popup shown when a requested appointment time is already booked.
Future<void> showScheduleFullDialog(
  BuildContext context, {
  DateTime? date,
}) {
  final dateLabel = date == null
      ? 'this day'
      : DateFormat('MMMM dd, yyyy').format(date);

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.event_busy_rounded, color: Color(0xFFC0392B)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Schedule Full',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(
          'The schedule for $dateLabel is already full at the selected time. '
          'That slot is no longer available. Please choose another date or time.',
          style: const TextStyle(height: 1.4, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'OK',
              style: TextStyle(
                color: AppTheme.royalBlue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    },
  );
}
