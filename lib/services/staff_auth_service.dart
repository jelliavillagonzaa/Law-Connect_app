import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../models/staff_model.dart';
import '../models/user_model.dart';
import 'email_otp_service.dart';
import 'sms_service.dart';
import 'staff_application_service.dart';

/// Service to handle staff authentication and data retrieval
/// Staff are stored in 'users' collection with role='staff'
class StaffAuthService {
  StaffAuthService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const String _staffRegOtpPurpose = 'staff_registration';

  /// Validates staff application for OTP / registration ([pending] or [approved]).
  Future<Map<String, dynamic>> _validateStaffApplicationForRegistration(
    String trimmedEmail,
  ) async {
    final docId = StaffApplicationService.applicationDocIdForEmail(trimmedEmail);
    final appSnap = await _firestore
        .collection(StaffApplicationService.collectionName)
        .doc(docId)
        .get();

    if (!appSnap.exists) {
      return {
        'ok': false,
        'message': 'No staff application found for this email.',
      };
    }

    final app = appSnap.data()!;
    final appEmail = (app['email'] as String? ?? '').trim().toLowerCase();
    if (appEmail != trimmedEmail) {
      return {'ok': false, 'message': 'Email does not match this application.'};
    }

    final status = app['status'] as String? ?? '';
    if (status == 'rejected') {
      return {
        'ok': false,
        'message': 'This application was not approved.',
      };
    }
    if (status == 'registered') {
      return {
        'ok': false,
        'message': 'This email is already registered as staff. Please sign in.',
      };
    }
    if (status != 'pending' && status != 'approved') {
      return {'ok': false, 'message': 'Application cannot be completed.'};
    }

    final existingRegUid = (app['registeredUid'] as String?)?.trim() ?? '';
    if (existingRegUid.isNotEmpty) {
      return {
        'ok': false,
        'message':
            'This application already finished email verification. Wait for an administrator to approve your application (if still pending) and activate your account, then sign in.',
      };
    }

    final assignedAttorneyId =
        (app['assignedAttorneyId'] as String?)?.trim() ?? '';
    if (status == 'approved' && assignedAttorneyId.isEmpty) {
      return {
        'ok': false,
        'message':
            'Your application is approved but missing an attorney assignment. Ask an administrator.',
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
        'ok': false,
        'message': 'A staff account with this email already exists.',
      };
    }

    return {'ok': true, 'docId': docId, 'app': app};
  }

  /// Send a 6-digit code (application may be [pending] or [approved]).
  Future<Map<String, dynamic>> sendStaffRegistrationOtp(String email) async {
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      return {'success': false, 'message': 'Please enter a valid email.'};
    }

    try {
      final check = await _validateStaffApplicationForRegistration(trimmedEmail);
      if (check['ok'] != true) {
        return {
          'success': false,
          'message': check['message'] as String? ?? 'Not allowed.',
        };
      }

      final app = check['app'] as Map<String, dynamic>;
      final name = (app['name'] as String? ?? 'Staff').trim();

      final otp = EmailOtpService.generateOtp();
      await _firestore
          .collection('email_verification_otps')
          .doc(trimmedEmail)
          .set({
        'email': trimmedEmail,
        'otp': otp,
        'expiresAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'used': false,
        'purpose': _staffRegOtpPurpose,
      });

      final emailOtpService = EmailOtpService();
      final sent = await emailOtpService.sendOtp(
        email: trimmedEmail,
        otp: otp,
        name: name.isEmpty ? 'Staff' : name,
      );

      if (!sent) {
        return {
          'success': false,
          'message':
              'Could not send the code. Check your email settings and try again.',
        };
      }

      return {
        'success': true,
        'message': 'Verification code sent to your email.',
      };
    } catch (e) {
      if (kDebugMode) debugPrint('sendStaffRegistrationOtp: $e');
      return {
        'success': false,
        'message': 'Could not send verification code: $e',
      };
    }
  }

  Future<String?> _staffRegistrationOtpError(
    String trimmedEmail,
    String otp,
  ) async {
    if (!EmailOtpService.isValidOtpFormat(otp.trim())) {
      return 'Enter the 6-digit verification code.';
    }

    final otpDoc = await _firestore
        .collection('email_verification_otps')
        .doc(trimmedEmail)
        .get();

    if (!otpDoc.exists) {
      return 'No verification code found. Tap Resend code.';
    }

    final data = otpDoc.data()!;
    if ((data['purpose'] as String?) != _staffRegOtpPurpose) {
      return 'Request a new code from this page.';
    }

    final used = data['used'] as bool? ?? false;
    if (used) {
      return 'This code was already used. Request a new one.';
    }

    final expiresAt = data['expiresAt'] as Timestamp?;
    if (expiresAt != null) {
      final expirationTime = expiresAt.toDate();
      if (DateTime.now().isAfter(
        expirationTime.add(const Duration(minutes: 5)),
      )) {
        return 'Code expired. Request a new one.';
      }
    }

    final storedOtp = data['otp'] as String?;
    if (storedOtp != otp.trim()) {
      return 'Invalid code. Try again.';
    }

    return null;
  }

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

  /// Applicant flow: after email OTP, creates Auth + Firestore staff profile.
  Future<Map<String, dynamic>> completeStaffRegistrationAfterApproval({
    required String email,
    required String password,
    required String otp,
  }) async {
    final trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      return {'success': false, 'message': 'Please enter a valid email.'};
    }

    final otpErr = await _staffRegistrationOtpError(trimmedEmail, otp);
    if (otpErr != null) {
      return {'success': false, 'message': otpErr};
    }

    try {
      final check = await _validateStaffApplicationForRegistration(trimmedEmail);
      if (check['ok'] != true) {
        return {
          'success': false,
          'message': check['message'] as String? ?? 'Not allowed.',
        };
      }

      final docId = check['docId'] as String;
      final app = check['app'] as Map<String, dynamic>;
      final appStatus = app['status'] as String? ?? '';
      final assignedAttorneyId =
          (app['assignedAttorneyId'] as String?)?.trim() ?? '';

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

      final awaitingAppApproval = appStatus == 'pending';
      // Application already approved → staff can sign in after OTP. Pending → active only after admin approves.
      final canUseAppNow = !awaitingAppApproval;

      await _firestore.collection('users').doc(staffId).set({
        'email': trimmedEmail,
        'name': name.isEmpty ? 'Staff' : name,
        'role': 'staff',
        'assignedAttorneyId': assignedAttorneyId,
        'isVerified': true,
        'isActive': canUseAppNow,
        if (awaitingAppApproval) 'staffPendingAdminActivation': true,
        if (awaitingAppApproval) 'staffAwaitingApplicationApproval': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phoneNumber': phone.trim(),
        if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
      });

      if (appStatus == 'approved') {
        await _firestore
            .collection(StaffApplicationService.collectionName)
            .doc(docId)
            .update({
          'status': 'registered',
          'registeredUid': staffId,
          'registeredAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Still pending: applicant may complete email/password before admin approves.
        await _firestore
            .collection(StaffApplicationService.collectionName)
            .doc(docId)
            .update({
          'registeredUid': staffId,
          'registeredAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      try {
        await _firestore
            .collection('email_verification_otps')
            .doc(trimmedEmail)
            .update({
          'used': true,
          'verifiedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Could not mark staff reg OTP used: $e');
        }
      }

      if (phone != null && phone.trim().isNotEmpty) {
        try {
          final sms = SmsService();
          await sms.queueSms(
            to: phone.trim(),
            body: awaitingAppApproval
                ? 'Law Connect: your staff profile was created. You can sign in after an administrator approves your application.'
                : 'Law Connect: your staff profile is ready. You can sign in with your email and password.',
            userId: staffId,
            meta: {'type': 'welcome', 'role': 'staff'},
          );
        } catch (_) {}
      }

      await _auth.signOut();

      final successMsg = awaitingAppApproval
          ? 'Account created. Wait for an administrator to approve your staff application — you can sign in right after approval.'
          : 'Account created. You can sign in now with your email and password.';

      return {
        'success': true,
        'message': successMsg,
        'staffId': staffId,
        'canSignInNow': canUseAppNow,
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
