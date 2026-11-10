import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Visual tokens for the Staff (APAOStaff) portal only.
class StaffUi {
  StaffUi._();

  // Core Palette — Executive Law Firm Navy & Warm Gold
  static const Color navyDeep = Color(0xFF07152B);
  static const Color navyMid = Color(0xFF0D223F);
  static const Color navy = Color(0xFF13365F);
  static const Color navyLight = Color(0xFF1D4A7D);

  static const Color gold = Color(0xFFF59E0B);
  static const Color goldGlow = Color(0xFFFBBF24);
  static const Color goldDeep = Color(0xFFD97706);
  static const Color goldSoft = Color(0xFFFEF3C7);

  static const Color background = Color(0xFFF6F8FC);
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardHover = Color(0xFFFAFCFF);
  static const Color text = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF334155);
  static const Color muted = Color(0xFF64748B);
  static const Color line = Color(0xFFE2E8F0);
  static const Color border = Color(0xFFE2E8F0);

  // Status Accents
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFFECFDF5);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFFFBEB);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFEFF6FF);
  static const Color danger = Color(0xFFEF4444);
  static const Color dangerLight = Color(0xFFFEF2F2);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color purpleLight = Color(0xFFF5F3FF);

  static const double radius = 16;
  static const double radiusSm = 12;
  static const double sidebarWidth = 250;

  // Gradients
  static const LinearGradient sidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF061427), Color(0xFF0A1F3B), Color(0xFF061427)],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF071830), Color(0xFF0D2547), Color(0xFF143765)],
  );

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
  );

  static const LinearGradient subtleNavyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10284A), Color(0xFF173D6C)],
  );

  // Shadows
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.04),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.02),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get cardShadowHover => [
        BoxShadow(
          color: navy.withValues(alpha: 0.12),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: gold.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get heroShadow => [
        BoxShadow(
          color: const Color(0xFF07152B).withValues(alpha: 0.28),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get goldButtonShadow => [
        BoxShadow(
          color: gold.withValues(alpha: 0.35),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];

  /// Bundled fast font helper — avoids GoogleFonts runtime network downloads and spaces collapsing.
  static TextStyle style({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w500,
    Color? color,
    double height = 1.25,
    double letterSpacing = 0,
    FontStyle fontStyle = FontStyle.normal,
  }) {
    return TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontFamilyFallback: const ['sans-serif'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      wordSpacing: 0.4,
      fontStyle: fontStyle,
    );
  }

  static TextStyle get heading => style(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        height: 1.15,
        letterSpacing: -0.4,
      );

  static TextStyle get title => style(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: text,
      );

  static TextStyle get body => style(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: muted,
      );

  static TextStyle get cardNumber => style(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: text,
        height: 1.1,
      );
}
