import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../services/email_otp_service.dart';
import '../services/admin_service.dart';
class AuthController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final EmailOtpService _emailOtpService = EmailOtpService();

  // In-memory cooldowns
  DateTime? _lastVerifyEmailAt;
  DateTime? _lastResetAt;

  bool _withinCooldown(DateTime? last, int seconds) {
    if (last == null) return false;
    return DateTime.now().difference(last).inSeconds < seconds;
  }

  // ==============================
  // CHECK IF EMAIL EXISTS
  // ==============================
  Future<bool> _checkEmailExists(String email) async {
    try {
      // Check if email exists by trying to sign in with a dummy password
      // This is a workaround for deprecated fetchSignInMethodsForEmail
      // If email exists, we'll get auth/user-not-found or auth/wrong-password
      // If email doesn't exist, we'll get auth/user-not-found
      try {
        await _auth.signInWithEmailAndPassword(
          email: email,
          password: 'dummy_check_password_12345',
        );
        // If we get here, email exists (shouldn't happen with dummy password)
        await _auth.signOut();
        return true;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found') {
          return false; // Email doesn't exist
        } else if (e.code == 'wrong-password') {
          return true; // Email exists (wrong password means user exists)
        } else {
          // Other error, assume email doesn't exist to allow registration
          return false;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking email existence: $e');
      // If there's an error, assume email doesn't exist to allow registration
      return false;
    }
  }

  // ==============================
  // SIGN UP (NEW FLOW: OTP FIRST, THEN CREATE ACCOUNT)
  // ==============================
  Future<void> registerUser({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String address,
    required String userType,
  }) async {
    try {
      // Step 1: Check if email already exists
      final emailExists = await _checkEmailExists(email);
      if (emailExists) {
        Get.snackbar(
          "Email Already Exists",
          "The email address is already in use by another account. Please use a different email or try logging in.",
          backgroundColor: Colors.red[200],
          duration: const Duration(seconds: 5),
        );
        return;
      }

      // Step 2: Generate OTP
      final otp = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000))
          .toString();

      // Step 3: Store registration data temporarily (before creating Firebase account)
      await _firestore.collection('pending_registrations').doc(email).set({
        'email': email,
        'password': password, // Note: In production, consider hashing this
        'fullName': name,
        'phone': phone,
        'address': address,
        'userType': userType,
        'otp': otp,
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(minutes: 5)),
        ),
        'createdAt': Timestamp.now(),
        'used': false,
        'otpSent': false, // Track if OTP has been sent
      });

      // Step 4: Navigate to OTP verification screen (OTP will be sent from there)
      Get.toNamed(
        '/verify-otp',
        arguments: {'email': email, 'purpose': 'register', 'name': name},
      );
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'email-already-in-use' =>
          "The email address is already in use by another account.",
        'invalid-email' => "Invalid email address format.",
        'weak-password' =>
          "Password is too weak. Please use a stronger password.",
        _ => e.message ?? "Registration failed",
      };
      Get.snackbar("Error", msg, backgroundColor: Colors.red[200]);
    } on FirebaseException catch (e) {
      if (kDebugMode)
        debugPrint(
          '❌ Firestore error during registration: ${e.code} - ${e.message}',
        );
      final msg = switch (e.code) {
        'permission-denied' =>
          "Permission denied. Please check your Firestore rules or try again.",
        'unavailable' =>
          "Service temporarily unavailable. Please try again later.",
        _ => e.message ?? "Database error occurred",
      };
      Get.snackbar("Error", msg, backgroundColor: Colors.red[200]);
    } catch (e) {
      // Catch any other exceptions including FirestoreException
      if (e.toString().contains('permission-denied') ||
          e.toString().contains('permission denied')) {
        if (kDebugMode) debugPrint('❌ Firestore permission error: $e');
        Get.snackbar(
          "Permission Error",
          "Unable to save registration data. Please make sure Firestore rules are deployed correctly.",
          backgroundColor: Colors.red[200],
          duration: const Duration(seconds: 5),
        );
      } else {
        if (kDebugMode) debugPrint('❌ Unexpected registration error: $e');
        Get.snackbar(
          "Error",
          "Unexpected error: $e",
          backgroundColor: Colors.red[200],
        );
      }
    }
  }

  // ==============================
  // LOGIN
  // ==============================
  Future<void> login(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        Get.snackbar(
          "Error",
          "Login failed. Please try again.",
          backgroundColor: Colors.red[200],
        );
        return;
      }

      // Get user role from Firestore to determine if email verification is needed
      String? userRole;
      try {
        final userDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          userRole = userDoc.data()?['role'] as String?;
        } else {
          // Try by email as fallback
          final userByEmailDoc = await _firestore
              .collection('users')
              .doc(email)
              .get();
          if (userByEmailDoc.exists) {
            userRole = userByEmailDoc.data()?['role'] as String?;
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Could not fetch user role: $e');
      }

      // Navigate to portal
      // TODO: Replace with actual route when screens are created
      // Get.offAllNamed('/portal');

      // Show appropriate message based on role
      // Admin and Attorney don't need email verification
      if (userRole == 'admin' || userRole == 'attorney') {
        Get.snackbar(
          "Welcome Back",
          "Login successful!",
          backgroundColor: Colors.green[200],
          duration: const Duration(seconds: 2),
        );
      } else if (!(user.emailVerified)) {
        // For clients, show verification reminder (but they already went through OTP)
        Get.snackbar(
          "Logged in",
          "Welcome! Your account is active.",
          backgroundColor: Colors.green[200],
          duration: const Duration(seconds: 2),
        );
      } else {
        Get.snackbar(
          "Welcome Back",
          "Login successful!",
          backgroundColor: Colors.green[200],
          duration: const Duration(seconds: 2),
        );
      }
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'too-many-requests' => "Too many attempts. Please wait a few minutes.",
        'user-not-found' => "No user found with that email.",
        'wrong-password' => "Incorrect password.",
        'invalid-credential' => "Invalid email or password.",
        'network-request-failed' => "Network error. Check your connection.",
        _ => e.message ?? "Login failed",
      };
      Get.snackbar("Login Failed", msg, backgroundColor: Colors.red[200]);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Unexpected login error: $e');
      Get.snackbar(
        "Error",
        "Unexpected error: $e",
        backgroundColor: Colors.red[200],
      );
    }
  }

  // ==============================
  // SEND OTP VIA EMAILJS (using EmailOtpService)
  // ==============================
  Future<bool> sendOtp(
    String email,
    String otp, {
    String? name,
    String? replyTo,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📧 AUTH CONTROLLER: Sending OTP via EmailOtpService');
        debugPrint('📧 To Email: $email');
        debugPrint('📧 OTP Code: $otp');
      }

      // Use the EmailOtpService to send OTP
      final success = await _emailOtpService.sendOtp(
        email: email,
        otp: otp,
        name: name,
        replyTo: replyTo,
      );

      if (kDebugMode) {
        if (success) {
          debugPrint('✅ AUTH CONTROLLER: OTP sent successfully');
        } else {
          debugPrint('❌ AUTH CONTROLLER: Failed to send OTP');
        }
      }

      return success;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ AUTH CONTROLLER: Error sending OTP: $e');
        debugPrint('❌ Stack trace: $stackTrace');
      }
      return false;
    }
  }

  // ==============================
  // SEND REGISTRATION OTP (from verification screen)
  // ==============================
  Future<bool> sendRegistrationOtp(String email, {String? name}) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 Starting OTP send for registration: $email');
      }

      // Get pending registration data
      final snap = await _firestore
          .collection('pending_registrations')
          .doc(email)
          .get();
      if (!snap.exists) {
        if (kDebugMode) {
          debugPrint('❌ No pending registration found for: $email');
          debugPrint('❌ User needs to register again');
        }
        return false;
      }

      final data = snap.data() as Map<String, dynamic>;
      final storedOtp = data['otp']?.toString() ?? '';
      final storedName = data['fullName']?.toString() ?? name ?? 'User';

      if (storedOtp.isEmpty) {
        if (kDebugMode) {
          debugPrint('❌ No OTP found in pending registration for: $email');
        }
        return false;
      }

      if (kDebugMode) {
        debugPrint('✅ Found OTP in Firestore, sending via EmailJS...');
        debugPrint('✅ OTP to send: $storedOtp');
      }

      // Send OTP via EmailJS
      final success = await sendOtp(
        email,
        storedOtp,
        name: storedName,
      );

      if (success) {
        // Mark OTP as sent
        try {
          await _firestore
              .collection('pending_registrations')
              .doc(email)
              .update({'otpSent': true, 'lastSentAt': Timestamp.now()});
          if (kDebugMode) {
            debugPrint('✅ OTP sent status updated in Firestore');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Failed to update otpSent status: $e');
          }
          // Don't fail the whole operation if update fails
        }
        return true;
      } else {
        if (kDebugMode) {
          debugPrint('❌ EmailJS sendOtp returned false');
          debugPrint('❌ Check the logs above for EmailJS response details');
          debugPrint('❌ Look for "📧 EMAILJS RESPONSE" section above');
        }
        return false;
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ sendRegistrationOtp error: $e');
        debugPrint('❌ Stack trace: $stackTrace');
      }
      return false;
    }
  }

  Future<bool> verifyRegistrationOtp(String email, String otp) async {
    try {
      // Step 1: Get pending registration data
      final snap = await _firestore
          .collection('pending_registrations')
          .doc(email)
          .get();
      if (!snap.exists) {
        Get.snackbar(
          "Invalid OTP",
          "No registration found for this email. Please register again.",
          backgroundColor: Colors.red[200],
        );
        return false;
      }

      final data = snap.data() as Map<String, dynamic>;
      final storedOtp = data['otp']?.toString() ?? '';
      final used = data['used'] == true;
      final expiresAtTs = data['expiresAt'];
      DateTime? expiresAt;
      if (expiresAtTs is Timestamp) {
        expiresAt = expiresAtTs.toDate();
      }

      // Step 2: Validate OTP
      if (used) {
        Get.snackbar(
          "OTP Already Used",
          "This OTP has already been used. Please register again.",
          backgroundColor: Colors.red[200],
        );
        return false;
      }
      if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
        Get.snackbar(
          "OTP Expired",
          "OTP has expired. Please register again.",
          backgroundColor: Colors.red[200],
        );
        // Clean up expired registration
        await _firestore
            .collection('pending_registrations')
            .doc(email)
            .delete();
        return false;
      }
      if (storedOtp != otp) {
        Get.snackbar(
          "Incorrect OTP",
          "Please double-check the code.",
          backgroundColor: Colors.red[200],
        );
        return false;
      }

      // Step 3: Get registration data
      final password = data['password']?.toString() ?? '';
      final name = data['fullName']?.toString() ?? '';
      final phone = data['phone']?.toString() ?? '';
      final address = data['address']?.toString() ?? '';
      final userType = data['userType']?.toString() ?? '';

      if (password.isEmpty) {
        Get.snackbar(
          "Error",
          "Invalid registration data. Please register again.",
          backgroundColor: Colors.red[200],
        );
        return false;
      }

      // Step 4: Create Firebase account (only after OTP verification)
      UserCredential? userCredential;
      try {
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          Get.snackbar(
            "Email Already Exists",
            "This email was registered while you were verifying. Please try logging in instead.",
            backgroundColor: Colors.red[200],
            duration: const Duration(seconds: 5),
          );
          // Clean up pending registration
          await _firestore
              .collection('pending_registrations')
              .doc(email)
              .update({'used': true});
          return false;
        }
        rethrow;
      }

      final user = userCredential.user;
      if (user == null) {
        Get.snackbar(
          "Error",
          "Failed to create account. Please try again.",
          backgroundColor: Colors.red[200],
        );
        return false;
      }

      // Step 5: Save user data to Firestore
      await _firestore.collection('users').doc(user.uid).set({
        'fullName': name,
        'email': email,
        'phone': phone,
        'address': address,
        'userType': userType,
        'createdAt': DateTime.now(),
        'isOtpVerified': true, // Mark as verified since OTP was checked
      });

      // Log signup/registration to system logs for admin visibility
      try {
        final adminService = AdminService();
        await adminService.logAction(
          action: 'user_registered',
          resourceType: 'user',
          resourceId: user.uid,
          details: 'New $userType signup',
          metadata: {'email': email, 'name': name, 'userType': userType},
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Failed to log registration action: $e');
        }
      }

      // Step 6: Mark OTP as used and clean up
      await _firestore.collection('pending_registrations').doc(email).update({
        'used': true,
      });

      Get.snackbar(
        "Account Created Successfully",
        "Your account has been verified and created. You can now log in.",
        backgroundColor: Colors.green[200],
        duration: const Duration(seconds: 4),
      );

      // Step 7: Navigate to login screen
      // TODO: Replace with actual route when screens are created
      // Get.offAllNamed('/login');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ verifyRegistrationOtp error: $e');
      Get.snackbar(
        "Error",
        "Failed to verify OTP: $e",
        backgroundColor: Colors.red[200],
      );
      return false;
    }
  }

  // ==============================
  // PASSWORD RESET via Firebase email (no OTP)
  // ==============================
  Future<bool> resetPassword(String email) async {
    try {
      if (_withinCooldown(_lastResetAt, 30)) {
        Get.snackbar(
          "Please wait",
          "You can request another email shortly.",
          backgroundColor: Colors.orange[200],
        );
        return false;
      }

      // Continue URL should be listed under Authorized domains (Firebase Console → Authentication).
      try {
        await _auth.sendPasswordResetEmail(
          email: email,
          actionCodeSettings: ActionCodeSettings(
            url: 'https://jurislink-app.firebaseapp.com/',
            handleCodeInApp: false,
          ),
        );
      } on FirebaseAuthException catch (e) {
        final m = e.message?.toLowerCase() ?? '';
        if (e.code == 'unauthorized-continue-uri' || m.contains('continue')) {
          await _auth.sendPasswordResetEmail(email: email);
        } else {
          rethrow;
        }
      }

      _lastResetAt = DateTime.now();

      if (kDebugMode) {
        debugPrint('✅ Password reset email sent to: $email (single Firebase email)');
      }

      Get.snackbar(
        "Check your email",
        "We sent one reset link to $email. Please check your inbox.",
        backgroundColor: Colors.green[200],
        duration: const Duration(seconds: 5),
      );
      return true;
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'invalid-email' => 'Invalid email address.',
        'user-not-found' => 'No user found with that email.',
        'too-many-requests' => 'Too many requests. Try again later.',
        _ => e.message ?? 'Failed to send reset email',
      };
      Get.snackbar("Error", msg, backgroundColor: Colors.red[200]);
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Unexpected error in resetPassword: $e');
      Get.snackbar(
        "Error",
        "Failed to start password reset: $e",
        backgroundColor: Colors.red[200],
      );
      return false;
    }
  }

  // ==============================
  // RESEND VERIFICATION EMAIL
  // ==============================
  Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null) {
      Get.snackbar(
        "Not logged in",
        "Log in first to resend verification email.",
        backgroundColor: Colors.orange[200],
      );
      return;
    }

    if (user.emailVerified) {
      Get.snackbar(
        "Already Verified",
        "Your email is already verified.",
        backgroundColor: Colors.blue[200],
      );
      return;
    }

    if (_withinCooldown(_lastVerifyEmailAt, 60)) {
      Get.snackbar(
        "Please wait",
        "You can resend another verification email soon.",
        backgroundColor: Colors.orange[200],
      );
      return;
    }

    try {
      await user.sendEmailVerification();
      _lastVerifyEmailAt = DateTime.now();

      Get.snackbar(
        "Verification Sent",
        "Check your inbox and spam folder at ${user.email}",
        backgroundColor: Colors.green[200],
        duration: const Duration(seconds: 5),
      );
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'too-many-requests' =>
          "Too many requests. Wait a minute and try again.",
        'invalid-email' => "Invalid email address.",
        _ => e.message ?? "Failed to send verification email.",
      };
      Get.snackbar("Error", msg, backgroundColor: Colors.red[200]);
    } catch (e) {
      Get.snackbar(
        "Error",
        "Unexpected error: $e",
        backgroundColor: Colors.red[200],
      );
    }
  }

  // ==============================
  // LOGOUT
  // ==============================
  Future<void> logout() async {
    await _auth.signOut();
    // TODO: Replace with actual route when screens are created
    // Get.offAllNamed('/login');
  }
}
