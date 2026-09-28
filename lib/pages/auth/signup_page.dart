import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../services/auth_service.dart';
import '../../services/system_settings_service.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/misamis_occidental_address_picker.dart';
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
  final _addressFieldKey = GlobalKey<FormFieldState<String>>();

  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneNumberController = TextEditingController();

  final _firstNameFocus = FocusNode();
  final _middleNameFocus = FocusNode();
  final _lastNameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  String _address = '';

  final AuthService _authService = AuthService();
  AppSystemSettings _settings = AppSystemSettings.fallback;
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
    SystemSettingsService.instance.load().then((settings) {
      if (!mounted) return;
      setState(() => _settings = settings);
      _updatePasswordStrength(_passwordController.text);
    });
  }

  void _submitSignupFromKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    _signup();
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
      _hasMinLength = value.length >= _settings.minPasswordLength;
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
      return 'Please complete your address (purok, barangay, and city)';
    }
    final parts = value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length < 5) {
      return 'Please select purok, barangay, city, province, and country';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    return _settings.validatePassword(value);
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

  String _policyNoticeText() {
    final privacy =
        _settings.privacy.isEmpty ? _privacyNoticeText : _settings.privacy;
    if (_settings.terms.isEmpty) return privacy;
    return '$privacy\n\nTerms & Conditions\n${_settings.terms}';
  }

  Future<void> _showPrivacyNotice() async {
    if (!mounted) return;

    await showDialog<void>(
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
            content: SingleChildScrollView(
              child: Text(
                _policyNoticeText(),
                style: const TextStyle(fontSize: 14, height: 1.45),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      },
    );
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

  Future<bool> _deliverOtpAfterChannelChoice({
    required String email,
    required String phone,
  }) async {
    final channel = await _showOtpChannelPicker(email: email, phone: phone);
    if (!mounted || channel == null) return false;

    // Open the OTP screen immediately. Sending from a dialog here used to
    // pop SignupPage itself (back to login) when the send finished quickly.
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
    final isValid = _formKey.currentState!.validate();
    _addressFieldKey.currentState?.validate();
    if (!isValid || _address.trim().isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final result = await _authService.clientSignup(
        firstName: _firstNameController.text.trim(),
        middleName: _middleNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        phoneNumber: _phoneNumberController.text.trim(),
        address: _address,
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
      resizeToAvoidBottomInset: true,
      backgroundColor: AppTheme.navy,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 20 : 32,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
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
                            focusNode: _firstNameFocus,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) =>
                                _middleNameFocus.requestFocus(),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) =>
                                _validateNamePart(v, 'first name'),
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Middle Name',
                            hint: 'Middle Name',
                            controller: _middleNameController,
                            focusNode: _middleNameFocus,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) =>
                                _lastNameFocus.requestFocus(),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) =>
                                _validateNamePart(
                                  v,
                                  'middle name',
                                  required: false,
                                ),
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Last Name',
                            hint: 'Last Name',
                            controller: _lastNameController,
                            focusNode: _lastNameFocus,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) =>
                                _emailFocus.requestFocus(),
                            textCapitalization: TextCapitalization.words,
                            validator: (v) => _validateNamePart(v, 'last name'),
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Email',
                            hint: 'name@example.com',
                            controller: _emailController,
                            focusNode: _emailFocus,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) =>
                                _phoneFocus.requestFocus(),
                            keyboardType: TextInputType.emailAddress,
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Phone Number',
                            hint: '09XXXXXXXXX (11 digits)',
                            controller: _phoneNumberController,
                            focusNode: _phoneFocus,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) =>
                                _passwordFocus.requestFocus(),
                            keyboardType: TextInputType.number,
                            maxLength: 11,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: _validatePhoneNumber,
                          ),
                          const SizedBox(height: 16),
                          MisamisOccidentalAddressPicker(
                            formFieldKey: _addressFieldKey,
                            onChanged: (value) => _address = value,
                            validator: _validateAddress,
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Password',
                            hint: 'Create a strong password',
                            controller: _passwordController,
                            focusNode: _passwordFocus,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) =>
                                _confirmPasswordFocus.requestFocus(),
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
                            focusNode: _confirmPasswordFocus,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) =>
                                _submitSignupFromKeyboard(),
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
            );
          },
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
    _firstNameFocus.dispose();
    _middleNameFocus.dispose();
    _lastNameFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneNumberController.dispose();
    super.dispose();
  }
}
