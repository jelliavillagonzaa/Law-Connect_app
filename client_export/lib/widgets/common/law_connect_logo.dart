import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Reusable Law Connect logo widget
class LawConnectLogo extends StatelessWidget {
  final double size;
  final Color? color;
  final Color? goldColor;
  final bool showGlow;

  const LawConnectLogo({
    super.key,
    this.size = 120,
    this.color,
    this.goldColor,
    this.showGlow = false,
  });

  @override
  Widget build(BuildContext context) {
    final logoColor = color ?? AppTheme.royalBlue;
    final ccColor = goldColor ?? AppTheme.gold;

    return Container(
      width: size,
      height: size,
      decoration: showGlow
          ? BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: logoColor.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            )
          : null,
      child: CustomPaint(
        painter: LawConnectLogoPainter(
          logoColor: logoColor,
          goldColor: ccColor,
        ),
      ),
    );
  }
}

/// Custom painter for Law Connect logo (Bridge + CC + Legal Scale)
class LawConnectLogoPainter extends CustomPainter {
  final Color logoColor;
  final Color goldColor;

  LawConnectLogoPainter({
    this.logoColor = Colors.white,
    this.goldColor = const Color(0xFFF1C40F),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = logoColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 3;

    // Draw bridge (arch)
    final bridgePath = Path();
    bridgePath.moveTo(center.dx - radius * 0.8, center.dy + radius * 0.3);
    bridgePath.quadraticBezierTo(
      center.dx,
      center.dy - radius * 0.5,
      center.dx + radius * 0.8,
      center.dy + radius * 0.3,
    );
    canvas.drawPath(bridgePath, paint);

    // Draw legal scale (balance)
    final scaleY = center.dy - radius * 0.2;
    // Left pan
    canvas.drawLine(
      Offset(center.dx - radius * 0.4, scaleY),
      Offset(center.dx - radius * 0.1, scaleY),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx - radius * 0.25, scaleY - radius * 0.15),
      Offset(center.dx - radius * 0.25, scaleY + radius * 0.15),
      paint,
    );
    // Right pan
    canvas.drawLine(
      Offset(center.dx + radius * 0.1, scaleY),
      Offset(center.dx + radius * 0.4, scaleY),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + radius * 0.25, scaleY - radius * 0.15),
      Offset(center.dx + radius * 0.25, scaleY + radius * 0.15),
      paint,
    );
    // Center support
    canvas.drawLine(
      Offset(center.dx, scaleY),
      Offset(center.dx, center.dy + radius * 0.2),
      paint,
    );

    // Draw "CC" text (simplified as overlapping circles)
    final ccPaint = Paint()
      ..color = goldColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // C letters (simplified representation)
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(center.dx - radius * 0.3, center.dy),
        radius: radius * 0.25,
      ),
      -1.5,
      3.0,
      false,
      ccPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(center.dx + radius * 0.3, center.dy),
        radius: radius * 0.25,
      ),
      -1.5,
      3.0,
      false,
      ccPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

