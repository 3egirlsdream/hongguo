import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core_bridge.dart';
import 'local_store.dart';
import 'models.dart';
import 'source_status.dart';

class LibraryUpdater extends ChangeNotifier {
  LibraryUpdater(this.repository, this.store, {this.onCatalogChanged})
    : _epoch = store.profileEpoch;
  final AppRepository repository;
  final LocalStore store;
  final ValueChanged<String>? onCatalogChanged;
  final int _epoch;
  static const _source = 'hongguo';
  SourceStatus? _status;
  String _error = '', _delivered = '';
  bool _pending = false,
      _stopRequested = false,
      _polling = false,
      _disposed = false;
  int _revision = 0, _ticks = 0;
  Timer? _timer;
  bool get _valid =>
      !_disposed && !store.locked && _epoch == store.profileEpoch;
  SourceStatus? status(String source) => source == _source ? _status : null;
  String error(String source) => source == _source ? _error : '';
  bool busy(String source) =>
      source == _source && (_pending || _status?.running == true);
  void _notify() {
    if (_valid) notifyListeners();
  }

  void startWatching() {
    if (_timer != null || !repository.supportsSourceManagement || !_valid)
      return;
    unawaited(refresh());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      _ticks++;
      if (_status?.running == true || _ticks % 5 == 0) unawaited(refresh());
    });
  }

  void _accept(SourceStatus status, {bool submitted = false}) {
    if (!_valid || status.source != _source) return;
    _status = status;
    _error = '';
    final revision =
        '${status.operation}|${status.startedAt}|${status.finishedAt}|${status.updatedAt}|${status.count}|${status.storageError}';
    if (!status.running &&
        (status.finishedAt != null || submitted) &&
        {
          'update',
          'more',
          'metadata',
          'retrySave',
        }.contains(status.operation) &&
        _delivered != revision) {
      _delivered = revision;
      onCatalogChanged?.call(_source);
    }
  }

  Future<void> refresh() async {
    if (_polling || !_valid || !repository.supportsSourceManagement) return;
    _polling = true;
    final revision = _revision;
    try {
      final status = await repository.sourceStatus(_source);
      if (_valid && revision == _revision) _accept(status);
    } catch (error) {
      if (_valid && revision == _revision) _error = error.toString();
    } finally {
      _polling = false;
      _notify();
    }
  }

  Future<void> update([Iterable<SourceSite>? sources]) async {
    if (!_valid ||
        !repository.supportsSourceManagement ||
        busy(_source) ||
        sources != null && !sources.any((s) => s.id == _source))
      return;
    _stopRequested = false;
    _pending = true;
    _error = '';
    _revision++;
    _notify();
    try {
      final status = await repository.startSourceJob(_source, 'update');
      _accept(status, submitted: true);
      if (_valid && _stopRequested && status.running)
        _accept(await repository.cancelSourceJob(_source));
    } catch (error) {
      if (_valid) _error = error.toString();
    } finally {
      _pending = false;
      _notify();
    }
  }

  Future<void> stop([Iterable<SourceSite>? sources]) async {
    if (!_valid || sources != null && !sources.any((s) => s.id == _source))
      return;
    _stopRequested = true;
    if (_pending || _status?.running != true) return;
    _pending = true;
    _revision++;
    _notify();
    try {
      _accept(await repository.cancelSourceJob(_source));
    } catch (error) {
      if (_valid) _error = error.toString();
    } finally {
      _pending = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
