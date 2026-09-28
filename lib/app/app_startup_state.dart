import 'dart:async' show Completer;

/// Global flags set during background Firebase init.
class AppStartupState {
  AppStartupState._();

  static bool firebaseReady = false;
  static Completer<void>? _ready;

  /// Completes when Firebase init finishes (success or failure).
  static Future<void> get whenFirebaseReady {
    if (firebaseReady) return Future<void>.value();
    return (_ready ??= Completer<void>()).future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {},
    );
  }

  static void markReady() {
    firebaseReady = true;
    _complete();
  }

  static void markFailed() {
    firebaseReady = false;
    _complete();
  }

  static void _complete() {
    final gate = _ready;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }
}
