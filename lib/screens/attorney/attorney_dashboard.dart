import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_card.dart';
import '../../widgets/feature_tile.dart';
import 'client_list_screen.dart';
import 'case_list_screen.dart';
import 'attorney_chat_screen.dart';
import 'attorney_profile_screen.dart';

class AttorneyDashboard extends StatelessWidget {
  const AttorneyDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Attorney Dashboard'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileCard(
              name: 'Attorney Name', // TODO: Fetch from Firestore
              email: 'attorney@lawfirm.com', // TODO: Fetch from Firestore
              role: 'Attorney',
              isVerified: true, // TODO: Fetch from Firestore
              onTap: () {
                Get.to(() => const AttorneyProfileScreen());
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Quick Actions',
                style: AppTheme.heading3,
              ),
            ),
            FeatureTile(
              title: 'My Clients',
              subtitle: 'View and manage your clients',
              icon: Icons.people_outlined,
              iconColor: AppTheme.navy,
              backgroundColor: AppTheme.navy.withOpacity(0.1),
              onTap: () {
                Get.to(() => const ClientListScreen());
              },
            ),
            FeatureTile(
              title: 'Cases',
              subtitle: 'Manage all your cases',
              icon: Icons.folder_outlined,
              iconColor: AppTheme.gold,
              backgroundColor: AppTheme.gold.withOpacity(0.1),
              onTap: () {
                Get.to(() => const CaseListScreen());
              },
            ),
            FeatureTile(
              title: 'Messages',
              subtitle: 'Chat with clients',
              icon: Icons.message_outlined,
              iconColor: AppTheme.success,
              backgroundColor: AppTheme.success.withOpacity(0.1),
              onTap: () {
                Get.to(() => const AttorneyChatScreen());
              },
            ),
          ],
        ),
      ),
    );
  }
}

