import 'package:flutter/material.dart';

import 'attorney_ui_theme.dart';

class AttorneyDashboardCard extends StatefulWidget {
  const AttorneyDashboardCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.pastel,
    this.subtitle,
    this.percentageChange,
    this.isPositiveChange = true,
    this.onTap,
    this.wide = false,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final Color pastel;
  final String? percentageChange;
  final bool isPositiveChange;
  final VoidCallback? onTap;
  final bool wide;

  @override
  State<AttorneyDashboardCard> createState() => _AttorneyDashboardCardState();
}

class _AttorneyDashboardCardState extends State<AttorneyDashboardCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 800;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: AttorneyUi.anim,
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..translateByDouble(0, _hover ? -3.0 : 0.0, 0, 1)
          ..scaleByDouble(
            _hover ? 1.02 : 1.0,
            _hover ? 1.02 : 1.0,
            1,
            1,
          ),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: AttorneyUi.card,
          borderRadius: BorderRadius.circular(AttorneyUi.radius),
          boxShadow: _hover ? AttorneyUi.cardShadowHover : AttorneyUi.cardShadow,
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
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            widget.pastel,
                            widget.pastel.withValues(alpha: 0.35),
                            Colors.white,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    width: widget.wide ? 220 : 150,
                    height: widget.wide ? 90 : 70,
                    child: CustomPaint(
                      painter: _WavePainter(
                        color: widget.iconColor.withValues(alpha: 0.16),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 18,
                    bottom: 16,
                    child: _MiniBars(color: widget.iconColor),
                  ),
                  Padding(
                    padding: EdgeInsets.all(compact ? 12 : 14),
                    child: widget.wide
                        ? _WideBody(
                            compact: compact,
                            title: widget.title,
                            value: widget.value,
                            icon: widget.icon,
                            iconColor: widget.iconColor,
                            percentageChange: widget.percentageChange,
                            isPositiveChange: widget.isPositiveChange,
                          )
                        : _StandardBody(
                            compact: compact,
                            title: widget.title,
                            value: widget.value,
                            subtitle: widget.subtitle,
                            icon: widget.icon,
                            iconColor: widget.iconColor,
                            percentageChange: widget.percentageChange,
                            isPositiveChange: widget.isPositiveChange,
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

class _StandardBody extends StatelessWidget {
  const _StandardBody({
    required this.compact,
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.subtitle,
    this.percentageChange,
    this.isPositiveChange = true,
  });

  final bool compact;
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final String? percentageChange;
  final bool isPositiveChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _RoundIcon(icon: icon, color: iconColor, compact: compact),
            const Spacer(),
            if (percentageChange != null)
              _PercentBadge(
                label: percentageChange!,
                positive: isPositiveChange,
              ),
          ],
        ),
        const Spacer(),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: AttorneyUi.style(
              fontSize: compact ? 22 : 26,
              fontWeight: FontWeight.w700,
              color: AttorneyUi.text,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: AttorneyUi.style(
            fontSize: compact ? 13 : 14,
            fontWeight: FontWeight.w600,
            color: AttorneyUi.text,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: AttorneyUi.style(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AttorneyUi.muted,
            ),
          ),
        ],
      ],
    );
  }
}

class _WideBody extends StatelessWidget {
  const _WideBody({
    required this.compact,
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.percentageChange,
    this.isPositiveChange = true,
  });

  final bool compact;
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final String? percentageChange;
  final bool isPositiveChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundIcon(icon: icon, color: iconColor, compact: compact),
        const SizedBox(width: 16),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: AttorneyUi.style(
              fontSize: compact ? 22 : 26,
              fontWeight: FontWeight.w700,
              color: AttorneyUi.text,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: AttorneyUi.style(
              fontSize: compact ? 14 : 16,
              fontWeight: FontWeight.w600,
              color: AttorneyUi.text,
            ),
          ),
        ),
        if (percentageChange != null)
          _PercentBadge(label: percentageChange!, positive: isPositiveChange),
        const SizedBox(width: 10),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.chevron_right_rounded, color: iconColor),
        ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.color,
    required this.compact,
  });

  final IconData icon;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 36 : 40,
      height: compact ? 36 : 40,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: compact ? 18 : 20),
    );
  }
}

class _PercentBadge extends StatelessWidget {
  const _PercentBadge({required this.label, required this.positive});

  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive ? AttorneyUi.success : AttorneyUi.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${positive ? '↑' : '↓'} $label',
        style: AttorneyUi.style(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    const heights = [10.0, 16.0, 12.0, 22.0, 14.0, 20.0, 26.0];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final h in heights)
          Container(
            width: 5,
            height: h,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size.height * 0.58)
      ..quadraticBezierTo(
        size.width * 0.28,
        size.height * 0.08,
        size.width * 0.55,
        size.height * 0.48,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.82,
        size.width,
        size.height * 0.38,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.color != color;
}
