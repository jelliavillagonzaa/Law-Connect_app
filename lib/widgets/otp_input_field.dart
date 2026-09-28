import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Six-digit OTP PIN field: one hidden input (paste + SMS autofill) over visual boxes.
class OtpInputField extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final String? initialValue;
  final bool enabled;
  final bool autoFocus;

  const OtpInputField({
    super.key,
    required this.onChanged,
    this.onCompleted,
    this.initialValue,
    this.enabled = true,
    this.autoFocus = true,
  });

  @override
  State<OtpInputField> createState() => OtpInputFieldState();
}

class OtpInputFieldState extends State<OtpInputField> {
  static const int _length = 6;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _otp = '';

  @override
  void initState() {
    super.initState();
    final seed = (widget.initialValue ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (seed.isNotEmpty) {
      final clipped = seed.length > _length ? seed.substring(0, _length) : seed;
      _controller.text = clipped;
      _otp = clipped;
    }
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void clear() {
    _controller.clear();
    _applyOtp('');
    _focusNode.requestFocus();
  }

  void _applyOtp(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final otp = digits.length > _length ? digits.substring(0, _length) : digits;
    if (_controller.text != otp) {
      _controller.value = TextEditingValue(
        text: otp,
        selection: TextSelection.collapsed(offset: otp.length),
      );
    }
    if (otp == _otp) return;
    setState(() => _otp = otp);
    widget.onChanged(otp);
    if (otp.length == _length) {
      widget.onCompleted?.call(otp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final maxBox = ((available - (gap * (_length - 1))) / _length)
            .clamp(36.0, 48.0);
        final boxSize = maxBox;
        final rowWidth = boxSize * _length + gap * (_length - 1);

        return GestureDetector(
          onTap: widget.enabled ? () => _focusNode.requestFocus() : null,
          child: Center(
            child: SizedBox(
              width: rowWidth,
              child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: 0,
                child: SizedBox(
                  height: boxSize + 8,
                  child: AutofillGroup(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: widget.enabled,
                      autofocus: widget.autoFocus,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      showCursor: false,
                      enableSuggestions: false,
                      autocorrect: false,
                      enableInteractiveSelection: false,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(_length),
                      ],
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        counterText: '',
                      ),
                      onChanged: _applyOtp,
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(_length, (index) {
                  final filled = index < _otp.length;
                  final isActive = focused && index == _otp.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    width: boxSize,
                    height: boxSize + 6,
                    decoration: BoxDecoration(
                      color: filled
                          ? AppTheme.royalBlue.withOpacity(0.06)
                          : Colors.grey[50],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isActive
                            ? AppTheme.royalBlue
                            : filled
                                ? AppTheme.royalBlue.withOpacity(0.45)
                                : Colors.grey[300]!,
                        width: isActive ? 2.2 : 1.2,
                      ),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: AppTheme.royalBlue.withOpacity(0.18),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: filled
                        ? Text(
                            _otp[index],
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: AppTheme.deepNavy,
                            ),
                          )
                        : isActive
                            ? Container(
                                width: 2,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: AppTheme.royalBlue,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              )
                            : const SizedBox.shrink(),
                  );
                }),
              ),
            ],
              ),
            ),
          ),
        );
      },
    );
  }
}
