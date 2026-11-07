import 'dart:async';

import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_test.dart' show DeviceFixtureRepository;

class InlineReservationFixture extends DeviceFixtureRepository {
  final operations = <bool>[];
  @override
  bool get supportsOfficialAccount => true;
  @override
  Future<Map<String, dynamic>> hongguoAccount(
    String command, [
    Map<String, dynamic> input = const {},
  ]) async {
    if (command == 'seasons') {
      final row = {
        'drama': const Drama(
          id: 'hongguo:700002',
          sourceId: '700002',
          source: 'hongguo',
          title: '合成后续季',
        ).toJson(),
        'number': 2,
        'playable': false,
        'reservable': true,
        'reserved': false,
      };
      return {
        'currentSeason': 1,
        'seasons': [row],
        'relatedWorks': [row],
      };
    }
    if (command == 'reserve') {
      operations.add(input['reserved'] == true);
      return {'confirmed': true, 'reserved': input['reserved']};
    }
    return {
      'loggedIn': true,
      'profile': {'uid': '7000000000000000001'},
    };
  }
}

class SeasonSwitchFixture extends InlineReservationFixture {
  static const nextDrama = Drama(
    id: 'hongguo:700003',
    source: 'hongguo',
    title: '合成第二季',
    episodes: 3,
  );
  bool resolvingNext = false;
  int nextAttempts = 0;
  int interrupted = 0;
  Completer<void>? gate;

  @override
  Future<Map<String, dynamic>> hongguoAccount(
    String command, [
    Map<String, dynamic> input = const {},
  ]) async {
    if (command == 'seasons') {
      final row = {
        'drama': nextDrama.toJson(),
        'number': 2,
        'playable': true,
        'reservable': false,
      };
      return {
        'currentSeason': 1,
        'seasons': [row],
        'relatedWorks': [row],
      };
    }
    return super.hongguoAccount(command, input);
  }

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) async {
    if (drama.id == nextDrama.id) {
      nextAttempts++;
      resolvingNext = true;
      gate = Completer<void>();
      Timer(const Duration(seconds: 1), () {
        if (!gate!.isCompleted) gate!.complete();
      });
      try {
        await gate!.future;
      } finally {
        resolvingNext = false;
      }
    }
    return super.resolve(drama, episode, quality: quality);
  }

  @override
  Future<void> cancelPlayback() async {
    if (resolvingNext) {
      interrupted++;
      if (!gate!.isCompleted) gate!.completeError(AppFailure('换季请求被取消'));
    }
    await super.cancelPlayback();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'inline season reservation and instant landscape controls on device',
    skip: const bool.fromEnvironment('SEASON_ONLY'),
    (tester) async {
      expect(const bool.fromEnvironment('DISABLE_REMOTE_IMAGES'), isTrue);
      MediaKit.ensureInitialized();
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      final repository = InlineReservationFixture();
      await repository.initialize();
      repository.accountStatus.value = {
        'loggedIn': true,
        'profile': {'uid': '7000000000000000001'},
      };
      final store = LocalStore(await SharedPreferences.getInstance());
      final detail = await repository.detail(DeviceFixtureRepository.drama);
      Future<void> until(bool Function() ready) async {
        final deadline = DateTime.now().add(const Duration(seconds: 35));
        while (!ready()) {
          if (DateTime.now().isAfter(deadline)) fail('device UI timeout');
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: PlayerScreen(
            detail: detail,
            initialIndex: 2,
            repository: repository,
            store: store,
          ),
        ),
      );
      await until(
        () =>
            find.byType(Video).evaluate().isNotEmpty &&
            repository.resolved.isNotEmpty,
      );
      await until(
        () =>
            tester
                .widget<Video>(find.byType(Video))
                .controller
                .player
                .state
                .duration >
            Duration.zero,
      );
      await tester.widget<Video>(find.byType(Video)).controller.player.pause();
      await until(() => find.text('预约').evaluate().isNotEmpty);
      await tester.tap(find.text('预约'));
      await tester.pump();
      expect(find.text('取消预约'), findsOneWidget);
      expect(repository.operations, [true]);
      expect(find.byType(PlayerScreen), findsOneWidget);
      await tester.tap(find.byTooltip('系列剧'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('取消预约'), findsOneWidget);
      await tester.tap(find.text('取消预约'));
      await tester.pump();
      expect(repository.operations, [true, false]);
      ScaffoldMessenger.of(tester.element(find.byType(PlayerScreen)))
          .clearSnackBars();
      await tester.pump(const Duration(milliseconds: 500));
      debugPrint('device checkpoint: inline reservation passed');
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 300));
      await binding.takeScreenshot('122-series-inline-reservation');
      debugPrint('device checkpoint: series screenshot captured');
      await tester.tap(find.byTooltip('收起详情面板'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('player-fullscreen')));
      await until(
        () =>
            MediaQuery.orientationOf(tester.element(find.byType(Video))) ==
            Orientation.landscape,
      );
      await until(
        () => find
            .byKey(const ValueKey('player-system-time'))
            .evaluate()
            .isNotEmpty,
      );
      final gesture = find.byKey(const ValueKey('player-gesture-surface'));
      await tester.tapAt(
        tester.getRect(gesture).topLeft +
            Offset(
              tester.getRect(gesture).width * .25,
              tester.getRect(gesture).height * .4,
            ),
      );
      await tester.pump();
      final hidden = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('player-system-time')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(hidden.opacity, 0);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tapAt(
        tester.getRect(gesture).topLeft +
            Offset(
              tester.getRect(gesture).width * .25,
              tester.getRect(gesture).height * .4,
            ),
      );
      await tester.pump();
      final shown = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('player-system-time')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(shown.opacity, 1);
      await binding.takeScreenshot('122-landscape-simple-controls-clock');
      await tester.tap(find.byKey(const ValueKey('player-speed')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('播放倍速'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('menu-speed-1.5')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<Video>(find.byType(Video)).controller.player.state.rate,
        1.5,
      );
      await tester.tap(find.byTooltip('关闭菜单'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(
        find.byKey(const ValueKey('player-fullscreen-episodes')),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('第'), findsWidgets);
      await binding.takeScreenshot('122-landscape-episodes');
      await tester.tap(find.byKey(const ValueKey('play-episode-1')));
      await until(() => repository.resolved.last == 1);
      await until(
        () =>
            tester
                .widget<Video>(find.byType(Video))
                .controller
                .player
                .state
                .position
                .inMilliseconds >
            500,
      );
      expect(tester.takeException(), isNull);
      binding.reportData ??= {};
      binding.reportData!.addAll({
        'inlineReservation': repository.operations,
        'instantOpacity': [hidden.opacity, shown.opacity],
        'landscapeClock': true,
        'imagesDisabled': true,
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
      store.dispose();
    },
  );
  testWidgets('season transition and pause gestures on native player', (
    tester,
  ) async {
    expect(const bool.fromEnvironment('DISABLE_REMOTE_IMAGES'), isTrue);
    MediaKit.ensureInitialized();
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    final repository = SeasonSwitchFixture();
    await repository.initialize();
    final store = LocalStore(await SharedPreferences.getInstance());
    Future<void> until(bool Function() ready, String step) async {
      final deadline = DateTime.now().add(const Duration(seconds: 35));
      while (!ready()) {
        if (DateTime.now().isAfter(deadline)) fail(step);
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: PlayerScreen(
          detail: await repository.detail(DeviceFixtureRepository.drama),
          initialIndex: 2,
          repository: repository,
          store: store,
        ),
      ),
    );
    await until(
      () => find
          .byKey(const ValueKey('footer-hongguo:700003'))
          .evaluate()
          .isNotEmpty,
      'season action',
    );
    await until(
      () =>
          find.byType(Video).evaluate().isNotEmpty &&
          tester
                  .widget<Video>(find.byType(Video))
                  .controller
                  .player
                  .state
                  .duration >
              Duration.zero,
      'original playback',
    );
    await tester
        .widget<Video>(find.byType(Video))
        .controller
        .player
        .setVolume(0);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('footer-hongguo:700003')),
        matching: find.byType(FilledButton),
      ),
    );
    await until(
      () =>
          find.byType(PlayerScreen).evaluate().length == 1 &&
          tester
                  .widget<PlayerScreen>(find.byType(PlayerScreen))
                  .detail
                  .drama
                  .id ==
              SeasonSwitchFixture.nextDrama.id,
      'replacement route',
    );
    await until(
      () =>
          find.byType(Video).evaluate().length == 1 &&
          tester
                  .widget<Video>(find.byType(Video))
                  .controller
                  .player
                  .state
                  .position
                  .inMilliseconds >
              500,
      'new season first playback',
    );
    final player = tester.widget<Video>(find.byType(Video)).controller.player;
    await player.setVolume(0);
    expect(repository.nextAttempts, 1);
    expect(repository.interrupted, 0);
    expect(repository.resolved.last, 1);
    expect(find.text('重试'), findsNothing);
    await binding.convertFlutterSurfaceToImage();
    await tester.pump(const Duration(milliseconds: 300));
    for (final landscape in [false, true]) {
      await player.pause();
      if (landscape) {
        await tester.pump(const Duration(milliseconds: 400));
        final surface = tester.getRect(
          find.byKey(const ValueKey('player-gesture-surface')),
        );
        await tester.tapAt(
          surface.topLeft + Offset(surface.width * .25, surface.height * .4),
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('player-fullscreen')));
        await until(
          () =>
              MediaQuery.orientationOf(tester.element(find.byType(Video))) ==
              Orientation.landscape,
          'landscape',
        );
      }
      for (final fraction in [.15, .5, .85]) {
        await player.pause();
        await player.seek(const Duration(seconds: 5));
        await until(
          () => (player.state.position.inMilliseconds - 5000).abs() < 600,
          'seek preparation',
        );
        await tester.pump(const Duration(milliseconds: 400));
        final surface = tester.getRect(
          find.byKey(const ValueKey('player-gesture-surface')),
        );
        final point =
            surface.topLeft +
            Offset(surface.width * fraction, surface.height * .35);
        final before = player.state.position;
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(point);
        await until(
          () => player.state.playing,
          'double tap resumes $landscape $fraction',
        );
        expect(
          (player.state.position - before).inMilliseconds.abs(),
          lessThan(1500),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(point);
        await until(
          () => !player.state.playing,
          'double tap pauses $landscape $fraction',
        );
        expect(find.byKey(const ValueKey('player-rewind')), findsNothing);
        expect(find.byKey(const ValueKey('player-forward')), findsNothing);
      }
      await tester.pump(const Duration(milliseconds: 400));
      final surface = tester.getRect(
        find.byKey(const ValueKey('player-gesture-surface')),
      );
      final before = player.state.position;
      final gesture = await tester.startGesture(
        surface.topLeft + Offset(surface.width * .3, surface.height * .4),
      );
      await gesture.moveBy(Offset(surface.width * .25, 0));
      await tester.pump(const Duration(milliseconds: 150));
      await gesture.up();
      await until(
        () => player.state.position > before + const Duration(seconds: 1),
        'horizontal swipe seeks',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(
        surface.topLeft + Offset(surface.width * .25, surface.height * .35),
      );
      await tester.pump();
      await binding.takeScreenshot(
        '123-${landscape ? 'landscape' : 'portrait'}-simple-controls',
      );
    }
    binding.reportData ??= {};
    binding.reportData!.addAll({
      'nextSeasonFirstAttempt': repository.nextAttempts,
      'seasonInterrupted': repository.interrupted,
      'doubleTapPauseResumeZones': 6,
      'horizontalSeekOrientations': 2,
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    store.dispose();
  });
}
