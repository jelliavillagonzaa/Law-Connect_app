import 'package:flutter/material.dart';

/// [Listenable.merge] must be created once, not inside [build].
/// Recreating it every frame deactivates [InheritedElement]s while widgets
/// still depend on them (`_dependents.isEmpty` red screen on Flutter web).
class StableMergedListenableBuilder extends StatefulWidget {
  const StableMergedListenableBuilder({
    super.key,
    required this.listenables,
    required this.builder,
    this.child,
  });

  final List<Listenable> listenables;
  final TransitionBuilder builder;
  final Widget? child;

  @override
  State<StableMergedListenableBuilder> createState() =>
      _StableMergedListenableBuilderState();
}

class _StableMergedListenableBuilderState
    extends State<StableMergedListenableBuilder> {
  late Listenable _merged = Listenable.merge(widget.listenables);

  @override
  void didUpdateWidget(covariant StableMergedListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_same(oldWidget.listenables, widget.listenables)) return;
    _merged = Listenable.merge(widget.listenables);
  }

  bool _same(List<Listenable> a, List<Listenable> b) {
    if (identical(a, b) || a.length != b.length) return a.length == b.length;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _merged,
      builder: widget.builder,
      child: widget.child,
    );
  }
}
