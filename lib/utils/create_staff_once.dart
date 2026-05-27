import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../firebase_options.dart';

/// One-time script to create staff account
/// Run this once in your app's main() or from a button
Future<void> createStaffAccountOnce() async {
  try {
    // Initialize Firebase if not already initialized
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      // Already initialized, continue
    }

    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;

    // Check if staff already exists
    final existingStaff = await firestore
        .collection('users')
        .where('email', isEqualTo: 'staff@gmail.com')
        .where('role', isEqualTo: 'staff')
        .get();

    if (existingStaff.docs.isNotEmpty) {
      print('⚠️ Staff account with email staff@gmail.com already exists!');
      return;
    }

    // Get first available attorney (or use empty string)
    String? attorneyId;
    final attorneysSnapshot = await firestore
        .collection('users')
        .where('role', isEqualTo: 'attorney')
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    if (attorneysSnapshot.docs.isNotEmpty) {
      attorneyId = attorneysSnapshot.docs.first.id;
      print('✅ Found attorney: ${attorneysSnapshot.docs.first.data()['name']}');
    } else {
      print('⚠️ No attorney found. Staff will be created without assignment.');
      attorneyId = '';
    }

    // Create Firebase Auth user
    print('Creating Firebase Auth user...');
    final credential = await auth.createUserWithEmailAndPassword(
      email: 'staff@gmail.com',
      password: '12345678',
    );

    final staffId = credential.user!.uid;
    print('✅ Firebase Auth user created. UID: $staffId');

    // Create Firestore document
    print('Creating Firestore document...');
    await firestore.collection('users').doc(staffId).set({
      'email': 'staff@gmail.com',
      'name': 'Staff User',
      'role': 'staff',
      'assignedAttorneyId': attorneyId,
      'isVerified': true,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    print('✅ Staff account created successfully!');
    print('📧 Email: staff@gmail.com');
    print('🔑 Password: 12345678');
    print('🆔 Staff ID: $staffId');
    if (attorneyId.isNotEmpty) {
      print('👨‍⚖️ Assigned to attorney: $attorneyId');
    } else {
      print(
        '⚠️ Not assigned to any attorney yet. Update assignedAttorneyId later.',
      );
    }
  } catch (e) {
    print('❌ Error creating staff account: $e');
    if (e.toString().contains('email-already-in-use')) {
      print('ℹ️ Staff account already exists in Firebase Auth.');
      print('   You may need to create the Firestore document manually.');
    }
  }
}
