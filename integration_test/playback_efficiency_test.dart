import 'dart:math' as math;

import 'package:duanju_app/background_executor.dart';
import 'package:duanju_app/danmaku_models.dart';
import 'package:duanju_app/danmaku_overlay.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/playback_preferences.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_test.dart' show DeviceFixtureRepository;

DanmakuPage syntheticPage((String, int, int) input) => DanmakuPage(
  episodeId: input.$1,
  startMs: input.$2,
  nextMs: math.min(input.$2 + 30000, input.$3),
  items: [
    for (var i = 0; i < 40; i++)
      if (input.$2 + i * 400 < input.$3)
        DanmakuItem(
          id: '${input.$1}-$i',
          text: '合成弹幕 $i',
          timeMs: input.$2 + i * 400,
        ),
  ],
);

class EfficiencyFixture extends DeviceFixtureRepository {
  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async {
    final plan = await super.resolve(drama, episode, quality: quality);
    return PlaybackPlan(
      url: plan.url,
      headers: plan.headers,
      decryptionKey: plan.decryptionKey,
      session: plan.session,
      danmakuId: 'synthetic-${episode.number}',
    );
  }

  @override
  Future<DanmakuPage> danmaku(
    PlaybackPlan plan, {
    required int startMs,
    required int durationMs,
  }) => BackgroundExecutor.shared.run(syntheticPage, (
    plan.danmakuId,
    startMs,
    durationMs,
  ));
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native playback, danmaku painting and idle work on device', (
    tester,
  ) async {
    expect(const bool.fromEnvironment('DISABLE_REMOTE_IMAGES'), isTrue);
    MediaKit.ensureInitialized();
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    final repository = EfficiencyFixture();
    await repository.initialize();
    final store = LocalStore(await SharedPreferences.getInstance());
    await store.setPlaybackPreferences(
      const PlaybackPreferences(autoAdvance: false, preload: false),
    );
    Future<void> until(bool Function() ready, String step) async {
      final clock = Stopwatch()..start();
      while (!ready()) {
        if (clock.elapsed > const Duration(seconds: 30)) fail(step);
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: PlayerScreen(
          detail: await repository.detail(DeviceFixtureRepository.drama),
          initialIndex: 0,
          repository: repository,
          store: store,
        ),
      ),
    );
    await until(() => find.byType(Video).evaluate().isNotEmpty, 'video');
    final player = tester.widget<Video>(find.byType(Video)).controller.player;
    await player.setVolume(0);
    await until(
      () =>
          player.state.position.inMilliseconds > 1000 &&
          find.byType(Flow).evaluate().isNotEmpty,
      'native playback and danmaku',
    );
    final delegate =
        tester.widget<Flow>(find.byType(Flow)).delegate as DanmakuFlowDelegate;
    final position = delegate.position.value;
    await tester.pump(const Duration(milliseconds: 500));
    expect(delegate.position.value, greaterThan(position));
    await player.pause();
    await tester.pump(const Duration(milliseconds: 400));
    final paused = delegate.position.value;
    final completedBefore = BackgroundExecutor.shared.tasksCompleted;
    final frames = <FrameTiming>[];
    void collect(List<FrameTiming> timings) => frames.addAll(timings);
    SchedulerBinding.instance.addTimingsCallback(collect);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pump();
    SchedulerBinding.instance.removeTimingsCallback(collect);
    expect(delegate.position.value, closeTo(paused, .01));
    expect(
      BackgroundExecutor.shared.tasksCompleted - completedBefore,
      lessThanOrEqualTo(1),
    );
    final pausedTasks =
        BackgroundExecutor.shared.tasksCompleted - completedBefore;
    final overlay = tester.widget<DanmakuOverlay>(find.byType(DanmakuOverlay));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    expect(overlay.controller.visible, isFalse);
    expect(overlay.controller.moving, isFalse);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Flow), findsOneWidget);
    await player.play();
    await until(
      () => player.state.position.inMilliseconds > paused + 400,
      'resume',
    );
    await player.pause();
    await binding.convertFlutterSurfaceToImage();
    await tester.pump(const Duration(milliseconds: 300));
    await binding.takeScreenshot('124-native-danmaku');
    binding.reportData ??= {};
    binding.reportData!.addAll({
      'nativeDanmakuMoves': true,
      'pausedDanmakuStable': true,
      'hiddenDanmakuStopped': true,
      'pausedSeconds': 3,
      'pausedFramesObserved': frames.length,
      'pausedBackgroundTasks': pausedTasks,
      'workersStarted': BackgroundExecutor.shared.workersStarted,
      'imagesDisabled': true,
      'measurementMode':
          'debug functional checks, not a battery or profile benchmark',
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    store.dispose();
  });
}
