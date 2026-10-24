import 'models.dart';

Map<String, dynamic> hongguoWatchPayload(WatchEntry entry, [Episode? episode]) {
  final videoId = episode == null ? entry.videoId : hongguoEpisodeID(episode);
  if (!RegExp(r'^[0-9]{1,20}$').hasMatch(videoId)) {
    throw StateError('此分集暂未返回官方视频身份，进度已保存在本机');
  }
  return {
    ...entry.toJson(),
    'updatedAt': entry.updatedAt.toUtc().toIso8601String(),
    'videoId': videoId,
    if (episode != null) 'episode': episode.number,
  };
}

String hongguoEpisodeID(Episode episode) {
  if (episode.videoId.isEmpty) {
    throw StateError('此分集暂未返回官方视频身份，进度已保存在本机');
  }
  return episode.videoId;
}
