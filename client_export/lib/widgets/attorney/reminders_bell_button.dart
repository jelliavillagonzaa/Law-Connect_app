import 'dart:async';

import 'package:flutter/material.dart';

import '../../screens/attorney/attorney_reminders_screen.dart';
import '../../services/hearing_notification_fanout_service.dart';
import '../../theme/app_theme.dart';

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

  @override
  void didUpdateWidget(RemindersBellButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _bellSub?.cancel();
      _reminderCount = HearingNotificationFanoutService.instance
          .peekInboxBellCount(widget.userId);
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

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AttorneyRemindersScreen(),
          ),
        );
      },
      child: Stack(
        children: [
          Container(
            margin: widget.includeMessageCount ? null : const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.notifications_active,
              color: badgeTotal > 0
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.8),
              size: 24,
            ),
          ),
          if (badgeTotal > 0)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  badgeTotal > 99 ? '99+' : '$badgeTotal',
                  style: const TextStyle(
                    color: AppTheme.royalBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
