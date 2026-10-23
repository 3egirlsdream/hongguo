import 'dart:async';

import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'local_media_screen.dart';
import 'local_store.dart';
import 'media_library.dart';
import 'models.dart';
import 'playback_continuity.dart';
import 'player_screen.dart';
import 'widgets.dart';

class PlaybackRestoreScreen extends StatefulWidget {
  const PlaybackRestoreScreen({
    super.key,
    required this.snapshot,
    required this.repository,
    required this.store,
  });

  final PlaybackSnapshot snapshot;
  final AppRepository repository;
  final LocalStore store;

  @override
  State<PlaybackRestoreScreen> createState() => _PlaybackRestoreScreenState();
}

class _PlaybackRestoreScreenState extends State<PlaybackRestoreScreen> {
  Object? _error;
  late final int _epoch;

  @override
  void initState() {
    super.initState();
    _epoch = widget.store.profileEpoch;
    _restore();
  }

  Future<void> _restore() async {
    setState(() => _error = null);
    final snapshot = widget.snapshot;
    try {
      if (widget.store.locked ||
          widget.store.profileEpoch != _epoch ||
          widget.store.profile.id != snapshot.profile ||
          !widget.store.allowsSource(snapshot.drama.source)) {
        throw StateError('当前用户已变更或无权播放');
      }
      var repository = widget.repository;
      late DramaDetail detail;
      if (snapshot.mediaId != null) {
        final library = MediaLibrary.current;
        if (library == null) throw StateError('本地媒体库尚未就绪');
        await library.reload();
        final item = library.items
            .where((item) => item.id == snapshot.mediaId)
            .firstOrNull;
        if (item == null) throw StateError('本地视频已不存在');
        repository = LocalFileRepository(
          repository,
          widget.store,
          item,
          library.fileFor(item),
        );
        detail = DramaDetail(item.drama, [
          Episode({
            'id': item.id,
            'title': item.merged ? '合并视频' : '第 ${snapshot.episodeNumber} 集',
            'currentEpisode': snapshot.episodeNumber,
          }, 1),
        ]);
      } else {
        detail = await repository.detail(snapshot.drama);
      }
      var index = detail.episodes.indexWhere(
        (episode) => episode.id == snapshot.episodeId,
      );
      if (index < 0) {
        index = detail.episodes.indexWhere(
          (episode) => episode.number == snapshot.episodeNumber,
        );
      }
      if (index < 0) throw StateError('原播放集数暂时不可用，请返回重新选集');
      if (!mounted) return;
      if (widget.store.locked ||
          widget.store.profileEpoch != _epoch ||
          widget.store.profile.id != snapshot.profile ||
          !widget.store.allowsSource(detail.drama.source)) {
        throw StateError('当前用户已变更或无权播放');
      }
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(
            detail: detail,
            initialIndex: index,
            initialPosition: snapshot.position,
            initialPlayWhenReady: snapshot.playing,
            localOnly: snapshot.localOnly,
            allowOnlineFallback: snapshot.allowOnlineFallback,
            mediaId: snapshot.mediaId,
            repository: repository,
            store: widget.store,
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    unawaited(PlaybackContinuity.discardRestore());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('恢复播放')),
    body: SafeArea(
      child: _error == null
          ? const Center(child: CircularProgressIndicator())
          : StatusPanel(
              title: '暂时无法恢复播放',
              message: _error.toString(),
              onRetry: _restore,
            ),
    ),
  );
}
