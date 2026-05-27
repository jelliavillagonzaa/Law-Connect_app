import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Service to help set up admin and attorney users in Firebase
/// This ensures users exist in both Firebase Auth and Firestore with correct roles
class UserSetupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create or update admin user in Firestore
  /// Call this after creating the user in Firebase Auth Console
  Future<void> setupAdminUser(String email, String uid) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'email': email,
        'name': 'Admin User',
        'fullName': 'Admin User',
        'role': 'admin',
        'isVerified': true, // Admin doesn't need email verification
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (kDebugMode) {
        debugPrint('✅ Admin user setup complete: $email');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to setup admin user: $e');
      }
      rethrow;
    }
  }

  /// Create or update attorney user in Firestore
  /// Call this after creating the user in Firebase Auth Console
  Future<void> setupAttorneyUser(String email, String uid, {
    String? name,
    List<String>? specialization,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'email': email,
        'name': name ?? 'Attorney User',
        'fullName': name ?? 'Attorney User',
        'role': 'attorney',
        'isVerified': true, // Attorney doesn't need email verification
        'isAvailable': true,
        'specialization': specialization ?? [],
        'ratingAverage': 0.0,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (kDebugMode) {
        debugPrint('✅ Attorney user setup complete: $email');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to setup attorney user: $e');
      }
      rethrow;
    }
  }

  /// Auto-setup user based on email pattern (for testing)
  /// This will automatically create Firestore document if user logs in
  Future<void> autoSetupUserOnLogin(String email, String uid) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      
      // If user document doesn't exist, create it based on email
      if (!userDoc.exists) {
        String role = 'client';
        bool isVerified = false;
        Map<String, dynamic> userData = {
          'email': email,
          'name': email.split('@')[0],
          'fullName': email.split('@')[0],
          'createdAt': FieldValue.serverTimestamp(),
        };

        // Auto-detect role from email
        if (email.toLowerCase().contains('admin')) {
          role = 'admin';
          isVerified = true;
          userData['role'] = role;
          userData['isVerified'] = isVerified;
        } else if (email.toLowerCase().contains('attorney') || 
                   email.toLowerCase().contains('lawyer')) {
          role = 'attorney';
          isVerified = true;
          userData['role'] = role;
          userData['isVerified'] = isVerified;
          userData['isAvailable'] = true;
          userData['specialization'] = [];
          userData['ratingAverage'] = 0.0;
        } else {
          role = 'client';
          isVerified = false;
          userData['role'] = role;
          userData['isVerified'] = isVerified;
        }

        await _firestore.collection('users').doc(uid).set(userData);
        
        if (kDebugMode) {
          debugPrint('✅ Auto-setup user: $email as $role');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to auto-setup user: $e');
      }
    }
  }
}

