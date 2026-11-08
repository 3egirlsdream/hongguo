import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

enum WorkLane { interactive, background, control }

class WorkCancelled implements Exception {
  const WorkCancelled();
  @override
  String toString() => '操作已取消';
}

class BackgroundWorkFailure implements Exception {
  const BackgroundWorkFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackgroundExecutor {
  BackgroundExecutor({
    int interactiveWorkers = 2,
    int backgroundWorkers = 2,
    this.maxPending = 64,
  }) : _lanes = {
         WorkLane.interactive: _Lane(interactiveWorkers),
         WorkLane.background: _Lane(backgroundWorkers),
         WorkLane.control: _Lane(1),
       } {
    if (interactiveWorkers < 1 || backgroundWorkers < 1 || maxPending < 1) {
      throw ArgumentError('后台任务配置无效');
    }
  }

  static final shared = BackgroundExecutor();
  final int maxPending;
  final Map<WorkLane, _Lane> _lanes;
  bool _closed = false;
  int workersStarted = 0;
  int tasksCompleted = 0;
  int tasksCancelled = 0;
  int get pending => _lanes.values.fold(0, (n, lane) => n + lane.queue.length);
  int get running => _lanes.values.fold(0, (n, lane) => n + lane.busy.length);

  Future<R> run<M, R>(
    R Function(M) operation,
    M message, {
    WorkLane lane = WorkLane.interactive,
    String? scope,
    int sequence = 0,
  }) {
    if (_closed) return Future.error(const WorkCancelled());
    if (scope != null && sequence > 0) {
      cancelQueued(scope, through: sequence - 1);
    }
    final target = _lanes[lane]!;
    if (target.queue.length >= maxPending) {
      return Future.error(const BackgroundWorkFailure('后台任务较多，请稍后重试'));
    }
    final task = _Work(operation, message, scope, sequence);
    target.queue.add(task);
    _dispatch(target, lane);
    return task.result.future.then((value) => value as R);
  }

  int cancelQueued(String scope, {int? through}) {
    var count = 0;
    for (final lane in _lanes.values) {
      lane.queue.removeWhere((task) {
        if (task.scope != scope || through != null && task.sequence > through) {
          return false;
        }
        task.result.completeError(const WorkCancelled());
        count++;
        return true;
      });
    }
    tasksCancelled += count;
    return count;
  }

  void _dispatch(_Lane lane, WorkLane name) {
    if (_closed) return;
    while (lane.queue.isNotEmpty) {
      _Worker? worker;
      for (final candidate in lane.workers) {
        if (!lane.busy.contains(candidate)) {
          worker = candidate;
          break;
        }
      }
      if (worker == null) {
        if (lane.workers.length >= lane.limit) return;
        worker = _Worker('guo-${name.name}-${++workersStarted}');
        lane.workers.add(worker);
      }
      final selected = worker;
      final task = lane.queue.removeFirst();
      lane.busy.add(selected);
      unawaited(() async {
        try {
          final value = await selected.run(task);
          if (!task.result.isCompleted) task.result.complete(value);
          tasksCompleted++;
        } catch (error, stack) {
          if (!task.result.isCompleted) task.result.completeError(error, stack);
          if (selected.failed) {
            lane.workers.remove(selected);
            selected.stop();
          }
        } finally {
          lane.busy.remove(selected);
          _dispatch(lane, name);
        }
      }());
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final lane in _lanes.values) {
      for (final task in lane.queue) {
        task.result.completeError(const WorkCancelled());
      }
      lane.queue.clear();
    }
    final workers = _lanes.values.expand((lane) => lane.workers).toList();
    await Future.wait(workers.map((worker) => worker.finish()));
    for (final worker in workers) {
      worker.stop();
    }
  }
}

class _Lane {
  _Lane(this.limit);
  final int limit;
  final queue = Queue<_Work>();
  final workers = <_Worker>[];
  final busy = <_Worker>{};
}

class _Work {
  _Work(this.operation, this.message, this.scope, this.sequence);
  final Function operation;
  final Object? message;
  final String? scope;
  final int sequence;
  final result = Completer<Object?>();
}

class _Worker {
  _Worker(String name) {
    _receive.listen((message) {
      if (message is SendPort) {
        _ready.complete(message);
      } else if (message is List && message.length == 3) {
        final current = _current;
        _current = null;
        if (message[0] == true) {
          current?.complete(message[1]);
        } else {
          current?.completeError(
            BackgroundWorkFailure(message[1] as String),
            StackTrace.fromString(message[2] as String),
          );
        }
      } else {
        failed = true;
        final error = BackgroundWorkFailure('后台线程已退出：$message');
        if (!_ready.isCompleted) _ready.completeError(error);
        _current?.completeError(error);
        _current = null;
      }
    });
    unawaited(
      Isolate.spawn(
        _workerMain,
        _receive.sendPort,
        debugName: name,
        onError: _receive.sendPort,
        onExit: _receive.sendPort,
        errorsAreFatal: true,
      ).then<void>(
        (isolate) {
          _isolate = isolate;
        },
        onError: (Object error, StackTrace stack) {
          failed = true;
          if (!_ready.isCompleted) _ready.completeError(error, stack);
        },
      ),
    );
  }
  final _receive = ReceivePort();
  final _ready = Completer<SendPort>();
  Completer<Object?>? _current;
  Isolate? _isolate;
  bool failed = false;

  Future<Object?> run(_Work task) async {
    final port = await _ready.future;
    final result = Completer<Object?>();
    _current = result;
    try {
      port.send([task.operation, task.message]);
    } catch (_) {
      _current = null;
      rethrow;
    }
    return result.future;
  }

  Future<void> finish() async {
    try {
      await _ready.future;
      await _current?.future;
    } catch (_) {}
  }

  void stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _receive.close();
  }
}

void _workerMain(SendPort parent) {
  final inbox = ReceivePort();
  parent.send(inbox.sendPort);
  inbox.listen((dynamic message) {
    try {
      final dynamic operation = message[0];
      final Object? result = operation(message[1]);
      parent.send([true, result, '']);
    } catch (error, stack) {
      parent.send([false, error.toString(), stack.toString()]);
    }
  });
}
