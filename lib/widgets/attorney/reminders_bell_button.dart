import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../screens/attorney/attorney_reminders_screen.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../common/app_icon_button.dart';

/// Reminders bell with instant cached badge (no waiting on StreamBuilder).
class RemindersBellButton extends StatefulWidget {
  final String userId;
  final int messageUnreadCount;
  final bool includeMessageCount;

  const RemindersBellButton({
    super.key,
    required this.userId,
    this.messageUnreadCount = 0,
    this.includeMessageCount = false,
  });

  @override
  State<RemindersBellButton> createState() => _RemindersBellButtonState();
}

class _RemindersBellButtonState extends State<RemindersBellButton> {
  late int _reminderCount;
  StreamSubscription<int>? _bellSub;

  @override
  void initState() {
    super.initState();
    final fanout = HearingNotificationFanoutService.instance;
    _reminderCount = fanout.peekInboxBellCount(widget.userId);

    if (kIsWeb) {
      unawaited(_refreshBellCountWeb());
      return;
    }

    unawaited(
      fanout.prepareBellCount(widget.userId).then((_) {
        if (!mounted) return;
        final next = fanout.peekInboxBellCount(widget.userId);
        if (next != _reminderCount) {
          setState(() => _reminderCount = next);
        }
      }),
    );
    fanout.warmInbox(widget.userId);
    _bellSub = fanout.watchInboxBellCount(widget.userId).listen((n) {
      if (!mounted || n == _reminderCount) return;
      setState(() => _reminderCount = n);
    });
  }

  Future<void> _refreshBellCountWeb() async {
    final fanout = HearingNotificationFanoutService.instance;
    await fanout.prepareBellCount(widget.userId);
    if (!mounted) return;
    final next = await fanout.refreshInboxBellCountOnce(widget.userId);
    if (!mounted || next == _reminderCount) return;
    setState(() => _reminderCount = next);
  }

  @override
  void didUpdateWidget(RemindersBellButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _bellSub?.cancel();
      _reminderCount = HearingNotificationFanoutService.instance
          .peekInboxBellCount(widget.userId);
      if (kIsWeb) {
        unawaited(_refreshBellCountWeb());
        return;
      }
      final fanout = HearingNotificationFanoutService.instance;
      fanout.warmInbox(widget.userId);
      _bellSub = fanout.watchInboxBellCount(widget.userId).listen((n) {
        if (!mounted || n == _reminderCount) return;
        setState(() => _reminderCount = n);
      });
    }
  }

  @override
  void dispose() {
    _bellSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badgeTotal = widget.includeMessageCount
        ? _reminderCount + widget.messageUnreadCount
        : _reminderCount;

    return AppIconButton.appBar(
      icon: Icons.notifications_active,
      tooltip: 'Reminders',
      badgeCount: badgeTotal,
      margin: widget.includeMessageCount ? null : const EdgeInsets.all(4),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AttorneyRemindersScreen(),
          ),
        );
      },
    );
  }
}
