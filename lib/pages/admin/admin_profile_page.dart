import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../../services/profile_service.dart';
import '../../widgets/common/profile_picture_widget.dart';
import '../../widgets/maps/oroquieta_map_picker.dart';
import '../../theme/app_theme.dart';

class AdminProfilePage extends StatefulWidget {
  const AdminProfilePage({super.key});

  @override
  State<AdminProfilePage> createState() => _AdminProfilePageState();
}

class _AdminProfilePageState extends State<AdminProfilePage> {
  final ProfileService _profileService = ProfileService();
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Admin Profile',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppTheme.royalBlue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Profile Picture
            ProfilePictureWidget(
              photoUrl: null,
              userName: _isLoading
                  ? 'Admin'
                  : (_userProfile?['name'] ??
                        user?.email?.split('@')[0] ??
                        'Admin'),
              size: 120,
              isEditable: true,
              onUpdated: _loadProfile,
            ),
            const SizedBox(height: 24),
            // Admin Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.admin_panel_settings,
                    color: Colors.red[700],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Administrator',
                    style: TextStyle(
                      color: Colors.red[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // User Info
            Text(
              _userProfile?['name'] ?? 'Admin',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              user?.email ?? '',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            // Additional Details Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Additional Details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _handleEditProfile,
                          icon: const Icon(Icons.edit, size: 16),
                          label: Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Location
                    if ((_userProfile?['officeAddress'] != null &&
                            _userProfile!['officeAddress']
                                .toString()
                                .isNotEmpty) ||
                        (_userProfile?['city'] != null &&
                            _userProfile!['city'].toString().isNotEmpty) ||
                        (_userProfile?['province'] != null &&
                            _userProfile!['province'].toString().isNotEmpty) ||
                        (_userProfile?['latitude'] != null &&
                            _userProfile?['longitude'] != null))
                      _buildLocationRow(),
                    if ((_userProfile?['officeAddress'] != null &&
                            _userProfile!['officeAddress']
                                .toString()
                                .isNotEmpty) ||
                        (_userProfile?['city'] != null &&
                            _userProfile!['city'].toString().isNotEmpty) ||
                        (_userProfile?['province'] != null &&
                            _userProfile!['province'].toString().isNotEmpty) ||
                        (_userProfile?['latitude'] != null &&
                            _userProfile?['longitude'] != null))
                      const SizedBox(height: 16),
                    if ((_userProfile?['officeAddress'] != null &&
                            _userProfile!['officeAddress']
                                .toString()
                                .isNotEmpty) ||
                        (_userProfile?['city'] != null &&
                            _userProfile!['city'].toString().isNotEmpty) ||
                        (_userProfile?['province'] != null &&
                            _userProfile!['province'].toString().isNotEmpty) ||
                        (_userProfile?['latitude'] != null &&
                            _userProfile?['longitude'] != null))
                      const Divider(height: 1),
                    if ((_userProfile?['officeAddress'] != null &&
                            _userProfile!['officeAddress']
                                .toString()
                                .isNotEmpty) ||
                        (_userProfile?['city'] != null &&
                            _userProfile!['city'].toString().isNotEmpty) ||
                        (_userProfile?['province'] != null &&
                            _userProfile!['province'].toString().isNotEmpty) ||
                        (_userProfile?['latitude'] != null &&
                            _userProfile?['longitude'] != null))
                      const SizedBox(height: 16),
                    // Bio
                    if (_userProfile?['bio'] != null &&
                        _userProfile!['bio'].toString().isNotEmpty)
                      _buildInfoRow(
                        Icons.description,
                        'Bio / Introduction',
                        _userProfile!['bio'],
                        isMultiLine: true,
                      ),
                    // Show message if no additional details
                    if ((_userProfile?['officeAddress'] == null ||
                            _userProfile!['officeAddress']
                                .toString()
                                .isEmpty) &&
                        (_userProfile?['city'] == null ||
                            _userProfile!['city'].toString().isEmpty) &&
                        (_userProfile?['province'] == null ||
                            _userProfile!['province'].toString().isEmpty) &&
                        (_userProfile?['latitude'] == null) &&
                        (_userProfile?['longitude'] == null) &&
                        (_userProfile?['bio'] == null ||
                            _userProfile!['bio'].toString().isEmpty))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.grey[400],
                                size: 48,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No additional details added yet',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Click Edit to add more information',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Profile Details Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profile Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      Icons.person,
                      'Name',
                      _userProfile?['name'] ?? 'Not set',
                    ),
                    const Divider(height: 24),
                    _buildInfoRow(
                      Icons.email,
                      'Email',
                      _userProfile?['email'] ?? 'Not set',
                    ),
                    const Divider(height: 24),
                    _buildInfoRow(Icons.shield, 'Role', 'Administrator'),
                    const Divider(height: 24),
                    _buildInfoRow(
                      Icons.calendar_today,
                      'Member Since',
                      _userProfile?['createdAt'] != null
                          ? _formatDate(_userProfile!['createdAt'])
                          : 'Unknown',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow() {
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
    final hasCoordinates =
        _userProfile?['latitude'] != null && _userProfile?['longitude'] != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.location_on, color: AppTheme.royalBlue, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Location',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fullAddress.isNotEmpty ? fullAddress : 'Not set',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              // Always show View Maps button if there's any location data
              if (fullAddress.isNotEmpty || hasCoordinates) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    try {
                      // Get initial coordinates if available
                      double? initialLat;
                      double? initialLng;

                      if (hasCoordinates) {
                        initialLat = _userProfile?['latitude'] as double?;
                        initialLng = _userProfile?['longitude'] as double?;
                      }

                      final result = await Navigator.push<MapPickerResult>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OroquietaMapPicker(
                            initialLatitude: initialLat,
                            initialLongitude: initialLng,
                          ),
                        ),
                      );

                      if (result != null && mounted) {
                        // Update profile with new coordinates
                        await _updateLocationCoordinates(
                          result.latitude,
                          result.longitude,
                          result.address,
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        String errorMessage = 'Failed to open map';
                        if (e.toString().contains('API key') ||
                            e.toString().contains('API_KEY')) {
                          errorMessage =
                              'Google Maps API key not configured. Please check GOOGLE_MAPS_SETUP.md for setup instructions.';
                        } else {
                          errorMessage = 'Failed to open map: ${e.toString()}';
                        }

                        Get.snackbar(
                          'Error',
                          errorMessage,
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                          duration: const Duration(seconds: 4),
                        );
                      }
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map, size: 16, color: AppTheme.royalBlue),
                      const SizedBox(width: 4),
                      Text(
                        'View Maps',
                        style: TextStyle(
                          fontSize: 12,
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

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    bool isMultiLine = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.royalBlue, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
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

  Future<void> _handleEditProfile() async {
    await _showEditProfileDialog();
  }

  Future<void> _updateLocationCoordinates(
    double lat,
    double lng,
    String? address,
  ) async {
    try {
      final updateData = <String, dynamic>{
        'latitude': lat,
        'longitude': lng,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (address != null && address.isNotEmpty) {
        updateData['mapsAddress'] = address;
      }

      await _profileService.updateProfile(updateData);
      await _loadProfile();

      if (mounted) {
        Get.snackbar(
          'Success',
          'Location updated successfully',
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Failed to update location: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
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
    final bioController = TextEditingController(
      text: _userProfile?['bio']?.toString() ?? '',
    );

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
                        // The coordinates will be saved when the dialog is saved
                        setDialogState(() {
                          // Store coordinates temporarily
                          _tempLatitude = result.latitude;
                          _tempLongitude = result.longitude;
                          _tempAddress = result.address;
                        });

                        // Optionally update the address field
                        if (result.address != null &&
                            result.address!.isNotEmpty &&
                            officeAddressController.text.isEmpty) {
                          officeAddressController.text = result.address!;
                        }
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
                  bio: bioController.text.trim(),
                  latitude: _tempLatitude,
                  longitude: _tempLongitude,
                  address: _tempAddress,
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

    // Clear temporary values after dialog closes
    _tempLatitude = null;
    _tempLongitude = null;
    _tempAddress = null;
  }

  double? _tempLatitude;
  double? _tempLongitude;
  String? _tempAddress;

  Future<void> _saveAdditionalDetails({
    required String officeAddress,
    required String city,
    required String province,
    required String bio,
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
      if (bio.isNotEmpty) {
        updateData['bio'] = bio;
      }
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

  String _formatDate(dynamic timestamp) {
    try {
      if (timestamp == null) return 'Unknown';
      final date = timestamp is DateTime ? timestamp : timestamp.toDate();
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Unknown';
    }
  }
}
