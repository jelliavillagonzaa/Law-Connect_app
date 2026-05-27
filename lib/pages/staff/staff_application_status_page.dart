import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/staff_application_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import 'staff_complete_registration_page.dart';

/// Look up application by email (document id is derived from email).
class StaffApplicationStatusPage extends StatefulWidget {
  const StaffApplicationStatusPage({super.key});

  @override
  State<StaffApplicationStatusPage> createState() =>
      _StaffApplicationStatusPageState();
}

class _StaffApplicationStatusPageState extends State<StaffApplicationStatusPage> {
  final _emailController = TextEditingController();
  final _service = StaffApplicationService();
  bool _loading = false;
  Map<String, dynamic>? _result;

  Future<void> _lookup() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      Get.snackbar(
        'Email',
        'Enter the email you used on your application.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    setState(() {
      _loading = true;
      _result = null;
    });

    final docId = StaffApplicationService.applicationDocIdForEmail(email);
    final snap = await _service.getApplication(docId);

    if (!mounted) return;
    setState(() => _loading = false);

    if (!snap.exists || snap.data() == null) {
      setState(() {
        _result = {'status': 'none', 'message': 'No application found for this email.'};
      });
      return;
    }

    final data = snap.data()!;
    setState(() {
      _result = {
        'status': data['status'] as String? ?? 'unknown',
        'rejectionReason': data['rejectionReason'] as String?,
        'email': data['email'] as String?,
        'registeredUid': data['registeredUid'] as String?,
      };
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
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
        title: const Text('Application status'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Enter the email address from your staff application.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.white.withValues(alpha: 0.88),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                          label: 'Email',
                          hint: 'Email',
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        AppButton(
                          text: 'Check status',
                          onPressed: _lookup,
                          isLoading: _loading,
                        ),
                      ],
                    ),
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: 20),
                    _StatusCard(
                      data: _result!,
                      onCompleteRegistration: () => Get.to(
                        () => const StaffCompleteRegistrationPage(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.data,
    required this.onCompleteRegistration,
  });

  final Map<String, dynamic> data;
  final VoidCallback onCompleteRegistration;

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? '';
    final message = data['message'] as String?;
    final reason = data['rejectionReason'] as String?;
    final registeredUid = (data['registeredUid'] as String?)?.trim() ?? '';
    final hasCompletedEmailStep = registeredUid.isNotEmpty;

    Color bg;
    IconData icon;
    String title;
    String body;

    switch (status) {
      case 'pending':
        bg = Colors.orange.shade100;
        icon = Icons.hourglass_top_rounded;
        if (hasCompletedEmailStep) {
          title = 'Email verified — awaiting decision';
          body =
              'Your password and email code are done. Wait for an administrator to approve your application — you can sign in as soon as they approve.';
        } else {
          title = 'Pending review';
          body =
              'An administrator may still be reviewing your application. You can already open “Complete registration” to set your password and enter the email code. Sign-in only works after approval and admin activation.';
        }
        break;
      case 'approved':
        bg = Colors.green.shade100;
        icon = Icons.check_circle_outline;
        title = 'Approved';
        body =
            'Open “Complete registration”: set your password and tap Continue — the OTP is sent to your email right away. Enter the code to create your account. After an administrator approves your application, you can sign in.';
        break;
      case 'rejected':
        bg = Colors.red.shade100;
        icon = Icons.cancel_outlined;
        title = 'Not approved';
        body = (reason != null && reason.isNotEmpty)
            ? reason
            : 'This application was not approved. Contact the firm for details.';
        break;
      case 'registered':
        bg = Colors.blue.shade100;
        icon = Icons.login_rounded;
        title = 'Already registered';
        body =
            'Your profile is on file. Sign in with your staff email and password (if login fails, ask an admin to confirm your application is approved and your account is enabled).';
        break;
      default:
        bg = Colors.grey.shade200;
        icon = Icons.info_outline;
        title = 'No application';
        body = message ?? 'No record found.';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.royalBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.darkText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.grey[900],
            ),
          ),
          if (status == 'approved' ||
              (status == 'pending' && !hasCompletedEmailStep)) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onCompleteRegistration,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.royalBlue,
                  foregroundColor: AppTheme.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Complete registration'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
