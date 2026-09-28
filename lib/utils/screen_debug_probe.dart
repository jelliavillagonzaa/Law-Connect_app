import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Debug-only instrumentation for screen freeze / crash diagnosis.
///
/// Logs to the console (`flutter run`) in debug builds. Wrap a screen with
/// [wrap] and use [track] around async work.
class ScreenDebugProbe {
  ScreenDebugProbe(this.screenName);

  final String screenName;
  final List<ProbeEvent> _events = <ProbeEvent>[];
  static const int _maxEvents = 48;

  Timer? _heartbeat;
  TimingsCallback? _frameTimingsCallback;
  int _slowFrameCount = 0;
  int _severeFrameCount = 0;
  Duration _worstFrame = Duration.zero;
  String? _lastError;
  int _buildCount = 0;
  bool _attached = false;
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  static const Duration _slowFrame = Duration(milliseconds: 32);
  static const Duration _severeFrame = Duration(milliseconds: 120);

  bool get isEnabled => kDebugMode;

  void attach() {
    if (!isEnabled || _attached) return;
    _attached = true;
    _log('attach');

    _frameTimingsCallback = (List<FrameTiming> timings) {
      for (final timing in timings) {
        final frame = timing.totalSpan;
        if (frame > _worstFrame) _worstFrame = frame;
        if (frame > _severeFrame) {
          _severeFrameCount++;
          _record(
            'FRAME_SEVERE',
            detail:
                '${frame.inMilliseconds}ms (build ${timing.buildDuration.inMilliseconds}ms, '
                'raster ${timing.rasterDuration.inMilliseconds}ms)',
            level: ProbeLevel.critical,
          );
        } else if (frame > _slowFrame) {
          _slowFrameCount++;
          if (_slowFrameCount % 8 == 1) {
            _record(
              'FRAME_SLOW',
              detail: '${frame.inMilliseconds}ms',
              level: ProbeLevel.warn,
            );
          }
        }
      }
      _notify();
    };
    SchedulerBinding.instance.addTimingsCallback(_frameTimingsCallback!);

    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_attached) return;
      _record(
        'heartbeat',
        detail:
            'builds=$_buildCount slowFrames=$_slowFrameCount '
            'severe=$_severeFrameCount worst=${_worstFrame.inMilliseconds}ms',
      );
    });
  }

  void detach() {
    if (!_attached) return;
    _log('detach');
    _heartbeat?.cancel();
    _heartbeat = null;
    if (_frameTimingsCallback != null) {
      SchedulerBinding.instance.removeTimingsCallback(_frameTimingsCallback!);
      _frameTimingsCallback = null;
    }
    _attached = false;
    _notify();
  }

  void event(String phase, {String? detail}) {
    _record(phase, detail: detail);
  }

  void onBuild({String? detail}) {
    _buildCount++;
    if (_buildCount <= 3 || _buildCount % 25 == 0) {
      _record('build', detail: detail ?? '#$_buildCount');
    }
  }

  Future<T> track<T>(String label, Future<T> Function() action) async {
    final sw = Stopwatch()..start();
    _record('$label:start');
    try {
      final result = await action();
      _record('$label:ok', duration: sw.elapsed);
      return result;
    } catch (e, st) {
      _lastError = '$e';
      _record(
        '$label:ERROR',
        detail: '$e\n${st.toString().split('\n').take(6).join('\n')}',
        level: ProbeLevel.critical,
      );
      rethrow;
    }
  }

  void trackSync(String label, void Function() action) {
    final sw = Stopwatch()..start();
    _record('$label:start');
    try {
      action();
      _record('$label:ok', duration: sw.elapsed);
    } catch (e, st) {
      _lastError = '$e';
      _record(
        '$label:ERROR',
        detail: '$e\n${st.toString().split('\n').take(6).join('\n')}',
        level: ProbeLevel.critical,
      );
      rethrow;
    }
  }

  Widget wrap(Widget child) {
    // Console-only in debug; never cover the UI with the probe panel.
    return child;
  }

  List<ProbeEvent> get recentEvents {
    final start = _events.length > 10 ? _events.length - 10 : 0;
    return _events.sublist(start);
  }

  String get summary {
    final err = _lastError == null ? '' : ' | lastError: $_lastError';
    return '$screenName | severeFrames=$_severeFrameCount worst=${_worstFrame.inMilliseconds}ms$err';
  }

  void _record(
    String phase, {
    String? detail,
    Duration? duration,
    ProbeLevel level = ProbeLevel.info,
  }) {
    if (!isEnabled) return;
    final event = ProbeEvent(
      at: DateTime.now(),
      phase: phase,
      detail: detail,
      duration: duration,
      level: level,
    );
    _events.add(event);
    if (_events.length > _maxEvents) {
      _events.removeRange(0, _events.length - _maxEvents);
    }
    _log(
      phase,
      detail: [
        if (duration != null) '${duration.inMilliseconds}ms',
        if (detail != null && detail.isNotEmpty) detail,
      ].join(' | '),
      level: level,
    );
    _notify();
  }

  void _log(
    String phase, {
    String? detail,
    ProbeLevel level = ProbeLevel.info,
  }) {
    if (!isEnabled) return;
    final prefix = level == ProbeLevel.critical
        ? '🔴'
        : level == ProbeLevel.warn
            ? '🟠'
            : '🔵';
    final body = detail == null || detail.isEmpty ? phase : '$phase — $detail';
    developer.log('$prefix [$screenName] $body', name: 'screen_debug', level: 800);
  }

  void _notify() {
    _tick.value++;
  }
}

enum ProbeLevel { info, warn, critical }

class ProbeEvent {
  const ProbeEvent({
    required this.at,
    required this.phase,
    this.detail,
    this.duration,
    this.level = ProbeLevel.info,
  });

  final DateTime at;
  final String phase;
  final String? detail;
  final Duration? duration;
  final ProbeLevel level;
}
