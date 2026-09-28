import 'package:flutter/material.dart';

import 'attorney_ui_theme.dart';

class AttorneyActionCard extends StatefulWidget {
  const AttorneyActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<AttorneyActionCard> createState() => _AttorneyActionCardState();
}

class _AttorneyActionCardState extends State<AttorneyActionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: AttorneyUi.anim,
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..translateByDouble(0, _hover ? -4.0 : 0.0, 0, 1),
        decoration: BoxDecoration(
          color: AttorneyUi.card,
          borderRadius: BorderRadius.circular(AttorneyUi.radius),
          boxShadow: _hover ? AttorneyUi.cardShadowHover : AttorneyUi.cardShadow,
          border: Border.all(color: AttorneyUi.line),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(AttorneyUi.radius),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AttorneyUi.radius),
              child: Stack(
                children: [
                  Positioned(
                    right: 24,
                    top: -8,
                    child: IgnorePointer(
                      child: Icon(
                        Icons.balance,
                        size: 88,
                        color: AttorneyUi.primary.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    width: 180,
                    height: 72,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _CreateWavePainter(
                          color: AttorneyUi.primary.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AttorneyUi.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add,
                            color: AttorneyUi.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                style: AttorneyUi.style(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AttorneyUi.text,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.subtitle,
                                style: AttorneyUi.style(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AttorneyUi.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AttorneyUi.muted,
                          size: 28,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateWavePainter extends CustomPainter {
  const _CreateWavePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height * 0.55)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.05,
        size.width * 0.62,
        size.height * 0.5,
      )
      ..quadraticBezierTo(
        size.width * 0.82,
        size.height * 0.85,
        size.width,
        size.height * 0.4,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CreateWavePainter oldDelegate) =>
      oldDelegate.color != color;
}
