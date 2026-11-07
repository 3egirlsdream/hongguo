import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:duanju_app/app_theme.dart';
import 'package:duanju_app/app_layout.dart';
import 'package:duanju_app/diary_service.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/rankings_screen.dart';
import 'package:duanju_app/ranking_models.dart';
import 'package:duanju_app/search_screen.dart';
import 'package:duanju_app/my_screen.dart';
import 'package:duanju_app/settings_screen.dart';
import 'package:duanju_app/theme_settings_screen.dart';
import 'package:duanju_app/profiles_screen.dart';
import 'package:duanju_app/resource_settings_screen.dart';
import 'package:duanju_app/about_screen.dart';
import 'package:duanju_app/detail_screen.dart';
import 'package:duanju_app/downloads_screen.dart';
import 'package:duanju_app/download_picker.dart';
import 'package:duanju_app/batch_download_screen.dart';
import 'package:duanju_app/local_media_screen.dart';
import 'package:duanju_app/merge_queue_screen.dart';
import 'package:duanju_app/catalog_management_screen.dart';
import 'package:duanju_app/hongguo_account_screen.dart';
import 'package:duanju_app/media_library.dart';
import 'package:duanju_app/lan_screen.dart';
import 'package:duanju_app/lan_controller.dart';
import 'package:duanju_app/player_menu.dart';
import 'package:duanju_app/playback_preferences.dart';

import 'fixtures.dart';

class DesignReviewRepository extends FixtureRepository {
  DesignReviewRepository(this.directory);
  final String directory;
  bool loggedIn = true;
  static final dramas = List.generate(
    12,
    (i) => Drama(
      id: 'hongguo:${800001 + i}',
      source: 'hongguo',
      sourceId: '${800001 + i}',
      title: ['山海之间：新的旅程', '风起时，与你再相逢', '长安旧事 第二季', '关于春天的约定'][i % 4],
      category: ['都市 · 情感', '古装 · 奇幻', '悬疑 · 剧情'][i % 3],
      episodes: 60 + i,
      releaseStatus: '已完结',
    ),
  );
  @override
  bool get supportsDownloads => true;
  @override
  bool get supportsOfficialAccount => true;
  @override
  bool get supportsSourceManagement => true;
  @override
  Future<String> downloadDirectory() async => directory;
  @override
  Future<Map<String, dynamic>> storage() async => {
    'directory': directory,
    'bytes': 1258291200,
    'free': 42949672960,
    'files': 32,
  };
  @override
  Future<CatalogPage> recommendations(
    String genre, {
    bool more = false,
    bool force = false,
  }) async => CatalogPage(dramas);
  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async =>
      CatalogPage(dramas);
  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async => CatalogPage(dramas);
  @override
  Future<List<CatalogCategory>> categories(
    String source, {
    bool force = false,
  }) async => const [
    CatalogCategory.all,
    CatalogCategory('urban', '都市'),
    CatalogCategory('costume', '古装'),
    CatalogCategory('mystery', '悬疑'),
  ];
  @override
  Future<DramaDetail> detail(Drama drama) async => DramaDetail(
    drama,
    List.generate(
      60,
      (i) => Episode({
        'id': '${i + 1}',
        'currentEpisode': i + 1,
        'title': '第${i + 1}集',
      }, i + 1),
    ),
  );
  @override
  Future<List<RankingBoard>> rankingBoards() async => const [
    RankingBoard(id: 'hongguo-hot', source: 'hongguo', name: '热播榜'),
    RankingBoard(id: 'hongguo-real', source: 'hongguo', name: '真人榜'),
    RankingBoard(id: 'hongguo-comic', source: 'hongguo', name: '漫剧榜'),
  ];
  @override
  Future<RankingPage> rankings(
    String board, {
    int page = 1,
    bool force = false,
  }) async => RankingPage(
    items: [
      for (var i = 0; i < dramas.length; i++)
        RankingItem(i + 1, dramas[i], metric: '${230 - i * 9}万热度'),
    ],
    updatedText: '今日更新',
  );
  @override
  Future<Map<String, dynamic>> hongguoAccount(
    String command, [
    Map<String, dynamic> input = const {},
  ]) async {
    if (command == 'status') {
      return {
        'loggedIn': loggedIn,
        'phase': loggedIn ? 'loggedIn' : 'idle',
        'profile': loggedIn
            ? {
                'uid': '8000000000000000001',
                'name': '野果用户',
                'publicId': '800001',
              }
            : null,
      };
    }
    if (command == 'favorites') {
      return {
        'items': [
          for (final d in dramas.take(3)) {'drama': d.toJson()},
        ],
        'hasMore': false,
      };
    }
    if (command == 'history') return {'items': []};
    if (command == 'reservations' || command == 'calendar') {
      return {
        'items': [
          for (final d in dramas.take(3))
            {
              'id': d.sourceId,
              'drama': d.toJson(),
              'reserved': true,
              'upcoming': true,
              'publishText': '11 月 20 日 18:00 上线',
            },
        ],
        'hasMore': false,
      };
    }
    return {};
  }
}

const designReviewPages = [
  'home',
  'rankings',
  'search',
  'my',
  'settings',
  'theme',
  'profiles',
  'profile-edit',
  'profiles-locked',
  'resource',
  'download-preferences',
  'storage',
  'about',
  'diary',
  'detail',
  'downloads',
  'batch-downloads',
  'local-media',
  'merge-queue',
  'content-management',
  'account',
  'login',
  'favorites',
  'history',
  'reservations',
  'calendar',
  'lan',
  'player-speed',
  'player-episodes',
  'player-settings',
  'player-quality',
  'download-picker',
];

Future<Widget> designReviewPage(
  String name,
  DesignReviewRepository repo,
  LocalStore store,
  MediaLibrary library,
  LanController link,
) async {
  return switch (name) {
    'home' => HomeScreen(repository: repo, store: store),
    'rankings' => RankingsScreen(repository: repo, store: store),
    'search' => SearchScreen(repository: repo, store: store),
    'my' => Scaffold(
      body: SafeArea(
        child: MyScreen(repository: repo, store: store, onRankings: () {}),
      ),
    ),
    'settings' => SettingsScreen(repository: repo, store: store),
    'theme' => ThemeSettingsScreen(store: store),
    'profiles' => ProfilesScreen(store: store),
    'profiles-locked' => ProfilesScreen(store: store, locked: true),
    'download-picker' => DownloadPicker(
      detail: await repo.detail(DesignReviewRepository.dramas.first),
      initialEpisodeNumber: 1,
    ),
    'profile-edit' => ProfileEditor(store: store),
    'resource' => ResourceSettingsScreen(repository: repo, store: store),
    'download-preferences' => DownloadPreferencesScreen(store: store),
    'storage' => StorageScreen(repository: repo, store: store),
    'about' => const AboutScreen(),
    'diary' => const DiaryScreen(),
    'detail' => DetailScreen(
      drama: DesignReviewRepository.dramas.first,
      repository: repo,
      store: store,
    ),
    'downloads' => DownloadsScreen(repository: repo, store: store),
    'batch-downloads' => BatchDownloadScreen(
      repository: repo,
      store: store,
      dramas: DesignReviewRepository.dramas.take(3).toList(),
    ),
    'local-media' => LocalMediaScreen(repository: repo, store: store),
    'merge-queue' => MergeQueueScreen(
      library: library,
      repository: repo,
      store: store,
    ),
    'content-management' => CatalogManagementScreen(
      repository: repo,
      store: store,
    ),
    'account' ||
    'login' => HongguoAccountScreen(repository: repo, store: store),
    'favorites' ||
    'history' ||
    'reservations' ||
    'calendar' => HongguoAccountScreen(
      repository: repo,
      store: store,
      collections: true,
      initialTab: [
        'favorites',
        'history',
        'reservations',
        'calendar',
      ].indexOf(name),
    ),
    'lan' => LanSyncScreen(controller: link),
    'player-speed' ||
    'player-episodes' ||
    'player-settings' ||
    'player-quality' => Scaffold(
      backgroundColor: Colors.black,
      body: PlayerMenu(
        section: switch (name) {
          'player-speed' => PlayerMenuSection.speed,
          'player-episodes' => PlayerMenuSection.episodes,
          'player-quality' => PlayerMenuSection.quality,
          _ => PlayerMenuSection.settings,
        },
        episodes: (await repo.detail(DesignReviewRepository.dramas.first))
            .episodes,
        currentIndex: 5,
        preferences: const PlaybackPreferences(),
        qualities: const [720, 1080],
        actualQuality: 1080,
        local: false,
        favorite: false,
        onEpisode: (_) {},
        onPreferences: (_) async {},
        onFavorite: () async {},
      ),
    ),
    _ => throw StateError(name),
  };
}

ThemeData reviewTheme(ThemeData base) {
  TextStyle? font(TextStyle? style) => style?.copyWith(fontFamily: 'ReviewUI');
  ButtonStyle? button(ButtonStyle? style) => style?.copyWith(
    textStyle: WidgetStatePropertyAll(font(style.textStyle?.resolve({}))),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'ReviewUI'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'ReviewUI'),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: font(base.appBarTheme.titleTextStyle),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: button(base.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button(base.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button(base.textButtonTheme.style),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      titleTextStyle: font(base.listTileTheme.titleTextStyle),
      subtitleTextStyle: font(base.listTileTheme.subtitleTextStyle),
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelStyle: font(base.tabBarTheme.labelStyle),
      unselectedLabelStyle: font(base.tabBarTheme.unselectedLabelStyle),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: font(base.chipTheme.labelStyle),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      titleTextStyle: font(base.dialogTheme.titleTextStyle),
      contentTextStyle: font(base.dialogTheme.contentTextStyle),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      hintStyle: font(base.inputDecorationTheme.hintStyle),
      labelStyle: font(base.inputDecorationTheme.labelStyle),
      helperStyle: font(base.inputDecorationTheme.helperStyle),
    ),
  );
}

void main() {
  if (!const bool.fromEnvironment('CAPTURE_DESIGN_REVIEW')) return;
  final output = const String.fromEnvironment(
    'DESIGN_REVIEW_OUTPUT',
    defaultValue: 'build/design-review/before',
  );
  final font = const String.fromEnvironment(
    'DESIGN_REVIEW_FONT',
    defaultValue: '/System/Library/Fonts/PingFang.ttc',
  );
  setUpAll(() async {
    final loader = FontLoader('ReviewUI')
      ..addFont(File(font).readAsBytes().then(ByteData.sublistView));
    await loader.load();
    await (FontLoader(
      'Roboto',
    )..addFont(File(font).readAsBytes().then(ByteData.sublistView))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  final variants = const bool.fromEnvironment('DESIGN_REVIEW_VARIANTS')
      ? ['phone', 'dark', 'narrow-large', 'tablet']
      : ['phone'];
  for (final variant in variants) {
    for (final name in designReviewPages) {
      testWidgets('review $variant $name', (tester) async {
        tester.view.physicalSize = switch (variant) {
          'tablet' => const Size(1024, 768),
          'narrow-large' => const Size(320, 740),
          _ => const Size(390, 844),
        };
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('duanju/update'),
              (call) async => {
                'version': appVersion,
                'build': 129,
                'canInstall': false,
              },
            );
        SharedPreferences.setMockInitialValues({});
        final store = testStore(await SharedPreferences.getInstance());
        final directory = await tester.runAsync(
          () => Directory.systemTemp.createTemp('guo-ui-'),
        );
        final repo = DesignReviewRepository(directory!.path);
        final library = MediaLibrary(repo, store);
        MediaLibrary.current = library;
        final link = LanController(repo, store, kind: 'phone');
        final page = await designReviewPage(name, repo, store, library, link);
        if (name == 'login') repo.loggedIn = false;
        final baseTheme = variant == 'dark' ? AppTheme.dark : AppTheme.light;
        final theme = reviewTheme(baseTheme);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('zh', 'CN')],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  variant == 'narrow-large' ? 1.6 : 1,
                ),
              ),
              child: child!,
            ),
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => const SizedBox()),
            onGenerateInitialRoutes: (_) => [
              MaterialPageRoute<void>(builder: (_) => const SizedBox()),
              MaterialPageRoute<void>(
                builder: (_) => AppLayout(
                  child: RepaintBoundary(
                    key: const ValueKey('review-boundary'),
                    child: page,
                  ),
                ),
              ),
            ],
          ),
        );
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 40));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('review-boundary')),
          );
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('$output/$variant').create(recursive: true);
          await File('$output/$variant/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull, reason: '$variant $name');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 200));
        link.dispose();
        library.dispose();
        MediaLibrary.current = null;
        store.dispose();
        await tester.runAsync(() => directory.delete(recursive: true));
      });
    }
  }
}
