import 'dart:io';
import 'dart:ui' as ui;

import 'package:duanju_app/hongguo_account_models.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/playback_preferences.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:duanju_app/player_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'player_fixtures.dart';

class SeriesRepository extends RouteRepository {
  List<DramaSeason> seasons = [];
  int season = 2;
  int preloads = 0;
  final accounts = <String>[];
  final progress = <Map<String, dynamic>>[];
  bool loggedIn = false;
  int immediateSyncs = 0;
  @override
  void requestOfficialSync() => immediateSyncs++;
  @override
  bool get supportsOfficialAccount => true;
  @override
  Future<Map<String, dynamic>> hongguoAccount(
    String command, [
    Map<String, dynamic> data = const {},
  ]) async {
    accounts.add(command);
    if (command == 'queueProgress') progress.add(data);
    if (command == 'status' && loggedIn) {
      return {
        'loggedIn': true,
        'profile': {'uid': '7000000000000000001'},
      };
    }
    return command == 'seasons'
        ? {
            'currentSeason': season,
            'seasons': seasons.map(row).toList(),
            'relatedWorks': seasons.map(row).toList(),
          }
        : {};
  }

  Map<String, dynamic> row(DramaSeason item) => {
    'drama': item.drama.toJson(),
    'number': item.number,
    'playable': item.playable,
    'reservable': item.reservable,
    'next': item.next,
  };
  @override
  Future<PlaybackPlan?> preload(
    Drama drama,
    Episode episode, {
    int quality = 0,
    bool online = false,
  }) async {
    preloads++;
    active.add('preloaded');
    return const PlaybackPlan(
      url: 'https://synthetic.test/preloaded.mp4',
      session: 'preloaded',
      prefetchedBytes: 8192,
    );
  }
}

DramaSeason season(
  int number, {
  bool playable = true,
  bool reservable = false,
}) => DramaSeason(
  drama: Drama(
    id: 'hongguo:season-$number',
    source: 'hongguo',
    title: '合成系列第$number季',
    episodes: playable ? 2 : 0,
  ),
  number: number,
  playable: playable,
  reservable: reservable,
);

void main() {
  test('favorite counts preserve units and switch at exact thresholds', () {
    for (final entry in {
      '0': '0',
      '9999': '9999',
      '10000': '1万',
      '265000': '26.5万',
      '99999999': '9999.9万',
      '100000000': '1亿',
      '126000000': '1.2亿',
      '26.5万': '26.5万',
      '2.5亿': '2.5亿',
      '1,234,567': '123.4万',
      '': '',
      '-1': '',
      'unknown': '',
    }.entries) {
      expect(playerFavoriteCount(entry.key), entry.value, reason: entry.key);
    }
    final drama = Drama.fromJson({'id': 'hongguo:1', 'favoriteCount': 265000});
    expect(
      drama.merge(Drama.fromJson({'id': drama.id})).favoriteCount,
      '265000',
    );
    expect(Drama.fromJson(drama.toJson()).favoriteCount, '265000');
  });

  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_PLAYER')) return;
    final font = const String.fromEnvironment('CAPTURE_FONT');
    final icons = const String.fromEnvironment('CAPTURE_ICONS');
    if (font.isNotEmpty) {
      final loader = FontLoader('Roboto')
        ..addFont(
          File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
    if (icons.isNotEmpty) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(
          File(icons)
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
  });
  Future<void> tick(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<LocalStore> mount(
    WidgetTester tester,
    SeriesRepository repository,
    ScriptedPlayer player, {
    Size size = const Size(390, 844),
    double scale = 1,
    int index = 0,
    String favoriteCount = '',
    PlaybackPreferences preferences = const PlaybackPreferences(),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({});
    final store = testStore(await SharedPreferences.getInstance());
    await store.setPlaybackPreferences(preferences);
    addTearDown(store.dispose);
    final detail = await repository.detail(FixtureRepository.free);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const ValueKey('capture-player'),
          child: PlayerScreen(
            detail: DramaDetail(
              detail.drama.merge(
                Drama(
                  id: detail.drama.id,
                  source: detail.drama.source,
                  title: detail.drama.title,
                  favoriteCount: favoriteCount,
                ),
              ),
              detail.episodes,
              currentSeason: repository.season,
              seasons: repository.seasons,
            ),
            initialIndex: index,
            repository: repository,
            store: store,
            playerFactory: () => Player(platformPlayer: player),
            videoBuilder: (controls) => Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFF22211D)),
                const Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(color: Color(0xFF596A65)),
                  ),
                ),
                controls,
              ],
            ),
          ),
        ),
      ),
    );
    await tick(tester);
    return store;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tick(tester);
    expect(tester.takeException(), isNull);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_PLAYER')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture-player')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/validation/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  test(
    'history payload includes timezone and the official episode identity',
    () {
      final date = DateTime(2026, 10, 24, 12, 30);
      final payload = hongguoWatchPayload(
        WatchEntry(
          drama: FixtureRepository.free,
          episode: 2,
          position: 55,
          duration: 120,
          updatedAt: date,
        ),
        Episode({'id': 'hongguo:123456'}, 2),
      );
      expect(payload['videoId'], '123456');
      expect(payload['updatedAt'], endsWith('Z'));
      expect(
        DateTime.parse(payload['updatedAt'] as String).isAtSameMomentAs(date),
        isTrue,
      );
    },
  );

  for (final layout in [
    (const Size(390, 844), 1.0),
    (const Size(240, 360), 1.0),
    (const Size(320, 700), 1.8),
    (const Size(1024, 768), 1.0),
  ]) {
    testWidgets(
      'player and episode sheet fit $layout without reopening media',
      (tester) async {
        final repository = SeriesRepository();
        final player = ScriptedPlayer();
        await mount(
          tester,
          repository,
          player,
          size: layout.$1,
          scale: layout.$2,
        );
        await capture(tester, 'player-${layout.$1.width.toInt()}');
        final open = find.byKey(const ValueKey('player-open-details'));
        if (open.evaluate().isNotEmpty) {
          await tester.tap(open);
          await tester.pumpAndSettle();
        }
        expect(find.text('简介'), findsOneWidget);
        expect(find.text('选集'), findsOneWidget);
        expect(find.text('系列剧'), findsOneWidget);
        expect(find.byKey(const ValueKey('play-episode-2')), findsOneWidget);
        await capture(tester, 'player-sheet-${layout.$1.width.toInt()}');
        expect(player.opened, hasLength(1));
        expect(tester.takeException(), isNull);
        await close(tester);
      },
    );
  }

  testWidgets('series puts later seasons in order before related works', (
    tester,
  ) async {
    final repository = SeriesRepository()
      ..seasons = [
        season(4),
        const DramaSeason(
          drama: Drama(id: 'hongguo:related', source: 'hongguo', title: '关联作品'),
          number: 0,
          playable: true,
          reservable: false,
        ),
        season(1),
        season(3),
      ];
    await mount(tester, repository, ScriptedPlayer());
    await tester.tap(find.byTooltip('系列剧'));
    await tester.pumpAndSettle();
    final list = find
        .descendant(
          of: find.byType(PlayerScreen),
          matching: find.byType(ListView),
        )
        .first;
    final view = tester.widget<ListView>(list);
    final children =
        (view.childrenDelegate as SliverChildListDelegate).children;
    final cards = children
        .where((child) => child.key.toString().contains('related-hongguo:'))
        .map((child) => child.key)
        .toList();
    expect(cards.take(2), [
      const ValueKey('related-hongguo:season-3'),
      const ValueKey('related-hongguo:season-4'),
    ]);
    await tester.drag(list, const Offset(0, -520));
    await tester.pumpAndSettle();
    await capture(tester, 'player-series');
    await close(tester);
  });

  testWidgets(
    'last episode prioritizes next season and reserves only at the last released season',
    (tester) async {
      final repository = SeriesRepository()
        ..seasons = [season(3), season(4, playable: false, reservable: true)];
      await mount(tester, repository, ScriptedPlayer(), index: 1);
      expect(
        find.byKey(const ValueKey('footer-hongguo:season-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('footer-hongguo:season-4')),
        findsNothing,
      );
      await close(tester);
      repository.season = 3;
      await mount(tester, repository, ScriptedPlayer(), index: 1);
      expect(
        find.byKey(const ValueKey('footer-hongguo:season-4')),
        findsOneWidget,
      );
      expect(find.text('预约'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets(
    'favorite count is visible below portrait, sheet and wide panel favorite actions',
    (tester) async {
      await mount(
        tester,
        SeriesRepository(),
        ScriptedPlayer(),
        favoriteCount: '265000',
      );
      expect(find.text('26.5万'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player-favorite-count')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('player-open-details')));
      await tester.pumpAndSettle();
      expect(find.text('26.5万'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player-panel-favorite-count')),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('player-panel-favorite-count')),
            )
            .dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.byKey(const ValueKey('player-panel-favorite')),
              )
              .dy,
        ),
      );
      await close(tester);
      await mount(
        tester,
        SeriesRepository(),
        ScriptedPlayer(),
        size: const Size(1000, 800),
        favoriteCount: '100000000',
      );
      expect(find.text('1亿'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player-panel-favorite-count')),
        findsOneWidget,
      );
      await close(tester);
    },
  );

  testWidgets(
    'portrait landscape video moves up with its play control and lower cast action is absent',
    (tester) async {
      final player = ScriptedPlayer();
      await mount(tester, SeriesRepository(), player);
      player.videoSize(1920, 1080);
      await tick(tester);
      final placement = tester.widget<Transform>(
        find.byKey(const ValueKey('player-media-placement')),
      );
      expect(placement.transform.getTranslation().y, lessThan(0));
      expect(placement.transform.getTranslation().y, greaterThanOrEqualTo(-36));
      expect(find.byTooltip('投屏'), findsNothing);
      await close(tester);
    },
  );

  testWidgets(
    'switching to the previous and next episode resumes their independent saved positions',
    (tester) async {
      final player = ScriptedPlayer();
      final store = await mount(tester, SeriesRepository(), player);
      Future<void> select(int number) async {
        await tester.tap(find.byKey(const ValueKey('player-open-details')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('play-episode-$number')));
        await tick(tester);
      }

      await player.seek(const Duration(seconds: 23));
      await select(2);
      await player.seek(const Duration(seconds: 47));
      await select(1);
      expect(player.opened.last.start, const Duration(seconds: 23));
      await select(2);
      expect(player.opened.last.start, const Duration(seconds: 47));
      final detail = await SeriesRepository().detail(FixtureRepository.free);
      expect(
        store.episodeWatched(detail.drama, detail.episodes.first)?.position,
        23,
      );
      await close(tester);
    },
  );

  testWidgets(
    'final seconds preload despite a short tail buffer and auto-advance reuses the plan',
    (tester) async {
      final repository = SeriesRepository();
      final player = ScriptedPlayer();
      await mount(tester, repository, player);
      player.state = player.state.copyWith(
        buffer: const Duration(seconds: 120),
      );
      await player.seek(const Duration(seconds: 117));
      await tick(tester);
      expect(repository.preloads, 1);
      player.finishEpisode();
      await tick(tester);
      expect(player.opened.last.uri, contains('preloaded.mp4'));
      expect(repository.primaryCalls, 1);
      expect(repository.active, ['preloaded']);
      await close(tester);
      expect(repository.active, isEmpty);
    },
  );

  testWidgets(
    'every completed episode queues immediate upload including automatic advance',
    (tester) async {
      final repository = SeriesRepository()..loggedIn = true;
      final player = ScriptedPlayer();
      await mount(tester, repository, player);
      player.finishEpisode();
      await tick(tester);
      expect(
        repository.progress.where(
          (row) =>
              row['flush'] == true && (row['watch'] as Map)['episode'] == 1,
        ),
        isNotEmpty,
      );
      player.finishEpisode();
      await tick(tester);
      expect(
        repository.progress.where(
          (row) =>
              row['flush'] == true && (row['watch'] as Map)['episode'] == 2,
        ),
        isNotEmpty,
      );
      expect(
        repository.progress.every(
          (row) => (row['watch'] as Map)['position'] == 120,
        ),
        isTrue,
      );
      await close(tester);
    },
  );

  testWidgets(
    'completion flush still runs when the final position was already saved',
    (tester) async {
      final repository = SeriesRepository()..loggedIn = true;
      final player = ScriptedPlayer();
      await mount(tester, repository, player, index: 1);
      await player.seek(const Duration(seconds: 120));
      await tester.pump(const Duration(seconds: 5));
      await tick(tester);
      expect(repository.progress, isNotEmpty);
      final before = repository.immediateSyncs;
      player.finishEpisode();
      await tick(tester);
      expect(repository.immediateSyncs, greaterThan(before));
      await close(tester);
    },
  );

  testWidgets(
    'disabled automatic playback and preload persist through menu changes',
    (tester) async {
      final repository = SeriesRepository();
      final player = ScriptedPlayer();
      final store = await mount(
        tester,
        repository,
        player,
        preferences: const PlaybackPreferences(
          autoAdvance: false,
          preload: false,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('player-speed')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-speed-1.5')));
      await tester.pumpAndSettle();
      expect(store.playbackPreferences.autoAdvance, isFalse);
      expect(store.playbackPreferences.preload, isFalse);
      await tester.tap(find.byTooltip('关闭菜单'));
      await tester.pumpAndSettle();
      await player.seek(const Duration(seconds: 117));
      player.finishEpisode();
      await tick(tester);
      expect(repository.preloads, 0);
      expect(repository.primaryCalls, 1);
      await close(tester);
    },
  );
}
