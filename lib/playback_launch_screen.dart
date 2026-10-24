import 'dart:async';

import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'follow_state.dart';
import 'local_store.dart';
import 'models.dart';
import 'player_screen.dart';
import 'playback_trace.dart';
import 'widgets.dart';

final _playbackLaunches = Expando<bool>();

Future<void> openPlaybackDirectly(
  BuildContext context, {
  required Drama drama,
  required AppRepository repository,
  required LocalStore store,
  WatchEntry? resumeOverride,
}) async {
  final navigator = Navigator.of(context);
  if (_playbackLaunches[navigator] == true) return;
  _playbackLaunches[navigator] = true;
  final trace = PlaybackTrace('click');
  final profileEpoch = store.profileEpoch;
  try {
    final detail = await trace.measure(
      'detail',
      () => repository.detail(drama),
    );
    if (!context.mounted || profileEpoch != store.profileEpoch) return;
    final mergedDrama = repository.catalogUpdates
        .current(drama)
        .merge(detail.drama);
    final merged = DramaDetail(
      mergedDrama,
      detail.episodes,
      warning: detail.warning,
      seasons: detail.seasons,
      currentSeason: detail.currentSeason,
    );
    repository.catalogUpdates.publish(mergedDrama, retryCover: true);
    unawaited(
      saveUserChange(
        context,
        () => trace.measure(
          'metadata_save',
          () => store.refreshDrama(mergedDrama),
        ),
      ),
    );
    if (!context.mounted || profileEpoch != store.profileEpoch) return;
    if (merged.episodes.isEmpty) {
      throw AppFailure('暂时没有可播放的集数');
    }
    final watched = resumeOverride?.drama.id == mergedDrama.id
        ? resumeOverride
        : store.watched(mergedDrama.id);
    final index = resumeEpisodeIndex(merged.episodes, watched);
    final episode = merged.episodes[index];
    if (episode.vip) {
      final accepted = await trace.measure(
        'vip_confirmation',
        () => showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('这是一集 VIP 内容'),
            content: const Text('部分内容可能仅提供试看或限制播放。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('尝试播放'),
              ),
            ],
          ),
        ),
      );
      if (accepted != true || !context.mounted) return;
    }
    final position =
        watched?.matchesEpisode(episode) == true && watched?.finished == false
        ? watched!.position
        : 0.0;
    if (!context.mounted || profileEpoch != store.profileEpoch) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          detail: merged,
          initialIndex: index,
          initialPosition: position,
          repository: repository,
          store: store,
          trace: trace,
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted || profileEpoch != store.profileEpoch) return;
    repository.catalogUpdates.publish(
      repository.catalogUpdates.current(drama),
      retryCover: true,
    );
    final message = error is AppFailure ? error.message : '暂时无法播放，请重试';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  } finally {
    _playbackLaunches[navigator] = false;
  }
}
