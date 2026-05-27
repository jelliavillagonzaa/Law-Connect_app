import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/otp_input_field.dart';
import '../attorney/attorney_dashboard.dart';
import '../admin/admin_dashboard.dart';
import '../staff/staff_dashboard.dart';
import '../../screens/client/dashboard_screen_with_nav.dart';

class OtpVerificationPage extends StatefulWidget {
  const OtpVerificationPage({super.key});

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  bool _isChecking = false;
  bool _isResending = false;
  bool _isSendingCode = false;
  bool _isOtpSubmitting = false;
  String? _userEmail;
  String? _userDisplayName;
  String _enteredOtp = '';

  @override
  void initState() {
    super.initState();
    _loadUserEmailAndName();
    _checkStaffAndRedirect();
  }
  
  // Auto-redirect staff/admin/attorney to their dashboard - they don't need email verification
  Future<void> _checkStaffAndRedirect() async {
    final user = _authService.currentUser;
    if (user == null) return;
    
    try {
      final role = await _firestoreService.getUserRole(user.uid);
      
      // Staff, admin, and attorney should not be on verification page - redirect them immediately
      if (role == 'staff') {
        // Redirect immediately without delay
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Get.offAll(() => const StaffDashboard());
          }
        });
      } else if (role == 'admin') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Get.offAll(() => const AdminDashboard());
          }
        });
      } else if (role == 'attorney') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Get.offAll(() => const AttorneyDashboard());
          }
        });
      }
    } catch (e) {
      // Error getting role - continue normally
    }
  }

  Future<void> _loadUserEmailAndName() async {
    final user = _authService.currentUser;
    if (user == null) return;
    final data = await _authService.getUserData(user.uid);
    if (!mounted) return;
    setState(() {
      _userEmail = user.email;
      _userDisplayName = data?.name;
    });
  }

  Future<void> _sendOtpToEmail() async {
    final user = _authService.currentUser;
    if (user?.email == null) {
      Get.snackbar(
        'Error',
        'No user logged in',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _isSendingCode = true);
    try {
      final result = await _authService.sendVerificationOtp(
        email: user!.email!,
        name: _userDisplayName,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        Get.snackbar(
          'Code sent',
          result['message'] ??
              'Check your email for the 6-digit code.',
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
      } else {
        Get.snackbar(
          'Could not send',
          result['message'] ?? 'Try again later.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  Future<void> _verifyOtpAndContinue() async {
    if (_isOtpSubmitting) return;
    final user = _authService.currentUser;
    if (user?.email == null) return;

    final otp = _enteredOtp.trim();
    if (otp.length != 6) {
      Get.snackbar(
        'Code',
        'Enter the 6-digit code from your email.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _isOtpSubmitting = true);
    try {
      final otpResult = await _authService.verifyOtp(
        email: user!.email!,
        otp: otp,
      );
      if (!mounted) return;
      if (otpResult['success'] != true) {
        Get.snackbar(
          'Verification',
          otpResult['message'] ?? 'Invalid code',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      await _firestoreService.updateUserVerification(user.uid, true);

      final role = await _firestoreService.getUserRole(user.uid);
      if (!mounted) return;

      Get.snackbar(
        'Success',
        'Email verified with your code. Welcome!',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
      _goToDashboardForRole(role);
    } catch (e) {
      if (mounted) {
        Get.snackbar(
          'Error',
          'Verification failed: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } finally {
      if (mounted) setState(() => _isOtpSubmitting = false);
    }
  }

  void _goToDashboardForRole(String? role) {
    if (role == 'admin') {
      Get.offAll(() => const AdminDashboard());
    } else if (role == 'attorney') {
      Get.offAll(() => const AttorneyDashboard());
    } else if (role == 'staff') {
      Get.offAll(() => const StaffDashboard());
    } else {
      Get.offAll(() => const DashboardScreenWithNav());
    }
  }
  
  Future<String?> _getUserRole() async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        return await _firestoreService.getUserRole(user.uid);
      }
    } catch (e) {
      // Error getting role
    }
    return null;
  }

  Future<void> _checkVerificationStatus() async {
    final user = _authService.currentUser;
    if (user == null) {
      Get.snackbar(
        'Error',
        'No user logged in',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    setState(() {
      _isChecking = true;
    });

    try {
      // Firebase link flow sets emailVerified; OTP flow sets Firestore isVerified only.
      final firebaseVerified = await _authService.checkEmailVerification();
      final firestoreVerified =
          await _firestoreService.getUserVerificationStatus(user.uid);

      if (firebaseVerified || firestoreVerified) {
        if (firebaseVerified) {
          await _firestoreService.updateUserVerification(user.uid, true);
        }

        final role = await _firestoreService.getUserRole(user.uid);

        Get.snackbar(
          'Success',
          'Email verified successfully!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );

        _goToDashboardForRole(role);
      } else {
        Get.snackbar(
          'Not Verified',
          'Use “Send code” and enter the OTP, or open the link in your email.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to check verification status: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      setState(() {
        _isChecking = false;
      });
    }
  }

  Future<void> _resendVerificationEmail() async {
    setState(() {
      _isResending = true;
    });

    try {
      final result = await _authService.resendVerificationEmail();
      
      if (result['success'] == true) {
        Get.snackbar(
          'Success',
          result['message'] ?? 'Verification email sent',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      } else {
        Get.snackbar(
          'Error',
          result['message'] ?? 'Failed to resend email',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to resend verification email: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      setState(() {
        _isResending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Verification'),
      ),
      body: Container(
        color: AppTheme.lightGray,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                // Orange banner for not verified status
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Please verify your email. Use the 6-digit code below, or open the link in the email we sent.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // Email icon with checkmark
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppTheme.royalBlue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(
                        Icons.email,
                        size: 80,
                        color: AppTheme.royalBlue,
                      ),
                      Positioned(
                        bottom: 15,
                        right: 15,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppTheme.royalBlue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Title
                Text(
                  'Verify Your Email',
                  textAlign: TextAlign.center,
                  style: AppTheme.cardTitleStyle.copyWith(
                    fontSize: 28,
                  ),
                ),
                const SizedBox(height: 16),
                // Instruction text
                Text(
                  'Verification for:',
                  textAlign: TextAlign.center,
                  style: AppTheme.cardDetailStyle.copyWith(
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                // Email address (clickable - opens Gmail)
                if (_userEmail != null)
                  GestureDetector(
                    onTap: () async {
                      // Open Gmail app or web
                      final gmailUrl = Uri.parse('https://mail.google.com/mail/u/0/#inbox');
                      final gmailAppUrl = Uri.parse('googlegmail://');
                      
                      try {
                        // Try to open Gmail app first
                        if (await canLaunchUrl(gmailAppUrl)) {
                          await launchUrl(gmailAppUrl);
                        } else if (await canLaunchUrl(gmailUrl)) {
                          // Fallback to Gmail web
                          await launchUrl(gmailUrl, mode: LaunchMode.externalApplication);
                        } else {
                          Get.snackbar(
                            'Info',
                            'Please open your email app manually',
                            backgroundColor: AppTheme.royalBlue,
                            colorText: Colors.white,
                          );
                        }
                      } catch (e) {
                        Get.snackbar(
                          'Error',
                          'Could not open email app: $e',
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _userEmail!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.royalBlue,
                          decoration: TextDecoration.underline,
                          decorationColor: AppTheme.royalBlue,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 28),
                // OTP verification (primary path)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.cleanWhite,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.pin_outlined,
                            color: AppTheme.royalBlue,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Verify with code (OTP)',
                            style: AppTheme.cardTitleStyle.copyWith(
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap “Send code” to get a 6-digit code by email, then enter it below.',
                        style: AppTheme.cardDetailStyle.copyWith(fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _isSendingCode ? null : _sendOtpToEmail,
                          icon: _isSendingCode
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.outgoing_mail, size: 20),
                          label: Text(
                            _isSendingCode ? 'Sending…' : 'Send code to email',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.royalBlue,
                            side: const BorderSide(color: AppTheme.royalBlue),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      OtpInputField(
                        onChanged: (value) {
                          setState(() => _enteredOtp = value);
                        },
                        onCompleted: (otp) {
                          setState(() => _enteredOtp = otp);
                          _verifyOtpAndContinue();
                        },
                      ),
                      const SizedBox(height: 20),
                      AppButton(
                        text: 'Verify with code',
                        onPressed: (_isOtpSubmitting || _enteredOtp.length != 6)
                            ? null
                            : _verifyOtpAndContinue,
                        isLoading: _isOtpSubmitting,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Or use the email link',
                  textAlign: TextAlign.center,
                  style: AppTheme.cardDetailStyle.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                // Link-based instructions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cleanWhite,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Open the verification email and tap the link, then tap “Check verification status”.',
                        textAlign: TextAlign.center,
                        style: AppTheme.cardDetailStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Primary button
                AppButton(
                  text: 'Check Verification Status',
                  onPressed: _checkVerificationStatus,
                  isLoading: _isChecking,
                ),
                const SizedBox(height: 16),
                // Resend button
                TextButton(
                  onPressed: _isResending ? null : _resendVerificationEmail,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.royalBlue,
                  ),
                  child: _isResending
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Resend Verification Email',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                // Skip to dashboard button for staff/admin/attorney
                FutureBuilder<String?>(
                  future: _getUserRole(),
                  builder: (context, snapshot) {
                    final role = snapshot.data;
                    if (role == 'staff' || role == 'admin' || role == 'attorney') {
                      return Column(
                        children: [
                          TextButton(
                            onPressed: () {
                              if (role == 'staff') {
                                Get.offAll(() => const StaffDashboard());
                              } else if (role == 'admin') {
                                Get.offAll(() => const AdminDashboard());
                              } else if (role == 'attorney') {
                                Get.offAll(() => const AttorneyDashboard());
                              }
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.royalBlue,
                            ),
                            child: const Text(
                              'Go to Dashboard',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                // Back to login
                TextButton(
                  onPressed: () async {
                    await _authService.logout();
                    Get.back();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.royalBlue,
                  ),
                  child: const Text(
                    'Back to Login',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

