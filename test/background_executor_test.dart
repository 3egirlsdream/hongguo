import 'dart:io';
import 'dart:isolate';

import 'package:duanju_app/background_executor.dart';
import 'package:flutter_test/flutter_test.dart';

String workerIdentity(int milliseconds) {
  sleep(Duration(milliseconds: milliseconds));
  return Isolate.current.debugName ?? '';
}

int failedWork(int _) => throw StateError('synthetic failure');

void main() {
  test('blocking work stays off the caller and workers are reused', () async {
    final executor = BackgroundExecutor(interactiveWorkers: 1);
    addTearDown(executor.close);
    var heartbeats = 0;
    final work = executor.run(workerIdentity, 80);
    while (executor.tasksCompleted == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      heartbeats++;
    }
    final first = await work;
    final second = await executor.run(workerIdentity, 0);
    expect(first, startsWith('guo-interactive-'));
    expect(second, first);
    expect(executor.workersStarted, 1);
    expect(heartbeats, greaterThan(3));
  });

  test(
    'control cancellation bypasses busy workers and removes queued work',
    () async {
      final executor = BackgroundExecutor(
        interactiveWorkers: 1,
        backgroundWorkers: 1,
      );
      addTearDown(executor.close);
      final busy = executor.run(workerIdentity, 150);
      final old = executor.run(
        workerIdentity,
        10000,
        scope: 'episode',
        sequence: 1,
      );
      final cancelled = expectLater(old, throwsA(isA<WorkCancelled>()));
      final latest = executor.run(
        workerIdentity,
        0,
        scope: 'episode',
        sequence: 2,
      );
      final control = await executor.run(
        workerIdentity,
        0,
        lane: WorkLane.control,
      );
      expect(control, startsWith('guo-control-'));
      expect(executor.tasksCompleted, 1);
      await cancelled;
      await busy;
      await latest;
      expect(executor.tasksCancelled, 1);
    },
  );

  test('task errors preserve the worker and pending limits apply', () async {
    final executor = BackgroundExecutor(interactiveWorkers: 1, maxPending: 1);
    addTearDown(executor.close);
    await expectLater(
      executor.run(failedWork, 0),
      throwsA(isA<BackgroundWorkFailure>()),
    );
    final busy = executor.run(workerIdentity, 30);
    final queued = executor.run(workerIdentity, 0);
    await expectLater(
      executor.run(workerIdentity, 0),
      throwsA(isA<BackgroundWorkFailure>()),
    );
    await busy;
    await queued;
    expect(executor.workersStarted, 1);
  });
}
