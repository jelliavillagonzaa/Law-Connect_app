import 'package:flutter/material.dart';

/// Visual tokens for the Client app only.
class ClientUi {
  ClientUi._();

  static const Color navy = Color(0xFF0E2A4A);
  static const Color navyMid = Color(0xFF163A66);
  static const Color gold = Color(0xFFF1C40F);
  static const Color background = Color(0xFFF5F7FB);
  static const Color card = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF12233F);
  static const Color muted = Color(0xFF6B7A90);
  static const Color line = Color(0xFFE6EAF2);
  static const Color green = Color(0xFF22C55E);

  static const double radius = 16;

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: navy.withValues(alpha: 0.07),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  static TextStyle get heading => const TextStyle(
        fontFamily: 'NotoSans',
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: navy,
      );

  static TextStyle get body => const TextStyle(
        fontFamily: 'NotoSans',
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: muted,
      );
}
