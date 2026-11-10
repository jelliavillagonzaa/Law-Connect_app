import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../services/auth_service.dart';
import '../../services/system_settings_service.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/misamis_occidental_address_picker.dart';
import '../../data/misamis_occidental_address_data.dart';
import '../../theme/app_theme.dart';
import 'otp_verification_signup.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key, this.initialRole, this.onClose});

  /// Ignored — sign-up is client-only. Kept so hot reload and old routes stay compatible.
  final String? initialRole;

  /// When opened as an overlay, this closes it instead of popping a route.
  final VoidCallback? onClose;

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  static const _stepCount = 6;

  static const _titles = <String>[
    'Your privacy comes first',
    'What should we call you?',
    'How can we reach you?',
    'Where do you live?',
    'Create a password',
    'Send your code',
  ];

  static final _emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  final _nameFormKey = GlobalKey<FormState>();
  final _contactFormKey = GlobalKey<FormState>();
  final _addressFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  final _confirmPasswordKey = GlobalKey<FormFieldState<String>>();

  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _streetController = TextEditingController();

  final _firstNameFocus = FocusNode();
  final _middleNameFocus = FocusNode();
  final _lastNameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  String _address = '';
  String? _city;
  String? _barangay;
  String? _addressPlaceError;
  String? _otpChannel;
  int _step = 0;

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

  bool get _hasPhone => _phoneNumberController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
    _phoneNumberController.addListener(_onPhoneChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await SystemSettingsService.instance.load();
      if (!mounted) return;
      setState(() => _settings = settings);
      _updatePasswordStrength(_passwordController.text);
    } catch (_) {
      // Password rules stay on the built-in fallback if settings are not ready.
    }
  }

  void _onPasswordChanged() {
    _updatePasswordStrength(_passwordController.text);
    final confirmState = _confirmPasswordKey.currentState;
    if (confirmState != null && _confirmPasswordController.text.isNotEmpty) {
      confirmState.validate();
    }
  }

  void _onPhoneChanged() {
    if (_phoneNumberController.text.trim().isEmpty && _otpChannel == 'sms') {
      setState(() => _otpChannel = 'email');
    } else if (mounted) {
      setState(() {});
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

  String? _validateNamePart(
    String? value,
    String fieldLabel, {
    bool required = true,
  }) {
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
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (!RegExp(r'^\d{11}$').hasMatch(trimmed)) {
      return 'Use 11 digits (09...), or leave this blank';
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

  String get _subtitle {
    switch (_step) {
      case 0:
        return 'Agree first. We only collect your details after this.';
      case 1:
        return 'Leave middle name blank if you do not have one.';
      case 2:
        return 'Email is how you log in. Add a phone only if you have one.';
      case 3:
        return 'Street, purok, or sitio — then your city and barangay.';
      case 4:
        return 'You will use this password when you log in.';
      case 5:
        return _hasPhone
            ? 'Choose Email or SMS. The code screen opens next.'
            : 'No mobile number, so the code goes to your email.';
      default:
        return '';
    }
  }

  IconData get _stepIcon {
    switch (_step) {
      case 0:
        return Icons.privacy_tip_outlined;
      case 1:
        return Icons.badge_outlined;
      case 2:
        return Icons.alternate_email_rounded;
      case 3:
        return Icons.home_outlined;
      case 4:
        return Icons.lock_outline_rounded;
      default:
        return Icons.mark_email_unread_outlined;
    }
  }

  String get _primaryLabel {
    switch (_step) {
      case 0:
        return 'I Agree';
      case 5:
        return 'Send code';
      default:
        return 'Next';
    }
  }

  bool get _primaryEnabled {
    if (_isLoading) return false;
    if (_step != 5) return true;
    if (!_hasPhone) return true;
    return _otpChannel == 'email' || _otpChannel == 'sms';
  }

  void _syncAddress() {
    final street = _streetController.text.trim();
    if (street.isEmpty || _city == null || _barangay == null) {
      _address = '';
      return;
    }
    _address = MisamisOccidentalAddressData.compose(
      street: street,
      barangay: _barangay!,
      city: _city!,
    );
  }

  void _setCity(String? city) {
    setState(() {
      _city = city;
      _barangay = null;
      _addressPlaceError = null;
      _syncAddress();
    });
  }

  void _setBarangay(String? barangay) {
    setState(() {
      _barangay = barangay;
      _addressPlaceError = null;
      _syncAddress();
    });
  }

  void _leaveSignup() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    Get.back();
  }

  void _back() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_step == 0) {
      _leaveSignup();
      return;
    }
    setState(() => _step -= 1);
  }

  void _next() {
    FocusManager.instance.primaryFocus?.unfocus();
    switch (_step) {
      case 0:
        setState(() => _step = 1);
      case 1:
        if (_nameFormKey.currentState?.validate() ?? false) {
          setState(() => _step = 2);
        }
      case 2:
        if (_contactFormKey.currentState?.validate() ?? false) {
          setState(() => _step = 3);
        }
      case 3:
        final formOk = _addressFormKey.currentState?.validate() ?? false;
        final placeOk = _city != null && _barangay != null;
        _syncAddress();
        if (formOk && placeOk && _address.isNotEmpty) {
          setState(() {
            _addressPlaceError = null;
            _step = 4;
          });
        } else {
          setState(() {
            _addressPlaceError = placeOk
                ? null
                : 'Select your city and barangay';
          });
        }
      case 4:
        if (_passwordFormKey.currentState?.validate() ?? false) {
          setState(() {
            _step = 5;
            if (!_hasPhone) _otpChannel = 'email';
          });
        }
      case 5:
        _signup();
    }
  }

  Future<void> _signup() async {
    final phone = _phoneNumberController.text.trim();
    final channel = phone.isEmpty ? 'email' : _otpChannel;
    if (channel != 'email' && channel != 'sms') {
      Get.snackbar(
        'Choose a destination',
        'Select Email or SMS so we know where to send the code.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.clientSignup(
        firstName: _firstNameController.text.trim(),
        middleName: _middleNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        phoneNumber: phone,
        address: _address,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        Get.offAll(
          () => OtpVerificationPage(
            email: _emailController.text.trim(),
            fullName: _displayName(),
            role: 'client',
            otpChannel: channel,
            phoneNumber: phone,
          ),
        );
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
      Get.snackbar(
        'Error',
        'An unexpected error occurred. Please try again.',
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
    final isSmallScreen = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppTheme.navy,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewHeight = constraints.maxHeight;
            final minHeight = viewHeight.isFinite
                ? (viewHeight - 40).clamp(0.0, viewHeight)
                : 0.0;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 20 : 32,
                vertical: 20,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Create your account',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Step ${_step + 1} of $_stepCount',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: List.generate(_stepCount, (index) {
                            final active = index <= _step;
                            return Expanded(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 240),
                                height: 5,
                                margin: EdgeInsets.only(
                                  right: index == _stepCount - 1 ? 0 : 6,
                                ),
                                decoration: BoxDecoration(
                                  color: active
                                      ? AppTheme.gold
                                      : Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
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
                                    color: AppTheme.royalBlue.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _stepIcon,
                                    color: AppTheme.royalBlue,
                                    size: 28,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                _titles[_step],
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _subtitle,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.4,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 22),
                              _stepBody(),
                              const SizedBox(height: 22),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: _isLoading ? null : _back,
                                    child: Text(
                                      _step == 0 ? 'Login' : 'Back',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SizedBox(
                                      height: 48,
                                      child: ElevatedButton(
                                        onPressed:
                                            _primaryEnabled ? _next : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.royalBlue,
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor:
                                              AppTheme.royalBlue.withValues(alpha: 0.45),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                        ),
                                        child: _isLoading
                                            ? const SizedBox(
                                                height: 20,
                                                width: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(Colors.white),
                                                ),
                                              )
                                            : Text(
                                                _primaryLabel,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
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
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _privacyStep();
      case 1:
        return _nameStep();
      case 2:
        return _contactStep();
      case 3:
        return _addressStep();
      case 4:
        return _passwordStep();
      case 5:
        return _channelStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _privacyStep() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.lightGray,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          _policyNoticeText(),
          style: const TextStyle(fontSize: 14, height: 1.45),
        ),
      ),
    );
  }

  Widget _nameStep() {
    return Form(
      key: _nameFormKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        children: [
          AppTextField(
            label: 'First name',
            hint: 'First name',
            controller: _firstNameController,
            focusNode: _firstNameFocus,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _middleNameFocus.requestFocus(),
            textCapitalization: TextCapitalization.words,
            validator: (v) => _validateNamePart(v, 'first name'),
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Middle name (optional)',
            hint: 'Leave blank if none',
            controller: _middleNameController,
            focusNode: _middleNameFocus,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _lastNameFocus.requestFocus(),
            textCapitalization: TextCapitalization.words,
            validator: (v) => _validateNamePart(
              v,
              'middle name',
              required: false,
            ),
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Last name',
            hint: 'Last name',
            controller: _lastNameController,
            focusNode: _lastNameFocus,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _next(),
            textCapitalization: TextCapitalization.words,
            validator: (v) => _validateNamePart(v, 'last name'),
          ),
        ],
      ),
    );
  }

  Widget _contactStep() {
    return Form(
      key: _contactFormKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: 'Email',
            hint: 'name@example.com',
            controller: _emailController,
            focusNode: _emailFocus,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _phoneFocus.requestFocus(),
            keyboardType: TextInputType.emailAddress,
            validator: _validateEmail,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Phone number (optional)',
            hint: '09XXXXXXXXX',
            controller: _phoneNumberController,
            focusNode: _phoneFocus,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _next(),
            keyboardType: TextInputType.number,
            maxLength: 11,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: _validatePhoneNumber,
          ),
          Text(
            'Skip this if you have no mobile number. The code will be emailed.',
            style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _addressStep() {
    return Form(
      key: _addressFormKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: MisamisOccidentalAddressPicker(
        streetController: _streetController,
        city: _city,
        barangay: _barangay,
        placeError: _addressPlaceError,
        onCityChanged: _setCity,
        onBarangayChanged: _setBarangay,
        onStreetChanged: () => setState(_syncAddress),
      ),
    );
  }

  Widget _passwordStep() {
    return Form(
      key: _passwordFormKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        children: [
          AppTextField(
            label: 'Password',
            hint: 'Create a strong password',
            controller: _passwordController,
            focusNode: _passwordFocus,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _confirmPasswordFocus.requestFocus(),
            obscureText: _obscurePassword,
            validator: _validatePassword,
            onChanged: _updatePasswordStrength,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey[700],
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
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
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Password requirements',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildRequirementItem(
                    'At least ${_settings.minPasswordLength} characters',
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
                  _buildRequirementItem('One number (0-9)', _hasNumber),
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
            label: 'Confirm password',
            hint: 'Confirm password',
            controller: _confirmPasswordController,
            focusNode: _confirmPasswordFocus,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _next(),
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
                setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _channelStep() {
    final email = _emailController.text.trim();
    final phone = _phoneNumberController.text.trim();

    return Column(
      children: [
        _channelTile(
          selected: _otpChannel == 'email' || !_hasPhone,
          icon: Icons.email_outlined,
          title: 'Email',
          subtitle: email,
          onTap: () => setState(() => _otpChannel = 'email'),
        ),
        if (_hasPhone) ...[
          const SizedBox(height: 10),
          _channelTile(
            selected: _otpChannel == 'sms',
            icon: Icons.sms_outlined,
            title: 'SMS',
            subtitle: phone,
            onTap: () => setState(() => _otpChannel = 'sms'),
          ),
        ],
      ],
    );
  }

  Widget _channelTile({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppTheme.sidebarActive : AppTheme.lightGray,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppTheme.royalBlue : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.royalBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: selected ? AppTheme.royalBlue : Colors.grey,
              ),
            ],
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
    _phoneNumberController.removeListener(_onPhoneChanged);
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
    _streetController.dispose();
    super.dispose();
  }
}
