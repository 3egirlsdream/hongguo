import 'dart:io';

import 'package:duanju_app/app_layout.dart';
import 'package:duanju_app/app_theme.dart';
import 'package:duanju_app/lan_controller.dart';
import 'package:duanju_app/media_library.dart';
import 'package:duanju_app/theme_settings_screen.dart';
import 'package:duanju_app/diary_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/design_review_test.dart'
    show DesignReviewRepository, designReviewPage, designReviewPages;
import '../test/fixtures.dart' show testStore;
import '../test/design_subpages_test.dart'
    show
        SubpageRepository,
        ReviewLanController,
        designSubpages,
        designSubpageBase,
        openDesignSubpage;
import 'reservation_controls_test.dart' as player_verification;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('SUBPAGES_ONLY')) {
    testWidgets('all pages on Android with synthetic content', (tester) async {
      expect(const bool.fromEnvironment('DISABLE_REMOTE_IMAGES'), isTrue);
      SharedPreferences.setMockInitialValues({});
      final store = testStore(await SharedPreferences.getInstance());
      final directory = await Directory.systemTemp.createTemp('guo-design-');
      final repo = DesignReviewRepository(directory.path);
      final library = MediaLibrary(repo, store);
      MediaLibrary.current = library;
      final link = LanController(repo, store, kind: 'phone');
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await binding.convertFlutterSurfaceToImage();
      final captured = <String>[];
      for (final name in designReviewPages) {
        repo.loggedIn = name != 'login';
        final page = await designReviewPage(name, repo, store, library, link);
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(name),
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('zh', 'CN')],
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => const SizedBox()),
            onGenerateInitialRoutes: (_) => [
              MaterialPageRoute<void>(builder: (_) => const SizedBox()),
              MaterialPageRoute<void>(builder: (_) => AppLayout(child: page)),
            ],
          ),
        );
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 80));
        }
        expect(tester.takeException(), isNull, reason: name);
        await binding.takeScreenshot('design-$name');
        captured.add(name);
        if (name == 'home') {
          await tester.tap(find.text('搜索好剧'));
          await tester.pumpAndSettle();
          expect(find.text('搜索短剧'), findsWidgets);
          await binding.takeScreenshot('design-home-search');
        }
        if (name == 'search') {
          await tester.enterText(find.byType(TextField).first, '山海');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          expect(find.text('山海之间：新的旅程'), findsWidgets);
          await binding.takeScreenshot('design-search-results');
        }
        if (name == 'detail') {
          if (find.byKey(const ValueKey('episode-1')).evaluate().isEmpty) {
            await tester.tap(find.textContaining('选集 · 60 集'));
          }
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('episode-1')), findsOneWidget);
          await binding.takeScreenshot('design-detail-expanded');
        }
        if (name == 'settings') {
          await tester.scrollUntilVisible(find.text('播放调试日记'), 250);
          DiaryService.add('合成界面走查');
          await tester.tap(find.text('播放调试日记'));
          await tester.pumpAndSettle();
          await binding.takeScreenshot('design-diary');
        }
        if (name == 'theme') {
          await tester.tap(find.text('主题'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('深色'));
          await tester.pumpAndSettle();
          expect(store.themeMode, 'dark');
          expect(find.byType(ThemeSettingsScreen), findsOneWidget);
          await store.setThemeMode('light');
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      }
      binding.reportData ??= {};
      binding.reportData!.addAll({
        'pages': captured,
        'count': captured.length,
        'remoteImagesDisabled': true,
      });
      link.dispose();
      library.dispose();
      MediaLibrary.current = null;
      store.dispose();
      await directory.delete(recursive: true);
    });
  }
  testWidgets('subpages and dialogs on Android with synthetic content', (
    tester,
  ) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await binding.convertFlutterSurfaceToImage();
    final captured = <String>[];
    final filter = const String.fromEnvironment('SUBPAGE_FILTER');
    for (final name in designSubpages.keys.where(
      (name) => filter.isEmpty || name == filter,
    )) {
      SharedPreferences.setMockInitialValues({});
      final store = testStore(await SharedPreferences.getInstance());
      final directory = await Directory.systemTemp.createTemp('guo-subpage-');
      final repo = SubpageRepository(directory.path);
      final library = MediaLibrary(repo, store);
      MediaLibrary.current = library;
      final link = ReviewLanController(repo, store);
      final page = await designSubpageBase(name, repo, store, library, link);
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('sub-$name'),
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh', 'CN')],
          onGenerateRoute: (_) =>
              MaterialPageRoute<void>(builder: (_) => const SizedBox()),
          onGenerateInitialRoutes: (_) => [
            MaterialPageRoute<void>(builder: (_) => const SizedBox()),
            MaterialPageRoute<void>(builder: (_) => AppLayout(child: page)),
          ],
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      await openDesignSubpage(tester, name, repo, store);
      expect(tester.takeException(), isNull, reason: name);
      await binding.takeScreenshot('subpage-$name');
      captured.add(name);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
      link.dispose();
      library.dispose();
      MediaLibrary.current = null;
      store.dispose();
      await directory.delete(recursive: true);
    }
    binding.reportData ??= {};
    binding.reportData!.addAll({
      'subpages': captured,
      'subpageCount': captured.length,
    });
  });
  if (!const bool.fromEnvironment('SUBPAGES_ONLY')) player_verification.main();
}
