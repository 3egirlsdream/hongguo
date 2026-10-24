import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'diary_service.dart';

class PlaybackTrace {
  PlaybackTrace(String trigger)
    : id = '${DateTime.now().microsecondsSinceEpoch}-${++_sequence}' {
    mark(trigger);
  }

  static final _zoneKey = Object();
  static int _sequence = 0;
  static PlaybackTrace? get current => Zone.current[_zoneKey] as PlaybackTrace?;

  final String id;
  final Stopwatch _clock = Stopwatch()..start();

  void event(
    String name, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {
    DiaryService.add(
      '[Playback] ${jsonEncode({'trace': id, 'event': name, 'elapsedMs': _clock.elapsedMilliseconds, ...fields, if (error != null) 'errorType': error.runtimeType.toString(), if (error != null) 'error': DiaryService.sanitize(error.toString()), if (stack != null) 'stack': DiaryService.sanitize(stack.toString().split('\n').take(6).join(' | '))})}',
    );
  }

  Future<void> networkSnapshot() async {
    try {
      final info = await const MethodChannel('duanju/device')
          .invokeMapMethod<String, dynamic>('diagnosticInfo')
          .timeout(const Duration(seconds: 2));
      event(
        'environment',
        fields: {
          for (final key in [
            'sdk',
            'manufacturer',
            'model',
            'transports',
            'internet',
            'validated',
            'metered',
            'proxy',
          ])
            if (info?.containsKey(key) == true) key: info![key],
        },
      );
    } catch (_) {
      event('environment_unavailable');
    }
  }

  T run<T>(T Function() work) => runZoned(work, zoneValues: {_zoneKey: this});

  void mark(String stage, {int? elapsedMs, bool ok = true}) {
    DiaryService.add(
      '[PlayTiming] trace=$id stage=$stage '
      '${elapsedMs == null ? '' : 'elapsed_ms=$elapsedMs '}'
      'total_ms=${_clock.elapsedMilliseconds} ok=$ok',
    );
  }

  Future<T> measure<T>(String stage, Future<T> Function() work) =>
      run(() async {
        final started = Stopwatch()..start();
        try {
          final result = await work();
          mark(stage, elapsedMs: started.elapsedMilliseconds);
          return result;
        } catch (error, stack) {
          mark(stage, elapsedMs: started.elapsedMilliseconds, ok: false);
          event(
            'stage_failed',
            fields: {'stage': stage},
            error: error,
            stack: stack,
          );
          rethrow;
        }
      });

  static void recordNative(String traceId, String action, Object? entries) {
    if (entries is! List) return;
    for (final entry in entries.whereType<Map>()) {
      DiaryService.add(
        '[PlayTiming] trace=$traceId action=$action '
        'stage=${entry['stage']} elapsed_ms=${entry['elapsedMs']} '
        'core_total_ms=${entry['totalMs']} ok=${entry['ok']}',
      );
    }
  }
}
