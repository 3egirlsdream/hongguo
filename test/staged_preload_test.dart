import 'dart:async';

import 'package:duanju_app/models.dart';
import 'package:duanju_app/playback_preloader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'playback_preloader_test.dart' show PreloadRepository;

class StagedRepository extends PreloadRepository {
  final warm = <Completer<int>>[];
  int warmCancellations = 0;
  @override
  bool get supportsStagedPreload => true;
  @override
  Future<int> warmPreload(PlaybackPlan plan) {
    final pending = Completer<int>();
    warm.add(pending);
    return pending.future;
  }

  @override
  Future<void> cancelPreloadWarm() async => warmCancellations++;
}

void main() {
  final episode = Episode({'id': '2'}, 2);
  const plan = PlaybackPlan(url: 'https://synthetic.test/2', session: 'next');
  testWidgets(
    'resolved address can be claimed while media warming is in flight',
    (tester) async {
      final repo = StagedRepository();
      final preloader = PlaybackPreloader(repo);
      preloader.prepare(
        FixtureRepository.free,
        episode,
        urgent: true,
        warm: false,
      );
      await tester.pump(const Duration(milliseconds: 1));
      repo.pending.single.complete(plan);
      await tester.pump(const Duration(milliseconds: 1));
      expect(repo.warm, isEmpty);
      preloader.prepare(FixtureRepository.free, episode, warm: true);
      expect(repo.warm, hasLength(1));
      final claimed = await preloader.claim(FixtureRepository.free, episode);
      expect(claimed?.session, 'next');
      expect(repo.warmCancellations, 1);
      repo.warm.single.complete(1000);
      await tester.pump(const Duration(milliseconds: 1));
      expect(preloader.take(FixtureRepository.free, episode), isNull);
      expect(repo.released, isEmpty);
      preloader.dispose();
    },
  );
  testWidgets('completed warm bytes survive claim without changing session', (
    tester,
  ) async {
    final repo = StagedRepository();
    final preloader = PlaybackPreloader(repo);
    preloader.prepare(FixtureRepository.free, episode, urgent: true);
    await tester.pump(const Duration(milliseconds: 1));
    repo.pending.single.complete(plan);
    await tester.pump(const Duration(milliseconds: 1));
    repo.warm.single.complete(4096);
    await tester.pump(const Duration(milliseconds: 1));
    final result = await preloader.claim(FixtureRepository.free, episode);
    expect(result?.session, 'next');
    expect(result?.prefetchedBytes, 4096);
    preloader.dispose();
  });
}
