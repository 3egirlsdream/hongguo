import 'dart:async';

import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/hongguo_account_screen.dart';
import 'package:duanju_app/saved_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

class CollectionRead {
  CollectionRead(this.command, this.input, this.owner);
  final String command, owner;
  final Map<String, dynamic> input;
  final done = Completer<Map<String, dynamic>>();
  bool cancelled = false;
  void complete(
    String title, {
    bool more = false,
    int offset = 20,
    String cursor = 'next',
  }) => done.complete({
    'items': title.isEmpty
        ? []
        : [
            {
              'id': title,
              'reserved': true,
              'upcoming': input['mode'] != 'online',
              'drama': {
                'id': 'hongguo:$title',
                'source': 'hongguo',
                'sourceId': title,
                'title': title,
                'episodes': 80,
              },
            },
          ],
    'hasMore': more,
    'offset': offset,
    'cursor': cursor,
  });
}

class CollectionRepository extends FixtureRepository {
  String uid = '7000000000000000001';
  bool logged = true;
  final reads = <CollectionRead>[];
  @override
  bool get supportsOfficialAccount => true;
  Map<String, dynamic> get status => {
    'loggedIn': logged,
    'phase': logged ? 'loggedIn' : 'idle',
    'profile': logged ? {'uid': uid} : null,
  };
  @override
  Future<Map<String, dynamic>> hongguoAccount(
    String command, [
    Map<String, dynamic> input = const {},
  ]) async => command == 'status' ? status : {'items': []};
  @override
  Future<Map<String, dynamic>> readAccountCollection(
    String command,
    Map<String, dynamic> input, {
    required String owner,
  }) {
    final read = CollectionRead(command, Map.of(input), owner);
    reads.add(read);
    return read.done.future;
  }

  @override
  Future<void> cancelAccountCollection(String owner) async {
    for (final r in reads) {
      if (r.owner == owner && !r.done.isCompleted) r.cancelled = true;
    }
  }

  void changeAccount(String next, {bool signedIn = true}) {
    uid = next;
    logged = signedIn;
    accountStatus.value = status;
  }
}

void main() {
  Future<void> tick(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<CollectionRepository> mount(WidgetTester t) async {
    t.view.physicalSize = const Size(440, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store = testStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    final repo = CollectionRepository();
    await t.pumpWidget(
      MaterialApp(
        home: HongguoAccountScreen(
          repository: repo,
          store: store,
          collections: true,
          initialTab: 2,
        ),
      ),
    );
    await tick(t);
    expect(repo.reads, hasLength(1));
    return repo;
  }

  Future<void> tab(WidgetTester t, String name) async {
    await t.tap(find.text(name));
    await tick(t);
  }

  Future<void> close(WidgetTester t, CollectionRepository repo) async {
    await t.pumpWidget(const SizedBox());
    for (final r in repo.reads) {
      if (!r.done.isCompleted) r.complete('');
    }
    await tick(t);
    expect(t.takeException(), isNull);
  }

  SavedLibrary library(WidgetTester t) =>
      t.widget<SavedLibrary>(find.byType(SavedLibrary));

  testWidgets(
    'new tab starts immediately and obsolete results cannot hide its loading state',
    (t) async {
      final repo = await mount(t);
      await tab(t, '上新预约');
      expect(repo.reads, hasLength(2));
      expect(repo.reads.first.cancelled, isTrue);
      repo.reads.first.complete('迟到旧预约');
      await tick(t);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      repo.reads.last.complete('当前上新');
      await tick(t);
      expect(find.text('当前上新'), findsOneWidget);
      expect(find.text('迟到旧预约'), findsNothing);
      await close(t, repo);
    },
  );
  testWidgets(
    'first load and API failure do not claim the reservation list is empty',
    (t) async {
      final repo = await mount(t);
      expect(find.text('正在加载预约'), findsOneWidget);
      expect(find.text('暂无预约记录'), findsNothing);
      repo.reads.last.done.completeError(AppFailure('合成请求失败'));
      await tick(t);
      expect(find.text('暂时无法加载'), findsOneWidget);
      expect(find.text('暂无预约记录'), findsNothing);
      final refresh = t
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tick(t);
      repo.reads.last.complete('恢复预约');
      await tick(t);
      await refresh;
      expect(find.text('恢复预约'), findsOneWidget);
      await close(t, repo);
    },
  );

  testWidgets(
    'round trip starts replacement read instead of remaining falsely empty',
    (t) async {
      final repo = await mount(t);
      await tab(t, '历史');
      await tab(t, '预约');
      expect(repo.reads.map((r) => r.command), [
        'reservations',
        'history',
        'reservations',
      ]);
      repo.reads[0].complete('旧结果');
      repo.reads[1].complete('');
      await tick(t);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      repo.reads[2].complete('新预约');
      await tick(t);
      expect(find.text('新预约'), findsOneWidget);
      expect(find.text('暂无预约记录'), findsNothing);
      await close(t, repo);
    },
  );
  testWidgets(
    'fresh cached pages restore items and pagination without another first page',
    (t) async {
      final repo = await mount(t);
      repo.reads.last.complete('第一页', more: true, cursor: 'first-session');
      await tick(t);
      await tab(t, '上新预约');
      repo.reads.last.complete('上新');
      await tick(t);
      await tab(t, '预约');
      expect(repo.reads, hasLength(2));
      expect(find.text('第一页'), findsOneWidget);
      expect(library(t).hasMore, isTrue);
      library(t).onLoadMore!();
      await tick(t);
      expect(repo.reads.last.input['offset'], 20);
      expect(repo.reads.last.input['cursor'], 'first-session');
      repo.reads.last.complete(
        '第二页',
        more: true,
        offset: 40,
        cursor: 'second-session',
      );
      await tick(t);
      await tab(t, '上新预约');
      await tab(t, '预约');
      expect(repo.reads, hasLength(3));
      expect(library(t).remoteFavorites.map((d) => d.title), ['第一页', '第二页']);
      library(t).onLoadMore!();
      await tick(t);
      expect(repo.reads.last.input['offset'], 40);
      expect(repo.reads.last.input['cursor'], 'second-session');
      await close(t, repo);
    },
  );
  testWidgets('online and upcoming filters retain independent cached lists', (
    t,
  ) async {
    final repo = await mount(t);
    repo.reads.last.complete('待上线剧');
    await tick(t);
    library(t).onFilterChanged!('online');
    await tick(t);
    expect(repo.reads.last.input['mode'], 'online');
    repo.reads.last.complete('已上线剧');
    await tick(t);
    library(t).onFilterChanged!('upcoming');
    await tick(t);
    expect(repo.reads, hasLength(2));
    expect(find.text('待上线剧'), findsOneWidget);
    library(t).onFilterChanged!('online');
    await tick(t);
    expect(repo.reads, hasLength(2));
    expect(find.text('已上线剧'), findsOneWidget);
    await close(t, repo);
  });
  testWidgets(
    'refresh failures retain cached rows and next visit retries stale data',
    (t) async {
      final repo = await mount(t);
      repo.reads.last.complete('保留预约');
      await tick(t);
      final refresh = t
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tick(t);
      expect(repo.reads.last.input['offset'], 0);
      expect(repo.reads.last.input['cursor'], '');
      repo.reads.last.done.completeError(AppFailure('合成网络失败'));
      await tick(t);
      await refresh;
      expect(find.text('保留预约'), findsOneWidget);
      await tab(t, '上新预约');
      repo.reads.last.complete('上新');
      await tick(t);
      await tab(t, '预约');
      expect(repo.reads, hasLength(4));
      expect(find.text('保留预约'), findsOneWidget);
      await close(t, repo);
    },
  );
  testWidgets('account changes clear caches and reject old account replies', (
    t,
  ) async {
    final repo = await mount(t);
    repo.changeAccount('7000000000000000002');
    await tick(t);
    expect(repo.reads, hasLength(2));
    expect(repo.reads.first.cancelled, isTrue);
    repo.reads.first.complete('旧账号');
    repo.reads.last.complete('新账号');
    await tick(t);
    expect(find.text('旧账号'), findsNothing);
    expect(find.text('新账号'), findsOneWidget);
    repo.changeAccount('', signedIn: false);
    await tick(t);
    repo.changeAccount('7000000000000000001');
    await tick(t);
    expect(repo.reads, hasLength(3));
    expect(find.text('新账号'), findsNothing);
    await close(t, repo);
  });
  testWidgets(
    'confirmed reservation changes invalidate both cached reservation collections',
    (t) async {
      final repo = await mount(t);
      repo.reads.last.complete('预约');
      await tick(t);
      await tab(t, '上新预约');
      repo.reads.last.complete('日历');
      await tick(t);
      repo.accountReservations.value = {'${repo.uid}/123': true};
      await tick(t);
      expect(repo.reads, hasLength(3));
      repo.reads.last.complete('新日历');
      await tick(t);
      await tab(t, '预约');
      expect(repo.reads, hasLength(4));
      await close(t, repo);
    },
  );
}
