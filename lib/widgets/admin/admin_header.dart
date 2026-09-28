import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'header_hero.dart';

class AdminHeader extends StatelessWidget {
  const AdminHeader({
    super.key,
    this.badgeCount = 0,
    this.findHits,
    this.onSubmitted,
  });

  final int badgeCount;
  final List<AdminSearchHit> Function(String query)? findHits;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final raw = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : (user?.email?.split('@').first ?? 'admin');
    return HeaderHero(
      adminName: raw,
      badgeCount: badgeCount,
      findHits: findHits,
      onSubmitted: onSubmitted,
    );
  }
}
