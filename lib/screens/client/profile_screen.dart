import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_card.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/secondary_button.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../pages/client/client_landing_page.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();
  UserModel? _currentUser;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      await AuthService().syncStaffRoleFromStaffApplication(
        uid: user.uid,
        email: user.email ?? '',
      );
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && mounted) {
        setState(() {
          _currentUser = UserModel.fromFirestore(userDoc.data()!, user.uid);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _editProfile() async {
    if (_currentUser == null) return;

    final nameController = TextEditingController(
      text: _currentUser!.fullName ?? _currentUser!.name,
    );
    final phoneController = TextEditingController(
      text: _currentUser!.phoneNumber ?? _currentUser!.phone ?? '',
    );
    final addressController = TextEditingController(
      text: _currentUser!.address ?? '',
    );

    final result = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Edit Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await _firestoreService.updateUserProfile(user.uid, {
            'fullName': nameController.text.trim(),
            'name': nameController.text.trim(),
            'phoneNumber': phoneController.text.trim(),
            'address': addressController.text.trim(),
          });
          await _loadUserData();
          if (mounted) {
            Get.snackbar(
              'Success',
              'Profile updated successfully',
              backgroundColor: AppTheme.success,
              colorText: AppTheme.white,
            );
            // Refresh the profile picture if it was updated
            setState(() {});
          }
        }
      } catch (e) {
        if (mounted) {
          Get.snackbar(
            'Error',
            'Failed to update profile: $e',
            backgroundColor: AppTheme.error,
            colorText: AppTheme.white,
          );
        }
      }
    }
  }

  Future<void> _changePassword() async {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    final result = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Change Password'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPasswordController,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (newPasswordController.text !=
                  confirmPasswordController.text) {
                Get.snackbar(
                  'Error',
                  'Passwords do not match',
                  backgroundColor: AppTheme.error,
                  colorText: AppTheme.white,
                );
                return;
              }
              if (newPasswordController.text.length < 6) {
                Get.snackbar(
                  'Error',
                  'Password must be at least 6 characters',
                  backgroundColor: AppTheme.error,
                  colorText: AppTheme.white,
                );
                return;
              }
              Get.back(result: true);
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          // TODO: Re-authenticate with old password
          // TODO: Update password using FirebaseAuth.instance.currentUser?.updatePassword()
          Get.snackbar(
            'Info',
            'Password change functionality requires re-authentication. Please use Firebase Console or implement re-auth flow.',
            backgroundColor: AppTheme.warning,
            colorText: AppTheme.white,
            duration: const Duration(seconds: 4),
          );
        }
      } catch (e) {
        if (mounted) {
          Get.snackbar(
            'Error',
            'Failed to change password: $e',
            backgroundColor: AppTheme.error,
            colorText: AppTheme.white,
          );
        }
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: Text('Logout', style: TextStyle(color: AppTheme.royalBlue, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseAuth.instance.signOut();
      } finally {
        // Navigate to splash screen (which will route appropriately)
        Get.offAll(() => const ClientLandingPage());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.lightBackground,
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentUser == null) {
      return Scaffold(
        backgroundColor: AppTheme.lightBackground,
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(title: const Text('Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            // Profile summary card
            ProfileCard(
              name: _currentUser!.fullName ?? _currentUser!.name,
              email: _currentUser!.email,
              role: _currentUser!.role,
              photoUrl: _currentUser!.photoUrl,
              isVerified: _currentUser!.isVerified,
              isEditable: true,
              onPhotoUpdated: () async {
                // Refresh user data after profile picture update
                try {
                  await _loadUserData();
                  // Force a rebuild to show the new photo
                  if (mounted) {
                    setState(() {});
                  }
                } catch (e) {
                  print('Error refreshing user data after photo update: $e');
                }
              },
            ),
            const SizedBox(height: 8),
            // Account details section header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppTheme.gold,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Account Details',
                    style: AppTheme.heading4.copyWith(
                      color: AppTheme.royalBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            // Account Details Container - all items in one card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Phone Number
                  if (_currentUser!.phoneNumber != null ||
                      _currentUser!.phone != null)
                    _buildAccountDetailRow(
                      icon: Icons.phone_outlined,
                      label: 'Phone Number',
                      value: _currentUser!.phoneNumber ?? 
                             _currentUser!.phone ?? 
                             'N/A',
                    ),
                  // Divider after phone if address exists
                  if ((_currentUser!.phoneNumber != null ||
                          _currentUser!.phone != null) &&
                      _currentUser!.address != null)
                    _buildDivider(),
                  // Address
                  if (_currentUser!.address != null)
                    _buildAccountDetailRow(
                      icon: Icons.location_on_outlined,
                      label: 'Address',
                      value: _currentUser!.address!,
                    ),
                  // Divider after address
                  if (_currentUser!.address != null) _buildDivider(),
                  // Account Created
                  _buildAccountDetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Account Created',
                    value: _formatDate(_currentUser!.createdAt),
                  ),
                  // Divider before Email Verification
                  _buildDivider(),
                  // Email Verification (last item - no divider after)
                  _buildAccountDetailRow(
                    icon: Icons.verified_outlined,
                    label: 'Email Verification',
                    value: _currentUser!.isVerified ? 'Verified ✓' : 'Not Verified',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Security & actions section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppTheme.gold,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Security & Settings',
                    style: AppTheme.heading4.copyWith(
                      color: AppTheme.royalBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  PrimaryButton(
                    text: 'Edit Profile',
                    icon: Icons.edit_outlined,
                    onPressed: _editProfile,
                  ),
                  const SizedBox(height: 12),
                  SecondaryButton(
                    text: 'Change Password',
                    icon: Icons.lock_outline,
                    onPressed: _changePassword,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _logout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.royalBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text('Logout', style: AppTheme.buttonText),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.royalBlue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.royalBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: Colors.grey.withOpacity(0.2),
    );
  }
}
