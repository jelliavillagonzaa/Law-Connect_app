import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/profile_card.dart';

class ClientListScreen extends StatelessWidget {
  const ClientListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: Fetch clients from Firestore
    final clients = <Map<String, dynamic>>[]; // Placeholder

    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('My Clients'),
      ),
      body: clients.isEmpty
          ? EmptyState(
              icon: Icons.people_outlined,
              title: 'No Clients',
              message: 'You don\'t have any clients yet',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: clients.length,
              itemBuilder: (context, index) {
                final client = clients[index];
                return ProfileCard(
                  name: client['name'] ?? 'Client Name',
                  email: client['email'] ?? 'client@example.com',
                  role: 'Client',
                  isVerified: client['isVerified'] ?? false,
                  onTap: () {
                    // TODO: Navigate to client details
                  },
                );
              },
            ),
    );
  }
}

