import 'dart:async';

import 'package:duanju_app/account_request_scheduler.dart';
import 'package:duanju_app/background_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reservation and calendar APIs bypass a blocked sync and preserve serialized writes', () async {
    final scheduler = AccountRequestScheduler();
    final blocked = Completer<String>();
    final sync = scheduler.run('sync', {}, () => blocked.future);
    var writeStarted = false;
    final write = scheduler.run('favorite', {}, () async {
      writeStarted = true;
      return 'written';
    });
    for (final command in [
      'reservations',
      'calendar',
      'history',
      'reserve',
      'status',
    ]) {
      expect(
        await scheduler
            .run(command, {}, () async => command)
            .timeout(const Duration(seconds: 1)),
        command,
      );
    }
    expect(writeStarted, isFalse);
    blocked.complete('synced');
    expect(await sync, 'synced');
    expect(await write, 'written');
  });
  test('cancelled queued reads do not execute and do not poison subsequent requests', () async {
    final scheduler = AccountRequestScheduler();
    final blocked = Completer<void>();
    final sync = scheduler.run('sync', {}, () => blocked.future);
    var current = true, calls = 0;
    final old = scheduler.run('favorites', {}, () async {
      if (!current) throw const WorkCancelled();
      calls++;
      return 1;
    });
    final cancelled = expectLater(old, throwsA(isA<WorkCancelled>()));
    current = false;
    expect(await scheduler.run('reservations', {}, () async => 20), 20);
    blocked.complete();
    await sync;
    await cancelled;
    expect(calls, 0);
    expect(await scheduler.run('profile', {}, () async => 1), 1);
  });
}
