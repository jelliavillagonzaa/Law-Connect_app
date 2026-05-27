import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/staff_model.dart';
import '../models/user_model.dart';
import 'sms_service.dart';
import 'staff_application_service.dart';

/// Service to handle staff authentication and data retrieval
/// Staff are stored in 'users' collection with role='staff'
class StaffAuthService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get staff data by ID (from users collection with role='staff')
  Future<StaffModel?> getStaffById(String staffId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(staffId).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        // Check if user has role='staff'
        if (data['role'] == 'staff') {
          return StaffModel.fromUserModel(
            UserModel.fromFirestore(data, staffId),
          );
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get current logged-in staff member
  Future<StaffModel?> getCurrentStaff() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return getStaffById(user.uid);
  }

  /// Check if current user is staff
  Future<bool> isCurrentUserStaff() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      final data = userDoc.data()!;
      return data['role'] == 'staff';
    }
    return false;
  }

  /// Get staff role (always returns 'staff' if exists)
  Future<String?> getStaffRole(String staffId) async {
    final staff = await getStaffById(staffId);
    return staff != null ? 'staff' : null;
  }

  /// Update staff profile
  Future<Map<String, dynamic>> updateStaffProfile({
    required String staffId,
    String? name,
    String? phone,
    String? phoneNumber,
    String? address,
    String? photoUrl,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (name != null) updateData['name'] = name;
      if (phone != null) updateData['phone'] = phone;
      if (phoneNumber != null) updateData['phoneNumber'] = phoneNumber;
      if (address != null) updateData['address'] = address;
      if (photoUrl != null) updateData['photoUrl'] = photoUrl;

      await _firestore.collection('users').doc(staffId).update(updateData);

      return {'success': true, 'message': 'Profile updated successfully'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to update profile: ${e.toString()}',
      };
    }
  }

  /// Create staff user (for admin use)
  Future<Map<String, dynamic>> createStaff({
    required String email,
    required String name,
    required String assignedAttorneyId,
    String? phone,
    String? address,
    String? password,
  }) async {
    try {
      // Check if staff already exists
      final existingStaff = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .where('role', isEqualTo: 'staff')
          .get();

      if (existingStaff.docs.isNotEmpty) {
        return {
          'success': false,
          'message': 'Staff with this email already exists',
        };
      }

      // Use custom password if provided, otherwise use temporary password
      final staffPassword = password ?? 'TempPassword123!';

      // Create Firebase Auth user first
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: staffPassword,
      );

      if (credential.user == null) {
        return {'success': false, 'message': 'Failed to create user account'};
      }

      final staffId = credential.user!.uid;

      // Create staff document in Firestore (in users collection with role='staff')
      // Same structure as attorney creation - no OTP, direct creation
      await _firestore.collection('users').doc(staffId).set({
        'email': email,
        'name': name,
        'role': 'staff',
        'assignedAttorneyId': assignedAttorneyId,
        'isVerified': true,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (phone != null) 'phone': phone,
        if (phone != null) 'phoneNumber': phone,
        if (address != null) 'address': address,
      });

      // No password reset email - password is already set (like attorney creation)
      // Staff can login directly with the provided password

      // Optional: Welcome SMS (best-effort; do not fail staff creation)
      if (phone != null && phone.trim().isNotEmpty) {
        try {
          final sms = SmsService();
          await sms.queueSms(
            to: phone,
            body:
                'Welcome to Law Connect, $name! Your staff account is ready. Please login using your email.',
            userId: staffId,
            meta: {'type': 'welcome', 'role': 'staff'},
          );
        } catch (_) {
          // Non-critical
        }
      }

      return {
        'success': true,
        'message': 'Staff created successfully. Account is ready to use.',
        'staffId': staffId,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to create staff: ${e.toString()}',
      };
    }
  }

  /// Applicant flow: admin has approved [staff_applications] doc; user sets password here.
  Future<Map<String, dynamic>> completeStaffRegistrationAfterApproval({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      return {'success': false, 'message': 'Please enter a valid email.'};
    }

    final docId = StaffApplicationService.applicationDocIdForEmail(trimmedEmail);

    try {
      final appSnap = await _firestore
          .collection(StaffApplicationService.collectionName)
          .doc(docId)
          .get();

      if (!appSnap.exists) {
        return {
          'success': false,
          'message': 'No staff application found for this email.',
        };
      }

      final app = appSnap.data()!;
      final appEmail = (app['email'] as String? ?? '').trim().toLowerCase();
      if (appEmail != trimmedEmail) {
        return {'success': false, 'message': 'Email does not match this application.'};
      }

      final status = app['status'] as String? ?? '';
      if (status != 'approved') {
        if (status == 'pending') {
          return {
            'success': false,
            'message': 'Your application is still pending admin review.',
          };
        }
        if (status == 'rejected') {
          return {
            'success': false,
            'message': 'This application was not approved.',
          };
        }
        if (status == 'registered') {
          return {
            'success': false,
            'message': 'This email is already registered as staff. Please sign in.',
          };
        }
        return {'success': false, 'message': 'Application cannot be completed.'};
      }

      final assignedAttorneyId = (app['assignedAttorneyId'] as String?)?.trim() ?? '';
      if (assignedAttorneyId.isEmpty) {
        return {
          'success': false,
          'message':
              'Your application is missing an attorney assignment. Ask an administrator to fix it.',
        };
      }

      final existingStaff = await _firestore
          .collection('users')
          .where('email', isEqualTo: trimmedEmail)
          .where('role', isEqualTo: 'staff')
          .limit(1)
          .get();

      if (existingStaff.docs.isNotEmpty) {
        return {
          'success': false,
          'message': 'A staff account with this email already exists.',
        };
      }

      final name = (app['name'] as String? ?? 'Staff').trim();
      final phone = app['phone'] as String?;
      final address = app['address'] as String?;

      final credential = await _auth.createUserWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );

      if (credential.user == null) {
        return {'success': false, 'message': 'Could not create account.'};
      }

      final staffId = credential.user!.uid;

      await _firestore.collection('users').doc(staffId).set({
        'email': trimmedEmail,
        'name': name.isEmpty ? 'Staff' : name,
        'role': 'staff',
        'assignedAttorneyId': assignedAttorneyId,
        'isVerified': true,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phoneNumber': phone.trim(),
        if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
      });

      await _firestore
          .collection(StaffApplicationService.collectionName)
          .doc(docId)
          .update({
        'status': 'registered',
        'registeredUid': staffId,
        'registeredAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (phone != null && phone.trim().isNotEmpty) {
        try {
          final sms = SmsService();
          await sms.queueSms(
            to: phone.trim(),
            body:
                'Welcome to Law Connect, $name! Your staff account is ready. Please sign in with your email.',
            userId: staffId,
            meta: {'type': 'welcome', 'role': 'staff'},
          );
        } catch (_) {}
      }

      return {
        'success': true,
        'message': 'Account created. You can sign in now.',
        'staffId': staffId,
      };
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        return {
          'success': false,
          'message':
              'This email already has an account. Try signing in, or use a different email.',
        };
      }
      return {'success': false, 'message': e.message ?? e.code};
    } catch (e) {
      return {
        'success': false,
        'message': 'Registration failed: ${e.toString()}',
      };
    }
  }
}
