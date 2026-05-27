import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../models/user_model.dart';
import 'user_setup_service.dart';
import 'email_otp_service.dart';
import 'fcm_service.dart';
import 'admin_service.dart';
import 'sms_service.dart';
import 'staff_application_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Limits rapid Firebase verification emails (multiple [AuthService] instances share this).
  static DateTime? _lastFirebaseVerificationEmailSentAt;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Helper method to retry Firestore operations
  Future<T> _retryFirestoreOperation<T>(
    Future<T> Function() operation, {
    int maxRetries = 5,
    String operationName = 'Firestore operation',
  }) async {
    int retries = maxRetries;
    Exception? lastError;

    while (retries > 0) {
      try {
        // Add small delay before operation
        if (retries < maxRetries) {
          await Future.delayed(
            Duration(milliseconds: 300 * (maxRetries - retries)),
          );
        }
        return await operation();
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        retries--;
        if (kDebugMode) {
          debugPrint('⚠️ $operationName failed, retries left: $retries - $e');
        }
        if (retries == 0) {
          if (kDebugMode) {
            debugPrint('❌ $operationName failed after all retries: $lastError');
          }
          rethrow;
        }
      }
    }
    throw lastError ?? Exception('Operation failed');
  }

  /// If [staff_applications] for this email is approved or registered for this [uid],
  /// updates [users/{uid}] to role `staff` when the profile is still `client`.
  /// Returns fields to merge into in-memory login payload, or null if nothing changed.
  Future<Map<String, dynamic>?> syncStaffRoleFromStaffApplication({
    required String uid,
    required String email,
  }) async {
    final emailNorm = email.trim().toLowerCase();
    if (emailNorm.isEmpty) return null;

    try {
      final appDocId = StaffApplicationService.applicationDocIdForEmail(emailNorm);
      if (appDocId.isEmpty) return null;

      final appSnap = await _firestore
          .collection(StaffApplicationService.collectionName)
          .doc(appDocId)
          .get();

      if (!appSnap.exists) return null;

      final app = appSnap.data()!;
      final status = (app['status'] as String? ?? '').toLowerCase();
      final appEmail = (app['email'] as String? ?? '').toLowerCase().trim();
      if (appEmail != emailNorm) return null;

      final regUid = app['registeredUid'] as String?;
      bool shouldBecomeStaff = false;
      if (status == 'registered') {
        if (regUid == uid) shouldBecomeStaff = true;
      } else if (status == 'approved') {
        if (regUid == null || regUid.isEmpty || regUid == uid) {
          shouldBecomeStaff = true;
        }
      }

      if (!shouldBecomeStaff) return null;

      final userSnap = await _firestore.collection('users').doc(uid).get();
      if (!userSnap.exists) return null;

      final data = userSnap.data()!;
      final currentRole = (data['role'] as String? ?? 'client').toLowerCase();

      if (currentRole == 'admin' || currentRole == 'attorney') return null;

      final attorneyId = (app['assignedAttorneyId'] as String?)?.trim() ?? '';
      final currentAttorney =
          (data['assignedAttorneyId'] as String?)?.trim() ?? '';

      if (currentRole == 'staff') {
        if (attorneyId.isNotEmpty && currentAttorney != attorneyId) {
          await _firestore.collection('users').doc(uid).update({
            'assignedAttorneyId': attorneyId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return {
            'role': 'staff',
            'isVerified': true,
            'assignedAttorneyId': attorneyId,
          };
        }
        return null;
      }

      final patch = <String, dynamic>{
        'role': 'staff',
        'isVerified': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (attorneyId.isNotEmpty) patch['assignedAttorneyId'] = attorneyId;

      await _firestore.collection('users').doc(uid).update(patch);

      if (kDebugMode) {
        debugPrint(
          '✅ Staff role synced from staff_applications for $emailNorm ($status)',
        );
      }

      return {
        'role': 'staff',
        'isVerified': true,
        if (attorneyId.isNotEmpty) 'assignedAttorneyId': attorneyId,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('syncStaffRoleFromStaffApplication: $e');
      }
      return null;
    }
  }

  // Client Signup with OTP Verification (Email verification before account creation)
  Future<Map<String, dynamic>> clientSignup({
    required String fullName,
    required String email,
    required String password,
    required String phoneNumber,
    required String address,
  }) async {
    try {
      // Check maintenance mode - block signup during maintenance
      final isMaintenanceMode = await _checkMaintenanceMode();
      if (isMaintenanceMode) {
        return {
          'success': false,
          'message':
              'System is under maintenance. Registration is temporarily disabled. Please try again later.',
        };
      }

      // Wait a bit to ensure Firestore is ready
      await Future.delayed(const Duration(milliseconds: 200));

      // Check if user document exists in Firestore (this is the source of truth)
      try {
        final emailQuery = await _retryFirestoreOperation(
          () => _firestore
              .collection('users')
              .where('email', isEqualTo: email)
              .limit(1)
              .get(),
          operationName: 'Check user by email',
          maxRetries: 2,
        );

        if (emailQuery.docs.isNotEmpty) {
          // User document exists in Firestore - block signup
          return {
            'success': false,
            'message': 'Email is already registered. Please login.',
          };
        }
      } catch (e) {
        // If check fails, allow signup to proceed
        if (kDebugMode) {
          debugPrint(
            '⚠️ Could not check user in Firestore, allowing signup: $e',
          );
        }
      }

      // Check and clean up pending signups
      try {
        final pendingDoc = await _retryFirestoreOperation(
          () => _firestore.collection('pending_signups').doc(email).get(),
          operationName: 'Check pending signup',
          maxRetries: 2,
        );

        if (pendingDoc.exists) {
          final pendingData = pendingDoc.data();
          if (pendingData != null) {
            final verified = pendingData['verified'] as bool? ?? false;

            if (verified) {
              // Was verified but user might have been deleted - check again
              try {
                final emailQuery = await _firestore
                    .collection('users')
                    .where('email', isEqualTo: email)
                    .limit(1)
                    .get();

                if (emailQuery.docs.isEmpty) {
                  // User was deleted from Firestore - clear pending and allow new signup
                  if (kDebugMode) {
                    debugPrint(
                      '✅ User deleted from Firestore - clearing verified pending signup',
                    );
                  }
                  await _firestore
                      .collection('pending_signups')
                      .doc(email)
                      .delete();
                } else {
                  // User still exists - block signup
                  return {
                    'success': false,
                    'message': 'Email is already registered. Please login.',
                  };
                }
              } catch (e) {
                // If check fails, clear pending and allow signup
                if (kDebugMode) {
                  debugPrint('⚠️ Could not verify user, clearing pending: $e');
                }
                try {
                  await _firestore
                      .collection('pending_signups')
                      .doc(email)
                      .delete();
                } catch (_) {
                  // Ignore delete errors
                }
              }
            } else {
              // Pending signup exists but not verified - delete old one and allow new signup
              if (kDebugMode) {
                debugPrint('✅ Clearing old unverified pending signup');
              }
              try {
                await _firestore
                    .collection('pending_signups')
                    .doc(email)
                    .delete();
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('⚠️ Could not delete old pending signup: $e');
                }
                // Continue anyway - will overwrite with new data
              }
            }
          }
        }
      } catch (e) {
        // If read fails, continue - we'll handle duplicate later
        if (kDebugMode) {
          debugPrint('⚠️ Could not check pending signup: $e');
        }
      }

      // Create Firebase Auth user first so we can send **real SMS** via Twilio
      // (our Supabase Edge Function `send-sms` requires a Firebase ID token).
      //
      // The account remains blocked until OTP verification sets isVerified=true in Firestore.
      UserCredential? userCredential;
      try {
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        String message = 'Account creation failed';
        switch (e.code) {
          case 'email-already-in-use':
            message = 'Email is already registered. Please login.';
            break;
          case 'invalid-email':
            message = 'Invalid email address';
            break;
          case 'weak-password':
            message = 'Password is too weak';
            break;
          default:
            message = e.message ?? message;
        }
        return {'success': false, 'message': message};
      }

      final createdUser = userCredential.user;
      if (createdUser == null) {
        return {'success': false, 'message': 'Failed to create user account'};
      }
      final userId = createdUser.uid;

      // Store signup data temporarily (OTP verification still required)
      final emailOtpService = EmailOtpService();
      final otp = EmailOtpService.generateOtp();

      // Get FCM token if available (for push notifications)
      String? fcmToken;
      try {
        final fcmService = FCMService();
        fcmToken = await fcmService.getToken();
        if (kDebugMode && fcmToken != null) {
          debugPrint('✅ FCM token obtained for OTP push notification');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Could not get FCM token for push notification: $e');
        }
        // Continue without FCM token - email will still be sent
      }

      await _retryFirestoreOperation(
        () => _firestore.collection('pending_signups').doc(email).set({
          'fullName': fullName,
          'email': email,
          // Keep password only to support legacy flows; user is already created in Firebase Auth.
          // Avoid using this for anything else.
          'password': password,
          'phoneNumber': phoneNumber,
          'address': address,
          'role': 'client',
          'userId': userId,
          'otp': otp,
          'fcmToken': fcmToken, // Store FCM token for push notifications
          'expiresAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'verified': false,
        }),
        operationName: 'Store pending signup',
      );

      // Send OTP via email and FCM push notification
      final otpSent = await emailOtpService.sendOtp(
        email: email,
        otp: otp,
        name: fullName,
        fcmToken: fcmToken, // Include FCM token for push notification
      );

      // Send OTP via real SMS (best-effort; do not fail signup if SMS fails)
      bool smsSent = false;
      try {
        final sms = SmsService();
        await sms.queueSms(
          to: phoneNumber,
          body:
              'Law Connect verification code: $otp\n\nDo not share this code with anyone.',
          userId: userId,
          meta: {'type': 'otp', 'channel': 'sms', 'role': 'client'},
        );
        smsSent = true;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Could not send OTP via SMS (non-critical): $e');
        }
      }

      if (!otpSent && !smsSent) {
        return {
          'success': false,
          'message':
              'Failed to send verification code. Please try again (email/SMS).',
        };
      }

      // Build success message based on what was sent
      String message = 'Verification code sent';
      final channels = <String>[];
      if (otpSent) channels.add('email');
      if (smsSent) channels.add('SMS');
      if (fcmToken != null) channels.add('push notification');
      if (channels.isNotEmpty) {
        message += ' via ${channels.join(', ')}.';
      } else {
        message += '.';
      }

      return {
        'success': true,
        'message': message,
        'email': email,
        'otp': otp, // Include OTP for display in mobile app
        'userId': userId,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error in clientSignup: $e');
      }
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  // Attorney Signup with OTP Verification
  Future<Map<String, dynamic>> attorneySignup({
    required String fullName,
    required String email,
    required String password,
    required String phoneNumber,
    required String address,
    required String specialization,
    required String barNumber,
    required String licenseState,
    String? licenseDocumentUrl,
  }) async {
    try {
      // Check maintenance mode - block signup during maintenance
      final isMaintenanceMode = await _checkMaintenanceMode();
      if (isMaintenanceMode) {
        return {
          'success': false,
          'message':
              'System is under maintenance. Registration is temporarily disabled. Please try again later.',
        };
      }

      // Wait a bit to ensure Firestore is ready
      await Future.delayed(const Duration(milliseconds: 200));

      // Check if user document exists in Firestore
      try {
        final emailQuery = await _retryFirestoreOperation(
          () => _firestore
              .collection('users')
              .where('email', isEqualTo: email)
              .limit(1)
              .get(),
          operationName: 'Check attorney by email',
          maxRetries: 2,
        );

        if (emailQuery.docs.isNotEmpty) {
          return {
            'success': false,
            'message': 'Email is already registered. Please login.',
          };
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ Could not check attorney in Firestore, allowing signup: $e',
          );
        }
      }

      // Check and clean up pending signups
      try {
        final pendingDoc = await _retryFirestoreOperation(
          () => _firestore.collection('pending_signups').doc(email).get(),
          operationName: 'Check pending attorney signup',
          maxRetries: 2,
        );

        if (pendingDoc.exists) {
          final pendingData = pendingDoc.data();
          if (pendingData != null) {
            final verified = pendingData['verified'] as bool? ?? false;

            if (verified) {
              try {
                final emailQuery = await _firestore
                    .collection('users')
                    .where('email', isEqualTo: email)
                    .limit(1)
                    .get();

                if (emailQuery.docs.isEmpty) {
                  await _firestore
                      .collection('pending_signups')
                      .doc(email)
                      .delete();
                } else {
                  return {
                    'success': false,
                    'message': 'Email is already registered. Please login.',
                  };
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint(
                    '⚠️ Could not verify attorney, clearing pending: $e',
                  );
                }
                try {
                  await _firestore
                      .collection('pending_signups')
                      .doc(email)
                      .delete();
                } catch (_) {}
              }
            } else {
              if (kDebugMode) {
                debugPrint('✅ Clearing old unverified pending attorney signup');
              }
              try {
                await _firestore
                    .collection('pending_signups')
                    .doc(email)
                    .delete();
              } catch (e) {
                if (kDebugMode) {
                  debugPrint(
                    '⚠️ Could not delete old pending attorney signup: $e',
                  );
                }
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Could not check pending attorney signup: $e');
        }
      }

      // Create Firebase Auth user first so we can send **real SMS** via Twilio
      UserCredential? userCredential;
      try {
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        String message = 'Account creation failed';
        switch (e.code) {
          case 'email-already-in-use':
            message = 'Email is already registered. Please login.';
            break;
          case 'invalid-email':
            message = 'Invalid email address';
            break;
          case 'weak-password':
            message = 'Password is too weak';
            break;
          default:
            message = e.message ?? message;
        }
        return {'success': false, 'message': message};
      }

      final createdUser = userCredential.user;
      if (createdUser == null) {
        return {'success': false, 'message': 'Failed to create user account'};
      }
      final userId = createdUser.uid;

      // Store signup data temporarily (OTP verification still required)
      final emailOtpService = EmailOtpService();
      final otp = EmailOtpService.generateOtp();

      // Get FCM token if available
      String? fcmToken;
      try {
        final fcmService = FCMService();
        fcmToken = await fcmService.getToken();
        if (kDebugMode && fcmToken != null) {
          debugPrint('✅ FCM token obtained for attorney OTP push notification');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Could not get FCM token for push notification: $e');
        }
      }

      // Parse specializations if provided
      List<String> specializationList = [];
      if (specialization.isNotEmpty) {
        specializationList = specialization
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }

      await _retryFirestoreOperation(
        () => _firestore.collection('pending_signups').doc(email).set({
          'fullName': fullName,
          'name': fullName, // For compatibility
          'email': email,
          // Keep password only to support legacy flows; user is already created in Firebase Auth.
          'password': password,
          'phoneNumber': phoneNumber,
          'address': address,
          'role': 'attorney',
          'userId': userId,
          'otp': otp,
          'fcmToken': fcmToken,
          'specialization': specializationList,
          'barNumber': barNumber,
          'licenseState': licenseState,
          'licenseDocumentUrl': licenseDocumentUrl,
          'expiresAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'verified': false,
          'pendingApproval': true, // Attorney needs admin approval
        }),
        operationName: 'Store pending attorney signup',
      );

      // Send OTP via email and FCM push notification
      final otpSent = await emailOtpService.sendOtp(
        email: email,
        otp: otp,
        name: fullName,
        fcmToken: fcmToken,
      );

      // Send OTP via real SMS (best-effort)
      bool smsSent = false;
      try {
        final sms = SmsService();
        await sms.queueSms(
          to: phoneNumber,
          body:
              'Law Connect verification code: $otp\n\nDo not share this code with anyone.',
          userId: userId,
          meta: {'type': 'otp', 'channel': 'sms', 'role': 'attorney'},
        );
        smsSent = true;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Could not send attorney OTP via SMS (non-critical): $e');
        }
      }

      if (!otpSent && !smsSent) {
        return {
          'success': false,
          'message':
              'Failed to send verification code. Please try again (email/SMS).',
        };
      }

      // Build success message
      String message = 'Verification code sent';
      final channels = <String>[];
      if (otpSent) channels.add('email');
      if (smsSent) channels.add('SMS');
      if (fcmToken != null) channels.add('push notification');
      if (channels.isNotEmpty) {
        message += ' via ${channels.join(', ')}.';
      } else {
        message += '.';
      }
      message += ' Your account will need admin approval after verification.';

      return {
        'success': true,
        'message': message,
        'email': email,
        'otp': otp,
        'userId': userId,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error in attorneySignup: $e');
      }
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  // Verify OTP and create account
  Future<Map<String, dynamic>> verifyOtpAndCreateAccount({
    required String email,
    required String otp,
  }) async {
    try {
      // Wait a bit to ensure Firestore is ready
      await Future.delayed(const Duration(milliseconds: 200));

      // Get pending signup data with retry
      final pendingDoc = await _retryFirestoreOperation(
        () => _firestore.collection('pending_signups').doc(email).get(),
        operationName: 'Get pending signup',
      );

      if (!pendingDoc.exists) {
        return {
          'success': false,
          'message': 'No signup found for this email. Please sign up again.',
        };
      }

      final pendingData = pendingDoc.data()!;
      final storedOtp = pendingData['otp'] as String?;
      final verified = pendingData['verified'] as bool? ?? false;

      // Check if already verified
      if (verified) {
        return {
          'success': false,
          'message': 'Email already verified. Please login.',
        };
      }

      // Verify OTP
      if (storedOtp != otp) {
        return {
          'success': false,
          'message': 'Invalid verification code. Please try again.',
        };
      }

      // Check if OTP is expired (5 minutes)
      final expiresAt = pendingData['expiresAt'] as Timestamp?;
      if (expiresAt != null) {
        final expirationTime = expiresAt.toDate();
        final now = DateTime.now();
        if (now.isAfter(expirationTime.add(const Duration(minutes: 5)))) {
          return {
            'success': false,
            'message': 'Verification code has expired. Please sign up again.',
          };
        }
      }

      // OTP is valid - the Firebase Auth user was already created during signup.
      final fullName = pendingData['fullName'] as String;
      final phoneNumber = pendingData['phoneNumber'] as String;
      final address = pendingData['address'] as String;

      final pendingUserId = pendingData['userId'] as String?;
      User? user = _auth.currentUser;
      if (user == null || user.email?.toLowerCase().trim() != email.toLowerCase().trim()) {
        // If app restarted, try to sign in using the stored password (legacy field).
        final password = pendingData['password'] as String?;
        if (password != null && password.isNotEmpty) {
          try {
            final signIn = await _auth.signInWithEmailAndPassword(
              email: email,
              password: password,
            );
            user = signIn.user;
          } catch (_) {
            // Ignore; we'll fall back to pendingUserId.
          }
        }
      }

      final userId = user?.uid ?? pendingUserId;
      if (userId == null || userId.isEmpty) {
        return {
          'success': false,
          'message': 'Could not find the created account. Please login and try again.',
        };
      }

      // Get FCM token from pending signup or get current token
      String? fcmToken = pendingData['fcmToken'] as String?;
      if (fcmToken == null || fcmToken.isEmpty) {
        // Try to get current FCM token
        try {
          final fcmService = FCMService();
          fcmToken = await fcmService.getToken();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Could not get FCM token: $e');
          }
        }
      }

      // Save user to Firestore with isVerified: true (since OTP was verified)
      await _retryFirestoreOperation(
        () => _firestore.collection('users').doc(userId).set({
          'fullName': fullName,
          'name': fullName, // For compatibility
          'email': email,
          'phoneNumber': phoneNumber,
          'address': address,
          'role': 'client',
          'isVerified': true, // Email verified via OTP
          'fcmToken': fcmToken, // Save FCM token
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }),
        operationName: 'Save user to Firestore',
      );

      // Also save FCM token using FCMService to ensure it's up to date
      if (fcmToken != null) {
        try {
          final fcmService = FCMService();
          await fcmService.saveTokenForUser(userId);
          if (kDebugMode) {
            debugPrint(
              '✅ FCM token saved after account creation for user: $userId',
            );
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '⚠️ Could not save FCM token after account creation: $e',
            );
          }
        }
      }

      // Mark pending signup as verified
      await _retryFirestoreOperation(
        () => _firestore.collection('pending_signups').doc(email).update({
          'verified': true,
          'verifiedAt': FieldValue.serverTimestamp(),
        }),
        operationName: 'Mark signup as verified',
      );

      // Log signup to system logs for admin visibility
      try {
        final adminService = AdminService();
        await adminService.logAction(
          action: 'user_registered',
          resourceType: 'user',
          resourceId: userId,
          details: 'New client signup',
          metadata: {
            'email': email,
            'name': fullName,
            'role': 'client',
          },
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Failed to log user_registered action: $e');
        }
      }

      // Welcome SMS (best-effort; do not block verification completion)
      try {
        final sms = SmsService();
        await sms.queueSms(
          to: phoneNumber,
          body:
              'WELCOME ${fullName.toUpperCase()}!\n\nWELCOME TO LAW CONNECT.\nHappy to have you!!',
          userId: userId,
          meta: {'type': 'welcome', 'role': 'client'},
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Welcome SMS not queued (non-critical): $e');
        }
      }

      return {
        'success': true,
        'message': 'Email verified! Account created successfully.',
        'userId': userId,
      };
    } on FirebaseAuthException catch (e) {
      String message = 'Account creation failed';
      switch (e.code) {
        case 'email-already-in-use':
          message = 'Email is already registered';
          break;
        case 'invalid-email':
          message = 'Invalid email address';
          break;
        case 'weak-password':
          message = 'Password is too weak';
          break;
        default:
          message = e.message ?? 'Account creation failed';
      }
      return {'success': false, 'message': message};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error in verifyOtpAndCreateAccount: $e');
      }
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  // Check maintenance mode with retry
  // Returns false if check fails - this ensures login is never blocked by maintenance mode check failures
  Future<bool> _checkMaintenanceMode() async {
    try {
      return await _retryFirestoreOperation(
        () async {
          final doc = await _firestore
              .collection('system_settings')
              .doc('maintenance')
              .get();
          final mode = doc.data()?['maintenanceMode'] ?? false;
          if (kDebugMode) {
            debugPrint('🔧 Maintenance mode status: $mode');
          }
          return mode;
        },
        operationName: 'Check maintenance mode',
        maxRetries: 2, // Reduced retries to fail faster and allow login
      );
    } catch (e) {
      // CRITICAL: If we can't check, assume maintenance mode is OFF to allow access
      // This ensures admins can always login to fix maintenance mode issues
      if (kDebugMode) {
        debugPrint('⚠️ Could not check maintenance mode, assuming OFF: $e');
      }
      return false; // Always return false on error to allow login
    }
  }

  // Login for all roles
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) {
        return {'success': false, 'message': 'Login failed'};
      }

      // Wait a bit to ensure Firestore is ready
      await Future.delayed(const Duration(milliseconds: 200));

      // Get user data from Firestore with retry logic
      DocumentSnapshot? userDoc;
      int retries = 5; // Increased retries
      Exception? lastError;

      while (retries > 0) {
        try {
          userDoc = await _firestore.collection('users').doc(user.uid).get();
          if (userDoc.exists) {
            break; // Success, exit loop
          }
          // Document doesn't exist, continue to auto-setup
          break;
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          retries--;
          if (retries > 0) {
            await Future.delayed(Duration(milliseconds: 300 * (5 - retries)));
            if (kDebugMode) {
              debugPrint(
                '⚠️ Firestore read failed, retrying... ($retries left): $e',
              );
            }
          } else {
            if (kDebugMode) {
              debugPrint('❌ Firestore read failed after retries: $lastError');
            }
            // Don't return error immediately - try to continue with auto-setup
          }
        }
      }

      // If user document doesn't exist, try to auto-setup based on email
      if (userDoc == null || !userDoc.exists) {
        if (kDebugMode) {
          debugPrint('⚠️ User document not found, attempting auto-setup...');
        }

        // Import and use UserSetupService for auto-setup
        try {
          final setupService = UserSetupService();
          await setupService.autoSetupUserOnLogin(email, user.uid);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Auto-setup failed: $e');
          }
        }

        // Try to get the document again with retry
        retries = 5;
        while (retries > 0) {
          try {
            userDoc = await _firestore.collection('users').doc(user.uid).get();
            if (userDoc.exists) break;
            retries--;
            if (retries > 0) {
              await Future.delayed(Duration(milliseconds: 300 * (5 - retries)));
            }
          } catch (e) {
            retries--;
            if (retries > 0) {
              await Future.delayed(Duration(milliseconds: 300 * (5 - retries)));
            }
          }
        }

        // Also try to find by email as fallback
        if (userDoc == null || !userDoc.exists) {
          try {
            final emailQuery = await _firestore
                .collection('users')
                .where('email', isEqualTo: email)
                .limit(1)
                .get();

            if (emailQuery.docs.isNotEmpty) {
              final doc = emailQuery.docs.first;
              // Update the document to use UID as document ID
              await _firestore
                  .collection('users')
                  .doc(user.uid)
                  .set(doc.data());
              userDoc = await _firestore
                  .collection('users')
                  .doc(user.uid)
                  .get();
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ Error finding user by email: $e');
            }
          }
        }

        // If still doesn't exist, create a basic user document
        if (userDoc == null || !userDoc.exists) {
          if (kDebugMode) {
            debugPrint('⚠️ Creating basic user document...');
          }

          // Try to infer role from email or use 'client' as default
          String defaultRole = 'client';
          final emailLower = email.toLowerCase().trim();

          // Check for admin - more comprehensive check
          if (emailLower.contains('admin') ||
              emailLower.startsWith('admin@') ||
              emailLower == 'admin@gmail.com' ||
              emailLower.contains('@admin.')) {
            defaultRole = 'admin';
            if (kDebugMode) {
              debugPrint('✅ Detected admin role from email: $email');
            }
          } else if (emailLower.contains('attorney') ||
              emailLower.contains('lawyer') ||
              emailLower.contains('@attorney')) {
            defaultRole = 'attorney';
          } else if (emailLower.contains('staff') ||
              emailLower.contains('@staff')) {
            defaultRole = 'staff';
          }

          if (kDebugMode) {
            debugPrint('📝 Creating user document with role: $defaultRole');
          }

          try {
            // Use retry logic for creating user document
            await _retryFirestoreOperation(
              () => _firestore.collection('users').doc(user.uid).set({
                'email': email,
                'name': email.split('@')[0],
                'role': defaultRole,
                'isVerified':
                    defaultRole !=
                    'client', // Admin/staff/attorney don't need verification
                'createdAt': FieldValue.serverTimestamp(),
              }),
              operationName: 'Create user document',
              maxRetries: 5,
            );

            // Try to get the document again with retry
            int retries = 5;
            while (retries > 0) {
              try {
                userDoc = await _firestore
                    .collection('users')
                    .doc(user.uid)
                    .get();
                if (userDoc.exists) break;
                retries--;
                if (retries > 0) {
                  await Future.delayed(
                    Duration(milliseconds: 300 * (5 - retries)),
                  );
                }
              } catch (e) {
                retries--;
                if (retries > 0) {
                  await Future.delayed(
                    Duration(milliseconds: 300 * (5 - retries)),
                  );
                }
              }
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('❌ Failed to create user document: $e');
            }
            // Don't return error immediately - try to continue with existing user data
            // This allows login even if document creation fails temporarily
            if (kDebugMode) {
              debugPrint(
                '⚠️ Continuing login despite document creation failure',
              );
            }
          }
        }
      }

      // Final check - if userDoc still doesn't exist, create minimal document
      if (userDoc == null || !userDoc.exists) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ User document still missing, creating minimal document...',
          );
        }

        // Determine role from email
        String defaultRole = 'client';
        final emailLower = email.toLowerCase();
        if (emailLower.contains('admin') || emailLower == 'admin@gmail.com') {
          defaultRole = 'admin';
        } else if (emailLower.contains('staff') || emailLower == 'staff@gmail.com') {
          defaultRole = 'staff';
        }

        try {
          await _retryFirestoreOperation(
            () => _firestore.collection('users').doc(user.uid).set({
              'email': email,
              'name': email.split('@')[0],
              'role': defaultRole,
              'isVerified': defaultRole != 'client',
              'createdAt': FieldValue.serverTimestamp(),
            }),
            operationName: 'Create minimal user document',
            maxRetries: 3,
          );

          // Get the document one more time
          userDoc = await _firestore.collection('users').doc(user.uid).get();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ Final attempt to create user document failed: $e');
          }
          // Create a temporary user data object to allow login
          // This prevents blocking admin login due to Firestore issues
          final tempUserData = {
            'email': email,
            'name': email.split('@')[0],
            'role': defaultRole,
            'isVerified': defaultRole != 'client',
          };

          // Use temp data to allow login to proceed
          final role = tempUserData['role'] as String;

          if (kDebugMode) {
            debugPrint('⚠️ Using temporary user data for login');
            debugPrint('✅ Role: $role');
          }

          return {
            'success': true,
            'user': UserModel.fromFirestore(tempUserData, user.uid),
            'role': role,
          };
        }
      }

      final userData = userDoc.data() as Map<String, dynamic>?;
      if (userData == null) {
        // If userData is null but we have user.uid, create minimal data
        final emailLower = email.toLowerCase().trim();
        String defaultRole = 'client';
        if (emailLower.contains('admin') ||
            emailLower.startsWith('admin@') ||
            emailLower == 'admin@gmail.com' ||
            emailLower.contains('@admin.')) {
          defaultRole = 'admin';
        } else if (emailLower.contains('staff') ||
            emailLower.startsWith('staff@') ||
            emailLower == 'staff@gmail.com') {
          defaultRole = 'staff';
        }

        final tempUserData = {
          'email': email,
          'name': email.split('@')[0],
          'role': defaultRole,
          'isVerified': defaultRole != 'client',
        };

        return {
          'success': true,
          'user': UserModel.fromFirestore(tempUserData, user.uid),
          'role': defaultRole,
        };
      }
      var userDataMap = Map<String, dynamic>.from(userData);
      final staffSync = await syncStaffRoleFromStaffApplication(
        uid: user.uid,
        email: email,
      );
      if (staffSync != null) {
        userDataMap.addAll(staffSync);
      }
      final role = userDataMap['role'] ?? 'client';
      final isVerified = userDataMap['isVerified'] ?? false;

      // IMPORTANT: Override role and verification for staff/admin/attorney emails
      // This ensures they can always login even if Firestore has wrong data
      final emailLower = email.toLowerCase().trim();
      String finalRole = role;
      bool finalIsVerified = isVerified;
      
      // Check for staff email - prioritize exact match
      if (emailLower == 'staff@gmail.com') {
        finalRole = 'staff';
        finalIsVerified = true;
        if (kDebugMode) {
          debugPrint('✅ Overriding role to staff based on exact email match: $email');
        }
      } else if (emailLower.contains('staff@') || 
          (emailLower.startsWith('staff') && emailLower.contains('@'))) {
        finalRole = 'staff';
        finalIsVerified = true;
        if (kDebugMode) {
          debugPrint('✅ Overriding role to staff based on email pattern: $email');
        }
      } else if (emailLower.contains('admin') ||
          emailLower.startsWith('admin@') ||
          emailLower == 'admin@gmail.com' ||
          emailLower.contains('@admin.')) {
        finalRole = 'admin';
        finalIsVerified = true;
      } else if (emailLower.contains('attorney') ||
          emailLower.contains('lawyer') ||
          emailLower.contains('@attorney')) {
        finalRole = 'attorney';
        finalIsVerified = true;
      }

      // If the user already completed Firebase's email verification link but
      // Firestore still has isVerified: false (sync bug / old data), align DB and allow login.
      try {
        await user.reload();
        final reloaded = _auth.currentUser;
        if (reloaded != null &&
            reloaded.emailVerified &&
            finalRole.toLowerCase() == 'client' &&
            !finalIsVerified) {
          await _firestore.collection('users').doc(reloaded.uid).update({
            'isVerified': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          finalIsVerified = true;
          if (kDebugMode) {
            debugPrint(
              '✅ Synced Firestore isVerified from Firebase Auth emailVerified',
            );
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Verification sync skipped: $e');
        }
      }

      if (kDebugMode) {
        debugPrint('✅ Login successful for: $email');
        debugPrint('✅ Role: $finalRole (original: $role)');
        debugPrint('✅ Is Verified: $finalIsVerified (original: $isVerified)');
      }

      // Check maintenance mode - only admins can login during maintenance
      // IMPORTANT: Always allow admins to login, even during maintenance
      // This ensures admins can always access the system to disable maintenance mode
      try {
        final isMaintenanceMode = await _checkMaintenanceMode();
        if (isMaintenanceMode) {
          // Check if user is admin - allow admins to always login
          final isAdmin = finalRole.toLowerCase() == 'admin';

          if (kDebugMode) {
            debugPrint(
              '🔧 Maintenance mode: $isMaintenanceMode, User role: $finalRole, Is Admin: $isAdmin',
            );
          }

          // Only block non-admin users during maintenance
          if (!isAdmin) {
            await _auth.signOut();
            return {
              'success': false,
              'message':
                  'System is under maintenance. Only administrators can access at this time.',
            };
          } else {
            // Admin can always login, even during maintenance
            if (kDebugMode) {
              debugPrint('✅ Admin login allowed during maintenance mode');
            }
          }
        }
      } catch (e) {
        // If maintenance mode check fails, ALWAYS allow login to proceed
        // This ensures admins can always login even if Firestore has issues
        if (kDebugMode) {
          debugPrint('⚠️ Maintenance mode check failed, allowing login: $e');
        }
        // Continue with login - don't block if we can't check maintenance mode
        // This is critical - we must allow login if check fails
      }

      // Block client login if not verified
      // Admin, Attorney, and Staff don't need verification (they are created by admin)
      // Only require verification for client role
      final rolesThatDontNeedVerification = ['admin', 'attorney', 'staff'];
      final needsVerification = !rolesThatDontNeedVerification.contains(finalRole.toLowerCase());
      
      if (needsVerification && !finalIsVerified) {
        // Keep the session: OTP / verification screens need currentUser.
        // Login UI treats success + needsVerification → verification flow (not a red error).
        final pendingUserData = Map<String, dynamic>.from(userDataMap);
        pendingUserData['role'] = finalRole;
        pendingUserData['isVerified'] = finalIsVerified;
        return {
          'success': true,
          'needsVerification': true,
          'role': finalRole,
          'message':
              'Please verify your email to continue. Check your inbox or complete verification on the next screen.',
          'user': UserModel.fromFirestore(pendingUserData, user.uid),
        };
      }

      // Save FCM token after successful login
      try {
        final fcmService = FCMService();
        await fcmService.saveTokenForUser(user.uid);
        if (kDebugMode) {
          debugPrint('✅ FCM token saved after login for user: ${user.uid}');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Could not save FCM token after login: $e');
        }
        // Don't fail login if FCM token save fails
      }

      // Log login action to system logs (for all roles)
      try {
        final adminService = AdminService();
        await adminService.logAction(
          action: 'login',
          resourceType: 'user',
          resourceId: user.uid,
          details: 'Role: $role',
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Failed to log login action: $e');
        }
      }

      // Update userData with final role and isVerified for consistency
      final updatedUserData = Map<String, dynamic>.from(userDataMap);
      updatedUserData['role'] = finalRole;
      updatedUserData['isVerified'] = finalIsVerified;
      
      return {
        'success': true,
        'user': UserModel.fromFirestore(updatedUserData, user.uid),
        'role': finalRole,
      };
    } on FirebaseAuthException catch (e) {
      String message = 'Login failed';
      switch (e.code) {
        case 'user-not-found':
          message = 'No user found with this email';
          break;
        case 'wrong-password':
          message = 'Incorrect password';
          break;
        case 'invalid-email':
          message = 'Invalid email address';
          break;
        case 'user-disabled':
          message = 'This account has been disabled';
          break;
        default:
          message = e.message ?? 'Login failed';
      }
      return {'success': false, 'message': message};
    } catch (e) {
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  // Verify OTP and create attorney account
  Future<Map<String, dynamic>> verifyOtpAndCreateAttorneyAccount({
    required String email,
    required String otp,
  }) async {
    try {
      // Wait a bit to ensure Firestore is ready
      await Future.delayed(const Duration(milliseconds: 200));

      // Get pending signup data with retry
      final pendingDoc = await _retryFirestoreOperation(
        () => _firestore.collection('pending_signups').doc(email).get(),
        operationName: 'Get pending attorney signup',
      );

      if (!pendingDoc.exists) {
        return {
          'success': false,
          'message': 'No signup found for this email. Please sign up again.',
        };
      }

      final pendingData = pendingDoc.data()!;
      final storedOtp = pendingData['otp'] as String?;
      final verified = pendingData['verified'] as bool? ?? false;
      final role = pendingData['role'] as String?;

      // Verify it's an attorney signup
      if (role != 'attorney') {
        return {
          'success': false,
          'message': 'Invalid signup type. Please use the correct signup flow.',
        };
      }

      // Check if already verified
      if (verified) {
        return {
          'success': false,
          'message': 'Email already verified. Please login.',
        };
      }

      // Verify OTP
      if (storedOtp != otp) {
        return {
          'success': false,
          'message': 'Invalid verification code. Please try again.',
        };
      }

      // Check if OTP is expired (5 minutes)
      final expiresAt = pendingData['expiresAt'] as Timestamp?;
      if (expiresAt != null) {
        final expirationTime = expiresAt.toDate();
        final now = DateTime.now();
        if (now.isAfter(expirationTime.add(const Duration(minutes: 5)))) {
          return {
            'success': false,
            'message': 'Verification code has expired. Please sign up again.',
          };
        }
      }

      // OTP is valid - the Firebase Auth user was already created during signup.
      final fullName = pendingData['fullName'] as String;
      final phoneNumber = pendingData['phoneNumber'] as String;
      final address = pendingData['address'] as String;
      final specialization =
          pendingData['specialization'] as List<dynamic>? ?? [];
      final barNumber = pendingData['barNumber'] as String?;
      final licenseState = pendingData['licenseState'] as String?;
      final licenseDocumentUrl = pendingData['licenseDocumentUrl'] as String?;

      final pendingUserId = pendingData['userId'] as String?;
      User? user = _auth.currentUser;
      if (user == null || user.email?.toLowerCase().trim() != email.toLowerCase().trim()) {
        final password = pendingData['password'] as String?;
        if (password != null && password.isNotEmpty) {
          try {
            final signIn = await _auth.signInWithEmailAndPassword(
              email: email,
              password: password,
            );
            user = signIn.user;
          } catch (_) {}
        }
      }

      final userId = user?.uid ?? pendingUserId;
      if (userId == null || userId.isEmpty) {
        return {
          'success': false,
          'message': 'Could not find the created account. Please login and try again.',
        };
      }

      // Get FCM token from pending signup or get current token
      String? fcmToken = pendingData['fcmToken'] as String?;
      if (fcmToken == null || fcmToken.isEmpty) {
        try {
          final fcmService = FCMService();
          fcmToken = await fcmService.getToken();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Could not get FCM token: $e');
          }
        }
      }

      // Save attorney to Firestore with isVerified: true but isActive: false
      await _retryFirestoreOperation(
        () => _firestore.collection('users').doc(userId).set({
          'fullName': fullName,
          'name': fullName,
          'email': email,
          'phoneNumber': phoneNumber,
          'address': address,
          'role': 'attorney',
          'isVerified': true, // Email verified via OTP
          'isActive': false, // Needs admin approval
          'isAvailable': true, // Default to available
          'pendingApproval': true, // Needs admin approval
          'specialization': specialization.map((s) => s.toString()).toList(),
          'barNumber': barNumber,
          'licenseState': licenseState,
          'licenseDocumentUrl': licenseDocumentUrl,
          'ratingAverage': 0.0,
          'fcmToken': fcmToken,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        }),
        operationName: 'Save attorney to Firestore',
      );

      // Also save FCM token using FCMService
      if (fcmToken != null) {
        try {
          final fcmService = FCMService();
          await fcmService.saveTokenForUser(userId);
          if (kDebugMode) {
            debugPrint(
              '✅ FCM token saved after attorney account creation for user: $userId',
            );
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '⚠️ Could not save FCM token after attorney account creation: $e',
            );
          }
        }
      }

      // Mark pending signup as verified
      await _retryFirestoreOperation(
        () => _firestore.collection('pending_signups').doc(email).update({
          'verified': true,
          'verifiedAt': FieldValue.serverTimestamp(),
        }),
        operationName: 'Mark attorney signup as verified',
      );

      // Notify all admins about new attorney signup
      await _notifyAdminsOfNewAttorneySignup(userId, fullName, email);

      return {
        'success': true,
        'message':
            'Email verified! Your account is pending admin approval. You will be notified when your account is activated.',
        'userId': userId,
      };
    } on FirebaseAuthException catch (e) {
      String message = 'Attorney account creation failed';
      switch (e.code) {
        case 'email-already-in-use':
          message = 'Email is already registered';
          break;
        case 'invalid-email':
          message = 'Invalid email address';
          break;
        case 'weak-password':
          message = 'Password is too weak';
          break;
        default:
          message = e.message ?? 'Attorney account creation failed';
      }
      return {'success': false, 'message': message};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error in verifyOtpAndCreateAttorneyAccount: $e');
      }
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  // Notify all admins about new attorney signup
  Future<void> _notifyAdminsOfNewAttorneySignup(
    String attorneyId,
    String attorneyName,
    String attorneyEmail,
  ) async {
    try {
      // Get all admin users
      final adminsSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();

      if (kDebugMode) {
        debugPrint(
          '📢 Notifying ${adminsSnapshot.docs.length} admins about new attorney signup',
        );
      }

      final fcmService = FCMService();

      // Send notification to each admin
      for (final adminDoc in adminsSnapshot.docs) {
        final adminId = adminDoc.id;
        try {
          await fcmService.sendNotificationToUser(
            userId: adminId,
            title: 'New Attorney Signup',
            body:
                '$attorneyName ($attorneyEmail) has signed up and needs approval.',
            data: {
              'type': 'new_attorney_signup',
              'attorneyId': attorneyId,
              'attorneyName': attorneyName,
              'attorneyEmail': attorneyEmail,
            },
          );

          // Also create a notification in Firestore
          await _firestore.collection('notifications').add({
            'userId': adminId,
            'title': 'New Attorney Signup',
            'message':
                '$attorneyName ($attorneyEmail) has signed up and needs approval.',
            'type': 'new_attorney_signup',
            'data': {
              'attorneyId': attorneyId,
              'attorneyName': attorneyName,
              'attorneyEmail': attorneyEmail,
            },
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Could not notify admin $adminId: $e');
          }
        }
      }

      if (kDebugMode) {
        debugPrint(
          '✅ Admin notifications sent for new attorney: $attorneyName',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error notifying admins: $e');
      }
      // Don't fail the signup if notification fails
    }
  }

  // Check email verification status
  Future<bool> checkEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    // Reload user to get latest verification status
    await user.reload();
    final reloadedUser = _auth.currentUser;

    return reloadedUser?.emailVerified ?? false;
  }

  // Resend verification email
  Future<Map<String, dynamic>> resendVerificationEmail() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'No user logged in'};
      }

      // Check if email is already verified
      await user.reload();
      if (user.emailVerified) {
        return {'success': false, 'message': 'Email is already verified'};
      }

      final last = _lastFirebaseVerificationEmailSentAt;
      if (last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 60)) {
        return {
          'success': false,
          'message': 'Please wait a minute before requesting another email.',
        };
      }

      final actionCodeSettings = ActionCodeSettings(
        url: 'https://jurislink-app.firebaseapp.com/',
        handleCodeInApp: false,
      );

      await user.sendEmailVerification(actionCodeSettings);
      _lastFirebaseVerificationEmailSentAt = DateTime.now();

      return {
        'success': true,
        'message': 'We sent one verification email. Please check your inbox.',
      };
    } on FirebaseAuthException catch (e) {
      String message = 'Failed to send verification email';
      if (e.code == 'too-many-requests') {
        message =
            'Too many requests. Please wait a few minutes before requesting another email.';
      } else if (e.code == 'user-not-found') {
        message = 'User not found. Please try logging in again.';
      } else {
        message = e.message ?? 'Failed to send verification email';
      }
      return {'success': false, 'message': message};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to send verification email: $e',
      };
    }
  }

  // Logout
  Future<void> logout() async {
    await _auth.signOut();
  }

  // Get user data from Firestore
  Future<UserModel?> getUserData(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        return UserModel.fromFirestore(userDoc.data()!, userId);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Send OTP code via email for verification
  Future<Map<String, dynamic>> sendVerificationOtp({
    required String email,
    String? name,
  }) async {
    try {
      final emailOtpService = EmailOtpService();

      // Generate 6-digit OTP
      final otp = EmailOtpService.generateOtp();

      // Check if this is for a pending signup
      final pendingSignup = await _firestore
          .collection('pending_signups')
          .doc(email)
          .get();

      if (pendingSignup.exists) {
        // Update OTP in pending_signups
        await _firestore.collection('pending_signups').doc(email).update({
          'otp': otp,
          'expiresAt': FieldValue.serverTimestamp(),
          'verified': false,
        });
      } else {
        // Store OTP in email_verification_otps collection (for other use cases)
        await _firestore.collection('email_verification_otps').doc(email).set({
          'email': email,
          'otp': otp,
          'expiresAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'used': false,
        }, SetOptions(merge: true));
      }

      // Send OTP via email
      final success = await emailOtpService.sendOtp(
        email: email,
        otp: otp,
        name: name,
      );

      // Also send OTP via real SMS if we have a pending signup with phoneNumber and a logged-in user
      bool smsSent = false;
      try {
        final pending = await _firestore.collection('pending_signups').doc(email).get();
        final phone = pending.data()?['phoneNumber'] as String?;
        final userId = pending.data()?['userId'] as String?;
        if (phone != null && phone.trim().isNotEmpty && userId != null && userId.isNotEmpty) {
          final sms = SmsService();
          await sms.queueSms(
            to: phone,
            body:
                'Law Connect verification code: $otp\n\nDo not share this code with anyone.',
            userId: userId,
            meta: {'type': 'otp', 'channel': 'sms', 'reason': 'resend'},
          );
          smsSent = true;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Resend OTP via SMS failed (non-critical): $e');
        }
      }

      if (success || smsSent) {
        return {
          'success': true,
          'message': smsSent
              ? 'Verification code sent to your email and SMS.'
              : 'Verification code sent to your email. Please check your inbox.',
          'otp': otp, // Include OTP for display in mobile app
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to send verification code. Please try again.',
        };
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error sending verification OTP: $e');
      }
      return {
        'success': false,
        'message': 'Failed to send verification code: $e',
      };
    }
  }

  // Verify OTP code
  Future<Map<String, dynamic>> verifyOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final otpDoc = await _firestore
          .collection('email_verification_otps')
          .doc(email)
          .get();

      if (!otpDoc.exists) {
        return {
          'success': false,
          'message': 'No verification code found. Please request a new one.',
        };
      }

      final data = otpDoc.data()!;
      final storedOtp = data['otp'] as String?;
      final used = data['used'] as bool? ?? false;
      final expiresAt = data['expiresAt'] as Timestamp?;

      // Check if OTP was already used
      if (used) {
        return {
          'success': false,
          'message': 'This verification code has already been used.',
        };
      }

      // Check if OTP is expired (5 minutes)
      if (expiresAt != null) {
        final expirationTime = expiresAt.toDate();
        final now = DateTime.now();
        if (now.isAfter(expirationTime.add(const Duration(minutes: 5)))) {
          return {
            'success': false,
            'message':
                'Verification code has expired. Please request a new one.',
          };
        }
      }

      // Verify OTP
      if (storedOtp != otp) {
        return {
          'success': false,
          'message': 'Invalid verification code. Please try again.',
        };
      }

      // Mark OTP as used
      await _firestore.collection('email_verification_otps').doc(email).update({
        'used': true,
        'verifiedAt': FieldValue.serverTimestamp(),
      });

      return {'success': true, 'message': 'Email verified successfully!'};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error verifying OTP: $e');
      }
      return {'success': false, 'message': 'Failed to verify code: $e'};
    }
  }
}
