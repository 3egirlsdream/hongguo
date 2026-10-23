import 'dart:async';

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
        } catch (_) {
          mark(stage, elapsedMs: started.elapsedMilliseconds, ok: false);
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
