import 'dart:async' show runZoned, runZonedGuarded, ZoneSpecification;
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Pass `--dart-define=VERBOSE_LOGS=true` to see full console output.
const bool kVerboseAppLogs = bool.fromEnvironment('VERBOSE_LOGS');

/// Full framework dumps only when verbose logging is enabled.
bool get kShowFrameworkErrors => kVerboseAppLogs;

String? _lastErrorSignature;
int _suppressedErrorCount = 0;
DateTime? _lastErrorAt;

/// Silence [debugPrint] unless verbose.
void configureQuietConsole() {
  if (kVerboseAppLogs) return;
  debugPrint = (String? message, {int? wrapWidth}) {};
}

/// App-wide logger — writes only when [kVerboseAppLogs] is true.
void appLog(String message, {String name = 'law_connect'}) {
  if (!kVerboseAppLogs) return;
  developer.log(message, name: name);
}

bool isBenignFirestoreRuntimeError(Object? error) {
  if (error == null) return false;
  final s = error.toString();
  if (s.contains('permission-denied') || s.contains('PERMISSION_DENIED')) {
    return true;
  }
  if (s.contains('Timestamp') && s.contains('is not a subtype of type')) {
    return true;
  }
  return false;
}

bool _isLayoutNoise(Object? error) {
  if (error == null) return false;
  final s = error.toString();
  return s.contains('Vertical viewport was given unbounded height') ||
      s.contains('RenderFlex children have non-zero flex') ||
      s.contains('BoxConstraints forces an infinite height') ||
      s.contains('mouse_tracker.dart') ||
      s.contains('Unexpected null value') ||
      s.contains('Assertion failed');
}

String _shortError(Object? error) {
  final line = error.toString().split('\n').first.trim();
  return line.length > 140 ? '${line.substring(0, 140)}…' : line;
}

void _logErrorOnce(Object error, [StackTrace? stack]) {
  if (isBenignFirestoreRuntimeError(error)) return;

  if (kVerboseAppLogs) {
    FlutterError.presentError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
    return;
  }

  final signature = '${error.runtimeType}:${_shortError(error)}';
  final now = DateTime.now();

  if (_lastErrorSignature == signature &&
      _lastErrorAt != null &&
      now.difference(_lastErrorAt!) < const Duration(seconds: 4)) {
    _suppressedErrorCount++;
    return;
  }

  if (_suppressedErrorCount > 0) {
    developer.log(
      '(suppressed $_suppressedErrorCount similar errors)',
      name: 'law_connect',
    );
    _suppressedErrorCount = 0;
  }

  _lastErrorSignature = signature;
  _lastErrorAt = now;

  final prefix = _isLayoutNoise(error) ? 'Layout' : 'Error';
  developer.log('$prefix: $signature', name: 'law_connect', level: 1000);
}

void installQuietErrorHandlers() {
  if (kVerboseAppLogs) return;

  FlutterError.onError = (FlutterErrorDetails details) {
    _logErrorOnce(details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _logErrorOnce(error, stack);
    return true;
  };
}

ZoneSpecification _quietZoneSpec() {
  if (kVerboseAppLogs) return ZoneSpecification();
  return ZoneSpecification(
    print: (self, parent, zone, line) {},
  );
}

/// Runs [body] in a quiet zone (silences [print], catches async errors).
Future<void> runQuietApp(Future<void> Function() body) async {
  if (kVerboseAppLogs) {
    await body();
    return;
  }

  final result = runZonedGuarded<Future<void>>(
    body,
    (error, stack) => _logErrorOnce(error, stack),
    zoneSpecification: _quietZoneSpec(),
  );

  if (result != null) {
    await result;
  } else {
    await runZoned(body, zoneSpecification: _quietZoneSpec());
  }
}

/// Alias for older call sites.
Future<void> runQuiet(Future<void> Function() body) => runQuietApp(body);
