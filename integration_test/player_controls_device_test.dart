import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/main.dart';
import 'package:duanju_app/player_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_test.dart' show DeviceFixtureRepository;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('device seek, gesture lock and episode swipe', (tester) async {
    expect(const bool.fromEnvironment('DISABLE_REMOTE_IMAGES'), isTrue);
    MediaKit.ensureInitialized();
    final repository = DeviceFixtureRepository();
    await repository.initialize();
    final store = LocalStore(await SharedPreferences.getInstance());

    Future<void> until(bool Function() ready, String step) async {
      final clock = Stopwatch()..start();
      while (!ready()) {
        if (clock.elapsed > const Duration(seconds: 35)) fail(step);
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await tester.pumpWidget(DuanjuApp(repository: repository, store: store));
    await until(() => find.text('设备播放验证').evaluate().isNotEmpty, 'catalog');
    await tester.tap(find.text('设备播放验证'));
    await until(() => find.byType(Video).evaluate().isNotEmpty, 'video');
    final player = tester.widget<Video>(find.byType(Video)).controller.player;
    await player.setVolume(0);
    await until(
      () =>
          player.state.duration.inSeconds >= 18 &&
          player.state.position.inMilliseconds > 500,
      'first episode playback',
    );

    Future<double> measuredRate(double rate) async {
      await player.setRate(rate);
      await until(() => (player.state.rate - rate).abs() < .01, 'rate $rate');
      final start = player.state.position;
      final clock = Stopwatch()..start();
      await tester.pump(const Duration(seconds: 2));
      final seconds = clock.elapsedMilliseconds / 1000;
      return (player.state.position - start).inMilliseconds / 1000 / seconds;
    }

    final normalRate = await measuredRate(1);
    final fastRate = await measuredRate(2);
    expect(normalRate, inInclusiveRange(.7, 1.3));
    expect(fastRate, inInclusiveRange(1.5, 2.5));
    expect(fastRate, greaterThan(normalRate * 1.5));
    await player.setRate(1);

    final surface = tester.getRect(find.byType(PlayerControls));
    await tester.tapAt(
      surface.topLeft + Offset(surface.width * .5, surface.height * .25),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('player-lock')));
    await tester.pump();
    expect(find.byKey(const ValueKey('player-unlock')), findsOneWidget);
    await tester.fling(find.byType(Video), const Offset(0, -180), 900);
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.resolved.last, 1);

    await tester.tap(find.byKey(const ValueKey('player-unlock')));
    await tester.pump();
    final right = Offset(
      surface.left + surface.width * .85,
      surface.top + surface.height * .4,
    );
    final before = player.state.position;
    await tester.tapAt(right);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(right);
    await until(
      () => player.state.position >= before + const Duration(seconds: 8),
      'double tap forward',
    );

    await tester.fling(find.byType(Video), const Offset(0, -180), 900);
    await until(() => repository.resolved.last == 2, 'swipe next episode');
    await until(
      () =>
          player.state.duration.inSeconds >= 18 &&
          player.state.position.inMilliseconds > 500,
      'second episode playback',
    );
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
