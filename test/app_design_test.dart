import 'package:duanju_app/app_bottom_navigation.dart';
import 'package:duanju_app/app_theme.dart';
import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/theme_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  testWidgets('home search opens the search tab and keeps tab history', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = testStore(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(repository: FixtureRepository(), store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索好剧'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppBottomNavigation>(find.byType(AppBottomNavigation))
          .selectedIndex,
      2,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppBottomNavigation>(find.byType(AppBottomNavigation))
          .selectedIndex,
      0,
    );
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
    'appearance dependencies stay consistent on screen and after restart',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = testStore(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ThemeSettingsScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('液态玻璃'));
      await tester.tap(find.text('液态玻璃'));
      await tester.pumpAndSettle();
      expect(store.themeAppearance.floatingBar, isTrue);
      expect(store.themeAppearance.liquidGlass, isTrue);
      await tester.scrollUntilVisible(find.text('模糊'), -200);
      await tester.tap(find.text('模糊'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('模糊'));
      await tester.pumpAndSettle();
      final toggles = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      expect(toggles.take(3).map((tile) => tile.value), [false, false, false]);
      final restored = testStore(store.preferences);
      expect(restored.themeAppearance.toJson(), store.themeAppearance.toJson());
      expect(restored.themeAppearance.liquidGlass, isFalse);
      await tester.pumpWidget(const SizedBox());
      restored.dispose();
      store.dispose();
    },
  );
}
