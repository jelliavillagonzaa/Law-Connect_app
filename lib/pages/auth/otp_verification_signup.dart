import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/auth_service.dart';
import '../../routes/portal_navigation.dart';
import '../../theme/app_theme.dart';
import '../../widgets/otp_input_field.dart';

class OtpVerificationPage extends StatefulWidget {
  final String email;
  final String? fullName;
  /// Ignored — OTP is never shown on screen. Kept for hot reload compatibility.
  final String? otp;
  final String role; // 'client' or 'attorney'
  /// `email` or `sms` — where the sign-up OTP was delivered.
  final String? otpChannel;
  final String? phoneNumber;

  const OtpVerificationPage({
    super.key,
    required this.email,
    this.fullName,
    this.otp,
    this.role = 'client',
    this.otpChannel,
    this.phoneNumber,
  });

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final AuthService _authService = AuthService();
  final GlobalKey<OtpInputFieldState> _otpFieldKey =
      GlobalKey<OtpInputFieldState>();

  bool _isSubmitting = false;
  bool _isSending = false;
  String _enteredOtp = '';
  String? _sendError;
  bool _codeSent = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  bool get _viaSms => widget.otpChannel == 'sms';

  String get _maskedDestination {
    if (_viaSms) {
      final phone = widget.phoneNumber ?? '';
      if (phone.length >= 4) return '•••• ${phone.substring(phone.length - 4)}';
      return phone.isEmpty ? 'your phone' : phone;
    }
    final email = widget.email;
    final at = email.indexOf('@');
    if (at <= 1) return email;
    return '${email[0]}•••${email.substring(at)}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sendOtp(isInitial: true);
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown([int seconds = 45]) {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  Future<void> _sendOtp({bool isInitial = false}) async {
    if (_isSending) return;
    setState(() {
      _isSending = true;
      _sendError = null;
    });

    try {
      final result = widget.role == 'client' &&
              (widget.otpChannel == 'email' || widget.otpChannel == 'sms')
          ? await _authService.sendClientSignupOtp(
              email: widget.email,
              channel: widget.otpChannel!,
              name: widget.fullName,
            )
          : await _authService.sendVerificationOtp(
              email: widget.email,
              name: widget.fullName,
              channel: widget.otpChannel,
            );

      if (!mounted) return;

      if (result['success'] == true) {
        setState(() {
          _codeSent = true;
          _sendError = null;
        });
        _startResendCooldown();
        if (!isInitial) {
          Get.snackbar(
            'Code sent',
            result['message'] ??
                (_viaSms
                    ? 'Check your SMS for the 6-digit code.'
                    : 'Check your email inbox and spam folder.'),
            backgroundColor: Colors.green,
            colorText: Colors.white,
          );
        }
      } else {
        setState(() {
          _sendError = result['message'] as String? ??
              'Could not send the verification code. Tap Resend.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sendError = 'Could not send the verification code. Tap Resend.';
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_isSubmitting) return;
    final otp = _enteredOtp.trim();

    if (otp.length != 6) {
      Get.snackbar(
        'Code required',
        'Enter the 6-digit verification code.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final result = widget.role == 'attorney'
          ? await _authService.verifyOtpAndCreateAttorneyAccount(
              email: widget.email,
              otp: otp,
            )
          : await _authService.verifyOtpAndCreateAccount(
              email: widget.email,
              otp: otp,
            );

      if (!mounted) return;

      if (result['success'] == true) {
        Get.snackbar(
          'Verified',
          result['message'] ?? 'Account created successfully.',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
        final portalRole = widget.role == 'attorney' ? 'attorney' : 'client';
        navigateToPortalDashboard(portalRole);
      } else {
        _otpFieldKey.currentState?.clear();
        setState(() => _enteredOtp = '');
        Get.snackbar(
          'Verification failed',
          result['message'] ?? 'Invalid code. Please try again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      if (!mounted) return;
      Get.snackbar(
        'Error',
        'Failed to verify code. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _goToLogin() {
    Get.offAllNamed('/LoginPage');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToLogin();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: AppTheme.navy,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 600;
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  isWide ? 24 : 20,
                  16,
                  isWide ? 24 : 20,
                  24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _goToLogin,
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Back to login'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Verify your ${_viaSms ? 'phone' : 'email'}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isWide ? 26 : 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isSending
                            ? 'Sending your 6-digit code…'
                            : _sendError != null
                                ? 'We could not send the code yet. You can still type it or tap Resend.'
                                : 'Enter the 6-digit code we sent to $_maskedDestination.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: Colors.white.withOpacity(0.82),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        padding: EdgeInsets.fromLTRB(
                          isWide ? 20 : 22,
                          isWide ? 24 : 28,
                          isWide ? 20 : 22,
                          22,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.12),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppTheme.royalBlue.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _viaSms
                                      ? Icons.sms_outlined
                                      : Icons.mark_email_unread_outlined,
                                  color: AppTheme.royalBlue,
                                  size: 30,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (_isSending)
                              _StatusBanner(
                                color: AppTheme.royalBlue,
                                icon: Icons.hourglass_top_rounded,
                                text: _viaSms
                                    ? 'Sending code via SMS…'
                                    : 'Sending code to your email…',
                              )
                            else if (_sendError != null)
                              _StatusBanner(
                                color: Colors.orange.shade800,
                                background: Colors.orange.shade50,
                                icon: Icons.error_outline_rounded,
                                text: _sendError!,
                              )
                            else if (_codeSent)
                              _StatusBanner(
                                color: Colors.green.shade800,
                                background: Colors.green.shade50,
                                icon: Icons.check_circle_outline_rounded,
                                text: _viaSms
                                    ? 'Code sent by SMS. Do not share it with anyone.'
                                    : 'Code sent to ${widget.email}. Check Inbox, Promotions, and Spam.',
                              ),
                            const SizedBox(height: 22),
                            Text(
                              'Enter verification code',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[850],
                              ),
                            ),
                            const SizedBox(height: 16),
                            OtpInputField(
                              key: _otpFieldKey,
                              onChanged: (otp) => _enteredOtp = otp,
                              onCompleted: (_) {
                                if (!_isSubmitting && mounted) {
                                  _verifyOtp();
                                }
                              },
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _isSubmitting ? null : _verifyOtp,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.royalBlue,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  disabledBackgroundColor:
                                      AppTheme.royalBlue.withOpacity(0.55),
                                ),
                                child: _isSubmitting
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    : const Text(
                                        'Verify and continue',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: (_isSending || _resendSeconds > 0)
                                  ? null
                                  : () => _sendOtp(),
                              child: _isSending
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _resendSeconds > 0
                                          ? 'Resend code in ${_resendSeconds}s'
                                          : 'Resend code',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final Color color;
  final Color? background;
  final IconData icon;
  final String text;

  const _StatusBanner({
    required this.color,
    this.background,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: background ?? color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
