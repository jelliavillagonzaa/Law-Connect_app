import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'firestore_mirror_helper.dart';

/// Service to help set up admin and attorney users in Firebase
/// This ensures users exist in both Firebase Auth and Firestore with correct roles
class UserSetupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create or update admin user in Firestore
  /// Call this after creating the user in Firebase Auth Console
  Future<void> setupAdminUser(String email, String uid) async {
    try {
      final data = <String, dynamic>{
        'email': email,
        'name': 'Admin User',
        'fullName': 'Admin User',
        'role': 'admin',
        'isVerified': true, // Admin doesn't need email verification
        'createdAt': FieldValue.serverTimestamp(),
      };
      final result = await HybridDatastore.set(
        collection: 'users',
        id: uid,
        data: data,
        options: SetOptions(merge: true),
      );
      if (!result.isSuccess) throw Exception(result.failureMessage);

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
      final data = <String, dynamic>{
        'email': email,
        'name': name ?? 'Attorney User',
        'fullName': name ?? 'Attorney User',
        'role': 'attorney',
        'isVerified': true, // Attorney doesn't need email verification
        'isAvailable': true,
        'specialization': specialization ?? [],
        'ratingAverage': 0.0,
        'createdAt': FieldValue.serverTimestamp(),
      };
      final result = await HybridDatastore.set(
        collection: 'users',
        id: uid,
        data: data,
        options: SetOptions(merge: true),
      );
      if (!result.isSuccess) throw Exception(result.failureMessage);

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
      
      // If user document doesn't exist, create it based on email or pending signup
      if (!userDoc.exists) {
        String role = 'client';
        bool isVerified = false;

        String clientName = email.split('@')[0];
        String? firstName;
        String? middleName;
        String? lastName;
        String? phone;
        String? address;

        try {
          final psDoc = await _firestore.collection('pending_signups').doc(email).get();
          if (psDoc.exists && psDoc.data() != null) {
            final ps = psDoc.data()!;
            firstName = ps['firstName']?.toString().trim();
            middleName = ps['middleName']?.toString().trim();
            lastName = ps['lastName']?.toString().trim();
            phone = ps['phoneNumber']?.toString().trim();
            address = ps['address']?.toString().trim();
            final composed = [firstName ?? '', middleName ?? '', lastName ?? ''].where((s) => s.isNotEmpty).join(' ').trim();
            if (composed.isNotEmpty) clientName = composed;
          }
        } catch (_) {}

        Map<String, dynamic> userData = {
          'email': email,
          'name': clientName,
          'fullName': clientName,
          if (firstName != null && firstName.isNotEmpty) 'firstName': firstName,
          if (middleName != null && middleName.isNotEmpty) 'middleName': middleName,
          if (lastName != null && lastName.isNotEmpty) 'lastName': lastName,
          if (phone != null && phone.isNotEmpty) 'phoneNumber': phone,
          if (address != null && address.isNotEmpty) 'address': address,
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

        final result = await HybridDatastore.set(
          collection: 'users',
          id: uid,
          data: userData,
        );
        if (!result.isSuccess) throw Exception(result.failureMessage);
        
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

