import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/follow_state.dart';
import 'package:duanju_app/hongguo_account_models.dart';
import 'package:duanju_app/hongguo_account_screen.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/my_screen.dart';
import 'package:duanju_app/official_history_sync.dart';
import 'package:duanju_app/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

class _AccountRepository extends FixtureRepository {
  final calls = <(String, Map<String, dynamic>)>[];
  final details = <String>[];
  var pending = 2;
  var lastSync = '';
  var failSync = false;
  var automaticRequests = 0;
  var name = '合成账号';
  var avatar = '';
  var publicId = '';
  final historyCache = <Map<String, dynamic>>[];
  @override
  void requestOfficialSync() => automaticRequests++;
  @override
  bool get supportsOfficialAccount => true;
  Map<String, dynamic> get status => {
    'loggedIn': true,
    'phase': 'loggedIn',
    'profile': {
      'uid': '7000000000000000001',
      'name': name,
      'avatarUrl': avatar,
      if (publicId.isNotEmpty) 'publicId': publicId,
    },
    'pending': pending,
    'lastSync': lastSync,
  };
  @override
  Future<Map<String, dynamic>> hongguoAccount(
    String command, [
    Map<String, dynamic> input = const {},
  ]) async {
    calls.add((command, input));
    if (command == 'history') return {'items': historyCache};
    if (command == 'favorites') return {'items': []};
    if (command == 'queueProgress') {
      historyCache.add(Map<String, dynamic>.from(input['watch'] as Map));
    }
    if (command == 'sync') {
      pending = failSync ? 1 : 0;
      if (failSync) throw AppFailure('合成：一条上传未获确认');
      lastSync = '2026-10-24T12:00:00Z';
    }
    return status;
  }

  @override
  Future<DramaDetail> detail(Drama drama) async {
    details.add(drama.id);
    throw AppFailure('合成详情不可用');
  }
}

void main() {
  Future<LocalStore> create() async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    return store;
  }

  WatchEntry watch(String id, {String videoId = '', int episode = 1}) =>
      WatchEntry(
        drama: Drama(
          id: 'hongguo:$id',
          source: 'hongguo',
          sourceId: id,
          title: '合成剧$id',
        ),
        videoId: videoId,
        episode: episode,
        position: 12,
        duration: 60,
        updatedAt: DateTime.utc(2026, 10, 24),
      );
  Future<void> account(
    WidgetTester tester,
    LocalStore store,
    _AccountRepository repository,
  ) async {
    tester.view.physicalSize = const Size(440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: HongguoAccountScreen(repository: repository, store: store),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('video identity survives local merges and resolves mixed legacy episode indices', () async {
    final store = await create();
    final entry = watch(
      '7000000000000000002',
      videoId: '7000000000000000003',
      episode: 2,
    );
    await store.saveWatch(entry);
    await store.refreshDrama(entry.drama);
    await store.saveWatch(entry);
    final restored = LocalStore(store.preferences);
    addTearDown(restored.dispose);
    final saved = restored.history.single;
    expect(saved.videoId, entry.videoId);
    expect(hongguoWatchPayload(saved)['videoId'], entry.videoId);
    expect(hongguoWatchPayload(saved)['updatedAt'], endsWith('Z'));
    final episodes = [
      Episode({'id': 'hongguo:7000000000000000003', 'currentEpisode': 1}, 1),
      Episode({'id': 'hongguo:7000000000000000004', 'currentEpisode': 2}, 2),
    ];
    expect(resumeEpisodeIndex(episodes, saved), 0);
    expect(saved.matchesEpisode(episodes.first), isTrue);
    expect(saved.matchesEpisode(episodes.last), isFalse);
    final finished = WatchEntry.fromJson({...saved.toJson(), 'position': 60});
    expect(resumeEpisodeIndex(episodes, finished), 1);
  });

  testWidgets(
    'account history sync is automatic without manual action buttons',
    (tester) async {
      final store = await create();
      final repository = _AccountRepository();
      await account(tester, store, repository);
      expect(repository.automaticRequests, greaterThan(0));
      for (final text in ['获取云端历史', '上传本机历史', '立即同步观看历史']) {
        expect(find.text(text), findsNothing);
      }
      expect(find.textContaining('观看历史全自动同步'), findsOneWidget);
      final before = repository.automaticRequests;
      await tester.pump(const Duration(seconds: 3));
      expect(repository.automaticRequests, before);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('automatic import continues after failures and does not requeue saved progress', () async {
    final store = await create();
    final repository = _AccountRepository();
    await store.saveWatch(watch('7000000000000000002'));
    await store.saveWatch(
      watch('7000000000000000004', videoId: '7000000000000000005'),
    );
    expect(
      await queueLocalOfficialHistory(
        repository,
        store,
        '7000000000000000001',
        isCurrent: () => true,
      ),
      1,
    );
    expect(
      repository.calls.where((call) => call.$1 == 'queueProgress').length,
      1,
    );
    expect(repository.details, ['hongguo:7000000000000000002']);
    await queueLocalOfficialHistory(
      repository,
      store,
      '7000000000000000001',
      isCurrent: () => true,
    );
    expect(
      repository.calls.where((call) => call.$1 == 'queueProgress').length,
      1,
    );
  });

  test('automatic import respects newer account progress and stops on profile change', () async {
    final store = await create();
    final repository = _AccountRepository();
    final entry = watch('7000000000000000004', videoId: '7000000000000000005');
    await store.saveWatch(entry);
    repository.historyCache.add({
      ...entry.toJson(),
      'updatedAt': entry.updatedAt
          .add(const Duration(days: 1))
          .toIso8601String(),
    });
    await queueLocalOfficialHistory(
      repository,
      store,
      '7000000000000000001',
      isCurrent: () => true,
    );
    expect(
      repository.calls.where((call) => call.$1 == 'queueProgress'),
      isEmpty,
    );
    repository.historyCache.clear();
    await queueLocalOfficialHistory(
      repository,
      store,
      '7000000000000000001',
      isCurrent: () => false,
    );
    expect(
      repository.calls.where((call) => call.$1 == 'queueProgress'),
      isEmpty,
    );
  });

  testWidgets(
    'My uses refreshed nickname, avatar and public account id without changing session uid',
    (tester) async {
      final store = await create();
      final repository = _AccountRepository();
      tester.view.physicalSize = const Size(440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyScreen(
              repository: repository,
              store: store,
              onRankings: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      repository.name = '新的合成昵称';
      repository.avatar = 'https://avatar.example.test/profile.png';
      repository.publicId = '7000000000000000009';
      repository.accountStatus.value = repository.status;
      await tester.pumpAndSettle();
      expect(find.text('新的合成昵称'), findsOneWidget);
      expect(find.text('红果号：7000000000000000009'), findsOneWidget);
      expect(
        tester.widget<AccountAvatar>(find.byType(AccountAvatar)).url,
        repository.avatar,
      );
      expect(
        (repository.status['profile'] as Map)['uid'],
        '7000000000000000001',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'My status updates only read historyCache history instead of repeatedly fetching remotely',
    (tester) async {
      final store = await create();
      final repository = _AccountRepository();
      tester.view.physicalSize = const Size(440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyScreen(
              repository: repository,
              store: store,
              onRankings: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = repository.calls
          .where((call) => call.$1 == 'history' && call.$2['refresh'] == true)
          .length;
      repository.lastSync = '2026-10-24T12:00:00Z';
      repository.accountStatus.value = repository.status;
      await tester.pumpAndSettle();
      repository.pending = 1;
      repository.accountStatus.value = repository.status;
      await tester.pumpAndSettle();
      final after = repository.calls
          .where((call) => call.$1 == 'history' && call.$2['refresh'] == true)
          .length;
      expect(after, before);
      expect(
        repository.calls.where(
          (call) => call.$1 == 'history' && call.$2['refresh'] != true,
        ),
        isNotEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
