import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../screens/client/dashboard/dashboard_notification_badge.dart';

/// Client app-bar bell with a live unread count (mobile + web).
class ClientNotificationBellButton extends StatefulWidget {
  const ClientNotificationBellButton({
    super.key,
    this.iconColor = Colors.white,
  });

  final Color iconColor;

  @override
  State<ClientNotificationBellButton> createState() =>
      _ClientNotificationBellButtonState();
}

class _ClientNotificationBellButtonState
    extends State<ClientNotificationBellButton>
    with WidgetsBindingObserver {
  final DashboardNotificationBadgeController _badge =
      DashboardNotificationBadgeController();
  StreamSubscription<User?>? _authSub;
  int _unread = 0;
  String? _uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindToUser(FirebaseAuth.instance.currentUser?.uid);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      _bindToUser(user?.uid);
    });
  }

  void _bindToUser(String? uid) {
    if (uid == _uid) return;
    _uid = uid;
    _badge.stop();
    if (uid == null) {
      if (_unread != 0 && mounted) setState(() => _unread = 0);
      return;
    }
    unawaited(
      _badge.start(uid, (count) {
        if (!mounted || count == _unread) return;
        setState(() => _unread = count);
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_badge.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _badge.stop();
    super.dispose();
  }

  Future<void> _openInbox() async {
    await Get.toNamed('/ClientNotifications');
    if (mounted) unawaited(_badge.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final count = _unread;
    return IconButton(
      tooltip: count > 0 ? 'Notifications ($count unread)' : 'Notifications',
      onPressed: _openInbox,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.notifications_outlined, color: widget.iconColor),
          if (count > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: count > 9 ? 5 : 4,
                  vertical: 1,
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1C40F),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: const Color(0xFF0E2A4A),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
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
