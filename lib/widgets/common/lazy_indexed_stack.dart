import 'package:flutter/material.dart';

/// Shows one child at a time; builds each tab only on first visit, then keeps it alive.
class LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget Function()> builders;

  /// When this value changes **while the same tab stays visible**, that tab is
  /// rebuilt (e.g. dashboard stats). Switching tabs does not remount a tab
  /// that was already built.
  final Object? activeTabRevision;

  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.builders,
    this.activeTabRevision,
  }) : assert(builders.length > 0);

  @override
  State<LazyIndexedStack> createState() => LazyIndexedStackState();
}

class _Prewarmed {
  const _Prewarmed();
}

class LazyIndexedStackState extends State<LazyIndexedStack> {
  static const _prewarmed = _Prewarmed();

  late List<Widget?> _built =
      List<Widget?>.filled(widget.builders.length, null);
  late List<Object?> _revisionWhenBuilt =
      List<Object?>.filled(widget.builders.length, null);

  void _ensureLength() {
    final n = widget.builders.length;
    if (_built.length == n) return;
    final oldBuilt = _built;
    final oldRev = _revisionWhenBuilt;
    _built = List<Widget?>.filled(n, null);
    _revisionWhenBuilt = List<Object?>.filled(n, null);
    final copy = oldBuilt.length < n ? oldBuilt.length : n;
    for (var i = 0; i < copy; i++) {
      _built[i] = oldBuilt[i];
      _revisionWhenBuilt[i] = oldRev[i];
    }
  }

  /// Build a tab in the background so the first tap is instant (e.g. calendar).
  void prewarm(int tabIndex) {
    _ensureLength();
    if (tabIndex < 0 || tabIndex >= _built.length) return;
    if (_built[tabIndex] != null) return;
    setState(() {
      _built[tabIndex] = widget.builders[tabIndex]();
      _revisionWhenBuilt[tabIndex] = _prewarmed;
    });
  }

  void _ensureVisibleTab() {
    _ensureLength();
    final i = widget.index.clamp(0, widget.builders.length - 1);
    final rev = widget.activeTabRevision;
    if (_built[i] == null) {
      _built[i] = widget.builders[i]();
      _revisionWhenBuilt[i] = rev;
      return;
    }
    if (_revisionWhenBuilt[i] == _prewarmed) {
      _revisionWhenBuilt[i] = rev;
      return;
    }
    if (_revisionWhenBuilt[i] != rev) {
      _built[i] = widget.builders[i]();
      _revisionWhenBuilt[i] = rev;
    }
  }

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureVisibleTab();
  }

  @override
  Widget build(BuildContext context) {
    _ensureVisibleTab();
    final i = widget.index.clamp(0, widget.builders.length - 1);

    return IndexedStack(
      index: i,
      sizing: StackFit.expand,
      children: List.generate(widget.builders.length, (j) {
        return KeyedSubtree(
          key: ValueKey<int>(j),
          child: _built[j] ?? const SizedBox.expand(),
        );
      }),
    );
  }
}
