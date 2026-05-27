import 'dart:async' show runZoned, ZoneSpecification;

import 'package:flutter/foundation.dart';

/// Pass `--dart-define=VERBOSE_LOGS=true` only when debugging backend issues.
const bool kVerboseAppLogs = bool.fromEnvironment('VERBOSE_LOGS');

/// In debug/profile, always surface framework errors (quiet console hid real crashes).
bool get kShowFrameworkErrors => kDebugMode || kProfileMode || kVerboseAppLogs;

/// Call once at startup (before Firebase / GetX) to silence [debugPrint] app-wide.
void configureQuietConsole() {
  if (kVerboseAppLogs) return;
  debugPrint = (String? message, {int? wrapWidth}) {};
}

/// Runs [body] in a zone where [print] is dropped (app + web + mobile).
Future<void> runQuiet(Future<void> Function() body) {
  if (kVerboseAppLogs) return body();
  return runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {},
    ),
  );
}

/// Legacy: zone around [runApp] only (prefer [runQuiet] for full [main]).
void runAppQuiet(void Function() runAppCallback) {
  if (kVerboseAppLogs) {
    runAppCallback();
    return;
  }
  runZoned(
    runAppCallback,
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {},
    ),
  );
}
