import 'package:duanju_app/app_bottom_navigation.dart';
import 'package:duanju_app/episode_browser.dart';
import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/player_interactions.dart';
import 'package:duanju_app/player_presentation.dart';
import 'package:duanju_app/swipe_tabs.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design_review_test.dart' show DesignReviewRepository;
import 'fixtures.dart';
import 'player_fixtures.dart';

void main() {
  Future<void> tick(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<LocalStore> store() async {
    SharedPreferences.setMockInitialValues({});
    final value = testStore(await SharedPreferences.getInstance());
    addTearDown(value.dispose);
    return value;
  }

  Future<void> swipe(
    WidgetTester tester,
    Finder finder,
    double direction,
  ) async {
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final rect = tester
        .getRect(finder)
        .intersect(Rect.fromLTWH(0, 70, screen.width, screen.height - 150));
    await tester.dragFrom(rect.center, Offset(rect.width * .4 * direction, 0));
    await tick(tester);
  }

  testWidgets(
    'nested tabs change once and ignore vertical, short and multitouch drags',
    (tester) async {
      int outer = 0, inner = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => SwipeTabs(
              index: outer,
              count: 3,
              onChanged: (value) => setState(() => outer = value),
              child: SwipeTabs(
                key: const ValueKey('inner'),
                index: inner,
                count: 3,
                onChanged: (value) => setState(() => inner = value),
                child: ListView(
                  children: List.generate(
                    40,
                    (i) => SizedBox(height: 60, child: Text('row $i')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final region = find.byKey(const ValueKey('inner'));
      await swipe(tester, region, -1);
      expect(inner, 2);
      expect(outer, 0);
      await swipe(tester, region, -1);
      expect(inner, 2);
      expect(outer, 0);
      await tester.drag(region, const Offset(0, -180));
      await tick(tester);
      expect(inner, 2);
      expect(find.text('row 0').hitTestable(), findsNothing);
      final point = tester.getRect(region).center;
      final short = await tester.startGesture(point);
      await short.moveBy(
        const Offset(25, 0),
        timeStamp: const Duration(seconds: 1),
      );
      await short.up(timeStamp: const Duration(seconds: 2));
      await tick(tester);
      expect(inner, 2);
      final first = await tester.startGesture(point, pointer: 1);
      final second = await tester.startGesture(
        point + const Offset(0, 20),
        pointer: 2,
      );
      await first.moveBy(const Offset(300, 0));
      await second.up();
      await first.up();
      await tick(tester);
      expect(inner, 2);
      expect(outer, 0);
    },
  );

  testWidgets(
    'bottom navigation stays click-only while My collection tabs swipe both ways',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            repository: DesignReviewRepository('/synthetic'),
            store: await store(),
          ),
        ),
      );
      await tick(tester);
      int selected() => tester
          .widget<AppBottomNavigation>(find.byType(AppBottomNavigation))
          .selectedIndex;
      await tester.dragFrom(const Offset(250, 450), const Offset(-180, 0));
      await tick(tester);
      expect(selected(), 0);
      await tester.drag(
        find.byType(AppBottomNavigation),
        const Offset(-160, 0),
      );
      await tick(tester);
      expect(selected(), 0);
      await tester.tap(find.byKey(const ValueKey('bottom-nav-3')));
      await tick(tester);
      expect(selected(), 3);
      final account = find.byKey(const ValueKey('account-swipe-tabs'));
      int tab() => tester.widget<SwipeTabs>(account).index;
      expect(tab(), 1);
      await swipe(tester, account, -1);
      expect(tab(), 2);
      await swipe(tester, account, -1);
      expect(tab(), 3);
      await swipe(tester, account, 1);
      expect(tab(), 2);
      await swipe(tester, account, 1);
      expect(tab(), 1);
      await swipe(tester, account, 1);
      expect(tab(), 0);
      expect(selected(), 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tick(tester);
    },
  );

  testWidgets(
    'rankings swipe through ordered boards without changing root navigation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            repository: DesignReviewRepository('/synthetic'),
            store: await store(),
          ),
        ),
      );
      await tick(tester);
      await tester.tap(find.byKey(const ValueKey('bottom-nav-1')));
      await tick(tester);
      final region = find.byKey(const ValueKey('ranking-swipe-tabs'));
      int tab() => tester.widget<SwipeTabs>(region).index;
      await swipe(tester, region, -1);
      expect(tab(), 1);
      await swipe(tester, region, -1);
      expect(tab(), 2);
      await swipe(tester, region, 1);
      expect(tab(), 1);
      expect(
        tester
            .widget<AppBottomNavigation>(find.byType(AppBottomNavigation))
            .selectedIndex,
        1,
      );
      await tester.pumpWidget(const SizedBox());
      await tick(tester);
    },
  );

  testWidgets('player details follow visible tab order and include download', (
    tester,
  ) async {
    final repository = DesignReviewRepository('/synthetic');
    final detail = await repository.detail(FixtureRepository.free);
    var selected = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PlayerDetailsPanel(
              detail: detail,
              repository: repository,
              currentSeason: 1,
              tab: selected,
              onTab: (value) => setState(() => selected = value),
              followed: false,
              onFavorite: () {},
              onDownload: () => setState(() => selected = 2),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    final region = find.byKey(const ValueKey('player-details-swipe-tabs'));
    for (final value in [0, 3, 2]) {
      await swipe(tester, region, -1);
      expect(selected, value);
    }
    await swipe(tester, region, 1);
    expect(selected, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('episode pages swipe without starting playback', (tester) async {
    var plays = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EpisodeBrowser(
            episodes: List.generate(
              120,
              (i) => Episode({'id': '${i + 1}'}, i + 1),
            ),
            onSelected: (_) => plays++,
          ),
        ),
      ),
    );
    final region = find.byKey(const ValueKey('episode-pages-swipe-tabs'));
    await swipe(tester, region, -1);
    expect(find.byKey(const ValueKey('episode-51')), findsOneWidget);
    await swipe(tester, region, -1);
    expect(find.byKey(const ValueKey('episode-101')), findsOneWidget);
    await swipe(tester, region, 1);
    expect(find.byKey(const ValueKey('episode-51')), findsOneWidget);
    expect(plays, 0);
  });

  testWidgets(
    'playback range tabs swipe and locate without playing another episode',
    (tester) async {
      var plays = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerEpisodePicker(
              episodes: List.generate(
                120,
                (i) => Episode({'id': '${i + 1}'}, i + 1),
              ),
              currentIndex: 0,
              playedNumbers: const {},
              onSelected: (_) => plays++,
            ),
          ),
        ),
      );
      final region = find.byKey(
        const ValueKey('player-episode-ranges-swipe-tabs'),
      );
      Future<void> change(double direction) async {
        final rect = tester.getRect(region);
        await tester.dragFrom(
          rect.center,
          Offset(rect.width * .4 * direction, 0),
        );
        await tick(tester);
      }

      await change(-1);
      expect(tester.widget<SwipeTabs>(region).index, 1);
      expect(
        find.byKey(const ValueKey('play-episode-31')).hitTestable(),
        findsOneWidget,
      );
      await change(-1);
      expect(tester.widget<SwipeTabs>(region).index, 2);
      await change(1);
      expect(tester.widget<SwipeTabs>(region).index, 1);
      expect(plays, 0);
    },
  );

  for (final screenHeight in [800.0, 1200.0]) {
    testWidgets(
      'episode zone and threshold use screen height across different video viewports at $screenHeight',
      (tester) async {
        for (final videoHeight in [180.0, 600.0]) {
          final platform = ScriptedPlayer();
          final player = Player(platformPlayer: platform);
          var switches = 0;
          final interactions = PlayerInteractions(
            player: player,
            available: () => true,
            baseSpeed: () => 1,
            onTogglePlayback: () {},
            onFullscreen: () {},
            onEpisode: (direction) {
              switches += direction;
              return '';
            },
          );
          void down(int pointer, double globalY, double localY) =>
              interactions.pointerDown(
                PointerDownEvent(
                  pointer: pointer,
                  position: Offset(200, globalY),
                  kind: PointerDeviceKind.touch,
                ).transformed(
                  Matrix4.translationValues(0, localY - globalY, 0),
                ),
                swipeEnabled: true,
                width: 400,
                height: videoHeight,
                screenSize: Size(400, screenHeight),
              );
          void move(
            int pointer,
            double globalY,
            double localY,
            double distance,
          ) {
            interactions.pointerMove(
              PointerMoveEvent(
                pointer: pointer,
                position: Offset(200, globalY - distance),
                kind: PointerDeviceKind.touch,
                timeStamp: const Duration(seconds: 1),
              ).transformed(Matrix4.translationValues(0, localY - globalY, 0)),
            );
            interactions.pointerUp(
              PointerUpEvent(
                pointer: pointer,
                position: Offset(200, globalY - distance),
                kind: PointerDeviceKind.touch,
                timeStamp: const Duration(seconds: 2),
              ).transformed(Matrix4.translationValues(0, localY - globalY, 0)),
            );
          }

          down(1, screenHeight * .5, 10);
          move(1, screenHeight * .5, 10, screenHeight * .06);
          expect(switches, 0);
          down(2, screenHeight * .5, 10);
          move(2, screenHeight * .5, 10, screenHeight * .10);
          expect(switches, 1);
          down(3, screenHeight * .1, videoHeight * .5);
          move(3, screenHeight * .1, videoHeight * .5, screenHeight * .10);
          expect(switches, 1);
          interactions.dispose();
          await player.dispose();
        }
      },
    );
  }
}
