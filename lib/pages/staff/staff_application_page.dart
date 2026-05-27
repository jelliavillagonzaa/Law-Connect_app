import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/staff_application_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';

/// Staff applies here; admin must approve before [StaffCompleteRegistrationPage].
class StaffApplicationPage extends StatefulWidget {
  const StaffApplicationPage({super.key});

  @override
  State<StaffApplicationPage> createState() => _StaffApplicationPageState();
}

class _StaffApplicationPageState extends State<StaffApplicationPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _messageController = TextEditingController();
  final _service = StaffApplicationService();

  bool _reqExperience = false;
  bool _reqAttorney = false;
  bool _reqConfidentiality = false;
  bool _reqAccurate = false;
  bool _loading = false;

  bool get _allRequirements =>
      _reqExperience && _reqAttorney && _reqConfidentiality && _reqAccurate;

  Future<void> _submit() async {
    if (!_allRequirements) {
      Get.snackbar(
        'Requirements',
        'Please confirm all staff requirements below.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    final result = await _service.submitApplication(
      email: _emailController.text,
      name: _nameController.text,
      phone: _phoneController.text,
      address: _addressController.text,
      message: _messageController.text,
      agreedToRequirements: true,
    );
    setState(() => _loading = false);

    if (!mounted) return;
    if (result['success'] == true) {
      Get.snackbar(
        'Submitted',
        result['message'] as String? ?? 'Application sent.',
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
      Get.back();
    } else {
      Get.snackbar(
        'Could not submit',
        result['message'] as String? ?? 'Try again later.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.white,
        title: const Text('Staff application'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Requirements',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Staff access is granted only after an administrator approves your application. '
                      'By applying, you confirm the following:',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: AppTheme.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ReqTile(
                      value: _reqExperience,
                      onChanged: (v) => setState(() => _reqExperience = v ?? false),
                      title: 'Relevant experience',
                      subtitle:
                          'You have administrative, legal-support, or equivalent experience suitable for a law office.',
                    ),
                    _ReqTile(
                      value: _reqAttorney,
                      onChanged: (v) => setState(() => _reqAttorney = v ?? false),
                      title: 'Supervision',
                      subtitle:
                          'You understand you will work under the direction of a licensed attorney assigned by the firm.',
                    ),
                    _ReqTile(
                      value: _reqConfidentiality,
                      onChanged: (v) =>
                          setState(() => _reqConfidentiality = v ?? false),
                      title: 'Confidentiality',
                      subtitle:
                          'You will protect client information and follow firm policies and applicable rules of professional conduct.',
                    ),
                    _ReqTile(
                      value: _reqAccurate,
                      onChanged: (v) => setState(() => _reqAccurate = v ?? false),
                      title: 'Accurate information',
                      subtitle:
                          'All details in this application are truthful; the firm may verify your background.',
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppTextField(
                            label: 'Full name',
                            hint: 'Full name',
                            controller: _nameController,
                            validator: (v) {
                              if (v == null || v.trim().length < 2) {
                                return 'Please enter your name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          AppTextField(
                            label: 'Work email',
                            hint: 'you@firm.com',
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (v == null || !v.contains('@')) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          AppTextField(
                            label: 'Phone',
                            hint: 'Phone number',
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            validator: (v) {
                              if (v == null || v.trim().length < 8) {
                                return 'Please enter a valid phone number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          AppTextField(
                            label: 'Address (optional)',
                            hint: 'City / region',
                            controller: _addressController,
                          ),
                          const SizedBox(height: 14),
                          AppTextField(
                            label: 'Message to admin (optional)',
                            hint: 'Prior role, availability, references…',
                            controller: _messageController,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 20),
                          AppButton(
                            text: 'Submit application',
                            onPressed: _submit,
                            isLoading: _loading,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReqTile extends StatelessWidget {
  const _ReqTile({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: CheckboxListTile(
          value: value,
          onChanged: onChanged,
          activeColor: AppTheme.gold,
          checkColor: AppTheme.navy,
          title: Text(
            title,
            style: const TextStyle(
              color: AppTheme.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: AppTheme.white.withValues(alpha: 0.75),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ),
    );
  }
}
