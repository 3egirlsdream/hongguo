import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'cover_screen_viewport.dart';

class AppOrientationController extends ChangeNotifier {
  bool _coverWindow = false;
  bool _disposed = false;
  Object? _playbackOwner;
  bool _playbackFullscreen = false;
  double _playbackAspectRatio = 1;
  List<DeviceOrientation> _playbackOrientations = DeviceOrientation.values;
  List<DeviceOrientation>? _appliedOrientations;
  Future<void> _pending = Future<void>.value();

  static List<DeviceOrientation> orientations({
    bool fullscreen = false,
    double aspectRatio = 1,
  }) {
    if (fullscreen && aspectRatio >= 1) {
      return const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ];
    }
    if (fullscreen) {
      return const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ];
    }
    return DeviceOrientation.values;
  }

  Future<void> setPlayback(
    Object owner, {
    required bool fullscreen,
    required double aspectRatio,
  }) async {
    if (_disposed) return;
    final previousOwner = _playbackOwner;
    final previousOrientations = _playbackOrientations;
    final previousFullscreen = _playbackFullscreen;
    final previousAspectRatio = _playbackAspectRatio;
    _playbackOwner = owner;
    _playbackFullscreen = fullscreen;
    _playbackAspectRatio = aspectRatio;
    _playbackOrientations = orientations(
      fullscreen: fullscreen,
      aspectRatio: aspectRatio,
    );
    _notifyLayout();
    final requested = _playbackOrientations;
    try {
      await _apply();
    } catch (_) {
      if (!_disposed &&
          identical(_playbackOwner, owner) &&
          identical(_playbackOrientations, requested)) {
        _playbackOwner = previousOwner;
        _playbackOrientations = previousOrientations;
        _playbackFullscreen = previousFullscreen;
        _playbackAspectRatio = previousAspectRatio;
        _notifyLayout();
      }
      rethrow;
    }
  }

  Future<void> releasePlayback(Object owner) {
    if (_disposed) return Future<void>.value();
    if (!identical(_playbackOwner, owner)) return Future<void>.value();
    _playbackOwner = null;
    _playbackFullscreen = false;
    _playbackOrientations = DeviceOrientation.values;
    _notifyLayout();
    return _apply();
  }

  Future<void> refresh() => _apply(force: true);

  Future<void> setCoverWindow(bool value) {
    if (_disposed) return Future<void>.value();
    final changed = _coverWindow != value;
    _coverWindow = value;
    if (changed) _notifyLayout();
    return _apply(force: changed);
  }

  int coverQuarterTurns(Size size) {
    if (!_coverWindow || !_playbackFullscreen) return 0;
    final landscape = _playbackAspectRatio >= 1;
    return landscape == (size.width > size.height) ? 0 : 1;
  }

  void _notifyLayout() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _apply({bool force = false}) {
    final next = _pending.catchError((Object _) {}).then((_) async {
      if (_disposed) return;
      final preferred = _coverWindow
          ? DeviceOrientation.values
          : _playbackOrientations;
      if (force || !listEquals(preferred, _appliedOrientations)) {
        await SystemChrome.setPreferredOrientations(preferred);
        if (!_disposed) _appliedOrientations = preferred;
      }
    });
    _pending = next;
    return next;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppOrientationScope extends StatefulWidget {
  const AppOrientationScope({
    super.key,
    this.coverWindow = false,
    required this.child,
  });

  final bool coverWindow;
  final Widget child;

  static AppOrientationController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_OrientationScope>()
      ?.controller;

  @override
  State<AppOrientationScope> createState() => _AppOrientationScopeState();
}

class _AppOrientationScopeState extends State<AppOrientationScope>
    with WidgetsBindingObserver {
  final _controller = AppOrientationController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apply(_controller.setCoverWindow(widget.coverWindow));
    _apply(_controller.refresh());
  }

  @override
  void didUpdateWidget(covariant AppOrientationScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverWindow != widget.coverWindow) {
      _apply(_controller.setCoverWindow(widget.coverWindow));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _apply(_controller.refresh());
  }

  void _apply(Future<void> operation) {
    unawaited(
      operation.catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'app orientation',
          ),
        );
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => CoverScreenViewport(
      quarterTurns: _controller.coverQuarterTurns(MediaQuery.sizeOf(context)),
      child: child!,
    ),
    child: _OrientationScope(controller: _controller, child: widget.child),
  );
}

class _OrientationScope extends InheritedWidget {
  const _OrientationScope({required this.controller, required super.child});

  final AppOrientationController controller;

  @override
  bool updateShouldNotify(_OrientationScope oldWidget) =>
      controller != oldWidget.controller;
}
