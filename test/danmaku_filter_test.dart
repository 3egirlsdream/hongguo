import 'package:duanju_app/danmaku_controller.dart';
import 'package:duanju_app/danmaku_filter.dart';
import 'package:duanju_app/danmaku_filter_dialog.dart';
import 'package:duanju_app/playback_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duanju_app/local_store.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'danmaku_fixtures.dart';
import 'danmaku_test.dart' show danmakuPlan, updateDanmaku, flushDanmaku;

void main() {
  test('contains matching normalizes case, full width, whitespace and invisible separators', () {
    final filter = DanmakuKeywordFilter(['剧透', 'ＡＢＣ', 'C++', '剧透', ' ']);
    expect(filter.keywords, hasLength(3));
    for (final text in [
      '这里有剧 透内容',
      '剧\u200b透了',
      '这是aBc内容',
      '这是ＡＢＣ内容',
      '使用C++',
    ]) {
      expect(filter.blocks(text), isTrue, reason: text);
    }
    expect(filter.blocks('正常讨论'), isFalse);
    expect(DanmakuKeywordFilter(['.*']).blocks('正常讨论'), isFalse);
    expect(DanmakuKeywordFilter(['.*']).blocks('文字.*文字'), isTrue);
    expect(DanmakuKeywordFilter(['   ']).blocks('正常讨论'), isFalse);
    expect(() => normalizeDanmakuKeywords(['x' * 51]), throwsFormatException);
    expect(
      () => normalizeDanmakuKeywords(List.generate(101, (i) => '关键词$i')),
      throwsFormatException,
    );
  });
  test(
    'preferences preserve keywords across unrelated changes and legacy records',
    () {
      final value = PlaybackPreferences.fromJson({
        'danmakuBlockedKeywords': ['剧透', 'ABC', 'ａｂｃ'],
      });
      expect(value.danmakuBlockedKeywords, ['剧透', 'ABC']);
      final restored = PlaybackPreferences.fromJson(
        value.copyWith(speed: 2, danmaku: false).toJson(),
      );
      expect(restored.danmakuBlockedKeywords, ['剧透', 'ABC']);
      expect(restored.speed, 2);
      expect(PlaybackPreferences.fromJson({}).danmakuBlockedKeywords, isEmpty);
    },
  );
  test('editing filters removes cached items immediately and restores without refetch', () async {
    final repository = DanmakuFixtureRepository();
    final controller = DanmakuController(repository)..setPlan(danmakuPlan);
    updateDanmaku(controller);
    await flushDanmaku();
    expect(controller.items, isNotEmpty);
    final calls = repository.danmakuCalls.length;
    final revision = controller.dataRevision;
    controller.setBlockedKeywords(['合成 弹幕']);
    expect(controller.items, isEmpty);
    expect(controller.dataRevision, greaterThan(revision));
    controller.setBlockedKeywords([]);
    expect(controller.items, isNotEmpty);
    expect(repository.danmakuCalls.length, calls);
    controller.dispose();
  });
  test(
    'keyword preferences are isolated by user and survive backup restore',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = LocalStore(prefs);
      addTearDown(store.dispose);
      await store.setPlaybackPreferences(
        const PlaybackPreferences(danmakuBlockedKeywords: ['剧透']),
      );
      await store.saveProfile(
        id: 'default',
        name: '管理员',
        sources: [],
        download: true,
        pin: 'abcdef12',
      );
      await store.saveProfile(
        name: '访客',
        sources: ['hongguo'],
        download: false,
      );
      final visitor = store.profiles.firstWhere((profile) => !profile.admin);
      await store.switchProfile(visitor.id);
      expect(store.playbackPreferences.danmakuBlockedKeywords, isEmpty);
      await store.setPlaybackPreferences(
        const PlaybackPreferences(danmakuBlockedKeywords: ['广告']),
      );
      await store.switchProfile('default', pin: 'abcdef12');
      expect(store.playbackPreferences.danmakuBlockedKeywords, ['剧透']);
      final backup = await store.exportBackup();
      await store.setPlaybackPreferences(const PlaybackPreferences());
      await store.importBackup(backup);
      await store.switchProfile('default', pin: 'abcdef12');
      expect(store.playbackPreferences.danmakuBlockedKeywords, ['剧透']);
      await store.switchProfile(visitor.id);
      expect(store.playbackPreferences.danmakuBlockedKeywords, ['广告']);
    },
  );
  for (final size in [const Size(320, 740), const Size(844, 390)]) {
    testWidgets(
      'keyword editor handles clear, cancel and validation at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        List<String>? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    saved = await showDialog<List<String>>(
                      context: context,
                      builder: (_) =>
                          const DanmakuFilterDialog(keywords: ['旧词']),
                    );
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('danmaku-filter-editor'));
        await tester.enterText(input, '剧透，ABC\nａｂｃ');
        await tester.tap(find.byKey(const ValueKey('danmaku-filter-save')));
        await tester.pumpAndSettle();
        expect(saved, ['剧透', 'ABC']);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('清空'));
        await tester.tap(find.byKey(const ValueKey('danmaku-filter-save')));
        await tester.pumpAndSettle();
        expect(saved, isEmpty);
      },
    );
  }
}
