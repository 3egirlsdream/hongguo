import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:duanju_app/app_layout.dart';
import 'package:duanju_app/app_theme.dart';
import 'package:duanju_app/catalog_sort.dart';
import 'package:duanju_app/catalog_sort_sheet.dart';
import 'package:duanju_app/drama_actions.dart';
import 'package:duanju_app/lan_controller.dart';
import 'package:duanju_app/lan_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/hongguo_account_screen.dart';
import 'package:duanju_app/media_library.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/profiles_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design_review_test.dart';
import 'fixtures.dart';
import 'interface_fixtures.dart';

const designSubpages = {
  'sort-filter': 'search',
  'theme-choice': 'theme',
  'download-filters': 'downloads',
  'download-queue': 'downloads',
  'downloads-populated': 'downloads',
  'favorite-actions': 'favorites',
  'favorite-filter': 'favorites',
  'history-filter': 'history',
  'reservation-actions': 'reservations',
  'lan-rename': 'lan',
  'lan-devices': 'lan',
  'lan-address': 'lan',
  'merge-add': 'merge-queue',
  'episode-jump': 'download-picker',
  'profile-password': 'profiles',
  'profile-delete': 'profile-edit',
  'resource-manual': 'resource',
  'logout-confirm': 'account',
  'player-settings-bottom': 'player-settings',
  'lan-manual': 'lan',
  'local-delete': 'local-media',
  'login-code': 'login',
  'login-mfa': 'login',
  'lan-conflicts': 'lan',
  'lan-push': 'lan',
};

class SubpageRepository extends DesignReviewRepository {
  SubpageRepository(super.directory);
  List<DownloadJob> jobs = [];
  String phase = '';
  @override
  Future<Map<String, dynamic>> hongguoAccount(
    String command, [
    Map<String, dynamic> input = const {},
  ]) async {
    if (command == 'status' && phase.isNotEmpty) {
      return {
        'loggedIn': false,
        'phase': phase,
        'retryAfter': 30,
        'smsNumber': '106900000000000',
        'smsContent': '合成界面验证，不发送短信',
        'verificationState': 'waiting',
      };
    }
    return super.hongguoAccount(command, input);
  }

  @override
  Future<List<DownloadJob>> downloads() async => jobs;
}

class ReviewLanController extends LanController {
  ReviewLanController(super.repository, super.store) : super(kind: 'phone');
  bool showConflict = false;
  @override
  int get conflictCount => showConflict ? 1 : super.conflictCount;
  void connectFixture() {
    connection = LanConnection(
      peer: LanPeer(
        id: 'a' * 32,
        name: '合成接收设备',
        pin: 'b' * 64,
        kind: 'phone',
        port: 12345,
      ),
      address: '127.0.0.1',
      token: 'synthetic',
      account: 'c' * 32,
      user: '观影用户',
      sources: const {'hongguo'},
      autoSync: false,
    );
    notifyListeners();
  }

  @override
  Future<void> ensureEnabled() async {}
  @override
  Future<void> rescan() async {}
}

Future<Widget> designSubpageBase(
  String name,
  SubpageRepository repo,
  LocalStore store,
  MediaLibrary library,
  LanController link,
) async {
  if (name == 'lan-conflicts') {
    (link as ReviewLanController).showConflict = true;
  }
  if (name == 'login-code' || name == 'login-mfa') {
    repo.loggedIn = false;
    repo.phase = name == 'login-code' ? 'code' : 'mfa';
  }
  if (name == 'local-delete') {
    final item = LocalMediaItem(
      id: 'synthetic-media',
      drama: DesignReviewRepository.dramas.first,
      file: 'synthetic.mp4',
      kind: 'local',
      episodes: [1],
      duration: 60,
      bytes: 1048576,
      created: DateTime(2026, 11, 8),
    );
    File('${repo.directory}/media-library.json').writeAsStringSync(
      jsonEncode({
        'items': [item.toJson()],
      }),
    );
  }
  if (name == 'downloads-populated') repo.jobs = InterfaceRepository().jobs;
  if (name == 'favorite-filter' || name == 'history-filter') {
    return Scaffold(
      body: HongguoAccountScreen(
        repository: repo,
        store: store,
        collections: true,
        embedded: true,
        initialTab: name == 'favorite-filter' ? 0 : 1,
      ),
    );
  }
  if (name == 'profile-password' || name == 'profile-delete') {
    await store.saveProfile(
      id: store.profile.id,
      name: store.profile.name,
      sources: const ['hongguo'],
      download: true,
      pin: '123456',
    );
    await store.saveProfile(
      name: '观影用户',
      sources: const ['hongguo'],
      download: true,
      pin: '123456',
    );
    if (name == 'profile-delete') {
      return ProfileEditor(store: store, profile: store.profiles.last);
    }
  }
  return designReviewPage(designSubpages[name]!, repo, store, library, link);
}

Future<void> openDesignSubpage(
  WidgetTester tester,
  String name,
  SubpageRepository repo,
  LocalStore store,
) async {
  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder.first);
    await tester.tap(finder.first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }

  switch (name) {
    case 'sort-filter':
      unawaited(
        chooseCatalogView(
          tester.element(find.byType(AppLayout)),
          const CatalogView(),
        ),
      );
    case 'theme-choice':
      await tap(find.text('主题'));
    case 'download-filters':
      await tap(find.byTooltip('筛选下载合集'));
    case 'download-queue':
      await tap(find.byKey(const ValueKey('download-queue-actions')));
    case 'favorite-actions':
      unawaited(
        showDramaActions(
          tester.element(find.byType(AppLayout)),
          drama: DesignReviewRepository.dramas.first,
          store: store,
          repository: repo,
          onDownload: () {},
          onSelect: () {},
        ),
      );
    case 'favorite-filter' || 'history-filter':
      await tap(find.text('筛选'));
    case 'reservation-actions':
      await tap(find.text(DesignReviewRepository.dramas.first.title));
    case 'lan-rename':
      await tap(find.byTooltip('修改设备名称'));
    case 'lan-devices' || 'lan-address':
      await tap(find.text('选择设备'));
      if (name == 'lan-address') await tap(find.text('输入地址连接'));
    case 'merge-add':
      await tap(find.text('添加剧集'));
    case 'episode-jump':
      await tap(find.byTooltip('跳转集数'));
    case 'profile-password':
      await tap(find.text('观影用户'));
    case 'profile-delete':
      await tap(find.text('删除用户'));
    case 'resource-manual':
      await tap(find.text('自动'));
      await tap(find.text('手动代理').last);
    case 'logout-confirm':
      await tap(find.text('退出账号'));
    case 'player-settings-bottom':
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -1200),
      );
    case 'lan-manual':
      (tester.widget<LanSyncScreen>(find.byType(LanSyncScreen)).controller
              as ReviewLanController)
          .connectFixture();
      await tester.pump();
      if (find.text('手动同步').evaluate().isEmpty) {
        await tester.scrollUntilVisible(find.text('手动同步'), 200);
      }
      await tap(find.text('手动同步'));
      expect(find.text('双向合并'), findsWidgets);
    case 'lan-conflicts':
      if (find.text('1 项记录待处理').evaluate().isEmpty) {
        await tester.scrollUntilVisible(find.text('1 项记录待处理'), 200);
      }
      await tap(find.text('1 项记录待处理'));
      expect(find.text('处理记录冲突'), findsOneWidget);
    case 'lan-push':
      final link =
          tester.widget<LanSyncScreen>(find.byType(LanSyncScreen)).controller
              as ReviewLanController;
      link.connectFixture();
      unawaited(
        showLanPush(
          tester.element(find.byType(AppLayout)),
          link,
          snapshot: () => LanPlaybackIntent(
            drama: DesignReviewRepository.dramas.first,
            episodeID: '1',
            episode: 1,
            position: 30,
          ),
          stillCurrent: () => true,
          onAccepted: () async {},
        ),
      );
    case 'local-delete':
      await tap(find.byTooltip('删除成品'));
    case 'downloads-populated' || 'login-code' || 'login-mfa':
      break;
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  if (name == 'lan-push') {
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Bad state:'), findsNothing);
    expect(find.text('关闭'), findsOneWidget);
  }
}

void main() {
  if (!const bool.fromEnvironment('CAPTURE_DESIGN_SUBPAGES')) return;
  final output = const String.fromEnvironment(
    'DESIGN_SUBPAGES_OUTPUT',
    defaultValue: 'build/design-followup/before',
  );
  setUpAll(() async {
    final bytes = File(
      const String.fromEnvironment(
        'DESIGN_REVIEW_FONT',
        defaultValue: 'build/design-review/review-font.ttc',
      ),
    ).readAsBytes().then(ByteData.sublistView);
    await (FontLoader('ReviewUI')..addFont(bytes)).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  final variants = const bool.fromEnvironment('DESIGN_SUBPAGES_VARIANTS')
      ? ['phone', 'dark', 'narrow-large', 'tablet']
      : ['phone'];
  for (final variant in variants) {
    for (final name in designSubpages.keys) {
      testWidgets('$variant $name', (tester) async {
        tester.view.physicalSize = switch (variant) {
          'narrow-large' => const Size(320, 740),
          'tablet' => const Size(1024, 768),
          _ => const Size(390, 844),
        };
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final store = testStore(await SharedPreferences.getInstance());
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('guo-subpage-'),
        ))!;
        final repo = SubpageRepository(directory.path);
        final library = MediaLibrary(repo, store);
        MediaLibrary.current = library;
        final link = ReviewLanController(repo, store);
        final page = await designSubpageBase(name, repo, store, library, link);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('subpage-frame'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: reviewTheme(
                variant == 'dark' ? AppTheme.dark : AppTheme.light,
              ),
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
                MaterialPageRoute<void>(builder: (_) => AppLayout(child: page)),
              ],
            ),
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 60));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await openDesignSubpage(tester, name, repo, store);
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('subpage-frame')),
          );
          final img = await boundary.toImage(pixelRatio: 2);
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          await Directory('$output/$variant').create(recursive: true);
          await File('$output/$variant/$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
          img.dispose();
        });
        expect(tester.takeException(), isNull, reason: '$variant $name');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 300));
        link.dispose();
        library.dispose();
        MediaLibrary.current = null;
        store.dispose();
        await tester.runAsync(() => directory.delete(recursive: true));
      });
    }
  }
}
