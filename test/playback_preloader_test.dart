import 'dart:async';

import 'package:duanju_app/models.dart';
import 'package:duanju_app/playback_preloader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

class PreloadRepository extends FixtureRepository {
  final pending = <Completer<PlaybackPlan?>>[];
  final released = <String>[];
  int cancellations = 0;

  @override
  Future<PlaybackPlan?> preload(
    Drama drama,
    Episode episode, {
    int quality = 0,
    bool online = false,
  }) {
    final result = Completer<PlaybackPlan?>();
    pending.add(result);
    return result.future;
  }

  @override
  Future<void> release(String session) async => released.add(session);

  @override
  Future<void> cancelPreload() async {
    cancellations++;
  }
}

void main() {
  const drama = FixtureRepository.free;
  final second = Episode({'id': '2'}, 2);
  final third = Episode({'id': '3'}, 3);
  const ready = PlaybackPlan(
    url: 'https://synthetic.test/next.mp4',
    session: 'next',
    prefetchedBytes: 8192,
  );

  testWidgets(
    'urgent preparation bypasses debounce and claims an in-flight result',
    (tester) async {
      final repository = PreloadRepository();
      final preloader = PlaybackPreloader(repository);
      preloader.prepare(drama, second);
      await tester.pump(const Duration(milliseconds: 100));
      expect(repository.pending, isEmpty);
      preloader.prepare(drama, second, urgent: true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.pending, hasLength(1));
      final claimed = preloader.claim(
        drama,
        second,
        wait: const Duration(milliseconds: 350),
      );
      repository.pending.single.complete(ready);
      await tester.pump(const Duration(milliseconds: 1));
      expect(await claimed, same(ready));
      expect(repository.released, isEmpty);
      expect(preloader.take(drama, second), isNull);
      preloader.dispose();
    },
  );

  testWidgets('an unrelated claim preserves the newer target', (tester) async {
    final repository = PreloadRepository();
    final preloader = PlaybackPreloader(repository);
    preloader.prepare(drama, third, urgent: true);
    await tester.pump(const Duration(milliseconds: 1));
    repository.pending.single.complete(ready);
    await tester.pump(const Duration(milliseconds: 1));
    expect(await preloader.claim(drama, second), isNull);
    expect(preloader.take(drama, third), same(ready));
    preloader.dispose();
  });

  testWidgets(
    'a cancelled generation releases a late plan without replacing the new one',
    (tester) async {
      final repository = PreloadRepository();
      final preloader = PlaybackPreloader(repository);
      preloader.prepare(drama, second, urgent: true);
      await tester.pump(const Duration(milliseconds: 1));
      preloader.prepare(drama, third, urgent: true);
      await tester.pump(const Duration(milliseconds: 1));
      repository.pending.first.complete(ready);
      repository.pending.last.complete(
        const PlaybackPlan(
          url: 'https://synthetic.test/third.mp4',
          session: 'third',
        ),
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.cancellations, 1);
      expect(repository.released, ['next']);
      expect(preloader.take(drama, third)?.session, 'third');
      preloader.dispose();
    },
  );

  testWidgets('claim timeout bounds the handoff and releases a late result', (
    tester,
  ) async {
    final repository = PreloadRepository();
    final preloader = PlaybackPreloader(repository);
    preloader.prepare(drama, second, urgent: true);
    await tester.pump(const Duration(milliseconds: 1));
    final claimed = preloader.claim(
      drama,
      second,
      wait: const Duration(milliseconds: 350),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(await claimed, isNull);
    repository.pending.single.complete(ready);
    await tester.pump(const Duration(milliseconds: 1));
    expect(repository.released, ['next']);
    preloader.dispose();
  });

  testWidgets(
    'expired credentials are released and transient failures retry after cooldown',
    (tester) async {
      var now = DateTime.utc(2026, 10, 24);
      final repository = PreloadRepository();
      final preloader = PlaybackPreloader(repository, now: () => now);
      preloader.prepare(drama, second, urgent: true);
      await tester.pump(const Duration(milliseconds: 1));
      repository.pending.single.complete(
        PlaybackPlan(
          url: ready.url,
          session: 'expired',
          expiresAt: now.add(const Duration(seconds: 4)).millisecondsSinceEpoch,
        ),
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.released, ['expired']);
      preloader.prepare(drama, second, urgent: true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.pending, hasLength(1));
      now = now.add(const Duration(seconds: 5));
      preloader.prepare(drama, second, urgent: true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.pending, hasLength(2));
      repository.pending.last.complete(ready);
      await tester.pump(const Duration(milliseconds: 1));
      expect(preloader.take(drama, second), same(ready));
      preloader.dispose();
    },
  );
}
