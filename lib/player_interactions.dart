import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'app_layout.dart';
import 'widgets.dart';

enum SwipeAction { none, volume, brightness, episode, seek }

class GestureHudState {
  const GestureHudState({this.type = SwipeAction.none, this.value = 0.0});
  final SwipeAction type;
  final double value; // 0.0 ~ 1.0
}

class PlayerInteractions extends ChangeNotifier {
  PlayerInteractions({
    required this.player,
    required this.available,
    required this.baseSpeed,
    required this.onTogglePlayback,
    required this.onFullscreen,
    required this.onEpisode,
    this.canEpisode,
    this.onSeek,
  }) {
    _playing = player.stream.playing.listen((playing) {
      if (!playing) cancel();
    });
    AppDevice.getBrightness()
        .then((val) {
          if (!_disposed) {
            _brightness = val;
            notifyListeners();
          }
        })
        .catchError((_) {});
  }

  final Player player;
  final bool Function() available;
  final double Function() baseSpeed;
  final VoidCallback onTogglePlayback;
  final VoidCallback onFullscreen;
  final String Function(int direction) onEpisode;
  final bool Function(int direction)? canEpisode;
  final Future<void> Function(Duration)? onSeek;
  late final StreamSubscription<bool> _playing;
  Timer? _holdTimer;
  Timer? _hintTimer;
  Future<void> _rates = Future<void>.value();
  final Set<int> _pointers = {};
  int? _pointer;
  Offset? _origin;
  Offset? _lastPosition;
  VelocityTracker? _episodeVelocity;
  double _episodeDragOffset = 0;
  bool _episodeDragging = false;
  double _swipeThreshold = 70;
  bool _swipeEnabled = false;
  bool _moved = false;
  bool _held = false;
  bool _boosting = false;
  bool _keyboardHold = false;
  bool _cancelUntilRelease = false;
  bool _disposed = false;
  double _unmutedVolume = 100;
  String _feedback = '';
  DateTime _ignoreTapUntil = DateTime(2000);
  SwipeAction _swipeAction = SwipeAction.none;
  bool _swipeDecided = false;
  Duration? _seekPreview;
  int _seekOriginMs = 0;
  double _viewWidth = 0;
  GestureHudState _hudState = const GestureHudState();
  double _brightness = 0.5;
  double _initialBrightness = 0.5;
  double _initialVolume = 100;
  double _viewHeight = 0.0;
  double _episodeHeight = 0.0;
  Timer? _hudTimer;

  double get episodeDragOffset => _episodeDragOffset;
  bool get episodeDragging => _episodeDragging;

  void _resetEpisodeDrag() {
    _episodeVelocity = null;
    final changed = _episodeDragging || _episodeDragOffset != 0;
    _episodeDragging = false;
    _episodeDragOffset = 0;
    if (changed) notifyListeners();
  }

  GestureHudState get hudState => _hudState;
  double get brightness => _brightness;
  bool get isBrightnessActive => _hudState.type == SwipeAction.brightness;

  void setBrightnessDirect(double value) {
    if (_disposed) return;
    _brightness = value.clamp(0.01, 1.0);
    AppDevice.setBrightness(_brightness);
    _showHud(SwipeAction.brightness, _brightness);
  }

  void dismissBrightnessHud() {
    _scheduleDismissHud();
  }

  String get feedback => _feedback;
  bool get boosting => _boosting;
  bool get suppressTap =>
      _held ||
      _boosting ||
      _cancelUntilRelease ||
      DateTime.now().isBefore(_ignoreTapUntil);
  Future<void> get pendingRates => _rates;

  void hint(String message, {bool persistent = false}) {
    if (_disposed) return;
    _hintTimer?.cancel();
    if (_feedback != message) {
      _feedback = message;
      notifyListeners();
    }
    if (!persistent && message.isNotEmpty) {
      _hintTimer = Timer(const Duration(milliseconds: 1200), () {
        hint(_boosting ? '3 倍速 · 松开恢复' : '', persistent: true);
      });
    }
  }

  Future<void> applySpeed() => _setRate(baseSpeed());

  Future<void> _setRate(double value) {
    _rates = _rates
        .catchError((Object _) {})
        .then((_) => player.setRate(value));
    unawaited(
      _rates.catchError((Object _) {
        hint('倍速调整失败，请重试');
      }),
    );
    return _rates;
  }

  void _beginHold({bool keyboard = false}) {
    if (!available() || _holdTimer != null || _boosting) return;
    _keyboardHold = keyboard;
    _holdTimer = Timer(const Duration(milliseconds: 350), () {
      _holdTimer = null;
      if (_disposed || !available()) {
        return;
      }
      _held = true;
      if (!player.state.playing || player.state.completed) return;
      _boosting = true;
      unawaited(_setRate(3));
      hint('3 倍速 · 松开恢复', persistent: true);
    });
  }

  void _endHold({bool tap = false, bool silent = false}) {
    final wasKeyboard = _keyboardHold;
    final boosted = _boosting;
    _holdTimer?.cancel();
    _holdTimer = null;
    _keyboardHold = false;
    _boosting = false;
    if (boosted) {
      unawaited(_setRate(baseSpeed()));
      if (!silent) hint('恢复 ${baseSpeed()} 倍速');
    } else if (tap && wasKeyboard) {
      seek(5);
    }
  }

  void cancel() {
    if (_disposed) return;
    if (_pointers.isNotEmpty) {
      _cancelUntilRelease = true;
      _ignoreTapUntil = DateTime.now().add(const Duration(milliseconds: 600));
    }
    _pointer = null;
    _origin = null;
    _lastPosition = null;
    _seekPreview = null;
    _held = false;
    _resetEpisodeDrag();
    _endHold(silent: true);
    if (_hudState.type != SwipeAction.none) _scheduleDismissHud();
    hint('');
  }

  void pointerDown(
    PointerDownEvent event, {
    required bool swipeEnabled,
    double width = 0.0,
    required double height,
    Size? screenSize,
  }) {
    _pointers.add(event.pointer);
    if (_pointers.length != 1 || _cancelUntilRelease) {
      cancel();
      return;
    }
    if (!available() || event.buttons != kPrimaryButton) return;
    _pointer = event.pointer;
    _origin = _lastPosition = event.localPosition;
    _resetEpisodeDrag();
    _swipeEnabled = swipeEnabled && event.kind == PointerDeviceKind.touch;
    final screen = screenSize ?? Size(width, height);
    _episodeHeight = screen.height;
    _swipeThreshold = screen.height * .08;
    _viewHeight = height;
    _viewWidth = width;
    _moved = _held = false;
    _swipeAction = SwipeAction.none;
    _swipeDecided = false;
    _seekOriginMs = player.state.position.inMilliseconds;

    _initialBrightness = _brightness;
    _initialVolume = player.state.volume.clamp(0.0, 100.0);
    if (_swipeEnabled && width > 0 && height > 0) {
      final position = Offset(
        event.localPosition.dx,
        screenSize == null ? event.localPosition.dy : event.position.dy,
      );
      final episodeArea = Rect.fromLTWH(
        width * .3,
        screen.height * .2,
        width * .4,
        screen.height * .6,
      );
      if (position.dx < episodeArea.left) {
        _swipeAction = SwipeAction.volume;
      } else if (position.dx >= episodeArea.right) {
        _swipeAction = SwipeAction.brightness;
      } else if (episodeArea.contains(position)) {
        _swipeAction = SwipeAction.episode;
        _episodeVelocity = VelocityTracker.withKind(event.kind)
          ..addPosition(event.timeStamp, event.localPosition);
      }
      if (_swipeAction == SwipeAction.brightness) {
        AppDevice.getBrightness()
            .then((value) {
              if (!_disposed && _pointer == event.pointer && !_moved) {
                _initialBrightness = _brightness = value;
              }
            })
            .catchError((Object _) {});
      }
    }
    _beginHold();
  }

  void pointerMove(PointerMoveEvent event) {
    if (_pointer != event.pointer || _origin == null) return;
    _lastPosition = event.localPosition;
    _episodeVelocity?.addPosition(event.timeStamp, event.localPosition);
    final diff = event.localPosition - _origin!;
    if (diff.distance > 12) {
      _moved = true;
      _endHold();
    }
    if (!_swipeEnabled || !_moved || _held || _viewHeight <= 0) return;

    if (!_swipeDecided) {
      if (diff.dx.abs() > diff.dy.abs() * 1.5) {
        _swipeAction = player.state.duration > Duration.zero && _viewWidth > 0
            ? SwipeAction.seek
            : SwipeAction.none;
      } else if (diff.dy.abs() <= diff.dx.abs() * 1.5) {
        return;
      }
      _swipeDecided = true;
    }

    if (_swipeAction == SwipeAction.seek) {
      final durationMs = player.state.duration.inMilliseconds;
      final spanMs = durationMs.clamp(0, 120000);
      final target = (_seekOriginMs + (diff.dx / _viewWidth * spanMs).round())
          .clamp(0, durationMs);
      _seekPreview = Duration(milliseconds: target);
      hint('跳转至 ${formatPosition(target / 1000)}', persistent: true);
      return;
    }

    final dy = _origin!.dy - event.localPosition.dy; // 向上滑动为增加，向下滑动为减少
    final deltaRatio = dy / (_viewHeight * 0.6);
    if (_swipeAction == SwipeAction.episode) {
      final direction = diff.dy < 0 ? 1 : -1;
      final canMove = canEpisode?.call(direction) ?? true;
      final offset = (diff.dy * (canMove ? 1 : .22)).clamp(
        -_episodeHeight * .85,
        _episodeHeight * .85,
      );
      if (!_episodeDragging || _episodeDragOffset != offset) {
        _episodeDragging = true;
        _episodeDragOffset = offset;
        notifyListeners();
      }
    }

    if (_swipeAction == SwipeAction.volume) {
      final volume = (_initialVolume + deltaRatio * 100).clamp(0.0, 100.0);
      unawaited(
        player.setVolume(volume).catchError((Object _) {
          hint('音量调整失败，请重试');
        }),
      );
      if (volume > 0) _unmutedVolume = volume;
      _showHud(SwipeAction.volume, volume / 100);
    } else if (_swipeAction == SwipeAction.brightness) {
      _brightness = (_initialBrightness + deltaRatio).clamp(0.01, 1.0);
      AppDevice.setBrightness(_brightness);
      _showHud(SwipeAction.brightness, _brightness);
    }
  }

  void pointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_cancelUntilRelease) {
      _ignoreTapUntil = DateTime.now().add(const Duration(milliseconds: 600));
      if (_pointers.isEmpty) _cancelUntilRelease = false;
      return;
    }
    if (_pointer != event.pointer || _origin == null) return;
    final delta = (_lastPosition ?? event.localPosition) - _origin!;
    _episodeVelocity?.addPosition(event.timeStamp, event.localPosition);
    final velocity =
        _episodeVelocity?.getVelocity().pixelsPerSecond ?? Offset.zero;
    final isVertical = delta.dy.abs() > delta.dx.abs() * 1.5;
    final isFling =
        delta.dy.abs() >= _episodeHeight * .03 &&
        velocity.dy.abs() >= _episodeHeight * .8 &&
        velocity.dy.abs() > velocity.dx.abs() * 1.5 &&
        velocity.dy.sign == delta.dy.sign;
    final switchEpisode =
        _episodeDragging &&
        isVertical &&
        (delta.dy.abs() >= _swipeThreshold || isFling);
    _resetEpisodeDrag();

    final seekPreview = _seekPreview;
    _seekPreview = null;
    if (seekPreview != null && available()) {
      _commitSeek(seekPreview);
      hint('跳转至 ${formatPosition(seekPreview.inMilliseconds / 1000)}');
    } else if (_swipeAction == SwipeAction.episode &&
        _swipeEnabled &&
        !_held &&
        _moved &&
        switchEpisode) {
      if (available()) hint(onEpisode(delta.dy < 0 ? 1 : -1));
    } else if (_swipeAction == SwipeAction.volume ||
        _swipeAction == SwipeAction.brightness) {
      _scheduleDismissHud();
    }

    if (_moved || _held) {
      _ignoreTapUntil = DateTime.now().add(const Duration(milliseconds: 600));
    }
    _pointer = null;
    _origin = null;
    _held = false;
    _endHold();
  }

  void pointerCancel(PointerCancelEvent event) {
    if (!_pointers.remove(event.pointer)) return;
    cancel();
    _ignoreTapUntil = DateTime.now().add(const Duration(milliseconds: 600));
    if (_pointers.isEmpty) _cancelUntilRelease = false;
  }

  void _showHud(SwipeAction action, double value) {
    if (_disposed) return;
    _hudTimer?.cancel();
    _hudState = GestureHudState(type: action, value: value);
    notifyListeners();
  }

  void _scheduleDismissHud() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 1000), () {
      if (_disposed) return;
      _hudState = const GestureHudState();
      notifyListeners();
    });
  }

  void seek(int seconds) {
    if (!available() || player.state.duration <= Duration.zero) return;
    _endHold();
    final target = (player.state.position.inMilliseconds + seconds * 1000)
        .clamp(0, player.state.duration.inMilliseconds);
    _commitSeek(Duration(milliseconds: target));
    hint('${seconds > 0 ? '快进至' : '后退至'} ${formatPosition(target / 1000)}');
  }

  void _commitSeek(Duration target) {
    unawaited(
      (onSeek ?? player.seek)(target).catchError((Object _) {
        hint('跳转失败，请重试');
      }),
    );
  }

  void changeVolume(double delta) {
    if (!available()) return;
    final volume = (player.state.volume + delta).clamp(0.0, 100.0);
    unawaited(player.setVolume(volume));
    if (volume > 0) _unmutedVolume = volume;
    hint(volume == 0 ? '已静音' : '音量 ${volume.round()}%');
  }

  void toggleMute() {
    if (_disposed) return;
    final current = player.state.volume;
    if (current > 0) _unmutedVolume = current;
    final target = current > 0 ? 0.0 : _unmutedVolume;
    unawaited(
      player
          .setVolume(target)
          .then((_) {
            hint(target == 0 ? '已静音' : '音量 ${target.round()}%');
          })
          .catchError((Object _) {
            hint('音量调整失败，请重试');
          }),
    );
  }

  KeyEventResult key(KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      if (key == LogicalKeyboardKey.arrowRight && _keyboardHold) {
        _endHold(tap: available());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final hardware = HardwareKeyboard.instance;
    if (hardware.isAltPressed ||
        hardware.isMetaPressed ||
        hardware.isShiftPressed) {
      cancel();
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.f11 || key == LogicalKeyboardKey.keyF) {
      if (event is KeyDownEvent) {
        cancel();
        onFullscreen();
      }
      return KeyEventResult.handled;
    }
    if (hardware.isControlPressed || !available()) {
      return KeyEventResult.ignored;
    }
    if (key != LogicalKeyboardKey.arrowRight) _endHold();
    if (key == LogicalKeyboardKey.arrowRight) {
      if (event is KeyDownEvent) _beginHold(keyboard: true);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      seek(-5);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      changeVolume(5);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      changeVolume(-5);
    } else if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (event is KeyDownEvent) onTogglePlayback();
    } else if (key == LogicalKeyboardKey.keyM) {
      if (event is KeyDownEvent) toggleMute();
    } else if (key == LogicalKeyboardKey.mediaTrackNext ||
        key == LogicalKeyboardKey.mediaTrackPrevious) {
      if (event is KeyDownEvent) {
        hint(onEpisode(key == LogicalKeyboardKey.mediaTrackNext ? 1 : -1));
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _disposed = true;
    _holdTimer?.cancel();
    _hintTimer?.cancel();
    _hudTimer?.cancel();
    AppDevice.resetBrightness(); // 离开播放器时自动恢复手机/平板系统默认亮度
    if (_boosting) unawaited(_setRate(baseSpeed()));
    _boosting = false;
    _playing.cancel();
    _pointers.clear();
    super.dispose();
  }
}
