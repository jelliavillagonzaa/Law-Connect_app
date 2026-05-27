import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/staff_auth_service.dart';

/// Utility function to create staff account with specific credentials
/// Run this once to create the staff account
Future<void> createStaffAccount() async {
  final staffService = StaffAuthService();
  final firestore = FirebaseFirestore.instance;

  try {
    // Get the first available attorney to assign staff to
    final attorneysSnapshot = await firestore
        .collection('users')
        .where('role', isEqualTo: 'attorney')
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    String attorneyId;
    if (attorneysSnapshot.docs.isNotEmpty) {
      attorneyId = attorneysSnapshot.docs.first.id;
      print('Found attorney: ${attorneysSnapshot.docs.first.data()['name']}');
    } else {
      // If no attorney exists, create a placeholder or use empty string
      // Staff can be assigned later
      print(
        'Warning: No active attorney found. Staff will need to be assigned later.',
      );
      attorneyId = ''; // You'll need to update this later
    }

    // Create staff account
    final result = await staffService.createStaff(
      email: 'staff@gmail.com',
      name: 'Staff User', // You can change this name
      assignedAttorneyId: attorneyId,
      password: '12345678', // Your specified password
    );

    if (result['success'] == true) {
      print('✅ Staff account created successfully!');
      print('Email: staff@gmail.com');
      print('Password: 12345678');
      print('Staff ID: ${result['staffId']}');
    } else {
      print('❌ Failed to create staff: ${result['message']}');
    }
  } catch (e) {
    print('❌ Error creating staff account: $e');
  }
}
