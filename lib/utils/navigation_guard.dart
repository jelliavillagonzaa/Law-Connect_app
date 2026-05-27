/// Prevents double-taps from stacking duplicate routes (common on mobile + web).
class NavigationGuard {
  NavigationGuard._();

  static bool _busy = false;

  static bool get isBusy => _busy;

  /// Runs [action] once; ignores further calls until [cooldown] elapses.
  static bool runOnce(void Function() action, {Duration cooldown = const Duration(milliseconds: 400)}) {
    if (_busy) return false;
    _busy = true;
    action();
    Future<void>.delayed(cooldown, () => _busy = false);
    return true;
  }
}
