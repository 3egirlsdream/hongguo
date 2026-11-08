import 'package:duanju_app/danmaku_overlay.dart';
import 'package:duanju_app/app_theme.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/playback_preferences.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_efficiency_test.dart' show EfficiencyFixture;
import 'playback_test.dart' show DeviceFixtureRepository;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'keywords persist and immediately filter native playback danmaku',
    (tester) async {
      expect(const bool.fromEnvironment('DISABLE_REMOTE_IMAGES'), isTrue);
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      MediaKit.ensureInitialized();
      final repository = EfficiencyFixture();
      await repository.initialize();
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      await store.setPlaybackPreferences(
        const PlaybackPreferences(preload: false, autoAdvance: false),
      );
      Future<void> until(bool Function() ready, String step) async {
        final watch = Stopwatch()..start();
        while (!ready()) {
          if (watch.elapsed > const Duration(seconds: 30)) fail(step);
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          home: PlayerScreen(
            detail: await repository.detail(DeviceFixtureRepository.drama),
            initialIndex: 0,
            initialPosition: .1,
            repository: repository,
            store: store,
          ),
        ),
      );
      await until(() => find.byType(Video).evaluate().isNotEmpty, 'video');
      final player = tester.widget<Video>(find.byType(Video)).controller.player;
      await player.setVolume(0);
      final overlay = tester.widget<DanmakuOverlay>(
        find.byType(DanmakuOverlay),
      );
      await until(
        () =>
            overlay.controller.items.isNotEmpty &&
            player.state.position.inMilliseconds > 1000,
        'danmaku',
      );
      await player.pause();
      await tester.pump(const Duration(milliseconds: 400));
      final resolves = repository.resolved.length;
      await tester.tap(find.byTooltip('播放设置与清晰度'));
      await tester.pump(const Duration(milliseconds: 300));
      final entry = find.byKey(const ValueKey('player-danmaku-keywords'));
      await tester.ensureVisible(entry);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(entry);
      await tester.pump(const Duration(milliseconds: 300));
      final input = find.byKey(const ValueKey('danmaku-filter-editor'));
      await tester.enterText(input, '合 成弹幕，ＡＢＣ\nabc');
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<TextField>(input).controller!.text,
        '合 成弹幕，ＡＢＣ\nabc',
      );
      await tester.tap(find.byKey(const ValueKey('danmaku-filter-save')));
      await tester.pump(const Duration(milliseconds: 600));

      await until(
        () => store.playbackPreferences.danmakuBlockedKeywords.length == 2,
        'saved filters',
      );
      expect(overlay.controller.items, isEmpty);
      final reload = LocalStore(prefs);
      expect(reload.playbackPreferences.danmakuBlockedKeywords, [
        '合 成弹幕',
        'ＡＢＣ',
      ]);
      reload.dispose();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('126-keyword-editor');
      await tester.tap(find.text('清空'));
      await tester.tap(find.byKey(const ValueKey('danmaku-filter-save')));
      await until(
        () =>
            store.playbackPreferences.danmakuBlockedKeywords.isEmpty &&
            overlay.controller.items.isNotEmpty,
        'restore cached danmaku',
      );
      expect(repository.resolved.length, resolves);
      expect(
        identical(
          tester.widget<Video>(find.byType(Video)).controller.player,
          player,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      binding.reportData ??= {};
      binding.reportData!.addAll({
        'instantFilter': true,
        'persistent': true,
        'normalizedDeduplication': true,
        'clearRestoresCachedDanmaku': true,
        'samePlayer': true,
        'resolveCalls': resolves,
        'imagesDisabled': true,
      });
      await tester.tap(find.byTooltip('关闭菜单'));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
      store.dispose();
    },
  );
}
