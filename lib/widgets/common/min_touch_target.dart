import 'package:flutter/material.dart';

/// Ensures at least [minSize]×[minSize] tap area with Material ripple feedback.
class MinTouchTarget extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double minSize;
  final BorderRadius borderRadius;
  final Color? splashColor;
  final Color? highlightColor;
  final String? tooltip;

  const MinTouchTarget({
    super.key,
    required this.child,
    this.onTap,
    this.minSize = 48,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.splashColor,
    this.highlightColor,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        splashColor: splashColor,
        highlightColor: highlightColor,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
          child: Center(child: child),
        ),
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) return content;
    return Tooltip(message: tooltip!, child: content);
  }
}
