import 'package:flutter/material.dart';

/// Subtle line-art scales of justice for the admin hero.
class ScalesOfJustice extends StatelessWidget {
  const ScalesOfJustice({
    super.key,
    this.size = 220,
    this.opacity = 0.10,
  });

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.square(size),
        painter: _ScalesPainter(color: Colors.white.withValues(alpha: opacity)),
      ),
    );
  }
}

class _ScalesPainter extends CustomPainter {
  const _ScalesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.028
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = color.withValues(alpha: 0.045)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    final cx = w * 0.52;
    final top = h * 0.10;
    final beamY = h * 0.28;
    final panY = h * 0.62;

    canvas.drawLine(Offset(cx, top + 8), Offset(cx, h * 0.88), stroke);
    canvas.drawLine(
      Offset(w * 0.28, h * 0.88),
      Offset(w * 0.76, h * 0.88),
      stroke,
    );

    canvas.drawCircle(Offset(cx, top), size.width * 0.045, fill);
    canvas.drawCircle(Offset(cx, top), size.width * 0.045, stroke);

    canvas.drawLine(Offset(w * 0.16, beamY), Offset(w * 0.88, beamY), stroke);

    _drawPan(canvas, Offset(w * 0.22, beamY), panY, w, stroke, fill);
    _drawPan(canvas, Offset(w * 0.82, beamY), panY, w, stroke, fill);
  }

  void _drawPan(
    Canvas canvas,
    Offset pivot,
    double panY,
    double sizeW,
    Paint stroke,
    Paint fill,
  ) {
    canvas.drawLine(pivot, Offset(pivot.dx - sizeW * 0.13, panY), stroke);
    canvas.drawLine(pivot, Offset(pivot.dx + sizeW * 0.13, panY), stroke);

    final pan = Path()
      ..moveTo(pivot.dx - sizeW * 0.16, panY)
      ..quadraticBezierTo(pivot.dx, panY + sizeW * 0.13, pivot.dx + sizeW * 0.16, panY)
      ..close();
    canvas.drawPath(pan, fill);
    canvas.drawPath(pan, stroke);
  }

  @override
  bool shouldRepaint(covariant _ScalesPainter oldDelegate) =>
      oldDelegate.color != color;
}
