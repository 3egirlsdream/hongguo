import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/detail_screen.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  Future<LocalStore> store() async {
    SharedPreferences.setMockInitialValues({});
    return LocalStore(await SharedPreferences.getInstance());
  }

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('fresh details and saved progress at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FixtureRepository();
      final local = await store();
      await tester.pumpWidget(
        MaterialApp(
          home: DetailScreen(
            drama: FixtureRepository.free,
            repository: repository,
            store: local,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('VIP：隐藏'), findsNothing);
      expect(find.text('测试短剧'), findsWidgets);
      expect(find.text('黄豆'), findsNothing);
      expect(find.text('会员测试剧'), findsNothing);
      expect(repository.detailCalls, 1);
      if (size.width < 960) {
        await tester.ensureVisible(find.text('选集 · 2 集'));
        await tester.tap(find.text('选集 · 2 集'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('episode-2')));
        expect(find.byKey(const ValueKey('episode-2')), findsOneWidget);
      }
      await tester.ensureVisible(find.byKey(const ValueKey('follow-status')));
      await tester.tap(find.byKey(const ValueKey('follow-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('想看'));
      await tester.pumpAndSettle();
      expect(local.isFavorite(FixtureRepository.free.id), isTrue);
      for (final episode in [1, 2]) {
        await local.saveWatch(
          WatchEntry(
            drama: FixtureRepository.free,
            episode: episode,
            position: 18.5,
            duration: 90,
            updatedAt: DateTime.now(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('继续播放 · 第 $episode 集'), findsOneWidget);
      }
      await local.clearHistory();
      await tester.pumpAndSettle();
      expect(find.text('立即播放'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      local.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  test('watch progress and favorites survive a new store', () async {
    final local = await store();
    await local.saveWatch(
      WatchEntry(
        drama: FixtureRepository.free,
        episode: 2,
        position: 18.5,
        duration: 90,
        updatedAt: DateTime.now(),
      ),
    );
    await local.toggleFavorite(FixtureRepository.free);
    final restored = LocalStore(local.preferences);
    expect(restored.watched(FixtureRepository.free.id)?.position, 18.5);
    expect(restored.watched(FixtureRepository.free.id)?.episode, 2);
    expect(restored.isFavorite(FixtureRepository.free.id), isTrue);
  });
}
