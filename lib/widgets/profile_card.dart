import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../services/profile_service.dart';
import 'verified_badge.dart';
import '../utils/safe_network_image.dart';
import 'common/safe_network_avatar.dart';

/// Profile card widget for displaying user information
class ProfileCard extends StatefulWidget {
  final String name;
  final String? email;
  final String? role;
  final String? photoUrl;
  final bool isVerified;
  final VoidCallback? onTap;
  final bool isEditable;
  final Future<void> Function()? onPhotoUpdated;

  const ProfileCard({
    super.key,
    required this.name,
    this.email,
    this.role,
    this.photoUrl,
    this.isVerified = false,
    this.onTap,
    this.isEditable = false,
    this.onPhotoUpdated,
  });

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  String? _currentPhotoUrl;
  bool _isUploading = false;
  bool _imageError = false;
  String? _localImageBase64;
  Uint8List? _previewImageBytes;
  final ProfileService _profileService = ProfileService();

  @override
  void initState() {
    super.initState();
    _currentPhotoUrl = widget.photoUrl;
    _imageError = false;
    _loadLocalImage();
  }

  @override
  void didUpdateWidget(ProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.photoUrl != oldWidget.photoUrl) {
      // Only update if we're not currently uploading
      if (!_isUploading) {
        final newPhotoUrl = widget.photoUrl;
        final oldPhotoUrl = oldWidget.photoUrl;

        _currentPhotoUrl = newPhotoUrl;
        _imageError = false; // Reset error state when URL changes

        // If changing to 'local_storage', load the local image
        if (newPhotoUrl == 'local_storage') {
          // Only reload if we don't already have the local image loaded
          if (_localImageBase64 == null || _localImageBase64!.isEmpty) {
            _loadLocalImage();
          }
        }
        // If changing FROM 'local_storage' to a network URL, clear local image
        else if (oldPhotoUrl == 'local_storage' &&
            newPhotoUrl != null &&
            newPhotoUrl.isNotEmpty &&
            newPhotoUrl != 'local_storage') {
          setState(() {
            _localImageBase64 = null;
          });
        }
        // If we have a network URL, keep local image only if we don't have network
        else if (newPhotoUrl != null &&
            newPhotoUrl.isNotEmpty &&
            newPhotoUrl != 'local_storage') {
          // Don't clear local image - keep it as fallback
        }
      }
    }
  }

  Future<void> _loadLocalImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _localImageBase64 = null;
        });
      }
      return;
    }

    // Only load from local storage if photoUrl is 'local_storage'
    final shouldLoadLocal =
        _currentPhotoUrl == 'local_storage' ||
        widget.photoUrl == 'local_storage';

    if (!shouldLoadLocal) {
      return;
    }

    try {
      final localImage = await _profileService.getLocalProfilePicture(user.uid);

      if (mounted) {
        setState(() {
          // Only update if we got a valid image
          if (localImage != null && localImage.isNotEmpty) {
            _localImageBase64 = localImage;
          } else if (_localImageBase64 == null) {
            // Only clear if we don't already have an image
            _localImageBase64 = null;
          }
          // Otherwise keep existing _localImageBase64
        });
      }
    } catch (e) {
      print('Error loading local profile image: $e');
      // Don't clear existing image on error - keep what we have
      if (mounted && _localImageBase64 == null) {
        setState(() {
          _localImageBase64 = null;
        });
      }
    }
  }

  Future<void> _changeProfilePicture() async {
    if (!widget.isEditable || _isUploading) return;

    bool uploadStarted = false;

    try {
      // Show bottom sheet to choose image source
      final ImageSource? source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
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

      if (!mounted) return;

      final profileService = ProfileService();
      final imageFile = await profileService.pickImage(source: source);
      if (imageFile == null || !mounted) return;

      // Set uploading state
      if (mounted) {
        setState(() {
          _isUploading = true;
          uploadStarted = true;
          _imageError = false;
        });
      }

      // Read image bytes for preview
      final imageBytes = await imageFile.readAsBytes();

      // Show preview immediately
      if (mounted) {
        setState(() {
          _previewImageBytes = imageBytes;
        });
      }

      // Upload with timeout protection
      final downloadUrl = await profileService
          .uploadProfilePicture(imageFile)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception(
                'Upload timeout. Please check your internet connection and try again.',
              );
            },
          );

      // Convert to base64 for local storage display
      final base64Image = base64Encode(imageBytes);

      // Update state with new photo URL and local image
      if (mounted) {
        setState(() {
          _currentPhotoUrl = downloadUrl;
          _localImageBase64 = base64Image;
          _previewImageBytes = null; // Clear preview after setting local image
          _isUploading = false;
          uploadStarted = false;
          _imageError = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Notify parent widget to refresh - do this after state update
        if (widget.onPhotoUpdated != null) {
          try {
            await widget.onPhotoUpdated!();
            // After parent refreshes, sync with widget's photoUrl if it changed
            // But DON'T clear our local image - we already have it loaded
            if (mounted) {
              final newPhotoUrl = widget.photoUrl ?? downloadUrl;
              setState(() {
                _currentPhotoUrl = newPhotoUrl;
                // If it's still 'local_storage', keep our loaded image
                // Don't reload if we already have it
                if (newPhotoUrl == 'local_storage' &&
                    (_localImageBase64 == null || _localImageBase64!.isEmpty)) {
                  _loadLocalImage();
                }
              });
            }
          } catch (e) {
            print('Error in onPhotoUpdated callback: $e');
            // Don't throw - the upload was successful even if refresh fails
            // Keep the local image we already loaded
          }
        }
      }
    } catch (e) {
      // Show error message with better error handling
      if (mounted) {
        String errorMessage = 'Failed to update profile picture';
        final errorString = e.toString().toLowerCase();

        // Check for specific error types (in order of specificity)
        if (errorString.contains('bucket') ||
            errorString.contains('not found') ||
            errorString.contains('does not exist')) {
          errorMessage =
              'Supabase Storage bucket not found. Please create the "files" bucket. See SUPABASE_DASHBOARD_SETUP.md';
        } else if (errorString.contains('permission') ||
            errorString.contains('unauthorized') ||
            errorString.contains('403') ||
            errorString.contains('policy')) {
          errorMessage =
              'Permission denied. Please configure Supabase Storage policies. See SUPABASE_DASHBOARD_SETUP.md';
        } else if (errorString.contains('storage') ||
            errorString.contains('supabase')) {
          errorMessage =
              'Supabase Storage error. Please check SUPABASE_DASHBOARD_SETUP.md for setup instructions.';
        } else if (errorString.contains('timeout') ||
            errorString.contains('Timeout')) {
          errorMessage =
              'Upload timeout. Please check your internet connection and try again.';
        } else if (errorString.contains('network') ||
            errorString.contains('connection')) {
          errorMessage =
              'Network error. Please check your internet connection and try again.';
        } else if (errorString.contains('readasbytessync') ||
            errorString.contains('nosuchmethod')) {
          errorMessage =
              'File format error. Please try selecting the image again.';
        } else if (errorString.contains('failed to upload')) {
          // Extract the actual error from the exception message
          final fullError = e.toString();
          // Try to get the actual error message after "Failed to upload profile photo: "
          if (fullError.contains('Failed to upload profile photo: ')) {
            final actualError = fullError
                .split('Failed to upload profile photo: ')
                .last;
            errorMessage = actualError.length > 100
                ? 'Upload failed: ${actualError.substring(0, 100)}...'
                : 'Upload failed: $actualError';
          } else {
            errorMessage = fullError.length > 100
                ? 'Upload failed: ${fullError.substring(0, 100)}...'
                : 'Upload failed: $fullError';
          }
        } else {
          // Show the actual error for debugging
          final fullError = e.toString();
          errorMessage = fullError.length > 150
              ? 'Error: ${fullError.substring(0, 150)}...'
              : 'Error: $fullError';
        }

        // Log the full error for debugging
        print('❌ Profile picture upload error: $e');
        if (e is Exception) {
          print('❌ Exception details: ${e.toString()}');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } finally {
      // Always ensure loading state is reset, even if an exception occurs
      if (uploadStarted && mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              InkWell(
                onTap: widget.isEditable ? _changeProfilePicture : null,
                borderRadius: BorderRadius.circular(35),
                child: Stack(
                  children: [
                    Builder(
                      builder: (context) {
                        // Check for preview image first
                        if (_previewImageBytes != null) {
                          return CircleAvatar(
                            radius: 35,
                            backgroundColor: AppTheme.navy.withOpacity(0.1),
                            backgroundImage: MemoryImage(_previewImageBytes!),
                            child: _isUploading
                                ? const CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      AppTheme.royalBlue,
                                    ),
                                  )
                                : null,
                          );
                        }

                        // Check for local storage image
                        final hasLocalImage =
                            _localImageBase64 != null &&
                            _localImageBase64!.isNotEmpty &&
                            (_currentPhotoUrl == 'local_storage' ||
                                widget.photoUrl == 'local_storage');

                        if (hasLocalImage) {
                          try {
                            return CircleAvatar(
                              radius: 35,
                              backgroundColor: AppTheme.navy.withOpacity(0.1),
                              backgroundImage: MemoryImage(
                                base64Decode(_localImageBase64!),
                              ),
                              child: _isUploading
                                  ? const CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        AppTheme.royalBlue,
                                      ),
                                    )
                                  : null,
                            );
                          } catch (e) {
                            print('Error decoding local image: $e');
                          }
                        }

                        final networkUrl = !_isUploading && !_imageError
                            ? _currentPhotoUrl
                            : null;
                        if (isValidNetworkImageUrl(networkUrl)) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              SafeNetworkAvatar(
                                photoUrl: networkUrl,
                                radius: 35,
                                fallbackLetter: widget.name,
                                backgroundColor:
                                    AppTheme.navy.withOpacity(0.1),
                                foregroundColor: AppTheme.navy,
                              ),
                              if (_isUploading)
                                const CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppTheme.royalBlue,
                                  ),
                                ),
                            ],
                          );
                        }

                        return CircleAvatar(
                          radius: 35,
                          backgroundColor: AppTheme.navy.withOpacity(0.1),
                          child: _isUploading
                              ? const CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    AppTheme.royalBlue,
                                  ),
                                )
                              : Text(
                                  widget.name.isNotEmpty
                                      ? widget.name[0].toUpperCase()
                                      : 'U',
                                  style: AppTheme.heading3.copyWith(
                                    color: AppTheme.navy,
                                  ),
                                ),
                        );
                      },
                    ),
                    if (widget.isEditable && !_isUploading)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.royalBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.name,
                            style: AppTheme.heading4,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.isVerified) ...[
                          const SizedBox(width: 8),
                          const VerifiedBadge(),
                        ],
                      ],
                    ),
                    if (widget.email != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.email!,
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (widget.role != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.gold.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.role!.toUpperCase(),
                          style: AppTheme.caption.copyWith(
                            color: AppTheme.gold,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
