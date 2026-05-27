import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';

class ProfilePictureWidget extends StatefulWidget {
  final String? photoUrl;
  final String userName;
  final double size;
  final bool isEditable;
  final VoidCallback? onUpdated;

  const ProfilePictureWidget({
    super.key,
    this.photoUrl,
    required this.userName,
    this.size = 100,
    this.isEditable = false,
    this.onUpdated,
  });

  @override
  State<ProfilePictureWidget> createState() => _ProfilePictureWidgetState();
}

class _ProfilePictureWidgetState extends State<ProfilePictureWidget> {
  final ProfileService _profileService = ProfileService();
  bool _isUploading = false;
  String? _localImageBase64;
  String? _tempPhotoUrl; // Temporary URL after upload, before parent reloads
  Uint8List? _previewImageBytes; // Show selected image immediately

  @override
  void initState() {
    super.initState();
    // Reset any stuck loading states
    _isUploading = false;
    // Always try to load local image on init
    _loadLocalImage();
  }

  @override
  void didUpdateWidget(ProfilePictureWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only reload if photoUrl actually changed
    if (oldWidget.photoUrl != widget.photoUrl) {
      // If changing FROM 'local_storage' to a network URL, clear local image
      if (oldWidget.photoUrl == 'local_storage' &&
          widget.photoUrl != null &&
          widget.photoUrl!.isNotEmpty &&
          widget.photoUrl != 'local_storage') {
        setState(() {
          _localImageBase64 = null;
          _tempPhotoUrl = null;
        });
      }
      // If changing TO 'local_storage' or to null/empty, try to load local image
      else if (widget.photoUrl == 'local_storage' ||
          widget.photoUrl == null ||
          widget.photoUrl!.isEmpty) {
        // Always try to load local image if we don't have it or if photoUrl changed to local_storage
        if (_localImageBase64 == null || _localImageBase64!.isEmpty) {
          _loadLocalImage();
        }
      }
      // If photoUrl is a network URL and we don't have local image, don't clear it
      // This preserves the image during rebuilds
    }
  }

  Future<void> _loadLocalImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return; // Don't clear existing image
    }

    // Always try to load local image if:
    // 1. photoUrl is 'local_storage' (explicitly stored locally)
    // 2. photoUrl is null or empty (might have local image)
    // 3. We don't have a local image loaded yet
    final shouldLoad =
        widget.photoUrl == 'local_storage' ||
        widget.photoUrl == null ||
        widget.photoUrl!.isEmpty ||
        _localImageBase64 == null ||
        _localImageBase64!.isEmpty;

    if (!shouldLoad &&
        widget.photoUrl != null &&
        widget.photoUrl!.isNotEmpty &&
        widget.photoUrl != 'local_storage') {
      // If we have a valid network URL, don't load local image
      return;
    }

    try {
      final localImage = await _profileService.getLocalProfilePicture(user.uid);
      if (mounted) {
        setState(() {
          // Only update if we got a valid image - never clear existing image
          if (localImage != null && localImage.isNotEmpty) {
            _localImageBase64 = localImage;
          }
          // Otherwise keep existing _localImageBase64 - never clear it!
        });
      }
    } catch (e) {
      print('Error loading local profile image: $e');
      // Never clear existing image on error - always keep what we have
    }
  }

  Future<void> _changeProfilePicture() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Get.snackbar(
          'Error',
          'No user logged in',
          backgroundColor: AppTheme.deepNavy,
          colorText: AppTheme.cleanWhite,
        );
        return;
      }

      final imageFile = await _profileService.pickImage();
      if (imageFile == null) {
        // User cancelled - make sure to reset state
        if (mounted) {
          setState(() {
            _isUploading = false;
            _previewImageBytes = null;
          });
        }
        return;
      }

      // Read image bytes immediately to show preview
      final imageBytes = await imageFile.readAsBytes();

      // Convert to base64 immediately so we can keep it
      final base64Image = base64Encode(imageBytes);

      if (mounted) {
        // Show the selected image immediately - DON'T clear local image
        setState(() {
          _previewImageBytes = imageBytes;
          // Keep the base64 version ready
          _localImageBase64 = base64Image;
          _isUploading = true;
        });
      }

      // Save to local storage in the background
      try {
        await _profileService
            .uploadProfilePicture(imageFile)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw Exception('Operation timed out');
              },
            );

        if (mounted) {
          // The base64Image is already set from preview, just clear preview
          setState(() {
            // Keep _localImageBase64 - it's already set from preview
            _previewImageBytes = null; // Clear preview
            _isUploading = false;
          });

          // Verify from storage to ensure consistency, but don't overwrite if we already have it
          final storedImage = await _profileService.getLocalProfilePicture(
            user.uid,
          );
          if (mounted) {
            setState(() {
              // Use stored version if available, otherwise keep what we have
              if (storedImage != null && storedImage.isNotEmpty) {
                _localImageBase64 = storedImage;
              }
              // Otherwise keep existing _localImageBase64
            });
          }

          // Call onUpdated callback to refresh parent widget
          if (widget.onUpdated != null) {
            widget.onUpdated!();
          }

          Get.snackbar(
            'Success',
            'Profile picture updated successfully',
            backgroundColor: AppTheme.royalBlue,
            colorText: AppTheme.cleanWhite,
            duration: const Duration(seconds: 2),
          );
        }
      } catch (uploadError) {
        // Always reset loading state on error
        if (mounted) {
          setState(() {
            _isUploading = false;
            // Keep preview so user can see what they selected
          });

          String errorMessage = 'Failed to save profile picture';
          if (uploadError.toString().contains('timeout') ||
              uploadError.toString().contains('Timeout')) {
            errorMessage = 'Operation timed out. Please try again.';
          } else if (uploadError.toString().contains('QuotaExceeded') ||
              uploadError.toString().contains('quota') ||
              uploadError.toString().contains('Storage quota')) {
            errorMessage =
                'Storage quota exceeded. Please clear your browser cache or use a smaller image.';
          } else {
            // Extract the actual error message, not the full exception
            final errorStr = uploadError.toString();
            if (errorStr.contains('Exception:')) {
              errorMessage = errorStr.split('Exception:').last.trim();
            } else {
              errorMessage =
                  'Error: ${errorStr.length > 100 ? errorStr.substring(0, 100) + "..." : errorStr}';
            }
          }

          Get.snackbar(
            'Error',
            errorMessage,
            backgroundColor: AppTheme.deepNavy,
            colorText: AppTheme.cleanWhite,
            duration: const Duration(seconds: 3),
          );
        }
      }
    } catch (e) {
      // Always reset state on any error
      if (mounted) {
        setState(() {
          _isUploading = false;
          _previewImageBytes = null;
        });
        Get.snackbar(
          'Error',
          'Failed to pick image: ${e.toString()}',
          backgroundColor: AppTheme.deepNavy,
          colorText: AppTheme.cleanWhite,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine which image to show: preview > local > tempUrl > photoUrl > default
    Widget? imageWidget;

    // Show preview image immediately if available
    if (_previewImageBytes != null) {
      imageWidget = Image.memory(
        _previewImageBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildDefaultAvatar(),
      );
    } else if (_isUploading) {
      imageWidget = Center(
        child: CircularProgressIndicator(
          strokeWidth: 3,
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.royalBlue),
        ),
      );
    }
    // Priority 1: Show local image if available (from local storage)
    else if (_localImageBase64 != null && _localImageBase64!.isNotEmpty) {
      try {
        imageWidget = Image.memory(
          base64Decode(_localImageBase64!),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) {
            print('Error decoding base64 image, trying to reload...');
            // Try to reload local image if decoding fails
            _loadLocalImage();
            return _buildDefaultAvatar();
          },
        );
      } catch (e) {
        print('Exception displaying local image: $e');
        // Try to reload local image
        _loadLocalImage();
        imageWidget = _buildDefaultAvatar();
      }
    }
    // Priority 2: Show temporary URL immediately after upload
    else if (_tempPhotoUrl != null) {
      imageWidget = Image.network(
        _tempPhotoUrl!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildDefaultAvatar(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.royalBlue),
            ),
          );
        },
      );
    }
    // Priority 3: Show network URL if available and not 'local_storage'
    else if (widget.photoUrl != null &&
        widget.photoUrl!.isNotEmpty &&
        widget.photoUrl != 'local_storage') {
      imageWidget = Image.network(
        widget.photoUrl!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) {
          // If network image fails, try loading local image as fallback
          _loadLocalImage();
          return _buildDefaultAvatar();
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.royalBlue),
            ),
          );
        },
      );
    }
    // Priority 4: If photoUrl is 'local_storage' but we don't have local image yet, try loading it
    else if (widget.photoUrl == 'local_storage') {
      // Try to load local image one more time
      if (_localImageBase64 == null || _localImageBase64!.isEmpty) {
        _loadLocalImage();
      }
      // Show loading or default while loading
      imageWidget = _buildDefaultAvatar();
    }
    // Priority 5: Default avatar with initial letter
    else {
      // Try loading local image as last resort if photoUrl is null/empty
      if ((widget.photoUrl == null || widget.photoUrl!.isEmpty) &&
          (_localImageBase64 == null || _localImageBase64!.isEmpty)) {
        _loadLocalImage();
      }
      imageWidget = _buildDefaultAvatar();
    }

    return Stack(
      children: [
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.cleanWhite,
            border: Border.all(
              color: AppTheme.cleanWhite,
              width: widget.size * 0.04,
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
          child: ClipOval(child: imageWidget),
        ),
        if (widget.isEditable && !_isUploading && _previewImageBytes == null)
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _changeProfilePicture,
              child: Container(
                padding: EdgeInsets.all(widget.size * 0.08),
                decoration: BoxDecoration(
                  color: AppTheme.royalBlue,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.cleanWhite, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.camera_alt,
                  color: AppTheme.cleanWhite,
                  size: widget.size * 0.2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.royalBlue.withOpacity(0.8),
            AppTheme.deepNavy.withOpacity(0.9),
          ],
        ),
      ),
      child: Center(
        child: Text(
          widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: widget.size * 0.4,
            fontWeight: FontWeight.bold,
            color: AppTheme.cleanWhite,
          ),
        ),
      ),
    );
  }
}
