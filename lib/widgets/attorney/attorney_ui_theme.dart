import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Visual tokens for the Attorney Dashboard only.
class AttorneyUi {
  AttorneyUi._();

  static const Color primary = Color(0xFF183B73);
  static const Color sidebar = Color(0xFF163A72);
  static const Color sidebarDeep = Color(0xFF102D59);
  static const Color accent = Color(0xFFFF8A3D);
  static const Color background = Color(0xFFF5F7FB);
  static const Color card = Color(0xFFFFFFFF);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color text = Color(0xFF12233F);
  static const Color muted = Color(0xFF6B7A90);
  static const Color line = Color(0xFFE6EAF2);

  static const double radius = 16;
  static const double heroRadius = 18;
  static const double sidebarWidth = 248;
  static const Duration anim = Duration(milliseconds: 200);

  static const LinearGradient sidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF102A61), Color(0xFF0A1931)],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF173B73), Color(0xFF214C91)],
  );

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: primary.withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get cardShadowHover => [
        BoxShadow(
          color: primary.withValues(alpha: 0.18),
          blurRadius: 36,
          offset: const Offset(0, 18),
        ),
        BoxShadow(
          color: accent.withValues(alpha: 0.12),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ];

  /// Bundled NotoSans — GoogleFonts.inter collapses spaces on Android/web.
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
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        height: 1.15,
      );

  static TextStyle get cardNumber => style(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: text,
        height: 1.15,
      );

  static TextStyle get cardTitle => style(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: text,
      );

  static TextStyle get description => style(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: muted,
        height: 1.35,
      );

  static TextStyle get sidebarLabel => style(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      );
}
