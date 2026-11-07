import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/player_season_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

class ReservationRepository extends FixtureRepository {
  final reservationRequests = <String>[];
  bool reservationFailure = false;
  @override
  bool get supportsOfficialAccount => true;
  @override
  Future<Map<String, dynamic>> hongguoAccount(
    String command, [
    Map<String, dynamic> input = const {},
  ]) async {
    reservationRequests.add(command);
    if (reservationFailure) throw AppFailure('预约失败');
    return {'confirmed': true, 'reserved': input['reserved']};
  }
}

void main() {
  testWidgets(
    'reserve and cancel inline without list scan; failure keeps state',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = testStore(await SharedPreferences.getInstance());
      final repository = ReservationRepository();
      repository.accountStatus.value = {
        'profile': {'uid': '7000000000000000001'},
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerSeasonActions(
              season: const DramaSeason(
                drama: Drama(
                  id: 'hongguo:7000000000000000002',
                  sourceId: '7000000000000000002',
                  source: 'hongguo',
                  title: '合成新季',
                ),
                number: 2,
                playable: false,
                reservable: true,
                reserved: false,
              ),
              repository: repository,
              store: store,
              onPlay: () async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('预约'));
      await tester.pump();
      expect(find.text('取消预约'), findsOneWidget);
      expect(repository.reservationRequests, ['reserve']);
      repository.reservationFailure = true;
      await tester.tap(find.text('取消预约'));
      await tester.pump();
      expect(find.text('取消预约'), findsOneWidget);
      repository.reservationFailure = false;
      await tester.tap(find.text('取消预约'));
      await tester.pump();
      expect(find.text('预约'), findsOneWidget);
      expect(repository.reservationRequests, ['reserve', 'reserve', 'reserve']);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
