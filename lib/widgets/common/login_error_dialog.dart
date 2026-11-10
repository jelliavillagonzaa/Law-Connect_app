import 'dart:ui';
import 'package:flutter/material.dart';

/// Structured, user-friendly login error details for display in UI dialogs and notices.
class LoginErrorInfo {
  final String title;
  final String message;
  final IconData icon;
  final bool isCredentialError;
  final bool isNetworkError;

  const LoginErrorInfo({
    required this.title,
    required this.message,
    required this.icon,
    this.isCredentialError = false,
    this.isNetworkError = false,
  });
}

/// Helper to sanitize any raw exception/error string and extract
/// clean, friendly, professional login error information.
///
/// Ensures raw technical dumps like `[cloud_firestore/permission-denied]`,
/// `firebase_auth/...`, stack traces, or internal error messages NEVER leak
/// to the end user on mobile or web.
class LoginErrorHelper {
  static LoginErrorInfo parse(dynamic raw) {
    if (raw == null) {
      return const LoginErrorInfo(
        title: 'Login Failed',
        message: 'Invalid email or password. Please verify your credentials and try again.',
        icon: Icons.lock_person_outlined,
        isCredentialError: true,
      );
    }

    final str = raw.toString().trim();
    final lower = str.toLowerCase();

    // 1. Invalid credential / wrong password / user not found
    if (lower.contains('invalid-credential') ||
        lower.contains('invalid_login_credentials') ||
        lower.contains('wrong-password') ||
        lower.contains('incorrect password') ||
        lower.contains('auth credential is incorrect') ||
        lower.contains('invalid email or password')) {
      return const LoginErrorInfo(
        title: 'Incorrect Credentials',
        message: 'The email or password you entered is incorrect. Please double-check your credentials and try again.',
        icon: Icons.lock_outline_rounded,
        isCredentialError: true,
      );
    }

    if (lower.contains('user-not-found') ||
        lower.contains('no user found') ||
        lower.contains('no account found')) {
      return const LoginErrorInfo(
        title: 'Account Not Found',
        message: 'No account was found with this email address. Please check your spelling or sign up.',
        icon: Icons.person_search_outlined,
        isCredentialError: true,
      );
    }

    // 2. Invalid email format
    if (lower.contains('invalid-email') || lower.contains('badly formatted')) {
      return const LoginErrorInfo(
        title: 'Invalid Email',
        message: 'Please enter a valid email address format (e.g. name@domain.com).',
        icon: Icons.alternate_email_rounded,
        isCredentialError: true,
      );
    }

    // 3. User account disabled / suspended
    if (lower.contains('user-disabled') || lower.contains('account has been disabled')) {
      return const LoginErrorInfo(
        title: 'Account Deactivated',
        message: 'This account has been disabled. Please contact your system administrator or support.',
        icon: Icons.block_flipped,
      );
    }

    // 4. Rate limiting / too many failed attempts
    if (lower.contains('too-many-requests') ||
        lower.contains('too many login attempts') ||
        lower.contains('too many attempts') ||
        lower.contains('15 minutes')) {
      return const LoginErrorInfo(
        title: 'Too Many Attempts',
        message: 'For security, sign-in has been temporarily paused due to several failed attempts. Please wait a few minutes before trying again.',
        icon: Icons.timer_outlined,
      );
    }

    // 5. Network, connection, or timeout issues
    if (lower.contains('network-request-failed') ||
        lower.contains('network_error') ||
        lower.contains('socketexception') ||
        lower.contains('client is offline') ||
        lower.contains('connection timed out') ||
        lower.contains('timeout') ||
        lower.contains('unavailable')) {
      return const LoginErrorInfo(
        title: 'Connection Issue',
        message: 'Unable to reach the server. Please check your internet connection and try again.',
        icon: Icons.wifi_off_rounded,
        isNetworkError: true,
      );
    }

    // 6. Maintenance mode
    if (lower.contains('maintenance')) {
      return const LoginErrorInfo(
        title: 'System Maintenance',
        message: 'The system is currently undergoing scheduled maintenance. Only administrators can sign in at this time.',
        icon: Icons.engineering_outlined,
      );
    }

    // 7. Staff application approval / activation
    if (lower.contains('staff application') ||
        lower.contains('waiting for administrator approval') ||
        lower.contains('not enabled for sign-in') ||
        lower.contains('pending admin')) {
      return const LoginErrorInfo(
        title: 'Application Pending',
        message: 'Your staff application is awaiting administrator approval and activation before you can sign in.',
        icon: Icons.badge_outlined,
      );
    }

    // 8. Email verification required
    if (lower.contains('verify your email') || lower.contains('verification required')) {
      return const LoginErrorInfo(
        title: 'Verification Required',
        message: 'Please complete your email verification before accessing the system.',
        icon: Icons.mark_email_unread_outlined,
      );
    }

    // 9. Raw Firestore or internal database exceptions (CATCH-ALL FOR FIRESTORE)
    if (lower.contains('firestore') ||
        lower.contains('permission-denied') ||
        lower.contains('permission denied') ||
        lower.contains('cloud_firestore') ||
        lower.contains('firebaseexception') ||
        lower.contains('platformexception') ||
        lower.contains('unexpected error') ||
        lower.contains('internal-error')) {
      return const LoginErrorInfo(
        title: 'Unable to Sign In',
        message: 'We could not complete your sign-in at this moment. Please check your connection and try again.',
        icon: Icons.error_outline_rounded,
      );
    }

    // If message is clean, human-readable and doesn't contain technical garbage
    if (!lower.contains('exception') &&
        !lower.contains('[') &&
        !lower.contains('{') &&
        !lower.contains('at ') &&
        str.length <= 160) {
      return LoginErrorInfo(
        title: 'Login Failed',
        message: str,
        icon: Icons.lock_person_outlined,
      );
    }

    // Generic fallback
    return const LoginErrorInfo(
      title: 'Login Failed',
      message: 'Invalid email or password. Please verify your credentials and try again.',
      icon: Icons.lock_person_outlined,
      isCredentialError: true,
    );
  }

  /// Sanitized single-line message for snackbars or simple text fields.
  static String sanitize(dynamic raw) {
    return parse(raw).message;
  }
}

/// A modern, high-end login error popup dialog designed for both App and Web.
///
/// Features:
/// - Luxury dark navy & gold legal portal styling matching Law Connect
/// - Soft crimson warning badge with glowing ring
/// - Perfectly centered and responsive on all screen sizes (mobile phones to 4K web)
/// - Integrated "Forgot password?" shortcut for credential errors
/// - Crisp, professional typography without technical jargon
Future<void> showLoginErrorDialog(
  BuildContext context, {
  required dynamic message,
  VoidCallback? onForgotPassword,
  VoidCallback? onRetry,
}) async {
  if (!context.mounted) return;

  final info = LoginErrorHelper.parse(message);

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.65),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, anim1, anim2) {
      return const SizedBox.shrink();
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curvedValue = Curves.easeOutBack.transform(animation.value);

      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Center(
          child: Transform.scale(
            scale: 0.9 + (0.1 * curvedValue),
            child: Opacity(
              opacity: animation.value.clamp(0.0, 1.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Dialog(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(26, 28, 26, 22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF0F223D),
                          Color(0xFF0A182B),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          blurRadius: 36,
                          offset: const Offset(0, 16),
                        ),
                        BoxShadow(
                          color: const Color(0xFFE53E3E).withValues(alpha: 0.08),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Glowing status badge icon
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                            border: Border.all(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              info.icon,
                              color: const Color(0xFFF87171),
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Title
                        Text(
                          info.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Sanitized user-friendly message
                        Text(
                          info.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: Color(0xFFB7C3D4),
                            fontWeight: FontWeight.w400,
                          ),
                        ),

                        // Contextual hint for credentials
                        if (info.isCredentialError) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: Color(0xFFE4A11A),
                                  size: 15,
                                ),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Passwords are case-sensitive. Check your Caps Lock.',
                                    style: TextStyle(
                                      color: Color(0xFFE4A11A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Primary Action: Try Again
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              if (onRetry != null) onRetry();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B6CB5),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Try Again',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),

                        // Optional "Forgot Password?" shortcut button
                        if (info.isCredentialError && onForgotPassword != null) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              onForgotPassword();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFE4A11A),
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            ),
                            child: const Text(
                              'Forgot your password?',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: Color(0xFFE4A11A),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
