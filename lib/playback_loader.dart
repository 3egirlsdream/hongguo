import 'core_bridge.dart';
import 'models.dart';

class PlaybackLoader {
  PlaybackLoader(this.repository);

  static final _owners = Expando<PlaybackLoader>('foreground-playback-owner');

  final AppRepository repository;
  bool get _ownsPlayback => identical(_owners[repository], this);
  int _generation = 0;
  bool _closed = false;

  Future<PlaybackPlan?> load(
    Drama drama,
    Episode episode, {
    int quality = 0,
    bool localOnly = false,
    bool online = false,
  }) => _load(() async {
    if (online) {
      return repository.resolveOnline(drama, episode, quality: quality);
    }
    if (localOnly) {
      final plan = await repository.localPlayback(drama, episode);
      if (plan == null || !plan.local) {
        throw AppFailure('本地视频不可用，请重新下载或选择在线播放。', code: 'local_media');
      }
      return plan;
    }
    return repository.resolve(drama, episode, quality: quality);
  });

  Future<PlaybackPlan?> fallback(PlaybackPlan current) =>
      _load(() => repository.fallback(current));

  Future<PlaybackPlan?> use(PlaybackPlan prepared) =>
      _load(() async => prepared);

  Future<PlaybackPlan?> _load(Future<PlaybackPlan> Function() resolve) async {
    if (_closed) {
      return null;
    }
    final generation = ++_generation;
    _owners[repository] = this;
    try {
      await repository.cancelPlayback();
      if (_closed || generation != _generation || !_ownsPlayback) {
        return null;
      }
      final plan = await resolve();
      if (_closed || generation != _generation || !_ownsPlayback) {
        await repository.release(plan.session);
        return null;
      }
      return plan;
    } catch (_) {
      if (_closed || generation != _generation || !_ownsPlayback) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _generation++;
    if (_ownsPlayback) {
      _owners[repository] = null;
      await repository.cancelPlayback();
    }
  }
}
