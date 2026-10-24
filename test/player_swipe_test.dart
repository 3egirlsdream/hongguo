import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'player_fixtures.dart';

void main() {
  Future<void> tick(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<(RouteRepository, ScriptedPlayer)> mount(
    WidgetTester tester, {
    int index = 0,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final LocalStore store = testStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    final repository = RouteRepository();
    final player = ScriptedPlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          detail: await repository.detail(FixtureRepository.free),
          initialIndex: index,
          repository: repository,
          store: store,
          playerFactory: () => Player(platformPlayer: player),
          videoBuilder: (_) => const ColoredBox(
            key: ValueKey('swipe-media'),
            color: Color(0xFF596A65),
          ),
        ),
      ),
    );
    await tick(tester);
    return (repository, player);
  }

  Finder getSurface() => find.byKey(const ValueKey('player-gesture-surface'));
  Offset origin(WidgetTester tester, {double x = .5, double y = .4}) {
    final rect = tester.getRect(getSurface());
    return rect.topLeft + Offset(rect.width * x, rect.height * y);
  }

  double offset(WidgetTester tester) => tester
      .widget<Transform>(find.byKey(const ValueKey('player-episode-motion')))
      .transform
      .entry(1, 3);
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tick(tester);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'video follows a central drag while controls and hit surface stay fixed; short drag springs back',
    (tester) async {
      final (repository, _) = await mount(tester);
      final surface = tester.getRect(getSurface());
      final controls = tester.getRect(
        find.byKey(const ValueKey('player-open-details')),
      );
      final media = tester.getTopLeft(
        find.byKey(const ValueKey('swipe-media')),
      );
      final gesture = await tester.startGesture(origin(tester));
      await gesture.moveBy(
        const Offset(0, -30),
        timeStamp: const Duration(milliseconds: 250),
      );
      await tester.pump();
      expect(offset(tester), closeTo(-30, .01));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('swipe-media'))).dy,
        closeTo(media.dy - 30, .01),
      );
      expect(tester.getRect(getSurface()), surface);
      expect(
        tester.getRect(find.byKey(const ValueKey('player-open-details'))),
        controls,
      );
      await gesture.up(timeStamp: const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      expect(offset(tester), 0);
      expect(repository.requestedEpisodes, [1]);
      await close(tester);
    },
  );

  testWidgets(
    'upward and downward drags switch exactly one episode after release',
    (tester) async {
      final (repository, player) = await mount(tester);
      for (final direction in [-1, 1]) {
        final gesture = await tester.startGesture(origin(tester));
        await gesture.moveBy(
          Offset(0, 100.0 * direction),
          timeStamp: const Duration(milliseconds: 300),
        );
        await tester.pump();
        expect(offset(tester), closeTo(100.0 * direction, .01));
        expect(repository.requestedEpisodes.length, direction == -1 ? 1 : 2);
        await gesture.up(timeStamp: const Duration(milliseconds: 350));
        await tick(tester);
      }
      expect(repository.requestedEpisodes, [1, 2, 1]);
      expect(player.opened, hasLength(3));
      expect(offset(tester), 0);
      await close(tester);
    },
  );

  testWidgets(
    'slow deliberate drags still switch after more than 1.5 seconds',
    (tester) async {
      final (repository, _) = await mount(tester);
      final gesture = await tester.startGesture(origin(tester));
      await gesture.moveBy(
        const Offset(0, -20),
        timeStamp: const Duration(milliseconds: 50),
      );
      await tester.pump(const Duration(milliseconds: 1700));
      await gesture.moveBy(
        const Offset(0, -80),
        timeStamp: const Duration(milliseconds: 1750),
      );
      await gesture.up(timeStamp: const Duration(milliseconds: 1800));
      await tick(tester);
      expect(repository.requestedEpisodes, [1, 2]);
      expect(offset(tester), 0);
      await close(tester);
    },
  );

  testWidgets(
    'a short fast vertical flick can switch without reaching the distance threshold',
    (tester) async {
      final (repository, _) = await mount(tester);
      final gesture = await tester.startGesture(origin(tester));
      for (var i = 1; i <= 3; i++) {
        await gesture.moveBy(
          const Offset(0, -12),
          timeStamp: Duration(milliseconds: 10 * i),
        );
      }
      await gesture.up(timeStamp: const Duration(milliseconds: 35));
      await tick(tester);
      expect(repository.requestedEpisodes, [1, 2]);
      await close(tester);
    },
  );

  testWidgets(
    'side adjustment and touches outside the central starting zone never translate the video',
    (tester) async {
      final (repository, player) = await mount(tester);
      for (final position in [
        origin(tester, x: .15),
        origin(tester, x: .85),
        origin(tester, y: .15),
      ]) {
        final gesture = await tester.startGesture(position);
        await gesture.moveBy(
          const Offset(0, 100),
          timeStamp: const Duration(milliseconds: 250),
        );
        await tester.pump();
        expect(offset(tester), 0);
        await gesture.up(timeStamp: const Duration(milliseconds: 300));
      }
      expect(player.state.volume, lessThan(100));
      expect(repository.requestedEpisodes, [1]);
      await close(tester);
    },
  );

  for (final index in [0, 1]) {
    testWidgets(
      'outer edge of episode $index has resistance and springs back',
      (tester) async {
        final (repository, _) = await mount(tester, index: index);
        final gesture = await tester.startGesture(origin(tester));
        await gesture.moveBy(
          Offset(0, index == 0 ? 120 : -120),
          timeStamp: const Duration(milliseconds: 250),
        );
        await tester.pump();
        expect(offset(tester).abs(), closeTo(26.4, .01));
        await gesture.up(timeStamp: const Duration(milliseconds: 300));
        await tick(tester);
        expect(repository.requestedEpisodes, [index + 1]);
        expect(offset(tester), 0);
        await close(tester);
      },
    );
  }

  for (final multitouch in [false, true]) {
    testWidgets(
      'cancelled or multitouch gesture springs back without switching: $multitouch',
      (tester) async {
        final (repository, _) = await mount(tester);
        final gesture = await tester.startGesture(origin(tester), pointer: 1);
        await gesture.moveBy(
          const Offset(0, -100),
          timeStamp: const Duration(milliseconds: 250),
        );
        await tester.pump();
        expect(offset(tester), -100);
        if (multitouch) {
          final second = await tester.startGesture(
            origin(tester, x: .6),
            pointer: 2,
          );
          await second.up();
          await gesture.up(timeStamp: const Duration(milliseconds: 300));
        } else {
          await gesture.cancel();
        }
        await tick(tester);
        expect(offset(tester), 0);
        expect(repository.requestedEpisodes, [1]);
        await close(tester);
      },
    );
  }

  testWidgets(
    'long press speed boost does not turn into a moving episode gesture',
    (tester) async {
      final (repository, player) = await mount(tester);
      final gesture = await tester.startGesture(origin(tester));
      await tester.pump(const Duration(milliseconds: 360));
      expect(player.state.rate, 3);
      await gesture.moveBy(
        const Offset(0, -100),
        timeStamp: const Duration(milliseconds: 400),
      );
      await gesture.up(timeStamp: const Duration(milliseconds: 450));
      await tick(tester);
      expect(offset(tester), 0);
      expect(player.state.rate, 1);
      expect(repository.requestedEpisodes, [1]);
      await close(tester);
    },
  );
}
