import 'dart:async';

import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'player_fixtures.dart';
import 'player_redesign_test.dart' show SeriesRepository, season;

class SwitchingRepository extends SeriesRepository {
  Completer<PlaybackPlan>? next;
  int nextRequests = 0;
  int interrupted = 0;

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    int quality = 0,
  }) {
    if (drama.id != 'hongguo:season-3') {
      return super.resolve(drama, episode, quality: quality);
    }
    nextRequests++;
    next = Completer<PlaybackPlan>();
    return next!.future;
  }

  @override
  Future<void> cancelPlayback() async {
    if (next != null && !next!.isCompleted) {
      interrupted++;
      next!.completeError(AppFailure('new season was cancelled'));
    }
  }
}

void main() {
  testWidgets(
    'next season first episode survives disposal of the outgoing route',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final store = testStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      final repository = SwitchingRepository()..seasons = [season(3)];
      final players = <ScriptedPlayer>[];
      final original = await repository.detail(FixtureRepository.free);
      Future<void> tick() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            detail: DramaDetail(
              original.drama,
              original.episodes,
              currentSeason: 2,
              seasons: repository.seasons,
            ),
            initialIndex: 1,
            repository: repository,
            store: store,
            playerFactory: () {
              final player = ScriptedPlayer();
              players.add(player);
              return Player(platformPlayer: player);
            },
            videoBuilder: (_) => const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tick();
      expect(players.single.opened, hasLength(1));
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('footer-hongguo:season-3')),
          matching: find.byType(FilledButton),
        ),
      );
      await tick();
      expect(players, hasLength(2));
      expect(players.first.disposed, isTrue);
      expect(repository.interrupted, 0);
      expect(repository.nextRequests, 1);
      repository.next!.complete(
        const PlaybackPlan(
          url: 'https://media.test/working-next-season.mp4',
          session: 'next-season',
        ),
      );
      await tick();
      expect(players.last.opened, hasLength(1));
      expect(players.last.state.playing, isTrue);
      expect(find.text('重试'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tick();
    },
  );
}
