import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase_options.dart';
import '../services/staff_auth_service.dart';

/// Quick function to create staff account
/// Call this once from your app
Future<void> createStaffAccountNow() async {
  try {
    // Initialize Firebase if needed
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      // Already initialized
    }

    final staffService = StaffAuthService();
    final firestore = FirebaseFirestore.instance;

    // Get first attorney (or use empty string)
    String attorneyId = '';
    try {
      final attorneys = await firestore
          .collection('users')
          .where('role', isEqualTo: 'attorney')
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      
      if (attorneys.docs.isNotEmpty) {
        attorneyId = attorneys.docs.first.id;
        print('✅ Found attorney: ${attorneys.docs.first.data()['name']}');
      } else {
        print('⚠️ No attorney found. Staff will be created without assignment.');
      }
    } catch (e) {
      print('⚠️ Could not find attorney: $e');
    }

    // Create staff account
    final result = await staffService.createStaff(
      email: 'staff@gmail.com',
      name: 'Staff User',
      assignedAttorneyId: attorneyId,
      password: '12345678',
    );

    if (result['success'] == true) {
      print('✅ Staff account created successfully!');
      print('📧 Email: staff@gmail.com');
      print('🔑 Password: 12345678');
      print('🆔 Staff ID: ${result['staffId']}');
    } else {
      print('❌ Failed: ${result['message']}');
    }
  } catch (e) {
    print('❌ Error: $e');
  }
}

