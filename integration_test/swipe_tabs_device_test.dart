import 'package:duanju_app/app_bottom_navigation.dart';
import 'package:duanju_app/app_theme.dart';
import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/playback_preferences.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:duanju_app/swipe_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/design_review_test.dart' show DesignReviewRepository;
import 'playback_efficiency_test.dart' show EfficiencyFixture;
import 'playback_test.dart' show DeviceFixtureRepository;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'internal tabs swipe, root navigation stays fixed and episode gestures scale with screen',
    (tester) async {
      expect(const bool.fromEnvironment('DISABLE_REMOTE_IMAGES'), isTrue);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      final store = LocalStore(await SharedPreferences.getInstance());
      await store.setPlaybackPreferences(
        const PlaybackPreferences(preload: false, autoAdvance: false),
      );
      Future<void> tick() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
      }

      Future<void> until(bool Function() ready, String step) async {
        final clock = Stopwatch()..start();
        while (!ready()) {
          if (clock.elapsed > const Duration(seconds: 30)) fail(step);
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> swipe(Finder finder, double direction) async {
        final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
        final rect = tester
            .getRect(finder)
            .intersect(Rect.fromLTWH(0, 70, screen.width, screen.height - 150));
        await tester.dragFrom(
          rect.center,
          Offset(rect.width * .4 * direction, 0),
        );
        await tick();
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(
            repository: DesignReviewRepository('/synthetic'),
            store: store,
          ),
        ),
      );
      await tick();
      int root() => tester
          .widget<AppBottomNavigation>(find.byType(AppBottomNavigation))
          .selectedIndex;
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      await tester.dragFrom(
        Offset(screen.width * .7, screen.height * .4),
        Offset(-screen.width * .4, 0),
      );
      await tick();
      expect(root(), 0);
      await swipe(find.byType(AppBottomNavigation), -1);
      expect(root(), 0);
      await tester.tap(find.byKey(const ValueKey('bottom-nav-3')));
      await tick();
      final account = find.byKey(const ValueKey('account-swipe-tabs'));
      int accountIndex() => tester.widget<SwipeTabs>(account).index;
      expect(accountIndex(), 1);
      for (final index in [2, 3]) {
        await swipe(account, -1);
        expect(accountIndex(), index);
      }
      for (final index in [2, 1, 0]) {
        await swipe(account, 1);
        expect(accountIndex(), index);
      }
      expect(root(), 3);
      await tester.tap(find.byKey(const ValueKey('bottom-nav-1')));
      await tick();
      final rankings = find.byKey(const ValueKey('ranking-swipe-tabs'));
      await swipe(rankings, -1);
      expect(tester.widget<SwipeTabs>(rankings).index, 1);
      await swipe(rankings, -1);
      expect(tester.widget<SwipeTabs>(rankings).index, 2);
      await swipe(rankings, 1);
      expect(tester.widget<SwipeTabs>(rankings).index, 1);
      expect(root(), 1);
      await tester.pumpWidget(const SizedBox());
      await tick();
      MediaKit.ensureInitialized();
      final repository = EfficiencyFixture();
      await repository.initialize();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: PlayerScreen(
            detail: await repository.detail(DeviceFixtureRepository.drama),
            initialIndex: 0,
            repository: repository,
            store: store,
          ),
        ),
      );
      await until(
        () => find.byType(Video).evaluate().isNotEmpty,
        'native video',
      );
      final player = tester.widget<Video>(find.byType(Video)).controller.player;
      await player.setVolume(0);
      await until(
        () => player.state.position.inMilliseconds > 500,
        'playback progress',
      );
      await tester.tap(find.byKey(const ValueKey('player-open-details')));
      await tick();
      final details = find.byKey(const ValueKey('player-details-swipe-tabs'));
      await swipe(details, -1);
      expect(tester.widget<SwipeTabs>(details).index, 2);
      await swipe(details, 1);
      expect(tester.widget<SwipeTabs>(details).index, 1);
      await swipe(details, 1);
      expect(tester.widget<SwipeTabs>(details).index, 0);
      await tester.tapAt(Offset(screen.width / 2, screen.height * .15));
      await tick();
      final dimensions = <Map<String, dynamic>>[];
      for (final landscape in [false, true]) {
        await SystemChrome.setPreferredOrientations([
          landscape
              ? DeviceOrientation.landscapeLeft
              : DeviceOrientation.portraitUp,
        ]);
        await until(
          () =>
              (tester.view.physicalSize.width >
                  tester.view.physicalSize.height) ==
              landscape,
          'orientation',
        );
        await tick();
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        final surface = tester.getRect(
          find.byKey(const ValueKey('player-gesture-surface')),
        );
        final before = repository.resolved.length;
        debugPrint(
          'gesture geometry: screen=$size surface=$surface resolved=$before',
        );
        for (final ratio in [.06, .10]) {
          final gesture = await tester.startGesture(
            Offset(surface.center.dx, size.height * .35),
          );
          await gesture.moveBy(
            Offset(0, -size.height * ratio),
            timeStamp: const Duration(seconds: 1),
          );
          await gesture.up(timeStamp: const Duration(seconds: 2));
          await tick();
          debugPrint('gesture ratio=$ratio resolved=${repository.resolved}');
          if (ratio == .06) {
            expect(repository.resolved.length, before);
          } else {
            await until(
              () =>
                  repository.resolved.length == before + 1 &&
                  player.state.position.inMilliseconds > 200,
              'screen-scaled switch',
            );
          }
        }
        dimensions.add({
          'width': size.width,
          'height': size.height,
          'viewportHeight': surface.height,
          'shortRatio': .06,
          'switchRatio': .10,
        });
      }
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await until(
        () => tester.view.physicalSize.height > tester.view.physicalSize.width,
        'restore portrait',
      );
      await tick();
      await tester.tap(find.byKey(const ValueKey('player-open-details')));
      await tick();
      await binding.convertFlutterSurfaceToImage();
      await tick();
      await binding.takeScreenshot('127-player-tabs');
      await tester.pumpWidget(const SizedBox());
      await tick();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomeScreen(
            repository: DesignReviewRepository('/synthetic'),
            store: store,
          ),
        ),
      );
      await tick();
      await tester.tap(find.byKey(const ValueKey('bottom-nav-3')));
      await tick();
      await binding.takeScreenshot('127-my-tabs');
      await tester.tap(find.byKey(const ValueKey('bottom-nav-1')));
      await tick();
      await binding.takeScreenshot('127-ranking-tabs');
      expect(tester.takeException(), isNull);
      binding.reportData ??= {};
      binding.reportData!.addAll({
        'rootClickOnly': true,
        'myTabsBothWays': true,
        'rankingTabsBothWays': true,
        'playerTabsVisualOrder': true,
        'screenRatioSwitching': dimensions,
        'imagesDisabled': true,
      });
      await tester.pumpWidget(const SizedBox());
      await tick();
      store.dispose();
    },
  );
}
