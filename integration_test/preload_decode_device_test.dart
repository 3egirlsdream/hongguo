import 'dart:io';

import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/playback_preferences.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_test.dart' show DeviceFixtureRepository;

class StagedDeviceRepository extends DeviceFixtureRepository {
  int resolves = 0, prepares = 0, warms = 0, warmedBytes = 0;
  bool warmFinished = false;
  @override
  bool get supportsStagedPreload => true;
  @override
  Future<DramaDetail> detail(Drama drama) async {
    final result = await super.detail(drama);
    final hd = const String.fromEnvironment('FIXTURE_HD_URL');
    return DramaDetail(drama, [
      for (final episode in result.episodes.take(2))
        if (episode.number == 1 && hd.isNotEmpty)
          Episode({...episode.raw, 'videoUrl': hd}, episode.number)
        else
          episode,
    ]);
  }

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) {
    resolves++;
    return super.resolve(drama, episode, quality: quality);
  }

  @override
  Future<PlaybackPlan?> preload(
    Drama drama,
    Episode episode, {
    int quality = 0,
    bool online = false,
  }) {
    prepares++;
    return native.preload(drama, episode, quality: quality, online: online);
  }

  @override
  Future<int> warmPreload(PlaybackPlan plan) async {
    warms++;
    warmedBytes = await native.warmPreload(plan);
    warmFinished = true;
    return warmedBytes;
  }

  @override
  Future<void> cancelPreload() => native.cancelPreload();
  @override
  Future<void> cancelPreloadWarm() => native.cancelPreloadWarm();
}

int cpuTicks() {
  final stat = File('/proc/self/stat').readAsStringSync();
  final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
  return int.parse(fields[11]) + int.parse(fields[12]);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('staged preload handoff and decoder output on native device', (
    tester,
  ) async {
    expect(const bool.fromEnvironment('DISABLE_REMOTE_IMAGES'), isTrue);
    MediaKit.ensureInitialized();
    final repository = StagedDeviceRepository();
    await repository.initialize();
    final store = LocalStore(await SharedPreferences.getInstance());
    await store.setPlaybackPreferences(
      const PlaybackPreferences(
        speed: 1,
        autoAdvance: false,
        danmaku: false,
        preload: true,
      ),
    );
    Future<void> until(bool Function() ready, String step) async {
      final clock = Stopwatch()..start();
      while (!ready()) {
        if (clock.elapsed > const Duration(seconds: 35)) fail(step);
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(
      MaterialApp(
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
    await until(
      () =>
          player.state.position.inMilliseconds >= 3000 &&
          repository.prepares == 1,
      'early address preparation',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.warms, 0);
    final actual = await (player.platform as NativePlayer).getProperty(
      'hwdec-current',
    );
    final cpuStart = cpuTicks();
    final clock = Stopwatch()..start();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    final cpu = cpuTicks() - cpuStart;
    final sampleMs = clock.elapsedMilliseconds;
    await tester.pump();
    final budget = await const MethodChannel('duanju/device')
        .invokeMapMethod<String, dynamic>('playbackBudget');
    await player.seek(const Duration(seconds: 14));
    await until(() => repository.warmFinished, 'near-end media warming');
    if (budget?['restricted'] != true) {
      await until(() => repository.warmedBytes > 0, 'media cache bytes');
    }
    final switchClock = Stopwatch()..start();
    final surface = find.byKey(const ValueKey('player-gesture-surface'));
    final rect = tester.getRect(surface);
    await tester.flingFrom(rect.center, const Offset(0, -220), 900);
    await until(
      () =>
          player.state.position.inMilliseconds > 250 &&
          player.state.position.inMilliseconds < 2000 &&
          player.state.duration > Duration.zero &&
          player.state.playing &&
          find.text('第 2 集').evaluate().isNotEmpty,
      'next episode handoff',
    );
    expect(repository.resolves, 1);
    expect(repository.prepares, 1);
    final secondActual = await (player.platform as NativePlayer).getProperty(
      'hwdec-current',
    );
    await player.pause();
    binding.reportData ??= {};
    binding.reportData!.addAll({
      'requestedDecoder': const String.fromEnvironment(
        'PLAYBACK_HWDEC',
        defaultValue: 'mediacodec',
      ),
      'actualDecoder': actual,
      'secondDecoder': secondActual,
      'foregroundResolveCalls': repository.resolves,
      'prepareCalls': repository.prepares,
      'warmCallsTotal': repository.warms,
      'earlyWarmCalls': 0,
      'cachedWarmBytes': repository.warmedBytes,
      'budget': budget,
      'cpuTicksOverFiveSeconds': cpu,
      'measurementMs': sampleMs,
      'switchToPlayingMs': switchClock.elapsedMilliseconds,
      'measurementKind':
          'profile functional and CPU sample, not battery measurement',
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    store.dispose();
  });
}
