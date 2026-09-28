import 'package:flutter/material.dart' hide SearchBar;

import 'admin_ui_theme.dart';

/// Premium glass search field used in [HeaderHero].
class SearchBar extends StatelessWidget {
  const SearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    this.hint = 'Search users, cases, logs…',
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onSubmitted: onSubmitted,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: AdminUi.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: Colors.white.withValues(alpha: 0.85),
          size: 20,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AdminUi.accent, width: 1.4),
        ),
      ),
    );
  }
}

/// Backward-compatible alias for existing imports.
class AdminSearchBar extends SearchBar {
  const AdminSearchBar({
    super.key,
    required super.controller,
    required super.focusNode,
    super.hint,
    super.onSubmitted,
  });
}
