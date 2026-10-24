import 'dart:async';

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

class OfficialHistoryScheduler {
  OfficialHistoryScheduler(this.synchronize);
  final Future<void> Function() synchronize;
  Timer? _periodic, _timer;
  bool _enabled = false, _running = false, _pending = false, _urgent = false;

  void start() {
    stop();
    _enabled = true;
    _periodic = Timer.periodic(
      const Duration(seconds: 90),
      (_) => request(immediate: true),
    );
    request(immediate: true);
  }

  void stop() {
    _enabled = false;
    _periodic?.cancel();
    _timer?.cancel();
    _periodic = _timer = null;
    _pending = _urgent = false;
  }

  void request({bool immediate = false}) {
    if (!_enabled) return;
    _pending = true;
    _urgent = _urgent || immediate;
    if (_running || (_timer?.isActive == true && !immediate)) return;
    _timer?.cancel();
    _timer = Timer(_urgent ? Duration.zero : const Duration(seconds: 15), _run);
  }

  Future<void> _run() async {
    _timer = null;
    if (!_enabled || _running) return;
    _pending = _urgent = false;
    _running = true;
    try {
      await synchronize();
    } catch (_) {
      _pending = true;
    } finally {
      _running = false;
      if (_enabled && _pending) request(immediate: _urgent);
    }
  }
}
