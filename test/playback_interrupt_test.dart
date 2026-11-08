import 'package:duanju_app/models.dart';
import 'package:duanju_app/playback_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'playback_loader_test.dart' show DeferredRepository;

void main() {
  test(
    'switch intent cancels resolution before the next media is prepared',
    () async {
      final repository = DeferredRepository();
      final loader = PlaybackLoader(repository);
      final request = loader.load(
        FixtureRepository.free,
        Episode({'id': '1'}, 1),
      );
      await Future<void>.delayed(Duration.zero);
      await loader.interrupt();
      expect(repository.cancellations, 2);
      repository.pending[1]!.complete(
        const PlaybackPlan(
          url: 'https://synthetic.test/1',
          session: 'obsolete',
        ),
      );
      expect(await request, isNull);
      expect(repository.released, ['obsolete']);
      await loader.close();
    },
  );
}
