import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../screens/attorney/attorney_reminders_screen.dart';
import '../../services/lightweight_reminders_inbox_service.dart';
import '../common/app_icon_button.dart';

/// Reminders bell — unread notification/reminder count only (not messages).
class RemindersBellButton extends StatefulWidget {
  const RemindersBellButton({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  State<RemindersBellButton> createState() => _RemindersBellButtonState();
}

class _RemindersBellButtonState extends State<RemindersBellButton> {
  int _reminderCount = 0;

  @override
  void initState() {
    super.initState();
    Timer(Duration(seconds: kIsWeb ? 6 : 4), () {
      if (!mounted) return;
      unawaited(_refreshBellCount());
    });
  }

  Future<void> _refreshBellCount() async {
    try {
      final next = await LightweightRemindersInboxService.countUnreadReminders(
        widget.userId,
      );
      if (!mounted || next == _reminderCount) return;
      setState(() => _reminderCount = next);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(RemindersBellButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      unawaited(_refreshBellCount());
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _reminderCount;
    return AppIconButton.appBar(
      icon: Icons.notifications_active,
      tooltip: count > 0 ? 'Reminders ($count unread)' : 'Reminders',
      badgeCount: count,
      margin: const EdgeInsets.all(4),
      onPressed: () async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (context) => const AttorneyRemindersScreen(
              skipHeavyWarmOnOpen: true,
            ),
          ),
        );
        if (mounted) unawaited(_refreshBellCount());
      },
    );
  }
}
