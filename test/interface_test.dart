import 'package:duanju_app/app_theme.dart';
import 'package:duanju_app/downloads_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'interface_fixtures.dart';

void main() {
  Future<LocalStore> localStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    return store;
  }

  void viewport(WidgetTester tester, Size size, [double scale = 1]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  for (final layout in [
    (const Size(360, 760), 1.0),
    (const Size(320, 844), 2.0),
    (const Size(1280, 800), 1.0),
  ]) {
    testWidgets(
      'download actions stay above filters and control the whole queue at $layout',
      (tester) async {
        viewport(tester, layout.$1, layout.$2);
        final repository = InterfaceRepository();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: DownloadsScreen(
              repository: repository,
              store: await localStore(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final menu = find.byKey(const ValueKey('download-queue-actions'));
        final local = find.byKey(const ValueKey('download-local-media'));
        expect(
          tester.getCenter(menu).dy,
          closeTo(tester.getCenter(local).dy, 1),
        );
        await tester.tap(find.text('短标题'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('download-task-task-0')),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('download-task-task-2')),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text('全部暂停'));
        await tester.pumpAndSettle();
        expect(repository.commands, ['pause:task-0']);
        expect(repository.jobs.where((job) => job.active), isEmpty);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text('全部继续'));
        await tester.pumpAndSettle();
        expect(repository.commands.last, 'resume:task-1');
        expect(repository.jobs.where((job) => job.active).length, 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
