import 'package:flutter/material.dart';

/// Visual tokens for the premium Admin Dashboard only.
class AdminUi {
  AdminUi._();

  static const Color primary = Color(0xFF183B73);
  static const Color secondary = Color(0xFF274C8E);
  static const Color accent = Color(0xFFFF8A3D);
  static const Color accentDeep = Color(0xFFE56A1A);
  static const Color background = Color(0xFFF5F7FB);
  static const Color card = Color(0xFFFFFFFF);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
  static const Color text = Color(0xFF12233F);
  static const Color muted = Color(0xFF6B7A90);
  static const Color line = Color(0xFFE6EAF2);

  static const double radius = 16;
  static const double heroRadius = 20;
  static const double sidebarWidth = 220;
  static const Duration anim = Duration(milliseconds: 200);

  static const LinearGradient navyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1A2B4B), Color(0xFF0A1324)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentDeep],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0C1B38), Color(0xFF183B73), Color(0xFF0A1324)],
  );

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF183B73).withValues(alpha: 0.08),
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
          color: const Color(0xFF183B73).withValues(alpha: 0.18),
          blurRadius: 36,
          offset: const Offset(0, 18),
        ),
        BoxShadow(
          color: accent.withValues(alpha: 0.14),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> get heroShadow => [
        BoxShadow(
          color: primary.withValues(alpha: 0.32),
          blurRadius: 36,
          offset: const Offset(0, 16),
        ),
      ];

  static BoxDecoration get panelDecoration => BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: cardShadow,
        border: Border.all(color: line),
      );

  static TextStyle get heading => const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: text,
        letterSpacing: -0.2,
      );

  static TextStyle get label => const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: text,
      );

  static TextStyle get description => const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: muted,
        height: 1.4,
      );
}
