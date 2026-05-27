import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_card.dart';
import '../../widgets/card_row.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';

class AttorneyProfileScreen extends StatelessWidget {
  const AttorneyProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),
            ProfileCard(
              name: 'Attorney Name', // TODO: Fetch from Firestore
              email: 'attorney@lawfirm.com', // TODO: Fetch from Firestore
              role: 'Attorney',
              isVerified: true, // TODO: Fetch from Firestore
            ),
            CardRow(
              label: 'Specialization',
              value: 'Corporate Law, Contract Law', // TODO: Fetch from Firestore
              icon: Icons.work_outline,
            ),
            CardRow(
              label: 'Phone Number',
              value: '+1 (555) 123-4567', // TODO: Fetch from Firestore
              icon: Icons.phone_outlined,
            ),
            CardRow(
              label: 'Office Address',
              value: '123 Law Street, City, State 12345', // TODO: Fetch from Firestore
              icon: Icons.location_on_outlined,
            ),
            CardRow(
              label: 'Rating',
              value: '4.8 ⭐ (120 reviews)', // TODO: Fetch from Firestore
              icon: Icons.star_outline,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  PrimaryButton(
                    text: 'Edit Profile',
                    icon: Icons.edit_outlined,
                    onPressed: () {
                      // TODO: Navigate to edit profile screen
                    },
                  ),
                  const SizedBox(height: 12),
                  SecondaryButton(
                    text: 'Change Password',
                    icon: Icons.lock_outline,
                    onPressed: () {
                      // TODO: Navigate to change password screen
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

