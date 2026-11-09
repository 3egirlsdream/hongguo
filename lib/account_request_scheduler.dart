class AccountRequestScheduler {
  Future<void> _pending = Future<void>.value();

  Future<T> run<T>(
    String command,
    Map<String, dynamic> input,
    Future<T> Function() request,
  ) {
    if (const {
          'status',
          'cancel',
          'logout',
          'queueProgress',
          'seasons',
          'reserve',
          'reservations',
          'calendar',
        }.contains(command) ||
        command == 'history' && input['refresh'] != true) {
      return Future.sync(request);
    }
    final pending = _pending.then((_) => request());
    _pending = pending.then<void>(
      (_) {},
      onError: (Object error, StackTrace trace) {},
    );
    return pending;
  }
}
