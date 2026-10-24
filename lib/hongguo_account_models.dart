import 'models.dart';

Map<String, dynamic> hongguoWatchPayload(WatchEntry entry, Episode episode) => {
  ...entry.toJson(),
  'updatedAt': entry.updatedAt.toUtc().toIso8601String(),
  'videoId': hongguoEpisodeID(episode),
};

String hongguoEpisodeID(Episode episode) {
  final raw = episode.raw['videoUrl'] as String? ?? '';
  final id = raw.startsWith('hongguo-cenc://')
      ? raw.substring('hongguo-cenc://'.length)
      : episode.id.split(':').last;
  if (!RegExp(r'^[0-9]{1,20}$').hasMatch(id)) {
    throw StateError('此分集暂未返回官方视频身份，进度已保存在本机');
  }
  return id;
}
