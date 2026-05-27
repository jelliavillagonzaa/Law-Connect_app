import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../services/profile_service.dart';
import '../../services/auth_service.dart';
import '../../controllers/auth_controller.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_list_page.dart';
import '../case/search_attorney_page.dart';
import '../notary/notary_portal.dart';
import '../splash_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();
  final ProfileService _profileService = ProfileService();
  final AuthService _authService = AuthService();
  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  AuthController? _authController;

  UserModel? _currentUser;
  int _selectedIndex = 0;
  String? _localImageBase64;

  @override
  void initState() {
    super.initState();
    try {
      _authController = Get.find<AuthController>();
    } catch (e) {
      // AuthController not found, will use AuthService
    }
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _authService.syncStaffRoleFromStaffApplication(
        uid: user.uid,
        email: user.email ?? '',
      );
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && mounted) {
        setState(() {
          _currentUser = UserModel.fromFirestore(userDoc.data()!, user.uid);
        });
        // Load local image if photoUrl is 'local_storage'
        if (_currentUser?.photoUrl == 'local_storage') {
          _loadLocalImage();
        } else {
          setState(() {
            _localImageBase64 = null;
          });
        }
      }
    }
  }

  Future<void> _loadLocalImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final localImage = await _profileService.getLocalProfilePicture(user.uid);
      if (mounted) {
        setState(() {
          _localImageBase64 = localImage;
        });
      }
    } catch (e) {
      print('Error loading local profile image: $e');
      if (mounted) {
        setState(() {
          _localImageBase64 = null;
        });
      }
    }
  }

  // Note: case-related helpers have been kept minimal because client-side
  // case management is no longer available in the app.

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: Text('My Cases', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Get.to(() => const SearchAttorneyPage()),
          ),
        ],
      ),
      body: _buildBody(isMobile: isMobile),
      // Client-side case creation has been disabled; no FAB for creating cases.
      floatingActionButton: null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Container(
            height: isMobile ? 65 : 70,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 4 : 8,
              vertical: 4,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: _buildBottomNavItem(Icons.folder, 'My Cases', 0),
                ),
                Expanded(child: _buildBottomNavItem(Icons.gavel, 'Notary', 1)),
                Expanded(
                  child: _buildBottomNavItem(
                    Icons.chat_bubble_outline,
                    'Messages',
                    2,
                  ),
                ),
                Expanded(
                  child: _buildBottomNavItem(Icons.person, 'Profile', 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody({required bool isMobile}) {
    if (_selectedIndex == 0) {
      // Cases tab is disabled for clients; show an informational message instead.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.info_outline,
                size: 64,
                color: AppTheme.royalBlue,
              ),
              const SizedBox(height: 16),
              Text(
                'Client case management is no longer available in the app.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Please contact your attorney directly for any questions about your cases.',
                style: TextStyle(fontSize: 14, color: const Color(0xFF6D6D6D)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    } else if (_selectedIndex == 3) {
      return _buildProfileTab();
    }
    // For Notary and Messages, they navigate away, so return empty
    return const SizedBox.shrink();
  }

  Widget _buildBottomNavItem(IconData icon, String label, int index) {
    final isActive = _selectedIndex == index;
    final isMobile = MediaQuery.of(context).size.width < 600;
    return GestureDetector(
      onTap: () {
        if (index == 1) {
          // Notary
          Get.to(() => const NotaryPortal());
        } else if (index == 2) {
          // Messages
          Get.to(() => const ChatListPage());
        } else {
          setState(() => _selectedIndex = index);
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 4 : 8,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.royalBlue.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isMobile ? 22 : 24,
              color: isActive ? AppTheme.royalBlue : const Color(0xFF6D6D6D),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isMobile ? 10 : 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive
                      ? AppTheme.royalBlue
                      : const Color(0xFF6D6D6D),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Note: case-related helpers have been trimmed because client-side
  // case management is no longer available in the app.

  Widget _buildProfileTab() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: isMobile ? 80 : 100, // Padding for bottom navigation
      ),
      child: Column(
        children: [
          // Enhanced Gradient Header
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.royalBlue, AppTheme.deepNavy],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 24.0 : 40.0,
                  vertical: 32.0,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // Large Circular Profile Picture with White Border and Shadow
                    GestureDetector(
                      onTap: () => _pickAndUploadPhoto(),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.cleanWhite,
                              border: Border.all(
                                color: AppTheme.cleanWhite,
                                width: 5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                  spreadRadius: 2,
                                ),
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: _buildProfilePicture(),
                          ),
                          // Camera Icon Overlay
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.royalBlue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppTheme.cleanWhite,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 20,
                                color: AppTheme.cleanWhite,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // User Name in Bold
                    Text(
                      _currentUser?.fullName ?? _currentUser?.name ?? 'User',
                      style: TextStyle(
                        fontSize: isMobile ? 26 : 28,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.cleanWhite,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    // Small Rounded Badge showing "Client"
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.gold, width: 1.5),
                      ),
                      child: Text(
                        'Client',
                        style: TextStyle(
                          color: AppTheme.gold,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
          // Enhanced Profile Information Card
          Padding(
            padding: EdgeInsets.all(isMobile ? 20.0 : 24.0),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.cleanWhite,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Card Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.royalBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.info_outline,
                            color: AppTheme.royalBlue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Profile Information',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkText,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    if (_currentUser != null) ...[
                      // Full Name
                      _buildEnhancedProfileInfoRow(
                        icon: Icons.person_outline,
                        label: 'Full Name',
                        value: _currentUser!.fullName ?? _currentUser!.name,
                        iconColor: AppTheme.royalBlue,
                      ),
                      const SizedBox(height: 20),
                      _buildDivider(),
                      const SizedBox(height: 20),
                      // Email
                      _buildEnhancedProfileInfoRow(
                        icon: Icons.email_outlined,
                        label: 'Email',
                        value: _currentUser!.email,
                        iconColor: AppTheme.royalBlue,
                      ),
                      const SizedBox(height: 20),
                      _buildDivider(),
                      const SizedBox(height: 20),
                      // Phone Number
                      if (_currentUser!.phoneNumber != null ||
                          _currentUser!.phone != null) ...[
                        _buildEnhancedProfileInfoRow(
                          icon: Icons.phone_outlined,
                          label: 'Phone Number',
                          value:
                              _currentUser!.phoneNumber ??
                              _currentUser!.phone ??
                              'N/A',
                          iconColor: AppTheme.royalBlue,
                        ),
                        const SizedBox(height: 20),
                        _buildDivider(),
                        const SizedBox(height: 20),
                      ],
                      // Address
                      if (_currentUser!.address != null) ...[
                        _buildEnhancedProfileInfoRow(
                          icon: Icons.location_on_outlined,
                          label: 'Address',
                          value: _currentUser!.address!,
                          iconColor: AppTheme.royalBlue,
                        ),
                        const SizedBox(height: 20),
                        _buildDivider(),
                        const SizedBox(height: 20),
                      ],
                      // Verification Status with Green Badge
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color:
                                  (_currentUser!.isVerified
                                          ? Colors.green
                                          : Colors.orange)
                                      .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.verified_user_outlined,
                              color: _currentUser!.isVerified
                                  ? Colors.green
                                  : Colors.orange,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Verification Status',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.mutedText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _currentUser!.isVerified
                                        ? Colors.green.withOpacity(0.1)
                                        : Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: _currentUser!.isVerified
                                          ? Colors.green
                                          : Colors.orange,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _currentUser!.isVerified
                                            ? Icons.check_circle
                                            : Icons.pending,
                                        size: 16,
                                        color: _currentUser!.isVerified
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _currentUser!.isVerified
                                            ? 'Verified'
                                            : 'Not Verified',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: _currentUser!.isVerified
                                              ? Colors.green
                                              : Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ] else
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    const SizedBox(height: 32),
                    // Edit Profile Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _editProfile(),
                        icon: const Icon(Icons.edit_outlined, size: 22),
                        label: Text(
                          'Edit Profile',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.royalBlue,
                          foregroundColor: AppTheme.cleanWhite,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 3,
                          shadowColor: AppTheme.royalBlue.withOpacity(0.3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Logout Button (Professional theme color, with icon, no arrow)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _handleLogout,
                        icon: const Icon(Icons.logout, size: 22),
                        label: Text(
                          'Logout',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.royalBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 3,
                          shadowColor: AppTheme.royalBlue.withOpacity(0.3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to logout?', style: TextStyle()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
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
      try {
        if (_authController != null) {
          await _authController!.logout();
        } else {
          await _authService.logout();
        }
        Get.offAll(() => const SplashScreen());
      } catch (e) {
        Get.offAll(() => const SplashScreen());
      }
    }
  }

  Widget _buildEnhancedProfileInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.mutedText,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.darkText,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: AppTheme.borderGray.withOpacity(0.5),
    );
  }

  Widget _buildProfilePicture() {
    final photoUrl = _currentUser?.photoUrl;

    // Check for local storage image first
    final hasLocalImage =
        _localImageBase64 != null &&
        _localImageBase64!.isNotEmpty &&
        photoUrl == 'local_storage';

    // Check for network image
    final hasNetworkImage =
        photoUrl != null && photoUrl.isNotEmpty && photoUrl != 'local_storage';

    if (hasLocalImage) {
      try {
        return ClipOval(
          child: Image.memory(
            base64Decode(_localImageBase64!),
            fit: BoxFit.cover,
            width: 140,
            height: 140,
            errorBuilder: (context, error, stackTrace) {
              return _buildDefaultAvatar();
            },
          ),
        );
      } catch (e) {
        print('Error decoding local image: $e');
        return _buildDefaultAvatar();
      }
    } else if (hasNetworkImage) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          fit: BoxFit.cover,
          width: 140,
          height: 140,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultAvatar();
          },
        ),
      );
    } else {
      return _buildDefaultAvatar();
    }
  }

  Widget _buildDefaultAvatar() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.royalBlue.withOpacity(0.1),
      ),
      child: Icon(Icons.person, size: 70, color: AppTheme.royalBlue),
    );
  }

  Future<void> _pickAndUploadPhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final ImageSource? source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!kIsWeb)
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Camera'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(kIsWeb ? 'Choose File' : 'Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (pickedFile == null) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        final photoUrl = await _storageService.uploadProfilePhoto(
          userId: user.uid,
          imageFile: pickedFile,
        );

        await _firestoreService.updateUserProfile(user.uid, {
          'photoUrl': photoUrl,
        });

        await _loadUserData();

        // Reload local image if photoUrl is 'local_storage'
        if (photoUrl == 'local_storage') {
          await _loadLocalImage();
        }

        if (mounted) {
          Navigator.of(context).pop();
          Get.snackbar(
            'Success',
            'Profile photo updated successfully',
            backgroundColor: Colors.green,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop();
          Get.snackbar(
            'Error',
            'Failed to upload photo: ${e.toString()}',
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 3),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to pick image: ${e.toString()}',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _editProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentUser == null) return;

    final nameController = TextEditingController(
      text: _currentUser!.fullName ?? _currentUser!.name,
    );
    final phoneController = TextEditingController(
      text: _currentUser!.phoneNumber ?? _currentUser!.phone ?? '',
    );
    final addressController = TextEditingController(
      text: _currentUser!.address ?? '',
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _firestoreService.updateUserProfile(user.uid, {
                  'fullName': nameController.text.trim(),
                  'name': nameController.text.trim(),
                  'phoneNumber': phoneController.text.trim(),
                  'address': addressController.text.trim(),
                });
                await _loadUserData();
                Navigator.pop(context);
                Get.snackbar(
                  'Success',
                  'Profile updated successfully',
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                );
              } catch (e) {
                Get.snackbar(
                  'Error',
                  'Failed to update profile: $e',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
