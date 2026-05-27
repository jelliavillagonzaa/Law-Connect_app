import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../theme/app_theme.dart';
import '../../widgets/card_row.dart';
import '../../widgets/primary_button.dart';
import '../../services/auth_service.dart';
import '../../controllers/auth_controller.dart';
import '../../pages/splash_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _handleSignOut() async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.royalBlue),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Try to use AuthController first
        try {
          final authController = Get.find<AuthController>();
          await authController.logout();
        } catch (e) {
          // If AuthController not found, use AuthService
          final authService = AuthService();
          await authService.logout();
        }

        // Navigate to splash screen (which will route to appropriate login)
        Get.offAll(() => const SplashScreen());
      } catch (e) {
        // Even if logout fails, navigate to splash screen
        Get.offAll(() => const SplashScreen());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            CardRow(
              label: 'Notifications',
              value: 'Enabled',
              icon: Icons.notifications_outlined,
              onTap: () {
                Get.snackbar(
                  'Notifications',
                  'Notification settings coming soon',
                  backgroundColor: AppTheme.navy,
                  colorText: AppTheme.white,
                );
              },
            ),
            CardRow(
              label: 'Privacy',
              value: 'Manage privacy settings',
              icon: Icons.privacy_tip_outlined,
              onTap: () {
                Get.snackbar(
                  'Privacy',
                  'Privacy settings coming soon',
                  backgroundColor: AppTheme.navy,
                  colorText: AppTheme.white,
                );
              },
            ),
            CardRow(
              label: 'Security',
              value: 'Change password, 2FA',
              icon: Icons.security_outlined,
              onTap: () {
                Get.snackbar(
                  'Security',
                  'Security settings coming soon',
                  backgroundColor: AppTheme.navy,
                  colorText: AppTheme.white,
                );
              },
            ),
            CardRow(
              label: 'About',
              value: 'App version 1.0.0',
              icon: Icons.info_outlined,
              onTap: () {
                Get.dialog(
                  AlertDialog(
                    title: const Text('About JurisLink'),
                    content: const Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('JurisLink'),
                        SizedBox(height: 8),
                        Text('Version: 1.0.0'),
                        SizedBox(height: 8),
                        Text(
                          'Professional legal services platform for clients, attorneys, and admins.',
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Get.back(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),
            CardRow(
              label: 'Help & Support',
              value: 'Get help and contact support',
              icon: Icons.help_outline,
              onTap: () {
                Get.snackbar(
                  'Help & Support',
                  'Support features coming soon',
                  backgroundColor: AppTheme.navy,
                  colorText: AppTheme.white,
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: PrimaryButton(
                text: 'Sign Out',
                icon: Icons.logout,
                onPressed: _handleSignOut,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
