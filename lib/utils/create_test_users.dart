import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../services/user_setup_service.dart';

/// Helper script to create test admin and attorney users
/// Run this once to set up the test users in Firestore
/// 
/// IMPORTANT: First create these users in Firebase Console:
/// 1. Go to Firebase Console → Authentication → Users
/// 2. Add user: admin@gmail.com, password: admin123
/// 3. Add user: attorney@gmail.com, password: attorney123
/// 4. Then run this function to set up their Firestore documents
Future<void> createTestUsers() async {
  final auth = FirebaseAuth.instance;
  final setupService = UserSetupService();

  try {
    // Try to sign in as admin to get UID
    try {
      final adminCredential = await auth.signInWithEmailAndPassword(
        email: 'admin@gmail.com',
        password: 'admin123',
      );
      
      if (adminCredential.user != null) {
        await setupService.setupAdminUser(
          'admin@gmail.com',
          adminCredential.user!.uid,
        );
        if (kDebugMode) {
          debugPrint('✅ Admin user created in Firestore');
        }
        await auth.signOut();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Admin user setup: $e');
        debugPrint('⚠️ Make sure admin@gmail.com exists in Firebase Auth');
      }
    }

    // Try to sign in as attorney to get UID
    try {
      final attorneyCredential = await auth.signInWithEmailAndPassword(
        email: 'attorney@gmail.com',
        password: 'attorney123',
      );
      
      if (attorneyCredential.user != null) {
        await setupService.setupAttorneyUser(
          'attorney@gmail.com',
          attorneyCredential.user!.uid,
          name: 'Attorney User',
          specialization: ['General Law', 'Criminal Defense'],
        );
        if (kDebugMode) {
          debugPrint('✅ Attorney user created in Firestore');
        }
        await auth.signOut();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Attorney user setup: $e');
        debugPrint('⚠️ Make sure attorney@gmail.com exists in Firebase Auth');
      }
    }

    if (kDebugMode) {
      debugPrint('✅ Test users setup complete!');
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('❌ Error setting up test users: $e');
    }
  }
}

