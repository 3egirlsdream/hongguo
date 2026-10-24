import 'dart:async';

import 'package:duanju_app/catalog_browser.dart';
import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/main.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/ranking_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

class CategoryRepository extends FixtureRepository {
  final categoryRequests = <String>[];
  Completer<CatalogPage>? pendingComic;
  bool failLegacy = false;
  bool paginate = false;
  final rankRequests = <String>[];

  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async =>
      category.isEmpty
      ? cachedPages[source] ?? CatalogPage([])
      : CatalogPage([]);

  @override
  Future<List<CatalogCategory>> categories(
    String source, {
    bool force = false,
  }) async => switch (source) {
    'hongguo' => const [
      CatalogCategory.all,
      CatalogCategory('short_play', '真人剧'),
      CatalogCategory('comic_series', '漫剧'),
      CatalogCategory('ai_series', 'AI 剧'),
    ],
    'huangguo-video' => const [CatalogCategory.all, CatalogCategory('2', '短片')],
    'huangguoai' => const [
      CatalogCategory.all,
      CatalogCategory('ai-duanju', 'AI 短剧'),
      CatalogCategory('ai-manju', 'AI 漫剧'),
    ],
    'cloudfront' => const [
      CatalogCategory.all,
      CatalogCategory('old-short', 'AI成人短剧'),
    ],
    _ => const [CatalogCategory.all],
  };

  @override
  Future<CatalogPage> catalog(
    String source, {
    int page = 1,
    String query = '',
    String category = '',
    bool force = false,
  }) async {
    categoryRequests.add('$source|$category|$page');
    if (source == 'cloudfront' && failLegacy) throw AppFailure('合成入口失败');
    if (category == 'ai-manju' && pendingComic != null) {
      return pendingComic!.future;
    }
    return CatalogPage(
      [
        Drama(
          id: '$source:$category:$page',
          source: source,
          title: '$source · ${category.isEmpty ? '全部' : category}',
          category: source == 'hongguo' ? '异能' : '',
        ),
      ],
      page: page,
      hasMore: paginate && source == 'huangguo-video' && page == 1,
    );
  }

  @override
  Future<List<RankingBoard>> rankingBoards() async => const [
    RankingBoard(id: 'hongguo-hot', source: 'hongguo', name: '总热播榜'),
    RankingBoard(id: 'hongguo-real', source: 'hongguo', name: '真人剧榜'),
  ];

  @override
  Future<RankingPage> rankings(
    String board, {
    int page = 1,
    bool force = false,
  }) async {
    rankRequests.add('$board|$page|$force');
    return RankingPage(
      items: [
        RankingItem(
          (page - 1) * 20 + 1,
          Drama(
            id: 'hongguo:rank:$board:$page',
            source: 'hongguo',
            title: '合成榜单第$page页',
          ),
        ),
      ],
      page: page,
      hasMore: page == 1,
    );
  }
}

void main() {
  Future<LocalStore> mount(
    WidgetTester tester,
    CategoryRepository repository, {
    String source = 'hongguo',
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    await store.setSource(source);
    await tester.pumpWidget(DuanjuApp(repository: repository, store: store));
    await tester.pumpAndSettle();
    return store;
  }

  test(
    'remote content types never hide fine categories from cached pages',
    () async {
      final repository = CategoryRepository();
      repository.cachedPages['hongguo'] = CatalogPage(const [
        Drama(
          id: 'hongguo:old1',
          source: 'hongguo',
          title: '缓存剧甲',
          category: '都市',
        ),
        Drama(
          id: 'hongguo:old2',
          source: 'hongguo',
          title: '缓存剧乙',
          category: '成长',
        ),
      ], page: 7);
      final browser = CatalogBrowser(repository);
      await browser.loadCategories();
      await browser.load(category: 'category:漫剧');
      expect(
        browser.categories().map((category) => category.name),
        containsAll(['真人剧', '漫剧', 'AI 剧', '都市', '成长', '异能']),
      );
      final local = await browser.load(category: 'local:都市');
      expect(local.items.map((drama) => drama.id), contains('hongguo:old1'));
    },
  );

  testWidgets(
    'rankings are separate from categories and preserve upstream rank numbers',
    (tester) async {
      final repository = CategoryRepository();
      await mount(tester, repository);
      await tester.tap(find.byKey(const ValueKey('bottom-nav-1')));
      await tester.pumpAndSettle();
      expect(repository.rankRequests, ['hongguo-hot|1|false']);
      expect(find.text('总热播榜'), findsOneWidget);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('rank-21-hongguo:rank:hongguo-hot:2')),
        findsOneWidget,
      );
      await tester.tap(find.text('真人剧榜'));
      await tester.pumpAndSettle();
      expect(repository.rankRequests.last, 'hongguo-real|1|false');
      expect(
        find.byKey(const ValueKey('rank-21-hongguo:rank:hongguo-hot:2')),
        findsNothing,
      );
      expect(repository.categoryRequests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
