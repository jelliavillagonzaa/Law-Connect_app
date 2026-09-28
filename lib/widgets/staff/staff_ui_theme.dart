import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Visual tokens for the Staff (APAOStaff) portal only.
class StaffUi {
  StaffUi._();

  static const Color navy = Color(0xFF0E2A4A);
  static const Color navyMid = Color(0xFF163A66);
  static const Color navyDeep = Color(0xFF0A1C33);
  static const Color gold = Color(0xFFD4A017);
  static const Color goldSoft = Color(0xFFF1C40F);
  static const Color background = Color(0xFFF4F6FA);
  static const Color card = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF12233F);
  static const Color muted = Color(0xFF6B7A90);
  static const Color line = Color(0xFFE6EAF2);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);
  static const Color purple = Color(0xFF7C3AED);

  static const double radius = 14;
  static const double sidebarWidth = 260;

  static const LinearGradient sidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0E2A4A), Color(0xFF081526)],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF0E2A4A), Color(0xFF1A4A7A)],
  );

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: navy.withValues(alpha: 0.07),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];

  static TextStyle get title => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: text,
      );

  static TextStyle get body => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: muted,
      );
}
