import 'package:flutter/material.dart';

import '../../screens/attorney/attorney_reminders_screen.dart';
import '../../services/hearing_notification_fanout_service.dart';
import 'attorney_ui_theme.dart';

/// Attorney dashboard bell. Badge is unread `notifications` count only.
class RemindersBellButton extends StatefulWidget {
  const RemindersBellButton({
    super.key,
    required this.userId,
    this.lightSurface = false,
  });

  final String userId;
  final bool lightSurface;

  @override
  State<RemindersBellButton> createState() => _RemindersBellButtonState();
}

class _RemindersBellButtonState extends State<RemindersBellButton> {
  late ValueNotifier<int> _unread;

  @override
  void initState() {
    super.initState();
    _bind(widget.userId);
  }

  @override
  void didUpdateWidget(RemindersBellButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _bind(widget.userId);
    }
  }

  void _bind(String userId) {
    final fanout = HearingNotificationFanoutService.instance;
    fanout.attachAttorneyBellWatcher(userId);
    _unread = fanout.attorneyUnreadNotificationBellListenable(userId);
  }

  Future<void> _openReminders() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => const AttorneyRemindersScreen(),
      ),
    );
    if (!mounted) return;
    HearingNotificationFanoutService.instance
        .attachAttorneyBellWatcher(widget.userId);
    await HearingNotificationFanoutService.instance
        .refreshAttorneyBellFromNotifications(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    final iconColor =
        widget.lightSurface ? AttorneyUi.primary : Colors.white;
    final bg = widget.lightSurface
        ? AttorneyUi.background
        : Colors.white.withValues(alpha: 0.2);

    return ValueListenableBuilder<int>(
      valueListenable: _unread,
      builder: (context, count, _) {
        final badge = count < 0 ? 0 : count;
        return Tooltip(
          message: badge > 0 ? 'Reminders ($badge unread)' : 'Reminders',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openReminders,
              customBorder: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.notifications_none_rounded,
                        color: iconColor,
                        size: 22,
                      ),
                    ),
                    if (badge > 0)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            badge > 99 ? '99+' : '$badge',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
