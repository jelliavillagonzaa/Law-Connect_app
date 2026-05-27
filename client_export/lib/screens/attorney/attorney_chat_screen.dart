import 'package:flutter/material.dart';
import '../../screens/client/conversations_list_screen.dart';

class AttorneyChatScreen extends StatelessWidget {
  const AttorneyChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Reuse the conversations list screen
    return const ConversationsListScreen();
  }
}

