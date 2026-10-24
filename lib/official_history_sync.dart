import 'core_bridge.dart';
import 'diary_service.dart';
import 'hongguo_account_models.dart';
import 'local_store.dart';
import 'models.dart';

Future<int> queueLocalOfficialHistory(
  AppRepository repository,
  LocalStore store,
  String uid, {
  required bool Function() isCurrent,
}) async {
  final cached = await repository.hongguoAccount('history', {'uid': uid});
  if (!isCurrent()) return 0;
  final saved = <String, WatchEntry>{
    for (final row in cached['items'] as List? ?? [])
      (row['drama'] as Map)['id'] as String: WatchEntry.fromJson(
        Map<String, dynamic>.from(row as Map),
      ),
  };
  final local = store.history.toList();
  var failed = 0;
  for (final row in local) {
    if (!isCurrent()) return failed;
    if (row.drama.source != 'hongguo' || row.position < .1) continue;
    final previous = saved[row.drama.id];
    if (previous != null && !row.updatedAt.isAfter(previous.updatedAt)) {
      continue;
    }
    try {
      Episode? episode;
      if (!RegExp(r'^[0-9]{1,20}$').hasMatch(row.videoId)) {
        final detail = await repository.detail(row.drama);
        if (!isCurrent()) return failed;
        episode = detail.episodes.where(row.matchesEpisode).firstOrNull;
        if (episode == null) throw AppFailure('分集信息暂不可用');
      }
      await repository.hongguoAccount('queueProgress', {
        'uid': uid,
        'watch': hongguoWatchPayload(row, episode),
      });
    } catch (error) {
      failed++;
      DiaryService.add('[Progress] 本机历史暂未加入官方队列，将自动重试：$error');
    }
  }
  return failed;
}
