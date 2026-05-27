import 'package:flutter/material.dart';

/// Shows one child at a time; builds each tab only on first visit, then keeps it alive.
class LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget Function()> builders;

  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.builders,
  }) : assert(builders.length > 0);

  @override
  State<LazyIndexedStack> createState() => LazyIndexedStackState();
}

class LazyIndexedStackState extends State<LazyIndexedStack> {
  late final List<Widget?> _built =
      List<Widget?>.filled(widget.builders.length, null);

  /// Build a tab in the background so the first tap is instant (e.g. calendar).
  void prewarm(int tabIndex) {
    if (tabIndex < 0 || tabIndex >= _built.length) return;
    if (_built[tabIndex] != null) return;
    setState(() => _built[tabIndex] = widget.builders[tabIndex]());
  }

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    final i = widget.index.clamp(0, widget.builders.length - 1);
    _built[i] ??= widget.builders[i]();
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.index.clamp(0, widget.builders.length - 1);
    if (_built[i] == null) {
      _built[i] = widget.builders[i]();
    }

    return IndexedStack(
      index: i,
      sizing: StackFit.expand,
      children: List.generate(widget.builders.length, (j) {
        return _built[j] ?? const SizedBox.expand();
      }),
    );
  }
}
