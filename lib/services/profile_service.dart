import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker();

  Future<XFile?> pickImage({ImageSource? source}) async {
    try {
      final ImageSource imageSource = source ?? ImageSource.gallery;
      final XFile? image = await _picker.pickImage(
        source: imageSource,
        maxWidth: 800, // Reduced from 1920 to save storage space
        maxHeight: 800, // Reduced from 1920 to save storage space
        imageQuality: 75, // Reduced from 90 to save storage space
      );
      return image;
    } catch (e) {
      throw Exception('Failed to pick image: $e');
    }
  }

  Future<String> uploadProfilePicture(XFile imageFile) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('No user logged in');

      // Save to local storage using base64
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_image_${user.uid}', base64Image);

      // Update Firestore to indicate local storage
      await _firestore.collection('users').doc(user.uid).update({
        'photoUrl': 'local_storage',
        'hasLocalPhoto': true,
        'profilePictureUpdatedAt': FieldValue.serverTimestamp(),
      });

      return 'local_storage';
    } catch (e) {
      throw Exception('Failed to save profile picture: $e');
    }
  }

  Future<String?> getLocalProfilePicture(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('profile_image_$userId');
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return null;

      final data = doc.data();

      // If photoUrl is from Firebase Storage, use it directly
      // Otherwise, check for local storage (backward compatibility)
      if (data?['photoUrl'] == 'local_storage' ||
          (data?['hasLocalPhoto'] == true &&
              (data?['photoUrl'] == null || data?['photoUrl'] == ''))) {
        final localImage = await getLocalProfilePicture(user.uid);
        if (localImage != null) {
          data!['localPhotoBase64'] = localImage;
        }
      }

      return data;
    } catch (e) {
      throw Exception('Failed to get user profile: $e');
    }
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('No user logged in');

      await _firestore.collection('users').doc(user.uid).update(data);
    } catch (e) {
      throw Exception('Failed to update profile: $e');
    }
  }

  Future<void> deleteOldProfilePicture(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('profile_image_$userId');
    } catch (e) {
      // Ignore errors
    }
  }
}
