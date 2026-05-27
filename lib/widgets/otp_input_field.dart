import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Custom OTP Input Widget with 6 separate boxes
class OtpInputField extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final String? initialValue;

  const OtpInputField({
    super.key,
    required this.onChanged,
    this.onCompleted,
    this.initialValue,
  });

  @override
  State<OtpInputField> createState() => _OtpInputFieldState();
}

class _OtpInputFieldState extends State<OtpInputField> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  String _lastOtp = '';

  @override
  void initState() {
    super.initState();
    // Don't set initial value here - let user type it
    // Setting it programmatically causes focus conflicts
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _notifyChange(String otp) {
    if (otp != _lastOtp) {
      _lastOtp = otp;
      widget.onChanged(otp);
      if (otp.length == 6 && widget.onCompleted != null) {
        widget.onCompleted!(otp);
      }
    }
  }

  void _onChanged(int index, String value) {
    if (value.length > 1) {
      // Handle paste: fill all fields
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 6) {
        for (int i = 0; i < 6; i++) {
          _controllers[i].text = digits[i];
        }
      } else {
        // Fill available digits
        for (int i = 0; i < digits.length && (index + i) < 6; i++) {
          _controllers[index + i].text = digits[i];
        }
      }
    } else if (value.isNotEmpty) {
      // Single digit entered
      _controllers[index].text = value;
    } else {
      // Backspace: clear current
      _controllers[index].text = '';
    }

    // Get current OTP and notify
    final otp = _controllers.map((c) => c.text).join();
    _notifyChange(otp);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(6, (index) {
        return SizedBox(
          width: 50,
          height: 60,
          child: TextField(
            key: ValueKey('otp_$index'),
            controller: _controllers[index],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            enableInteractiveSelection: false,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.royalBlue,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.royalBlue, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red, width: 1),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onChanged: (value) => _onChanged(index, value),
          ),
        );
      }),
    );
  }
}
