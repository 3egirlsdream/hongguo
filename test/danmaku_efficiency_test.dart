import 'package:duanju_app/danmaku_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'danmaku_fixtures.dart';
import 'danmaku_test.dart' show danmakuPlan, updateDanmaku, flushDanmaku;

void main() {
  test(
    'steady position events do not rebuild the overlay or playback menu',
    () async {
      var now = DateTime(2026);
      final controller = DanmakuController(
        DanmakuFixtureRepository(),
        now: () => now,
      )..setPlan(danmakuPlan);
      addTearDown(controller.dispose);
      updateDanmaku(controller);
      await flushDanmaku();
      var notifications = 0;
      controller.addListener(() => notifications++);
      for (var i = 1; i <= 20; i++) {
        now = now.add(const Duration(milliseconds: 100));
        updateDanmaku(controller, position: i * 100);
      }
      expect(notifications, 0);
      updateDanmaku(controller, position: 2000, playing: false);
      expect(notifications, 1);
    },
  );

  test('an outgoing overlay cannot cancel the new season request', () async {
    final repository = DanmakuFixtureRepository()..holdDanmaku = true;
    final old = DanmakuController(repository)..setPlan(danmakuPlan);
    updateDanmaku(old);
    final current = DanmakuController(repository)..setPlan(danmakuPlan);
    updateDanmaku(current);
    old.dispose();
    expect(repository.danmakuCancellations, 0);
    for (final call in repository.danmakuCalls) {
      call.result.complete(DanmakuFixtureRepository.page(call));
    }
    await flushDanmaku();
    expect(current.items, isNotEmpty);
    current.dispose();
  });
}
