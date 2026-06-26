import 'package:flutter/material.dart';

import '../profile_screen.dart';
import '../conversations_list_screen.dart';
import '../appointments_screen.dart';
import '../cases_list_screen.dart';

/// Non-home dashboard tabs — loaded as a separate deferred library on web.
Widget buildClientDashboardTab(int index) {
  switch (index) {
    case 1:
      return const CasesListScreen();
    case 2:
      return const AppointmentsScreen();
    case 3:
      return const ConversationsListScreen();
    case 4:
      return const ProfileScreen();
    default:
      return const SizedBox.shrink();
  }
}
