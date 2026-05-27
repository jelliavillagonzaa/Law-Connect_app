import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/app_text_field.dart';
import '../../theme/app_theme.dart';
import 'otp_verification_signup.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key, this.initialRole});

  /// Ignored — sign-up is client-only. Kept so hot reload and old routes stay compatible.
  final String? initialRole;

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  final _formKey = GlobalKey<FormState>();
  final _confirmPasswordKey = GlobalKey<FormFieldState<String>>();

  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _addressController = TextEditingController();

  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool _hasMinLength = false;
  bool _hasUpperCase = false;
  bool _hasLowerCase = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    _updatePasswordStrength(_passwordController.text);
    final confirmState = _confirmPasswordKey.currentState;
    if (confirmState != null && _confirmPasswordController.text.isNotEmpty) {
      confirmState.validate();
    }
  }

  void _updatePasswordStrength(String value) {
    setState(() {
      _hasMinLength = value.length >= 8;
      _hasUpperCase = value.contains(RegExp(r'[A-Z]'));
      _hasLowerCase = value.contains(RegExp(r'[a-z]'));
      _hasNumber = value.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    });
  }

  String _displayName() {
    return [
      _firstNameController.text.trim(),
      _middleNameController.text.trim(),
      _lastNameController.text.trim(),
    ].where((s) => s.isNotEmpty).join(' ');
  }

  String? _validateNamePart(String? value, String fieldLabel, {bool required = true}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Please enter your $fieldLabel' : null;
    }
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      return '$fieldLabel must be at least 2 characters';
    }
    if (!RegExp(r"^[a-zA-ZÀ-ÿ'.\-\s]+$").hasMatch(trimmed)) {
      return '$fieldLabel can only contain letters';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email';
    }
    final trimmed = value.trim();
    if (!_emailRegex.hasMatch(trimmed)) {
      return 'Enter a valid email (e.g. name@example.com)';
    }
    return null;
  }

  String? _validatePhoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone number';
    }
    if (!RegExp(r'^\d{11}$').hasMatch(value)) {
      return 'Phone number must be exactly 11 digits (numbers only)';
    }
    return null;
  }

  String? _validateAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your address';
    }
    final parts = value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length < 5) {
      return 'Use format: Street, Barangay, City, Province, Country';
    }
    for (final part in parts) {
      if (part.length < 2) {
        return 'Each address part must be at least 2 characters';
      }
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return 'Password must contain at least one special character';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  static const _privacyNoticeText =
      "Don't worry about the personal data you provide during sign up. "
      'Your information is protected and handled securely in accordance with '
      'the Data Privacy Act of 2012 (Republic Act No. 10173) of the Philippines. '
      'We value your privacy and ensure that your data will only be used for '
      'authorized purposes within the system.';

  Future<void> _showPrivacyNotice() async {
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.privacy_tip_outlined, color: AppTheme.royalBlue),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Your Privacy Matters',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: const SingleChildScrollView(
              child: Text(
                _privacyNoticeText,
                style: TextStyle(fontSize: 14, height: 1.45),
              ),
            ),
          ),
        );
      },
    );

    await Future.delayed(const Duration(seconds: 10));

    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Future<String?> _showOtpChannelPicker({
    required String email,
    required String phone,
  }) async {
    if (!mounted) return null;

    String? selected;

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Receive OTP via',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Choose where we should send your one-time verification code:',
                    style: TextStyle(fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: selected == 'email',
                    activeColor: AppTheme.royalBlue,
                    onChanged: (checked) {
                      setDialogState(() {
                        selected = checked == true ? 'email' : null;
                      });
                    },
                    title: const Text(
                      'Email',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(email),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: selected == 'sms',
                    activeColor: AppTheme.royalBlue,
                    onChanged: (checked) {
                      setDialogState(() {
                        selected = checked == true ? 'sms' : null;
                      });
                    },
                    title: const Text(
                      'SMS',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(phone),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: selected == null
                      ? null
                      : () => Navigator.of(dialogContext).pop(selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.royalBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Send OTP'),
                ),
              ],
            );
          },
        );
      },
    );

    return choice;
  }

  Future<void> _showOtpSendingDialog(String channel) async {
    if (!mounted) return;

    final label = channel == 'sms' ? 'SMS' : 'Email';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppTheme.royalBlue),
                const SizedBox(height: 20),
                Text(
                  'Sending OTP to your $label...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please wait.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppTheme.mutedText),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _closeRootDialogIfOpen() {
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Future<void> _showOtpSentNotice({
    required String channel,
    required String destination,
  }) async {
    if (!mounted) return;

    final channelLabel = channel == 'sms' ? 'SMS' : 'Email';
    final destLabel = channel == 'sms'
        ? 'phone number ending in ${destination.length >= 4 ? destination.substring(destination.length - 4) : destination}'
        : 'email ($destination)';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.mark_email_read_outlined, color: AppTheme.royalBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'OTP sent to your $channelLabel',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              'We sent your verification code to your $channelLabel ($destLabel).\n\n'
              'Please do not share this code with anybody.\n\n'
              'Input your OTP on the next screen.',
              style: const TextStyle(fontSize: 14, height: 1.45),
            ),
          ),
        );
      },
    );

    await Future.delayed(const Duration(seconds: 5));

    _closeRootDialogIfOpen();
  }

  Future<bool> _deliverOtpAfterChannelChoice({
    required String email,
    required String phone,
  }) async {
    final channel = await _showOtpChannelPicker(email: email, phone: phone);
    if (!mounted || channel == null) return false;

    await _showOtpSendingDialog(channel);

    final sendResult = await _authService.sendClientSignupOtp(
      email: email,
      channel: channel,
      name: _displayName(),
    );

    _closeRootDialogIfOpen();

    if (!mounted) return false;

    if (sendResult['success'] != true) {
      Get.snackbar(
        'Error',
        sendResult['message'] as String? ??
            'Failed to send verification code.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
      return false;
    }

    await _showOtpSentNotice(
      channel: channel,
      destination: sendResult['destination'] as String? ??
          (channel == 'sms' ? phone : email),
    );

    if (!mounted) return false;

    Get.offAll(
      () => OtpVerificationPage(
        email: email,
        fullName: _displayName(),
        role: 'client',
        otpChannel: channel,
        phoneNumber: phone,
      ),
    );

    return true;
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _authService.clientSignup(
        firstName: _firstNameController.text.trim(),
        middleName: _middleNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        phoneNumber: _phoneNumberController.text.trim(),
        address: _addressController.text.trim(),
      );

      if (!mounted) return;

      if (result['success'] == true) {
        await _showPrivacyNotice();

        if (!mounted) return;

        final email = _emailController.text.trim();
        final phone = _phoneNumberController.text.trim();

        await _deliverOtpAfterChannelChoice(email: email, phone: phone);
      } else {
        Get.snackbar(
          'Error',
          result['message'] ?? 'Registration failed. Please try again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      if (!mounted) return;

      String errorMessage = 'An unexpected error occurred';
      if (e.toString().contains('FIRESTORE')) {
        errorMessage =
            'Database connection error. Please check your internet connection and try again.';
      } else {
        errorMessage = 'Error: ${e.toString()}';
      }

      Get.snackbar(
        'Error',
        errorMessage,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 20 : 32,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Create Your Account',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Fill in your details to get started',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppTextField(
                            label: 'First Name',
                            hint: 'First Name',
                            controller: _firstNameController,
                            textCapitalization: TextCapitalization.words,
                            validator: (v) =>
                                _validateNamePart(v, 'first name'),
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Middle Name',
                            hint: 'Middle Name',
                            controller: _middleNameController,
                            textCapitalization: TextCapitalization.words,
                            validator: (v) =>
                                _validateNamePart(v, 'middle name'),
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Last Name',
                            hint: 'Last Name',
                            controller: _lastNameController,
                            textCapitalization: TextCapitalization.words,
                            validator: (v) => _validateNamePart(v, 'last name'),
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Email',
                            hint: 'name@example.com',
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Phone Number',
                            hint: '09XXXXXXXXX (11 digits)',
                            controller: _phoneNumberController,
                            keyboardType: TextInputType.number,
                            maxLength: 11,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: _validatePhoneNumber,
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Address',
                            hint:
                                'Street, Barangay, City, Province, Country',
                            controller: _addressController,
                            maxLines: 3,
                            validator: _validateAddress,
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Password',
                            hint: 'Create a strong password',
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            validator: _validatePassword,
                            onChanged: _updatePasswordStrength,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey[700],
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          if (_passwordController.text.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.grey[300]!,
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Password Requirements:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildRequirementItem(
                                    'At least 8 characters',
                                    _hasMinLength,
                                  ),
                                  _buildRequirementItem(
                                    'One uppercase letter (A-Z)',
                                    _hasUpperCase,
                                  ),
                                  _buildRequirementItem(
                                    'One lowercase letter (a-z)',
                                    _hasLowerCase,
                                  ),
                                  _buildRequirementItem(
                                    'One number (0-9)',
                                    _hasNumber,
                                  ),
                                  _buildRequirementItem(
                                    'One special character (!@#\$%...)',
                                    _hasSpecialChar,
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),
                          AppTextField(
                            fieldKey: _confirmPasswordKey,
                            label: 'Confirm Password',
                            hint: 'Confirm Password',
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            validator: _validateConfirmPassword,
                            onChanged: (_) {
                              _confirmPasswordKey.currentState?.validate();
                            },
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey[700],
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 28),
                          Center(
                            child: SizedBox(
                              width: 180,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _signup,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.royalBlue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  elevation: 3,
                                  shadowColor: AppTheme.royalBlue.withOpacity(
                                    0.4,
                                  ),
                                  disabledBackgroundColor: AppTheme.royalBlue
                                      .withOpacity(0.6),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    : const Text(
                                        'Sign Up',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.3,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Already have an account? ',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                ),
                              ),
                              TextButton(
                                onPressed: () => Get.back(),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Login',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.royalBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequirementItem(String text, bool isValid) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.circle,
            size: 16,
            color: isValid ? Colors.green : Colors.grey[400],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: isValid ? Colors.green[700] : Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneNumberController.dispose();
    _addressController.dispose();
    super.dispose();
  }
}
