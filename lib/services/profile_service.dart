import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firestore_mirror_helper.dart';
import 'supabase_storage_service.dart';

class ProfileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker();
  final SupabaseStorageService _supabaseStorage = SupabaseStorageService();

  Future<XFile?> pickImage({ImageSource? source}) async {
    try {
      final ImageSource imageSource = source ?? ImageSource.gallery;
      final XFile? image = await _picker.pickImage(
        source: imageSource,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 75,
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

      final bytes = await imageFile.readAsBytes();
      final publicUrl = await _supabaseStorage.uploadProfilePhoto(
        userId: user.uid,
        imageFile: imageFile,
      );

      // Keep a local cache so the avatar still shows if the network is slow.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_image_${user.uid}', base64Encode(bytes));

      final existing = await _firestore.collection('users').doc(user.uid).get();
      final existingData = existing.data() ?? <String, dynamic>{};

      // Persist the public URL. Firestore is what the app reads; Supabase
      // users.photo_url is best-effort and must not fail the upload.
      await _firestore.collection('users').doc(user.uid).set(
        {
          'photoUrl': publicUrl,
          'hasLocalPhoto': false,
          'profilePictureUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      final result = await HybridDatastore.set(
        collection: 'users',
        id: user.uid,
        data: {
          'photoUrl': publicUrl,
          'hasLocalPhoto': false,
          'email': existingData['email'] ?? user.email ?? '',
          'name': existingData['name'] ??
              existingData['fullName'] ??
              user.displayName ??
              '',
          'role': existingData['role'] ?? 'client',
        },
        options: SetOptions(merge: true),
      );
      if (!result.firestoreOk && !result.supabaseOk) {
        throw Exception(result.failureMessage);
      }

      return publicUrl;
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

      final result = await HybridDatastore.update(
        collection: 'users',
        id: user.uid,
        patch: data,
      );
      if (!result.isSuccess) throw Exception(result.failureMessage);
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
