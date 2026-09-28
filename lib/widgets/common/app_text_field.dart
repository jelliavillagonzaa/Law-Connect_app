import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';

class AppTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool readOnly;
  final Key? fieldKey;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final void Function(String)? onFieldSubmitted;
  /// When false, the field uses a placeholder only (no reserved floating-label space).
  final bool showFloatingLabel;

  const AppTextField({
    super.key,
    this.fieldKey,
    required this.label,
    this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.onChanged,
    this.prefixIcon,
    this.suffixIcon,
    this.readOnly = false,
    this.focusNode,
    this.textInputAction,
    this.onFieldSubmitted,
    this.showFloatingLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      readOnly: readOnly,
      focusNode: focusNode,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: showFloatingLabel ? label : null,
        hintText: hint ?? (showFloatingLabel ? null : label),
        floatingLabelBehavior: showFloatingLabel
            ? FloatingLabelBehavior.auto
            : FloatingLabelBehavior.never,
        isDense: !showFloatingLabel,
        prefixIcon: prefixIcon != null
            ? IconTheme(
                data: const IconThemeData(color: AppTheme.royalBlue),
                child: prefixIcon!,
              )
            : null,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppTheme.cleanWhite,
      ),
    );
  }
}

