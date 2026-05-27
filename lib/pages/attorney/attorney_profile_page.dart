import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/profile_service.dart';
import '../../services/auth_service.dart';
import '../../controllers/auth_controller.dart';
import '../../widgets/common/profile_picture_widget.dart';
import '../../widgets/maps/oroquieta_map_picker.dart';
import '../../widgets/maps/oroquieta_map_viewer.dart';
import '../../theme/app_theme.dart';
import '../auth/login_page.dart';

class AttorneyProfilePage extends StatefulWidget {
  /// When true, renders without [Scaffold] (used inside [AttorneyDashboard] tabs).
  final bool embedded;

  const AttorneyProfilePage({super.key, this.embedded = false});

  @override
  State<AttorneyProfilePage> createState() => _AttorneyProfilePageState();
}

class _AttorneyProfilePageState extends State<AttorneyProfilePage> {
  final ProfileService _profileService = ProfileService();
  final AuthService _authService = AuthService();
  AuthController? _authController;
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;

  // Temporary variables for map picker results
  double? _tempLatitude;
  double? _tempLongitude;
  String? _tempAddress;

  @override
  void initState() {
    super.initState();
    try {
      _authController = Get.find<AuthController>();
    } catch (e) {
      // AuthController not found, will use AuthService
    }
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getCurrentUserProfile();
      if (mounted) {
        setState(() {
          _userProfile = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 800;

    final scrollContent = ScrollConfiguration(
      behavior: const ScrollBehavior().copyWith(scrollbars: false),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 48 : 24,
          vertical: isDesktop ? 32 : 24,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 800 : double.infinity,
            ),
            child: Column(
              children: <Widget>[
                  // Profile Picture
                  ProfilePictureWidget(
                    photoUrl: _userProfile?['photoUrl'],
                    userName: _isLoading
                        ? 'Attorney'
                        : (_userProfile?['name'] ??
                              user?.email?.split('@')[0] ??
                              'Attorney'),
                    size: isDesktop ? 150 : 120,
                    isEditable: true,
                    onUpdated: _loadProfile,
                  ),
                  SizedBox(height: isDesktop ? 32 : 24),
                  // User Info
                  Text(
                    _userProfile?['name'] ?? 'Attorney',
                    style: TextStyle(
                      fontSize: isDesktop ? 28 : 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user?.email ?? '',
                    style: TextStyle(
                      fontSize: isDesktop ? 16 : 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Rating
                  if (_userProfile?['ratingAverage'] != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.star,
                          color: Colors.amber,
                          size: isDesktop ? 24 : 20,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          (() {
                            final v = _userProfile?['ratingAverage'];
                            if (v is num) return v.toStringAsFixed(1);
                            final parsed = num.tryParse(v.toString());
                            if (parsed != null) return parsed.toStringAsFixed(1);
                            return v.toString();
                          })(),
                          style: TextStyle(
                            fontSize: isDesktop ? 18 : 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  // Online / Offline toggle (settings)
                  if (_userProfile != null)
                    _buildAvailabilityHeaderToggle(isDesktop: isDesktop),
                  SizedBox(height: isDesktop ? 40 : 32),
                  // Profile Details – all info in a single container
                  Card(
                    elevation: 2,
                    margin: EdgeInsets.only(bottom: isDesktop ? 16 : 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(isDesktop ? 20 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Profile Information',
                                style: TextStyle(
                                  fontSize: isDesktop ? 20 : 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _handleEditBasicInfo,
                                icon: Icon(
                                  Icons.edit_outlined,
                                  size: isDesktop ? 18 : 16,
                                ),
                                label: Text(
                                  'Edit',
                                  style: TextStyle(
                                    fontSize: isDesktop ? 14 : 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            height: 1,
                            margin: EdgeInsets.symmetric(
                              vertical: isDesktop ? 12 : 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.grey[300]!,
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          _buildCompactInfoRow(
                            icon: Icons.person,
                            label: 'Name',
                            value: _userProfile?['name'] ?? 'Not set',
                            isDesktop: isDesktop,
                          ),
                          SizedBox(height: isDesktop ? 12 : 10),
                          _buildCompactInfoRow(
                            icon: Icons.email,
                            label: 'Email',
                            value: _userProfile?['email'] ?? 'Not set',
                            isDesktop: isDesktop,
                          ),
                          SizedBox(height: isDesktop ? 12 : 10),
                          _buildCompactInfoRow(
                            icon: Icons.phone,
                            label: 'Phone',
                            value: _userProfile?['phone'] ?? 'Not set',
                            isDesktop: isDesktop,
                          ),
                          SizedBox(height: isDesktop ? 12 : 10),
                          _buildCompactInfoRow(
                            icon: Icons.work,
                            label: 'Specializations',
                            value: _userProfile?['specialization'] != null
                                ? (_userProfile!['specialization'] as List)
                                      .join(', ')
                                : 'Not set',
                            isDesktop: isDesktop,
                          ),
                          SizedBox(height: isDesktop ? 12 : 10),
                          _buildCompactInfoRow(
                            icon: Icons.check_circle,
                            label: 'Availability',
                            value: _userProfile?['isAvailable'] == true
                                ? 'Available'
                                : 'Unavailable',
                            isDesktop: isDesktop,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: isDesktop ? 32 : 24),
                  // Additional Details - Professional Container
                  Container(
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
                      padding: EdgeInsets.all(isDesktop ? 24 : 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // Header with Edit button
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Additional Details',
                                style: TextStyle(
                                  fontSize: isDesktop ? 22 : 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkText,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _handleEditProfile,
                                icon: Icon(
                                  Icons.edit,
                                  size: isDesktop ? 18 : 16,
                                  color: AppTheme.royalBlue,
                                ),
                                label: Text(
                                  'Edit',
                                  style: TextStyle(
                                    fontSize: isDesktop ? 14 : 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.royalBlue,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isDesktop ? 12 : 8,
                                    vertical: isDesktop ? 8 : 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // Location card
                          if ((_userProfile?['officeAddress'] != null &&
                                  _userProfile!['officeAddress']
                                      .toString()
                                      .isNotEmpty) ||
                              (_userProfile?['city'] != null &&
                                  _userProfile!['city']
                                      .toString()
                                      .isNotEmpty) ||
                              (_userProfile?['province'] != null &&
                                  _userProfile!['province']
                                      .toString()
                                      .isNotEmpty))
                            Container(
                              margin: EdgeInsets.only(
                                bottom: isDesktop ? 16 : 12,
                              ),
                              padding: EdgeInsets.all(isDesktop ? 18 : 16),
                              decoration: BoxDecoration(
                                color: AppTheme.lightGray.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.borderGray.withOpacity(0.5),
                                  width: 1,
                                ),
                              ),
                              child: _buildLocationRow(isDesktop: isDesktop),
                            ),
                          // Bio card
                          if (_userProfile?['bio'] != null &&
                              _userProfile!['bio'].toString().isNotEmpty)
                            Container(
                              margin: EdgeInsets.only(
                                bottom: isDesktop ? 16 : 12,
                              ),
                              padding: EdgeInsets.all(isDesktop ? 18 : 16),
                              decoration: BoxDecoration(
                                color: AppTheme.lightGray.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.borderGray.withOpacity(0.5),
                                  width: 1,
                                ),
                              ),
                              child: _buildInfoRow(
                                Icons.description,
                                'Bio / Introduction',
                                _userProfile!['bio'],
                                isDesktop: isDesktop,
                              ),
                            ),
                          // Languages card
                          if (_userProfile?['languages'] != null)
                            Container(
                              margin: EdgeInsets.only(
                                bottom: isDesktop ? 16 : 12,
                              ),
                              padding: EdgeInsets.all(isDesktop ? 18 : 16),
                              decoration: BoxDecoration(
                                color: AppTheme.lightGray.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.borderGray.withOpacity(0.5),
                                  width: 1,
                                ),
                              ),
                              child: _buildInfoRow(
                                Icons.language,
                                'Languages Spoken',
                                _userProfile!['languages'] is List
                                    ? (_userProfile!['languages'] as List).join(
                                        ', ',
                                      )
                                    : _userProfile!['languages'].toString(),
                                isDesktop: isDesktop,
                              ),
                            ),
                          // Rate information card
                          if (_userProfile?['rateType'] != null ||
                              _userProfile?['consultationFee'] != null)
                            Container(
                              margin: EdgeInsets.only(
                                bottom: isDesktop ? 16 : 12,
                              ),
                              padding: EdgeInsets.all(isDesktop ? 18 : 16),
                              decoration: BoxDecoration(
                                color: AppTheme.lightGray.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.borderGray.withOpacity(0.5),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppTheme.royalBlue.withOpacity(
                                        0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.attach_money,
                                      color: AppTheme.royalBlue,
                                      size: isDesktop ? 24 : 20,
                                    ),
                                  ),
                                  SizedBox(width: isDesktop ? 16 : 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Rate Information',
                                          style: TextStyle(
                                            fontSize: isDesktop ? 13 : 11,
                                            color: AppTheme.mutedText,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        if (_userProfile?['rateType'] != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            child: Text(
                                              'Rate Type: ${_userProfile!['rateType']}',
                                              style: TextStyle(
                                                fontSize: isDesktop ? 16 : 14,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.darkText,
                                              ),
                                            ),
                                          ),
                                        if (_userProfile?['consultationFee'] !=
                                            null)
                                          Text(
                                            'Consultation Fee: ₱${_userProfile!['consultationFee']}',
                                            style: TextStyle(
                                              fontSize: isDesktop ? 16 : 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.darkText,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Empty-state if no additional details
                          if ((_userProfile?['officeAddress'] == null ||
                                  _userProfile!['officeAddress']
                                      .toString()
                                      .isEmpty) &&
                              (_userProfile?['city'] == null ||
                                  _userProfile!['city'].toString().isEmpty) &&
                              (_userProfile?['province'] == null ||
                                  _userProfile!['province']
                                      .toString()
                                      .isEmpty) &&
                              (_userProfile?['mapsPin'] == null ||
                                  _userProfile!['mapsPin']
                                      .toString()
                                      .isEmpty) &&
                              (_userProfile?['bio'] == null ||
                                  _userProfile!['bio'].toString().isEmpty) &&
                              _userProfile?['languages'] == null &&
                              _userProfile?['rateType'] == null &&
                              _userProfile?['consultationFee'] == null)
                            Container(
                              padding: EdgeInsets.all(isDesktop ? 32 : 24),
                              decoration: BoxDecoration(
                                color: AppTheme.lightGray.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.borderGray.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: AppTheme.mutedText,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No additional details added yet',
                                    style: TextStyle(
                                      fontSize: isDesktop ? 15 : 13,
                                      color: AppTheme.mutedText,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Click Edit to add more information',
                                    style: TextStyle(
                                      fontSize: isDesktop ? 13 : 11,
                                      color: AppTheme.mutedText.withOpacity(
                                        0.7,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: isDesktop ? 32 : 24),
                  // Logout Button (text only, no arrow/icon)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _handleLogout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.royalBlue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: isDesktop ? 18 : 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        'Logout',
                        style: TextStyle(
                          fontSize: isDesktop ? 18 : 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isDesktop ? 32 : 24),
                ],
              ),
            ),
          ),
        ),
      );

    if (widget.embedded) {
      return scrollContent;
    }

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 158, 182, 215),
      appBar: !isDesktop
          ? AppBar(
              title: Text(
                'My Profile',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppTheme.royalBlue,
              foregroundColor: Colors.white,
            )
          : null,
      body: scrollContent,
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
        Get.offAll(() => const LoginPage());
      } catch (e) {
        Get.offAll(() => const LoginPage());
      }
    }
  }

  Widget _buildLocationRow({bool isDesktop = false}) {
    final addressParts = <String>[];
    if (_userProfile?['officeAddress'] != null &&
        _userProfile!['officeAddress'].toString().isNotEmpty) {
      addressParts.add(_userProfile!['officeAddress'].toString());
    }
    if (_userProfile?['city'] != null &&
        _userProfile!['city'].toString().isNotEmpty) {
      addressParts.add(_userProfile!['city'].toString());
    }
    if (_userProfile?['province'] != null &&
        _userProfile!['province'].toString().isNotEmpty) {
      addressParts.add(_userProfile!['province'].toString());
    }

    final fullAddress = addressParts.join(', ');
    final mapsPin = _userProfile?['mapsPin']?.toString() ?? '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.location_on,
          color: AppTheme.royalBlue,
          size: isDesktop ? 28 : 24,
        ),
        SizedBox(width: isDesktop ? 20 : 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Location',
                style: TextStyle(
                  fontSize: isDesktop ? 14 : 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fullAddress.isNotEmpty ? fullAddress : 'Not set',
                style: TextStyle(
                  fontSize: isDesktop ? 18 : 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              // Show "View Maps" button if coordinates or address is available
              if ((_userProfile?['latitude'] != null &&
                      _userProfile?['longitude'] != null) ||
                  fullAddress.isNotEmpty ||
                  mapsPin.isNotEmpty) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    // Open Flutter map viewer with location
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OroquietaMapViewer(
                          latitude: _userProfile?['latitude'] as double?,
                          longitude: _userProfile?['longitude'] as double?,
                          locationName: fullAddress.isNotEmpty
                              ? fullAddress
                              : 'Oroquieta City, Philippines',
                          address: fullAddress.isNotEmpty
                              ? fullAddress
                              : 'Oroquieta City, Philippines',
                        ),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.map,
                        size: isDesktop ? 18 : 16,
                        color: AppTheme.royalBlue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'View Maps',
                        style: TextStyle(
                          fontSize: isDesktop ? 14 : 12,
                          color: AppTheme.royalBlue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Availability toggle shown under the avatar/name in settings
  Widget _buildAvailabilityHeaderToggle({required bool isDesktop}) {
    final isAvailable = _userProfile?['isAvailable'] == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isAvailable
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFFFF9800),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isAvailable ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: isDesktop ? 14 : 12,
              fontWeight: FontWeight.w600,
              color: isAvailable
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFFFF9800),
            ),
          ),
          const SizedBox(width: 8),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: isAvailable,
              onChanged: (value) => _updateAvailabilityFromSettings(value),
              activeColor: const Color(0xFF4CAF50),
              activeTrackColor: const Color(0xFF4CAF50).withOpacity(0.4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateAvailabilityFromSettings(bool isAvailable) async {
    try {
      await _profileService.updateProfile({
        'isAvailable': isAvailable,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          _userProfile = {...?_userProfile, 'isAvailable': isAvailable};
        });

        Get.snackbar(
          'Status updated',
          isAvailable ? 'You are now online.' : 'You are now offline.',
          backgroundColor: isAvailable ? Colors.green : Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to update availability: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    bool isDesktop = false,
    bool isMultiLine = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.royalBlue, size: isDesktop ? 28 : 24),
        SizedBox(width: isDesktop ? 20 : 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isDesktop ? 14 : 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: isDesktop ? 18 : 16,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: isMultiLine ? null : 3,
                overflow: isMultiLine
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Compact info row for single container layout
  Widget _buildCompactInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDesktop,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.royalBlue, size: isDesktop ? 22 : 20),
        SizedBox(width: isDesktop ? 16 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isDesktop ? 12 : 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: isDesktop ? 16 : 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleEditBasicInfo() async {
    await _showEditBasicInfoDialog();
  }

  Future<void> _showEditBasicInfoDialog() async {
    final nameController = TextEditingController(
      text: _userProfile?['name']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: _userProfile?['phone']?.toString() ?? '',
    );
    final specializationController = TextEditingController(
      text: _userProfile?['specialization'] is List
          ? (_userProfile!['specialization'] as List).join(', ')
          : _userProfile?['specialization']?.toString() ?? '',
    );
    bool isAvailable = _userProfile?['isAvailable'] == true;

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 800;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Edit Profile Information',
                style: TextStyle(
                  fontSize: isDesktop ? 22 : 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          content: SizedBox(
            width: isDesktop ? 600 : double.infinity,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                    controller: specializationController,
                    decoration: const InputDecoration(
                      labelText: 'Specializations',
                      hintText: 'e.g. Family Law, Criminal Defense',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.work),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: isAvailable
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFF9800),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isAvailable
                                ? 'Available for appointments'
                                : 'Unavailable',
                            style: TextStyle(fontSize: isDesktop ? 14 : 12),
                          ),
                        ),
                        Switch(
                          value: isAvailable,
                          onChanged: (value) {
                            setDialogState(() {
                              isAvailable = value;
                            });
                          },
                          activeColor: const Color(0xFF4CAF50),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: isDesktop ? 14 : 12,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                await _saveBasicInfo(
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                  specialization: specializationController.text.trim(),
                  isAvailable: isAvailable,
                );
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.royalBlue,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Save',
                style: TextStyle(
                  fontSize: isDesktop ? 14 : 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveBasicInfo({
    required String name,
    required String phone,
    required String specialization,
    required bool isAvailable,
  }) async {
    try {
      final updateData = <String, dynamic>{};

      if (name.isNotEmpty) {
        updateData['name'] = name;
        updateData['fullName'] = name;
      }
      if (phone.isNotEmpty) {
        updateData['phone'] = phone;
        updateData['phoneNumber'] = phone;
      }
      if (specialization.isNotEmpty) {
        final specs = specialization
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        updateData['specialization'] = specs;
      }
      updateData['isAvailable'] = isAvailable;
      updateData['updatedAt'] = FieldValue.serverTimestamp();

      if (updateData.isNotEmpty) {
        await _profileService.updateProfile(updateData);
        await _loadProfile();

        if (mounted) {
          Get.snackbar(
            'Success',
            'Profile information updated',
            backgroundColor: Colors.green,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to update profile information: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _handleEditProfile() async {
    await _showEditProfileDialog();
  }

  Future<void> _showEditProfileDialog() async {
    final officeAddressController = TextEditingController(
      text: _userProfile?['officeAddress']?.toString() ?? '',
    );
    final cityController = TextEditingController(
      text: _userProfile?['city']?.toString() ?? '',
    );
    final provinceController = TextEditingController(
      text: _userProfile?['province']?.toString() ?? '',
    );
    final mapsPinController = TextEditingController(
      text: _userProfile?['mapsPin']?.toString() ?? '',
    );
    final bioController = TextEditingController(
      text: _userProfile?['bio']?.toString() ?? '',
    );
    final languagesController = TextEditingController(
      text: _userProfile?['languages'] is List
          ? (_userProfile!['languages'] as List).join(', ')
          : _userProfile?['languages']?.toString() ?? '',
    );
    final consultationFeeController = TextEditingController(
      text: _userProfile?['consultationFee']?.toString() ?? '',
    );

    String selectedRateType = _userProfile?['rateType']?.toString() ?? '';

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 800;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Edit Additional Details',
                style: TextStyle(
                  fontSize: isDesktop ? 22 : 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          content: SizedBox(
            width: isDesktop ? 600 : double.infinity,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 0),
                  // Office Address
                  TextField(
                    controller: officeAddressController,
                    decoration: InputDecoration(
                      labelText: 'Office Address',
                      hintText: 'Enter office address',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.location_on),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  // City
                  TextField(
                    controller: cityController,
                    decoration: const InputDecoration(
                      labelText: 'City',
                      hintText: 'Enter city',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_city),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Province
                  TextField(
                    controller: provinceController,
                    decoration: const InputDecoration(
                      labelText: 'Province',
                      hintText: 'Enter province',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.map),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Map Picker Button
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push<MapPickerResult>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OroquietaMapPicker(
                            initialLatitude:
                                _userProfile?['latitude'] as double?,
                            initialLongitude:
                                _userProfile?['longitude'] as double?,
                          ),
                        ),
                      );

                      if (result != null) {
                        setDialogState(() {
                          // Store coordinates temporarily for saving
                          _tempLatitude = result.latitude;
                          _tempLongitude = result.longitude;
                          _tempAddress = result.address;

                          // Optionally update the address field if empty
                          if (result.address != null &&
                              result.address!.isNotEmpty &&
                              officeAddressController.text.isEmpty) {
                            officeAddressController.text = result.address!;
                          }
                        });
                      }
                    },
                    icon: const Icon(Icons.map),
                    label: const Text('Select Location on Map'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.royalBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Google Maps Pin (legacy support)
                  TextField(
                    controller: mapsPinController,
                    decoration: const InputDecoration(
                      labelText: 'Google Maps Link (Optional)',
                      hintText: 'https://maps.google.com/...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.pin_drop),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Short Bio
                  TextField(
                    controller: bioController,
                    decoration: const InputDecoration(
                      labelText: 'Short Bio / Introduction',
                      hintText: 'Tell clients about yourself...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),
                  // Languages Spoken
                  TextField(
                    controller: languagesController,
                    decoration: const InputDecoration(
                      labelText: 'Languages Spoken',
                      hintText: 'English, Tagalog, Spanish (comma separated)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.language),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Rate Type
                  DropdownButtonFormField<String>(
                    value: selectedRateType.isEmpty ? null : selectedRateType,
                    decoration: const InputDecoration(
                      labelText: 'Rate Type',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Per hour',
                        child: Text('Per hour'),
                      ),
                      DropdownMenuItem(
                        value: 'Per consultation',
                        child: Text('Per consultation'),
                      ),
                      DropdownMenuItem(value: 'Fixed', child: Text('Fixed')),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selectedRateType = value ?? '';
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  // Consultation Fee
                  TextField(
                    controller: consultationFeeController,
                    decoration: const InputDecoration(
                      labelText: 'Consultation Fee (₱)',
                      hintText: '0.00',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.payments),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: isDesktop ? 14 : 12,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                await _saveAdditionalDetails(
                  officeAddress: officeAddressController.text.trim(),
                  city: cityController.text.trim(),
                  province: provinceController.text.trim(),
                  mapsPin: mapsPinController.text.trim(),
                  bio: bioController.text.trim(),
                  languages: languagesController.text.trim(),
                  rateType: selectedRateType,
                  consultationFee: consultationFeeController.text.trim(),
                  latitude: _tempLatitude,
                  longitude: _tempLongitude,
                  address: _tempAddress,
                );
                // Clear temporary values
                _tempLatitude = null;
                _tempLongitude = null;
                _tempAddress = null;
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.royalBlue,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Save',
                style: TextStyle(
                  fontSize: isDesktop ? 14 : 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAdditionalDetails({
    required String officeAddress,
    required String city,
    required String province,
    required String mapsPin,
    required String bio,
    required String languages,
    required String rateType,
    required String consultationFee,
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    try {
      final updateData = <String, dynamic>{};

      if (officeAddress.isNotEmpty) {
        updateData['officeAddress'] = officeAddress;
      }
      if (city.isNotEmpty) {
        updateData['city'] = city;
      }
      if (province.isNotEmpty) {
        updateData['province'] = province;
      }
      if (mapsPin.isNotEmpty) {
        updateData['mapsPin'] = mapsPin;
      }
      if (bio.isNotEmpty) {
        updateData['bio'] = bio;
      }
      if (languages.isNotEmpty) {
        // Convert comma-separated string to list
        final languagesList = languages
            .split(',')
            .map((lang) => lang.trim())
            .where((lang) => lang.isNotEmpty)
            .toList();
        updateData['languages'] = languagesList;
      }
      if (rateType.isNotEmpty) {
        updateData['rateType'] = rateType;
      }
      if (consultationFee.isNotEmpty) {
        // Try to parse as number
        final fee = double.tryParse(consultationFee);
        if (fee != null) {
          updateData['consultationFee'] = fee;
        } else {
          updateData['consultationFee'] = consultationFee;
        }
      }

      // Add coordinates from map picker if available
      if (latitude != null && longitude != null) {
        updateData['latitude'] = latitude;
        updateData['longitude'] = longitude;
        if (address != null && address.isNotEmpty) {
          updateData['mapsAddress'] = address;
        }
      }

      if (updateData.isNotEmpty) {
        updateData['updatedAt'] = FieldValue.serverTimestamp();
        await _profileService.updateProfile(updateData);
        await _loadProfile();

        if (mounted) {
          Get.snackbar(
            'Success',
            'Profile updated successfully',
            backgroundColor: Colors.green,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
          );
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
