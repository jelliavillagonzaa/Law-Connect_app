import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../models/staff_model.dart';
import '../../services/staff_auth_service.dart';
import '../../services/calendar_session_cleanup.dart';
import '../../widgets/common/profile_picture_widget.dart';
import '../../theme/app_theme.dart';
import '../auth/login_page.dart';

class StaffProfilePage extends StatefulWidget {
  const StaffProfilePage({super.key});

  @override
  State<StaffProfilePage> createState() => _StaffProfilePageState();
}

class _StaffProfilePageState extends State<StaffProfilePage> {
  final StaffAuthService _staffAuthService = StaffAuthService();
  StaffModel? _currentStaff;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentStaff = StaffModel(
        id: user.uid,
        name: user.displayName ?? 'Staff',
        email: user.email ?? '',
        photoUrl: user.photoURL,
        assignedAttorneyId: '',
        createdAt: user.metadata.creationTime ?? DateTime.now(),
        isVerified: user.emailVerified,
      );
    }
    _loadStaffData();
  }

  Future<void> _loadStaffData() async {
    try {
      final staff = await _staffAuthService
          .getCurrentStaff()
          .timeout(const Duration(seconds: 4));
      if (mounted && staff != null) {
        setState(() => _currentStaff = staff);
      }
    } catch (_) {}
  }

  Future<void> _editProfile() async {
    if (_currentStaff == null) return;

    final nameController = TextEditingController(text: _currentStaff!.name);
    final phoneController = TextEditingController(text: _currentStaff!.phoneNumber ?? '');
    final addressController = TextEditingController(text: _currentStaff!.address ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Edit Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressController,
                decoration: InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.location_on),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Save',
              style: TextStyle(
                color: AppTheme.royalBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final result = await _staffAuthService.updateStaffProfile(
            staffId: user.uid,
            name: nameController.text.trim(),
            phoneNumber: phoneController.text.trim().isEmpty 
                ? null 
                : phoneController.text.trim(),
            address: addressController.text.trim().isEmpty 
                ? null 
                : addressController.text.trim(),
          );

          if (result['success'] == true) {
            await _loadStaffData();
            if (mounted) {
              Get.snackbar(
                'Success',
                'Profile updated successfully',
                backgroundColor: Colors.green,
                colorText: Colors.white,
                duration: const Duration(seconds: 2),
              );
            }
          } else {
            if (mounted) {
              Get.snackbar(
                'Error',
                result['message'] ?? 'Failed to update profile',
                backgroundColor: Colors.red,
                colorText: Colors.white,
                duration: const Duration(seconds: 3),
              );
            }
          }
        }
      } catch (e) {
        if (mounted) {
          Get.snackbar(
            'Error',
            'Failed to update profile: $e',
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 3),
          );
        }
      }
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Logout',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: TextStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Logout',
              style: TextStyle(
                color: AppTheme.royalBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      CalendarSessionCleanup.onLogout();
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Get.offAll(() => const LoginPage());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (_currentStaff == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'My Profile',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppTheme.royalBlue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Staff not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'My Profile',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editProfile,
            tooltip: 'Edit Profile',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          children: [
            // Profile Picture
            ProfilePictureWidget(
              photoUrl: _currentStaff!.photoUrl,
              userName: _currentStaff!.name,
              size: 120,
              isEditable: true,
              onUpdated: _loadStaffData,
            ),
            const SizedBox(height: 16),
            // User Info
            Text(
              _currentStaff!.name,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user?.email ?? _currentStaff!.email,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            // Profile Details Card
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 2,
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Profile Information',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildInfoRow(
                        Icons.person_outline,
                        'Name',
                        _currentStaff!.name,
                      ),
                      _buildInfoRow(
                        Icons.email_outlined,
                        'Email',
                        _currentStaff!.email,
                      ),
                      _buildInfoRow(
                        Icons.phone_outlined,
                        'Phone',
                        _currentStaff!.phoneNumber ?? 'Not set',
                      ),
                      _buildInfoRow(
                        Icons.location_on_outlined,
                        'Address',
                        _currentStaff!.address ?? 'Not set',
                      ),
                      _buildInfoRow(
                        Icons.work_outline,
                        'Role',
                        'Staff (Paralegal/Legal Assistant)',
                      ),
                      _buildInfoRow(
                        Icons.calendar_today_outlined,
                        'Member Since',
                        DateFormat('MMM dd, yyyy')
                            .format(_currentStaff!.createdAt),
                        showDivider: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Logout Button
            Align(
              alignment: Alignment.center,
              child: ElevatedButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text(
                  'Logout',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.royalBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 12,
                  ),
                  minimumSize: const Size(140, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    bool showDivider = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.royalBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppTheme.royalBlue, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.darkText,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            thickness: 1,
            indent: 0,
            endIndent: 0,
            color: AppTheme.borderGray,
          ),
      ],
    );
  }
}
