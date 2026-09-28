import 'dart:ui';

import 'package:flutter/material.dart' hide SearchBar;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'admin_ui_theme.dart';

class AdminTopBar extends StatefulWidget {
  const AdminTopBar({super.key, this.badgeCount = 0});

  final int badgeCount;

  @override
  State<AdminTopBar> createState() => _AdminTopBarState();
}

class _AdminTopBarState extends State<AdminTopBar> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1100;
    final now = DateTime.now();
    final dateLabel = DateFormat('MMM d, y').format(now);
    final weekday = DateFormat('EEEE').format(now);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _searchFocus.requestFocus,
      },
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: compact
              ? Column(
                  children: [
                    _SearchField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _Bell(badgeCount: widget.badgeCount),
                        const Spacer(),
                        _DateBlock(dateLabel: dateLabel, weekday: weekday),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: _SearchField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                      ),
                    ),
                    const SizedBox(width: 16),
                    _Bell(badgeCount: widget.badgeCount),
                    const SizedBox(width: 16),
                    _DateBlock(dateLabel: dateLabel, weekday: weekday),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AdminUi.text,
          ),
          cursorColor: AdminUi.accent,
          decoration: InputDecoration(
            hintText: 'Search users, cases, logs…',
            hintStyle: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AdminUi.muted,
            ),
            prefixIcon: const Icon(Icons.search_rounded, color: AdminUi.muted),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: UnconstrainedBox(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AdminUi.line),
                  ),
                  child: Text(
                    'Ctrl + K',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AdminUi.muted,
                    ),
                  ),
                ),
              ),
            ),
            filled: true,
            fillColor: const Color(0xFFF3F5F8),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: AdminUi.accent, width: 1.4),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bell extends StatelessWidget {
  const _Bell({this.badgeCount = 0});

  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F5F8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: AdminUi.primary,
              size: 22,
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: const BoxDecoration(
                  color: Color(0xFFE11D48),
                  borderRadius: BorderRadius.all(Radius.circular(99)),
                ),
                child: Text(
                  badgeCount > 9 ? '9+' : '$badgeCount',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.dateLabel, required this.weekday});

  final String dateLabel;
  final String weekday;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          dateLabel,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AdminUi.text,
          ),
        ),
        Text(
          weekday,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AdminUi.muted,
          ),
        ),
      ],
    );
  }
}
