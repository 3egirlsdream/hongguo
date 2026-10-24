import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'app_layout.dart';
import 'app_orientation.dart';
import 'app_theme.dart';
import 'core_bridge.dart';
import 'diary_service.dart';
import 'danmaku_controller.dart';
import 'danmaku_overlay.dart';
import 'download_picker.dart';
import 'downloads_screen.dart';
import 'drama_list_card.dart';
import 'follow_state.dart';
import 'local_store.dart';
import 'library_account_actions.dart';
import 'hongguo_account_models.dart';
import 'models.dart';
import 'playback_loader.dart';
import 'playback_continuity.dart';
import 'playback_preloader.dart';
import 'playback_recovery.dart';
import 'playback_preferences.dart';
import 'playback_trace.dart';
import 'player_controls.dart';
import 'player_interactions.dart';
import 'player_menu.dart';
import 'player_presentation.dart';
import 'player_season_actions.dart';
import 'widgets.dart';
import 'catalog_management_screen.dart';
import 'lan_controller.dart';
import 'lan_screen.dart';
import 'video_output_size.dart';

Object? _pictureInPictureHandlerOwner;

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.detail,
    required this.initialIndex,
    required this.repository,
    required this.store,
    this.initialPosition = 0,
    this.initialPlayWhenReady = true,
    this.initialFullscreen = false,
    this.localOnly = false,
    this.allowOnlineFallback = true,
    this.mediaId,
    this.playerFactory,
    this.videoBuilder,
    this.handoff,
    this.trace,
  });
  final DramaDetail detail;
  final int initialIndex;
  final double initialPosition;
  final bool initialPlayWhenReady;
  final bool initialFullscreen;
  final bool localOnly;
  final bool allowOnlineFallback;
  final String? mediaId;
  final AppRepository repository;
  final LocalStore store;
  final LanIncomingPlayback? handoff;
  final PlaybackTrace? trace;
  @visibleForTesting
  final Player Function()? playerFactory;
  @visibleForTesting
  final Widget Function(Widget controls)? videoBuilder;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController? _video;
  late final PlaybackLoader _loader;
  late final PlaybackPreloader _preloader;
  late final PlaybackTrace _initialTrace;
  PlaybackTrace? _activeTrace;
  Stopwatch? _mediaOpenClock;
  bool _tracedVideoParameters = false;
  bool _tracedProgress = false;
  bool _preloadEnabled = true;
  bool _fastEpisodeSwitch = false;
  Timer? _switchLoadingTimer;
  late final DanmakuController _danmaku;
  int _seekSequence = 0;
  bool _danmakuEnabled = true;
  late final PlayerInteractions _interactions;
  final _playerFocus = FocusNode(debugLabel: 'player-surface');
  final _videoPaneKey = GlobalKey();
  final _videoSurfaceKey = GlobalKey();
  Timer? _lifecyclePauseTimer;
  bool _pausedForLifecycle = false;
  bool _advanceOnResume = false;
  final _continuityOwner = '${DateTime.now().microsecondsSinceEpoch}';
  int _pictureInPictureRevision = 0;
  final _menuRevision = ValueNotifier<int>(0);
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final _recovery = PlaybackRecovery();
  Object _lanIdentity = Object();
  bool _handoffOwned = true;
  double? _lanFirstPosition;
  String? _savedProgressKey;
  final _health = PlaybackHealth();
  Timer? _saveTimer;
  Timer? _healthTimer;
  Timer? _errorTimer;
  Timer? _pictureInPictureExitTimer;
  Future<void> _operations = Future<void>.value();
  late int _index;
  late final int _profileEpoch;
  int _openedIndex = -1;
  int _generation = 0;
  int _requestedQuality = 0;
  bool _loading = true;
  bool _forceOnline = false;
  bool _localFailure = false;
  bool _fullscreen = false;
  bool _automaticFullscreenSuppressed = false;
  bool _panelOpen = false;
  int _mobileTab = 0;
  bool _detailsSheetOpen = false;
  bool _favoriteBusy = false;
  bool _autoAdvance = true;
  bool? _systemFullscreen;
  Orientation? _lastOrientation;
  bool _closed = false;
  bool _leavingPlayback = false;
  bool _acceptErrors = false;
  bool _foreground = true;
  bool _playIntent = true;
  bool _showControlsOnPlaybackReady = true;
  bool _pendingError = false;
  bool _pictureInPictureSupported = false;
  bool _pictureInPictureActive = false;
  bool _pictureInPictureRequested = false;
  bool _pictureInPictureHandlerInstalled = false;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  Timer? _hardwareDecodeWatch;
  String _loadingMessage = '正在准备播放';
  String? _error;
  bool _progressSaveFailed = false;
  bool _progressQueueFailed = false;
  String _officialUID = '';
  PlaybackPlan? _plan;
  double _speed = 1;
  double _aspectRatio = 9 / 16;
  double _resumePosition = 0;
  bool _rotating = false;
  bool _openingSeason = false;
  List<DramaSeason> _seasons = const [];
  List<DramaSeason> _relatedWorks = const [];
  int _currentSeason = 0;
  int _seasonsGeneration = 0;
  int _seasonsRetryCount = 0;
  Timer? _seasonsRetryTimer;
  DateTime? _seasonsFetchedAt;
  bool _seasonsLoading = false;
  String? _seasonsError;
  bool _coverWindow = false;
  AppOrientationController? _orientationController;
  bool get _pictureInPictureVisible =>
      _pictureInPictureActive || _pictureInPictureRequested;
  bool get _canUsePictureInPicture => _pictureInPictureSupported;
  PlaybackPreferences get _preferences => PlaybackPreferences(
    speed: _speed,
    quality: _requestedQuality,
    autoAdvance: _autoAdvance,
    danmaku: _danmakuEnabled,
    preload: _preloadEnabled,
  );
  String get _qualityLabel => _plan?.local == true
      ? '本地原画'
      : _requestedQuality == 0
      ? '自动'
      : '${_requestedQuality}P';
  String get _session => _plan?.session ?? '';
  double get _currentPosition =>
      _openedIndex == _index && _player.state.position.inMilliseconds > 0
      ? _player.state.position.inMilliseconds / 1000
      : _resumePosition;

  @override
  void initState() {
    super.initState();
    _initialTrace = widget.trace ?? PlaybackTrace('player_enter');
    _initialTrace.mark('player_init');
    WidgetsBinding.instance.addObserver(this);
    PlaybackContinuity.windowChanges.addListener(_windowChanged);
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _foreground = _lifecycleState == AppLifecycleState.resumed;
    _index = widget.initialIndex;
    _playIntent = widget.initialPlayWhenReady;
    _fullscreen = widget.initialFullscreen;
    _profileEpoch = widget.handoff?.profileEpoch ?? widget.store.profileEpoch;
    _currentSeason = widget.detail.currentSeason;
    _seasons = widget.detail.seasons;
    _relatedWorks = widget.detail.seasons;
    unawaited(_loadSeasons());
    if (widget.repository.supportsOfficialAccount && widget.mediaId == null) {
      unawaited(
        widget.repository
            .hongguoAccount('status')
            .then((status) {
              if (mounted && widget.store.profileEpoch == _profileEpoch) {
                _officialUID =
                    (status['profile'] as Map?)?['uid'] as String? ?? '';
              }
            })
            .catchError((Object _) {}),
      );
    }
    final preferences = widget.store.playbackPreferences;
    _speed = preferences.speed;
    _requestedQuality = preferences.quality;
    _autoAdvance = preferences.autoAdvance;
    _danmakuEnabled = preferences.danmaku;
    _preloadEnabled = preferences.preload;
    _loader = PlaybackLoader(widget.repository);
    _preloader = PlaybackPreloader(widget.repository);
    _danmaku = DanmakuController(widget.repository)
      ..setEnabled(_danmakuEnabled);
    widget.store.addListener(_accessChanged);
    widget.repository.accountFavorites.addListener(_accountChanged);
    widget.repository.accountStatus.addListener(_officialAccountChanged);
    _player =
        widget.playerFactory?.call() ??
        Player(
          configuration: const PlayerConfiguration(
            bufferSize: 32 * 1024 * 1024,
            logLevel: MPVLogLevel.error,
          ),
        );
    _video = widget.videoBuilder == null
        ? VideoController(
            _player,
            configuration: const VideoControllerConfiguration(
              enableHardwareAcceleration: true,
            ),
          )
        : null;
    _interactions = PlayerInteractions(
      player: _player,
      available: () =>
          !_closed &&
          widget.store.profileEpoch == _profileEpoch &&
          !_loading &&
          _error == null &&
          _foreground &&
          !_panelOpen,
      baseSpeed: () => _speed,
      onTogglePlayback: _togglePlayback,
      onSeek: _seekTo,
      onFullscreen: _rotate,
      canEpisode: (direction) =>
          _index + direction >= 0 &&
          _index + direction < widget.detail.episodes.length,
      onEpisode: (direction) {
        final next = _index + direction;
        if (next < 0) return '已经是第一集';
        if (next >= widget.detail.episodes.length) return '已经是最后一集';
        unawaited(_play(next));
        return '第 ${widget.detail.episodes[next].number} 集';
      },
    );
    _playerFocus.addListener(() {
      if (!_playerFocus.hasPrimaryFocus && !_closed) _interactions.cancel();
    });
    _configurePictureInPicture();
    _subscriptions.add(
      _player.stream.error.listen((error) {
        if (!_closed && _acceptErrors && mounted && error.trim().isNotEmpty) {
          _queueRecovery();
        }
      }),
    );
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (completed &&
            !_loading &&
            !_closed &&
            _acceptErrors &&
            _error == null) {
          final duration = _player.state.duration;
          if (duration <= Duration.zero ||
              _player.state.position < duration - const Duration(seconds: 2)) {
            _queueRecovery();
          } else if (_autoAdvance &&
              _index + 1 < widget.detail.episodes.length) {
            if (_foreground && !_panelOpen) {
              _play(_index + 1, showControlsOnReady: false);
            } else {
              _advanceOnResume = true;
              unawaited(_player.pause());
              _checkpoint();
              unawaited(_saveProgress(flush: true));
            }
          } else {
            _playIntent = false;
            _interactions.cancel();
            unawaited(_player.pause());
            unawaited(_saveProgress(flush: true));
          }
        }
      }),
    );
    _subscriptions.add(
      _player.stream.position.listen((position) {
        if (!_closed && _openedIndex == _index && position > Duration.zero) {
          if (!_tracedProgress) {
            _tracedProgress = true;
            _activeTrace?.mark(
              'playback_progress',
              elapsedMs: _mediaOpenClock?.elapsedMilliseconds,
            );
          }
          _resumePosition = position.inMilliseconds / 1000;
        }
        _syncDanmaku();
        _syncPreload();
        _acknowledgeHandoff();
      }),
    );
    for (final stream in [
      _player.stream.duration,
      _player.stream.buffer,
      _player.stream.playing,
      _player.stream.buffering,
      _player.stream.rate,
      _player.stream.completed,
    ]) {
      _subscriptions.add(
        stream.listen((_) {
          _syncDanmaku();
          _syncPreload();
          _acknowledgeHandoff();
        }),
      );
    }
    _subscriptions.add(
      _player.stream.videoParams.listen((parameters) {
        final size = videoDisplaySize(parameters);
        if (size != null && mounted && !_closed) {
          if (!_tracedVideoParameters && _mediaOpenClock != null) {
            _tracedVideoParameters = true;
            _activeTrace?.mark(
              'video_parameters',
              elapsedMs: _mediaOpenClock!.elapsedMilliseconds,
            );
          }
          setState(() {
            _aspectRatio = size.width / size.height;
          });
          if (_fullscreen) _schedulePlaybackOrientation();
          _scheduleSystemUi();
        }
      }),
    );
    _saveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _saveProgress(),
    );
    _healthTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkpoint();
      if (!_closed &&
          _acceptErrors &&
          !_loading &&
          _error == null &&
          _health.stalled(
            position: _player.state.position,
            playing: _player.state.playing && _playIntent,
            foreground: _foreground,
            now: DateTime.now(),
          )) {
        unawaited(_recover());
      }
    });
    final handoff = widget.handoff;
    if (handoff != null) {
      handoff.consumed = true;
      handoff.stop = () async {
        if (_handoffOwned && !_closed) await _stopForLan();
      };
    }
    if (_profileEpoch != widget.store.profileEpoch ||
        handoff?.cancelled == true) {
      handoff?.fail('接收用户已变更，推送已取消');
      if (handoff != null) {
        unawaited(widget.repository.release(handoff.plan.session));
      }
      _loading = false;
      _error = '播放接收已取消';
    } else {
      _play(
        _index,
        position: widget.initialPosition,
        playWhenReady: widget.initialPlayWhenReady,
        handoffPlan: handoff?.plan,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closed) {
        _checkpoint();
        widget.repository.catalogUpdates.publish(
          widget.repository.catalogUpdates.current(widget.detail.drama),
          retryCover: true,
        );
      }
    });
  }

  void _accessChanged() {
    if (mounted && !_closed) {
      setState(() {});
      _menuRevision.value++;
    }
    if (!_closed &&
        (widget.store.profileEpoch != _profileEpoch || widget.store.locked)) {
      _preloader.clear();
      _handoffOwned = false;
      _playIntent = false;
      unawaited(PlaybackContinuity.clear(_continuityOwner));
      widget.handoff?.fail('接收端用户已变更');
      unawaited(_player.pause());
    }
    if (!_closed &&
        (widget.store.profileEpoch != _profileEpoch ||
            widget.store.locked ||
            !widget.store.allowsSource('hongguo'))) {
      _danmaku.setPlan(null);
    }
  }

  void _configurePictureInPicture() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _pictureInPictureHandlerInstalled = true;
    _pictureInPictureHandlerOwner = this;
    AppDevice.channel.setMethodCallHandler((call) async {
      if (call.method == 'pictureInPictureChanged') {
        final arguments = call.arguments;
        final active = arguments is Map && arguments['active'] == true;
        _setPictureInPictureStatus(
          active: active,
          requested: false,
          delayHiddenPause: !active,
        );
      }
    });
    unawaited(_refreshPictureInPictureStatus());
  }

  Future<void> _refreshPictureInPictureStatus() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final revision = _pictureInPictureRevision;
    try {
      final status = await AppDevice.channel.invokeMapMethod<String, dynamic>(
        'pictureInPictureStatus',
      );
      if (!mounted || _closed || revision != _pictureInPictureRevision) return;
      _setPictureInPictureStatus(
        supported: status?['supported'] == true,
        active: status?['active'] == true,
      );
    } on PlatformException {
      if (mounted && !_closed && revision == _pictureInPictureRevision) {
        _setPictureInPictureStatus(supported: false, active: false);
      }
    } on MissingPluginException {
      if (mounted && !_closed && revision == _pictureInPictureRevision) {
        _setPictureInPictureStatus(supported: false, active: false);
      }
    }
  }

  void _setPictureInPictureStatus({
    bool? supported,
    bool? active,
    bool? requested,
    bool delayHiddenPause = false,
  }) {
    if (active != null) _pictureInPictureRevision++;
    final nextSupported = supported ?? _pictureInPictureSupported;
    final nextActive = active ?? _pictureInPictureActive;
    final nextRequested =
        requested ?? (nextActive ? false : _pictureInPictureRequested);
    void assign() {
      _pictureInPictureSupported = nextSupported;
      _pictureInPictureActive = nextActive;
      _pictureInPictureRequested = nextRequested;
    }

    if (mounted && !_closed) {
      setState(assign);
    } else {
      assign();
    }
    if (_pictureInPictureVisible ||
        _lifecycleState == AppLifecycleState.resumed) {
      _pictureInPictureExitTimer?.cancel();
      _applyLifecycleVisibility(pauseWhenHidden: false);
      return;
    }
    _pictureInPictureExitTimer?.cancel();
    _applyLifecycleVisibility(pauseWhenHidden: !delayHiddenPause);
    if (delayHiddenPause) {
      _pictureInPictureExitTimer = Timer(const Duration(milliseconds: 700), () {
        if (!_closed &&
            !_pictureInPictureVisible &&
            _lifecycleState != AppLifecycleState.resumed) {
          _applyLifecycleVisibility();
        }
      });
    }
  }

  void _applyLifecycleVisibility({bool pauseWhenHidden = true}) {
    final visible =
        _lifecycleState == AppLifecycleState.resumed ||
        _pictureInPictureVisible;
    _foreground = visible;
    if (visible) {
      _lifecyclePauseTimer?.cancel();
      if (_advanceOnResume &&
          !_panelOpen &&
          _playIntent &&
          widget.store.profileEpoch == _profileEpoch &&
          !widget.store.locked &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        _advanceOnResume = false;
        unawaited(_play(_index + 1, showControlsOnReady: false));
      }
      if (_pausedForLifecycle || (_playIntent && !_player.state.playing)) {
        _pausedForLifecycle = false;
        if (_playIntent &&
            !_loading &&
            _error == null &&
            widget.store.profileEpoch == _profileEpoch &&
            !widget.store.locked &&
            (ModalRoute.of(context)?.isCurrent ?? true)) {
          unawaited(
            _serialize(() async {
              if (!_closed &&
                  _foreground &&
                  _playIntent &&
                  widget.store.profileEpoch == _profileEpoch &&
                  !widget.store.locked) {
                await _player.play();
              }
            }).catchError((Object _) {
              if (!_closed) _queueRecovery();
            }),
          );
        }
      }
    }
    _syncDanmaku();
    _syncPreload();
    _health.reset();
    if (!visible) _interactions.cancel();
    if (pauseWhenHidden &&
        !visible &&
        (_lifecycleState == AppLifecycleState.paused ||
            _lifecycleState == AppLifecycleState.inactive ||
            _lifecycleState == AppLifecycleState.hidden)) {
      _lifecyclePauseTimer?.cancel();
      _lifecyclePauseTimer = Timer(const Duration(milliseconds: 900), () async {
        if (_closed || _foreground || _pictureInPictureVisible) return;
        _pausedForLifecycle = _playIntent;
        try {
          await _serialize(() async {
            if (_closed || _foreground || _pictureInPictureVisible) return;
            await _player.pause();
            await _saveProgress(flush: true);
          });
        } catch (_) {
          DiaryService.add('[Play] 后台暂停未完成，将在恢复前台后重新确认播放状态');
        }
      });
    }
    if (visible && _pendingError) {
      _queueRecovery();
    }
  }

  /// 硬件解码自愈：部分机型 mediacodec 初始化成功但解不出画面（黑屏/花屏，
  /// 声音正常）。播放 8 秒后若时间在走但仍无视频尺寸，切回软件解码并回到原位。
  void _watchHardwareDecode() {
    _hardwareDecodeWatch?.cancel();
    _hardwareDecodeWatch = Timer(const Duration(seconds: 8), () async {
      if (_closed || !_foreground) return;
      final state = _player.state;
      if (!state.playing || state.position <= Duration.zero) return;
      if ((state.width ?? 0) > 0 && (state.height ?? 0) > 0) return;
      final platform = _player.platform;
      if (platform is! NativePlayer) return;
      DiaryService.add('[Play] 硬解 8 秒无画面，回退软件解码');
      try {
        await platform.setProperty('hwdec', 'no');
        await _player.seek(state.position);
        if (_playIntent && _foreground) await _player.play();
      } catch (_) {
        // 回退失败时保持现有播放，交由播放恢复逻辑处理。
      }
    });
  }

  Future<void> _enterPictureInPicture() async {
    if (!_canUsePictureInPicture ||
        _closed ||
        _loading ||
        _error != null ||
        _panelOpen ||
        _pictureInPictureVisible) {
      return;
    }
    _interactions.cancel();
    final rawRatio = _aspectRatio.isFinite && _aspectRatio > 0
        ? _aspectRatio
        : 16 / 9;
    final ratio = rawRatio.clamp(1 / 2.39, 2.39).toDouble();
    final width = ratio >= 1 ? (1000 * ratio).round() : 1000;
    final height = ratio >= 1 ? 1000 : (1000 / ratio).round();
    _setPictureInPictureStatus(requested: true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _closed) return;
    final sourceRect = _pictureInPictureSourceRect();
    final arguments = <String, int>{'width': width, 'height': height};
    if (sourceRect != null) arguments.addAll(sourceRect);
    final revision = _pictureInPictureRevision;
    try {
      final status = await AppDevice.channel.invokeMapMethod<String, dynamic>(
        'enterPictureInPicture',
        arguments,
      );
      if (!mounted || _closed || revision != _pictureInPictureRevision) return;
      final supported = status?['supported'] == true;
      final active = status?['active'] == true;
      final requested = status?['requested'] == true;
      _setPictureInPictureStatus(
        supported: supported,
        active: active,
        requested: requested && !active,
      );
      if (!supported || (!active && !requested)) {
        _notice('当前设备不支持画中画');
      } else if (requested && !active) {
        _pictureInPictureExitTimer?.cancel();
        _pictureInPictureExitTimer = Timer(const Duration(seconds: 2), () {
          if (!_closed &&
              _pictureInPictureRequested &&
              !_pictureInPictureActive) {
            _setPictureInPictureStatus(requested: false);
          }
        });
      }
    } on PlatformException {
      _setPictureInPictureStatus(requested: false);
      _notice('无法进入画中画，请检查系统权限');
    } on MissingPluginException {
      _setPictureInPictureStatus(supported: false, requested: false);
      _notice('当前平台不支持画中画');
    }
  }

  Map<String, int>? _pictureInPictureSourceRect() {
    final paneContext = _videoPaneKey.currentContext;
    final renderObject = paneContext?.findRenderObject();
    if (paneContext == null ||
        renderObject is! RenderBox ||
        !renderObject.hasSize) {
      return null;
    }
    final rect = Rect.fromPoints(
      renderObject.localToGlobal(Offset.zero),
      renderObject.localToGlobal(renderObject.size.bottomRight(Offset.zero)),
    );
    final ratio = View.of(paneContext).devicePixelRatio;
    final left = (rect.left * ratio).round().clamp(0, 100000);
    final top = (rect.top * ratio).round().clamp(0, 100000);
    final right = (rect.right * ratio).round().clamp(0, 100000);
    final bottom = (rect.bottom * ratio).round().clamp(0, 100000);
    if (right <= left || bottom <= top) return null;
    return {'left': left, 'top': top, 'right': right, 'bottom': bottom};
  }

  void _attachLanPlayback() {
    LanController.current?.attachPlayback(
      LanPlaybackHost(
        identity: _lanIdentity,
        title:
            '${widget.detail.drama.title} · 第 ${widget.detail.episodes[_index].number} 集',
        stop: _stopForLan,
      ),
    );
  }

  void _acknowledgeHandoff() {
    final handoff = widget.handoff;
    if (!_handoffOwned ||
        handoff == null ||
        handoff.cancelled ||
        handoff.started.isCompleted ||
        _closed ||
        _loading ||
        _error != null ||
        _openedIndex != _index ||
        _index != widget.initialIndex ||
        widget.store.profileEpoch != _profileEpoch) {
      return;
    }
    final state = _player.state;
    final position = state.position.inMilliseconds / 1000;
    final duration = state.duration.inMilliseconds / 1000;
    if (duration > 0 && handoff.position > duration + 2) {
      handoff.fail('续播位置超过接收端分集时长');
      return;
    }
    if (!state.playing ||
        state.buffering ||
        (state.width ?? 0) <= 0 ||
        position < handoff.position - .5 ||
        position > handoff.position + 20) {
      return;
    }
    _lanFirstPosition ??= position;
    if (position >= _lanFirstPosition! + .15) handoff.acknowledge(position);
  }

  Future<void> _stopForLan() async {
    final generation = _generation;
    await _serialize(() async {
      if (_closed ||
          generation != _generation ||
          widget.store.profileEpoch != _profileEpoch) {
        return;
      }
      _playIntent = false;
      _interactions.cancel();
      _health.reset();
      await _player.pause();
      await _saveProgress(flush: true);
    });
  }

  Future<void> _pushToDevice() async {
    final link = LanController.current;
    if (link == null ||
        _panelOpen ||
        _closed ||
        _loading ||
        _error != null ||
        widget.mediaId != null) {
      return;
    }
    final generation = _generation;
    final index = _index;
    bool current() =>
        mounted &&
        !_closed &&
        generation == _generation &&
        index == _index &&
        widget.store.profileEpoch == _profileEpoch;
    _interactions.cancel();
    setState(() => _panelOpen = true);
    try {
      await showLanPush(
        context,
        link,
        snapshot: () => LanPlaybackIntent(
          drama: widget.detail.drama,
          episodeID: widget.detail.episodes[index].id,
          episode: widget.detail.episodes[index].number,
          position: _currentPosition,
        ),
        stillCurrent: current,
        onAccepted: () async {
          if (!current()) throw StateError('本机播放内容已变更');
          await _stopForLan();
          if (!current()) throw StateError('本机播放内容已变更');
        },
      );
    } catch (error) {
      if (mounted && !_closed) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted && !_closed) setState(() => _panelOpen = false);
    }
  }

  void _syncPreload() {
    if (_closed || !_acceptErrors) return;
    if (!_preloadEnabled ||
        !_foreground ||
        widget.localOnly ||
        _loading ||
        _error != null ||
        _openedIndex != _index ||
        widget.store.profileEpoch != _profileEpoch ||
        widget.store.locked ||
        _index + 1 >= widget.detail.episodes.length) {
      _preloader.clear();
      return;
    }
    final state = _player.state;
    final duration = state.duration.inMilliseconds;
    final position = state.position.inMilliseconds;
    if (state.completed ||
        _playIntent &&
            !state.playing &&
            duration > 0 &&
            duration - position <= 1500) {
      return;
    }
    if (!_playIntent || !state.playing && !state.buffering) {
      _preloader.pause();
      return;
    }
    if (duration <= 0 || position < 2000) return;
    final rate = state.rate.isFinite && state.rate > 0 ? state.rate : 1.0;
    final remaining = (duration - position).clamp(0, duration);
    final lead = (30000 * rate).clamp(12000.0, 60000.0);
    final window = (duration * .4).clamp(0.0, lead);
    if (remaining > window) return;
    final urgent = remaining / rate <= 8000;
    final buffered = state.buffer.inMilliseconds;
    final tailBuffered = buffered >= duration - 250;
    if (state.buffering) {
      if (!urgent) _preloader.pause();
      return;
    }
    if (!urgent && !tailBuffered && (buffered - position) / rate < 5000) return;
    _preloader.prepare(
      widget.detail.drama,
      widget.detail.episodes[_index + 1],
      quality: _requestedQuality,
      urgent: urgent,
    );
  }

  void _syncDanmaku({bool discontinuity = false}) {
    if (_closed) return;
    final state = _player.state;
    _danmaku.update(
      position: state.position,
      duration: state.duration,
      speed: state.rate,
      playing: state.playing && _playIntent && !state.completed,
      buffering: state.buffering,
      foreground: _foreground,
      available:
          !_loading &&
          _error == null &&
          _openedIndex == _index &&
          widget.store.profileEpoch == _profileEpoch &&
          !widget.store.locked &&
          widget.store.allowsSource('hongguo'),
      discontinuity: discontinuity,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _coverWindow = AppLayout.isCoverWindow(context);
    final controller = AppOrientationScope.maybeOf(context);
    if (!identical(_orientationController, controller)) {
      _orientationController = controller;
      if (_fullscreen) _schedulePlaybackOrientation();
    }
    final orientation = MediaQuery.orientationOf(context);
    if (_lastOrientation != null && _lastOrientation != orientation) {
      _automaticFullscreenSuppressed = false;
      _interactions.cancel();
    }
    _lastOrientation = orientation;
    _scheduleSystemUi();
  }

  void _schedulePlaybackOrientation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closed || !_fullscreen) return;
      unawaited(
        _orientationController
            ?.setPlayback(this, fullscreen: true, aspectRatio: _aspectRatio)
            .catchError((Object _) {
              if (!_closed) _notice('无法调整播放方向，请重试全屏');
            }),
      );
    });
  }

  void _windowChanged() {
    if (!mounted || _closed) return;
    _interactions.cancel();
    _checkpoint();
    _health.reset();
    _systemFullscreen = null;
    unawaited(_saveProgress(flush: true));
    unawaited(_refreshPictureInPictureStatus());
    _applyLifecycleVisibility();
    _scheduleSystemUi();
  }

  void _scheduleSystemUi() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closed) return;
      final fullscreen = _showFullscreen;
      if (_systemFullscreen == fullscreen) return;
      _systemFullscreen = fullscreen;
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        ),
      );
    });
  }

  @override
  void didChangeMetrics() {
    if (_closed) return;
    _checkpoint();
    _interactions.cancel();
    _health.reset();
    unawaited(_saveProgress(flush: true));
    _scheduleSystemUi();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _checkpoint();
    _lifecycleState = state;
    _applyLifecycleVisibility();
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPictureInPictureStatus());
      _scheduleSystemUi();
    }
  }

  void _queueRecovery() {
    if (_closed || !_acceptErrors || _error != null) {
      return;
    }
    _pendingError = true;
    if (!_foreground || (_errorTimer?.isActive ?? false)) {
      return;
    }
    final ticket = _generation;
    final position = _player.state.position;
    _errorTimer = Timer(const Duration(milliseconds: 900), () {
      if (_closed || ticket != _generation || !_foreground || !_acceptErrors) {
        return;
      }
      _pendingError = false;
      final state = _player.state;
      if (state.playing &&
          !state.buffering &&
          (state.width ?? 0) > 0 &&
          state.position > position + const Duration(milliseconds: 300)) {
        return;
      }
      unawaited(_recover());
    });
  }

  Future<void> _recover() async {
    final current = _plan;
    if (_closed ||
        !_acceptErrors ||
        !_foreground ||
        current == null ||
        _error != null) {
      return;
    }
    _acceptErrors = false;
    _danmaku.setPlan(null);
    _errorTimer?.cancel();
    _pendingError = false;
    final position = _currentPosition;
    final action = current.local
        ? PlaybackRecoveryAction.stop
        : _recovery.next(current);
    if (action == PlaybackRecoveryAction.stop) {
      _resumePosition = position;
      final ticket = _generation;
      try {
        await _serialize(() async {
          if (_closed || ticket != _generation) {
            return;
          }
          try {
            await _saveProgress();
            _openedIndex = -1;
            await _player.stop();
          } finally {
            await widget.repository.release(current.session);
          }
        });
      } catch (_) {}
      if (mounted && !_closed && ticket == _generation) {
        setState(() {
          _loading = false;
          _localFailure = current.local;
          _error = current.local
              ? widget.allowOnlineFallback
                    ? '本地视频读取失败，请重试或重新下载；也可以手动改为在线播放。'
                    : '本地成品读取失败，请重试或重新生成。'
              : '自动恢复未成功，请检查网络后重试，也可换一集或选择其他清晰度。';
        });
      }
      return;
    }
    await _play(_index, position: position, recoveryAction: action);
  }

  void _togglePlayback() {
    if (_closed || _loading || _error != null) return;
    _handoffOwned = false;
    widget.handoff?.fail('接收端已操作播放');
    _interactions.cancel();
    _playIntent = !_player.state.playing;
    _advanceOnResume = false;
    _checkpoint();
    _health.reset();
    if (_playIntent && _player.state.completed) {
      unawaited(_play(_index));
      return;
    }
    unawaited(_player.playOrPause());
    if (!_playIntent) unawaited(_saveProgress(flush: true));
    _syncDanmaku();
  }

  void _checkpoint({double? position}) {
    if (_closed ||
        _leavingPlayback ||
        widget.store.locked ||
        widget.store.profileEpoch != _profileEpoch ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    final index = _advanceOnResume && _index + 1 < widget.detail.episodes.length
        ? _index + 1
        : _index;
    final episode = widget.detail.episodes[index];
    unawaited(
      PlaybackContinuity.checkpoint(
        _continuityOwner,
        PlaybackSnapshot(
          profile: widget.store.profile.id,
          drama: widget.detail.drama,
          episodeId: episode.id,
          episodeNumber: episode.number,
          position: index != _index
              ? 0
              : position ?? (_loading ? _resumePosition : _currentPosition),
          playing: _playIntent,
          localOnly: widget.localOnly,
          allowOnlineFallback: widget.allowOnlineFallback,
          fullscreen: _fullscreen,
          mediaId: widget.mediaId,
        ),
      ),
    );
  }

  Future<void> _saveProgress({bool flush = false}) async {
    if (_openedIndex < 0 || widget.store.profileEpoch != _profileEpoch) {
      return;
    }
    final position = _player.state.position.inMilliseconds / 1000;
    final duration = _player.state.duration.inMilliseconds / 1000;
    if (position < .1) {
      return;
    }
    final store = widget.store;
    final savedEpisode = widget.detail.episodes[_openedIndex];
    final progressKey =
        '${widget.mediaId ?? widget.detail.drama.id}:$_openedIndex:$position:$duration';
    if (_savedProgressKey == progressKey &&
        !_progressSaveFailed &&
        !_progressQueueFailed) {
      if (flush && widget.mediaId == null) {
        LanController.current?.flush();
        if (_officialUID.isNotEmpty) widget.repository.requestOfficialSync();
      }
      return;
    }
    final entry = WatchEntry(
      drama: widget.repository.catalogUpdates.current(widget.detail.drama),
      episode: savedEpisode.number,
      videoId: widget.detail.drama.source == 'hongguo'
          ? savedEpisode.videoId
          : '',
      position: position,
      duration: duration,
      updatedAt: DateTime.now(),
    );
    var localSaved = false;
    try {
      await Future<void>.value();
      if (store.profileEpoch != _profileEpoch) return;
      if (widget.mediaId == null) {
        await store.saveWatch(entry);
        localSaved = true;
        _progressSaveFailed = false;
        if (store.profileEpoch != _profileEpoch) return;
        if (_officialUID.isNotEmpty) {
          await widget.repository.hongguoAccount('queueProgress', {
            'uid': _officialUID,
            'watch': hongguoWatchPayload(entry, savedEpisode),
            'flush': flush,
          });
        }
        if (flush) LanController.current?.flush();
      } else {
        await store.saveMediaWatch(widget.mediaId!, entry);
      }
      _savedProgressKey = progressKey;
      _progressSaveFailed = _progressQueueFailed = false;
    } catch (error) {
      if (localSaved) {
        _savedProgressKey = progressKey;
        if (!_progressQueueFailed) {
          DiaryService.add('[Progress] 本机进度已保存，官方进度暂未加入同步队列，将继续重试：$error');
        }
        _progressQueueFailed = true;
      } else {
        if (!_progressSaveFailed) {
          DiaryService.add('[Progress] 本机观看进度保存失败');
          if (mounted && !_closed) _notice('观看进度保存失败，请检查存储空间后重试。');
        }
        _progressSaveFailed = true;
      }
    }
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _operations.catchError((Object _) {}).then((_) => operation());
    _operations = next;
    return next;
  }

  Future<void> _play(
    int index, {
    double position = 0,
    PlaybackRecoveryAction? recoveryAction,
    bool playWhenReady = true,
    PlaybackPlan? handoffPlan,
    bool showControlsOnReady = true,
  }) {
    final trace = _generation == 0
        ? _initialTrace
        : PlaybackTrace('episode_request');
    return trace.run(
      () => _playWithTrace(
        index,
        trace: trace,
        position: position,
        recoveryAction: recoveryAction,
        playWhenReady: playWhenReady,
        handoffPlan: handoffPlan,
        showControlsOnReady: showControlsOnReady,
      ),
    );
  }

  Future<void> _recordInitialFirstFrame(PlaybackTrace trace, int ticket) async {
    try {
      await _video!.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 30),
      );
      if (!_closed && ticket == _generation) {
        trace.mark(
          'first_frame',
          elapsedMs: _mediaOpenClock?.elapsedMilliseconds,
        );
      }
    } catch (_) {
      if (!_closed && ticket == _generation) {
        trace.mark('first_frame_unconfirmed', ok: false);
      }
    }
  }

  Future<void> _playWithTrace(
    int index, {
    required PlaybackTrace trace,
    double position = 0,
    PlaybackRecoveryAction? recoveryAction,
    bool playWhenReady = true,
    PlaybackPlan? handoffPlan,
    bool showControlsOnReady = true,
  }) async {
    if (_closed ||
        widget.store.profileEpoch != _profileEpoch ||
        index < 0 ||
        index >= widget.detail.episodes.length) {
      return;
    }
    final ticket = ++_generation;
    final automaticNext =
        !showControlsOnReady &&
        index == _index + 1 &&
        recoveryAction == null &&
        position == 0;
    _acceptErrors = false;
    _switchLoadingTimer?.cancel();
    _activeTrace = trace;
    _mediaOpenClock = null;
    _tracedVideoParameters = false;
    _tracedProgress = false;
    trace.mark('episode_prepare');
    _advanceOnResume = false;
    _interactions.cancel();
    if (widget.handoff != null &&
        handoffPlan == null &&
        recoveryAction == null) {
      _handoffOwned = false;
      widget.handoff?.fail('接收端已更换播放内容');
    }
    if (index != _index) _forceOnline = false;
    final warmed =
        handoffPlan ??
        (recoveryAction == null && _preloadEnabled && !widget.localOnly
            ? await _preloader.claim(
                widget.detail.drama,
                widget.detail.episodes[index],
                quality: _requestedQuality,
                online: _forceOnline,
                wait: automaticNext
                    ? const Duration(milliseconds: 350)
                    : Duration.zero,
              )
            : null);
    if (_closed || ticket != _generation) {
      if (warmed != null) await widget.repository.release(warmed.session);
      return;
    }
    _preloader.clear();
    trace.mark(warmed == null ? 'next_preload_miss' : 'next_preload_hit');
    _fastEpisodeSwitch = automaticNext && warmed != null;
    _seekSequence++;
    _danmaku.setPlan(null);
    _acceptErrors = false;
    _pendingError = false;
    _errorTimer?.cancel();
    _health.reset();
    if (recoveryAction == null) {
      _recovery.reset();
      _playIntent = playWhenReady;
    }
    _resumePosition = position;
    _showControlsOnPlaybackReady = showControlsOnReady;
    setState(() {
      _index = index;
      _loading = true;
      _error = null;
      _localFailure = false;
      _loadingMessage = switch (recoveryAction) {
        PlaybackRecoveryAction.alternative => '正在切换备用线路',
        PlaybackRecoveryAction.refresh => '正在重新获取播放地址',
        _ => '正在准备播放',
      };
    });
    if (_fastEpisodeSwitch) {
      _switchLoadingTimer = Timer(const Duration(milliseconds: 450), () {
        if (mounted && !_closed && ticket == _generation && _loading) {
          setState(() => _fastEpisodeSwitch = false);
        }
      });
    }
    if (index == widget.detail.episodes.length - 1) {
      _refreshSeasonsIfNeeded();
    }
    LanController.current?.detachPlayback(_lanIdentity);
    _lanIdentity = Object();
    _attachLanPlayback();
    PlaybackPlan? prepared;
    PlaybackPlan? retained;
    PlaybackPlan? retired;
    bool installed = false;
    try {
      await trace.measure(
        'player_prepare',
        () => _serialize(() async {
          if (_closed || ticket != _generation) {
            return;
          }
          if (automaticNext && warmed != null) {
            unawaited(_saveProgress(flush: true));
          } else {
            await _saveProgress(flush: true);
          }
          if (_closed || ticket != _generation) return;
          _openedIndex = -1;
          if (warmed == null) await _player.stop();
          final previous = _plan;
          _plan = null;
          if (recoveryAction == PlaybackRecoveryAction.alternative) {
            retained = previous;
          } else if (previous != null) {
            if (warmed != null) {
              retired = previous;
            } else {
              await widget.repository.release(previous.session);
            }
          }
        }),
      );
      if (_closed || ticket != _generation) {
        return;
      }
      prepared = await trace.measure(
        'resolve',
        () async => retained != null
            ? await _loader.fallback(retained!)
            : warmed != null
            ? await _loader.use(warmed)
            : await _loader.load(
                widget.detail.drama,
                widget.detail.episodes[index],
                quality: _requestedQuality,
                localOnly: widget.localOnly,
                online: _forceOnline,
              ),
      );
      if (prepared == null) {
        return;
      }
      final plan = prepared;
      await _serialize(() async {
        if (_closed || ticket != _generation) {
          await widget.repository.release(plan.session);
          return;
        }
        if (plan.url.isEmpty) {
          throw AppFailure('未返回播放地址，请重试');
        }
        final configureClock = Stopwatch()..start();
        final platform = _player.platform;
        if (platform is NativePlayer) {
          await platform.setProperty('hwdec', 'mediacodec-copy');
          await platform.setProperty('hwdec-codecs', 'all');
          await platform.setProperty('vd-lavc-skiploopfilter', 'nonkey');
          await platform.setProperty('vd-lavc-threads', '4');
          await platform.setProperty('vd-lavc-fast', 'yes');
          await platform.setProperty('video-sync', 'audio');
          await platform.setProperty('framedrop', 'vo');
          await platform.setProperty(
            'demuxer-lavf-o',
            [
              'seg_max_retry=3',
              'strict=experimental',
              'allowed_extensions=ALL',
              plan.local
                  ? 'protocol_whitelist=[file,crypto,data]'
                  : 'protocol_whitelist=[http,https,tcp,tls,crypto,data,file]',
              if (plan.decryptionKey.isNotEmpty)
                'decryption_key=${plan.decryptionKey}',
            ].join(','),
          );
          await platform.setProperty('network-timeout', '20');
        }
        _plan = plan;
        installed = true;
        _acceptErrors = true;
        trace.mark(
          'player_configure',
          elapsedMs: configureClock.elapsedMilliseconds,
        );
        trace.mark('media_open_start');
        _mediaOpenClock = Stopwatch()..start();
        if (ticket == 1 && _video != null) {
          unawaited(_recordInitialFirstFrame(trace, ticket));
        }
        await _player.open(
          Media(
            plan.url,
            httpHeaders: plan.headers,
            start: position > 0
                ? Duration(milliseconds: (position * 1000).round())
                : null,
          ),
          play: _foreground && _playIntent,
        );
        trace.mark(
          'media_open_return',
          elapsedMs: _mediaOpenClock?.elapsedMilliseconds,
        );
        if (_closed || ticket != _generation) {
          return;
        }
        _openedIndex = index;
        _watchHardwareDecode();
        _attachLanPlayback();
        _health.reset();
        await _interactions.applySpeed();
        if (mounted && !_closed && ticket == _generation) {
          setState(() {
            _loading = false;
            _fastEpisodeSwitch = false;
          });
          _danmaku.setPlan(plan);
          _syncDanmaku();
          _acknowledgeHandoff();
          _menuRevision.value++;
        }
      });
    } catch (error) {
      if (mounted && !_closed && ticket == _generation) {
        setState(() => _fastEpisodeSwitch = false);
      }
      trace.mark('play_failed', ok: false);
      DiaryService.add('[Play] 捕获播放流程错误: $error');
      if (!_closed && mounted && ticket == _generation) {
        if (prepared != null && identical(_plan, prepared)) {
          _acceptErrors = true;
          _queueRecovery();
        } else {
          if (prepared != null) {
            await widget.repository.release(prepared.session);
          }
          if (mounted && !_closed && ticket == _generation) {
            setState(() {
              _loading = false;
              _localFailure =
                  (error is AppFailure && error.code == 'local_media') ||
                  (widget.localOnly && !_forceOnline);
              _error = error is AppFailure ? error.message : '无法播放这一集，请重试或换一集。';
              widget.handoff?.fail(_error!);
            });
          }
        }
      } else if (prepared != null && !installed) {
        await widget.repository.release(prepared.session);
      }
    } finally {
      if (ticket == _generation) _switchLoadingTimer?.cancel();
      final previous = retired;
      if (previous != null) {
        unawaited(
          widget.repository.release(previous.session).catchError((Object _) {}),
        );
      }
      if (warmed != null && !installed) {
        await widget.repository.release(warmed.session);
      }
      if (retained != null) {
        await widget.repository.release(retained!.session);
      }
    }
  }

  Future<void> _switchOnline() async {
    _forceOnline = true;
    await _retry();
  }

  Future<void> _retry({int? quality}) async {
    final position = _currentPosition;
    if (quality != null) {
      _requestedQuality = quality;
    }
    await _play(
      _index,
      position: position,
      playWhenReady: quality == null || _error != null || _player.state.playing,
    );
  }

  bool get _showFullscreen =>
      _fullscreen ||
      (!_coverWindow &&
          !_automaticFullscreenSuppressed &&
          _aspectRatio >= 1 &&
          MediaQuery.orientationOf(context) == Orientation.landscape);

  Future<void> _rotate() async {
    if (_rotating) {
      return;
    }
    final fullscreen = !_showFullscreen;
    final previous = _fullscreen;
    final previousSuppressed = _automaticFullscreenSuppressed;
    _interactions.cancel();
    _rotating = true;
    setState(() {
      _fullscreen = fullscreen;
      _detailsSheetOpen = false;
      _automaticFullscreenSuppressed = !fullscreen;
    });
    try {
      await (_orientationController?.setPlayback(
            this,
            fullscreen: fullscreen,
            aspectRatio: _aspectRatio,
          ) ??
          SystemChrome.setPreferredOrientations(
            AppOrientationController.orientations(
              fullscreen: fullscreen,
              aspectRatio: _aspectRatio,
            ),
          ));
    } catch (_) {
      if (mounted && !_closed) {
        setState(() {
          _fullscreen = previous;
          _automaticFullscreenSuppressed = previousSuppressed;
        });
        _notice('无法切换全屏，请重试');
      }
    } finally {
      _rotating = false;
      if (mounted && !_closed) _scheduleSystemUi();
      _checkpoint();
    }
  }

  void _notice(String message) {
    if (!mounted || _closed) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setPreferences(PlaybackPreferences preferences) async {
    if (_closed || widget.store.profileEpoch != _profileEpoch) {
      throw StateError('当前用户已变更');
    }
    _interactions.cancel();
    final nextPreferences = preferences;
    await widget.store.setPlaybackPreferences(nextPreferences);
    if (!mounted || _closed || widget.store.profileEpoch != _profileEpoch) {
      return;
    }
    final qualityChanged = nextPreferences.quality != _requestedQuality;
    setState(() {
      _speed = nextPreferences.speed;
      _requestedQuality = nextPreferences.quality;
      _autoAdvance = nextPreferences.autoAdvance;
      _danmakuEnabled = nextPreferences.danmaku;
      _preloadEnabled = nextPreferences.preload;
    });
    _danmaku.setEnabled(_danmakuEnabled);
    _syncDanmaku();
    if (qualityChanged) _preloader.clear();
    _syncPreload();
    _menuRevision.value++;
    await _interactions.applySpeed();
    if (qualityChanged && _plan?.local != true) {
      await _retry(quality: nextPreferences.quality);
    }
  }

  void _accountChanged() {
    if (mounted && !_closed) {
      setState(() {});
      _menuRevision.value++;
    }
  }

  void _officialAccountChanged() {
    if (!mounted || _closed || widget.store.profileEpoch != _profileEpoch) {
      return;
    }
    final status = widget.repository.accountStatus.value;
    final uid = (status['profile'] as Map?)?['uid'] as String? ?? '';
    if (uid == _officialUID) return;
    _officialUID = uid;
    _savedProgressKey = null;
  }

  Future<void> _toggleDanmaku() async {
    if (widget.detail.drama.source != 'hongguo') return;
    try {
      await _setPreferences(_preferences.copyWith(danmaku: !_danmakuEnabled));
    } catch (_) {
      _notice('弹幕偏好未能保存，请重试');
    }
  }

  Future<void> _retryDanmakuFromControls() async {
    try {
      _danmaku.retry();
      _menuRevision.value++;
    } catch (_) {
      _notice('弹幕重试失败，请稍后再试');
    }
  }

  Future<void> _submitDownloadSelection(DownloadSelection selection) async {
    if (!widget.repository.supportsDownloads ||
        !widget.store.canDownload ||
        widget.store.profileEpoch != _profileEpoch ||
        widget.mediaId != null) {
      return;
    }
    final added = await widget.repository.enqueueDownloads(
      widget.detail,
      selection.episodes,
      quality: selection.quality,
    );
    if (!mounted || _closed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added == 0 ? '所选集数已在下载列表中' : '已加入 $added 集，已有任务自动跳过'),
        action: SnackBarAction(
          label: '查看',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DownloadsScreen(
                  repository: widget.repository,
                  store: widget.store,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openPanel(PlayerMenuSection section) async {
    if (_panelOpen || _closed) return;
    _interactions.cancel();
    setState(() => _panelOpen = true);
    final menuTheme = _showFullscreen ? AppTheme.dark : PlayerStyle.panelTheme;
    var enterPictureInPicture = false;
    try {
      final index = await showDialog<int>(
        context: context,
        builder: (menuContext) => AnimatedBuilder(
          animation: Listenable.merge([
            _menuRevision,
            widget.store,
            widget.repository.accountFavorites,
            _danmaku,
            _preloader,
          ]),
          builder: (_, _) => Theme(
            data: menuTheme,
            child: PlayerMenu(
              section: section,
              episodes: widget.detail.episodes,
              currentIndex: _index,
              playedNumbers: widget.store.playedEpisodes(
                widget.detail.drama.id,
              ),
              preferences: _preferences,
              qualities: _plan?.qualities ?? [],
              actualQuality: _plan?.quality ?? 0,
              local: _plan?.local == true,
              favorite:
                  (widget.store.isFavorite(widget.detail.drama.id) ||
                  widget.repository.isAccountFavorite(widget.detail.drama.id)),
              onEpisode: (index) => Navigator.pop(menuContext, index),
              onPictureInPicture: _canUsePictureInPicture
                  ? () => Navigator.pop(menuContext, -1)
                  : null,
              onPreferences: _setPreferences,
              showDanmaku: widget.detail.drama.source == 'hongguo',
              danmakuStatus: _danmaku.status,
              onRetryDanmaku: _danmaku.canRetry ? _danmaku.retry : null,
              preloadStatus: _preloader.status,
              onFavorite: () => updateLibraryFollowing(
                context,
                widget.repository,
                widget.store,
                widget.detail.drama,
              ),
            ),
          ),
        ),
      );
      if (index == -1) {
        enterPictureInPicture = true;
      } else if (mounted && !_closed && index != null && index != _index) {
        await _play(index);
      }
    } finally {
      if (mounted && !_closed) {
        setState(() => _panelOpen = false);
        _applyLifecycleVisibility();
        _playerFocus.requestFocus();
      }
    }
    if (enterPictureInPicture && mounted && !_closed) {
      await _enterPictureInPicture();
    }
  }

  Future<void> _seekTo(Duration target) async {
    if (_closed || _loading || _error != null) return;
    _handoffOwned = false;
    widget.handoff?.fail('接收端已调整播放位置');
    final ticket = ++_seekSequence;
    final generation = _generation;
    _danmaku.beginSeek();
    var succeeded = false;
    try {
      await _player.seek(target);
      succeeded = true;
      if (!_closed && ticket == _seekSequence && generation == _generation) {
        _resumePosition = target.inMilliseconds / 1000;
        _checkpoint(position: _resumePosition);
      }
    } catch (_) {
      _notice('跳转失败，请重试');
    } finally {
      if (!_closed && ticket == _seekSequence && generation == _generation) {
        _danmaku.endSeek(succeeded ? target : _player.state.position);
      }
    }
  }

  void _back() {
    if (_showFullscreen) {
      _rotate();
    } else if (_detailsSheetOpen) {
      _closeDetailsSheet();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    unawaited(
      PlaybackContinuity.clear(
        _continuityOwner,
        preserveForRestart: !_leavingPlayback,
      ),
    );
    _closed = true;
    _seasonsGeneration++;
    _seasonsRetryTimer?.cancel();
    LanController.current?.detachPlayback(_lanIdentity);
    widget.handoff?.fail('接收端已退出播放');
    widget.store.removeListener(_accessChanged);
    widget.repository.accountFavorites.removeListener(_accountChanged);
    widget.repository.accountStatus.removeListener(_officialAccountChanged);
    _danmaku.dispose();
    _preloader.dispose();
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    PlaybackContinuity.windowChanges.removeListener(_windowChanged);
    _saveTimer?.cancel();
    _switchLoadingTimer?.cancel();
    _healthTimer?.cancel();
    _errorTimer?.cancel();
    _pictureInPictureExitTimer?.cancel();
    _lifecyclePauseTimer?.cancel();
    _hardwareDecodeWatch?.cancel();
    if (_pictureInPictureHandlerInstalled &&
        identical(_pictureInPictureHandlerOwner, this)) {
      _pictureInPictureHandlerOwner = null;
      AppDevice.channel.setMethodCallHandler(null);
    }
    _interactions.dispose();
    _playerFocus.dispose();
    _menuRevision.dispose();
    unawaited(_saveProgress(flush: true));
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    unawaited(widget.repository.release(_session));
    unawaited(_loader.close().catchError((Object _) {}));
    unawaited(
      _operations.catchError((Object _) {}).then((_) async {
        await _interactions.pendingRates.catchError((Object _) {});
        await _player.dispose();
      }),
    );
    unawaited(
      (_orientationController?.releasePlayback(this) ??
              SystemChrome.setPreferredOrientations(
                AppOrientationController.orientations(),
              ))
          .catchError((Object _) {}),
    );
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final fullscreen = _showFullscreen;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: AppTheme.systemBars(Brightness.dark).copyWith(
              systemNavigationBarIconBrightness:
                  _detailsSheetOpen && !fullscreen
                  ? Brightness.dark
                  : Brightness.light,
            ),
            child: _buildPlayer(context),
          );
        },
      ),
    );
  }

  Future<void> _loadSeasons({bool automatic = false}) async {
    if (_closed ||
        _seasonsLoading ||
        widget.localOnly ||
        widget.mediaId != null ||
        !widget.repository.supportsOfficialAccount ||
        widget.store.profileEpoch != _profileEpoch) {
      return;
    }
    _seasonsRetryTimer?.cancel();
    if (!automatic) _seasonsRetryCount = 0;
    final generation = ++_seasonsGeneration;
    setState(() {
      _seasonsLoading = true;
      _seasonsError = null;
    });
    try {
      final id = widget.detail.drama.sourceId.isNotEmpty
          ? widget.detail.drama.sourceId
          : widget.detail.drama.id.split(':').last;
      final result = await widget.repository.hongguoAccount('seasons', {
        'id': id,
      });
      if (!mounted ||
          _closed ||
          generation != _seasonsGeneration ||
          widget.store.profileEpoch != _profileEpoch) {
        return;
      }
      final seasons = [
        for (final row in result['seasons'] as List? ?? const [])
          DramaSeason.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
      final relatedWorks = [
        for (final row
            in result['relatedWorks'] as List? ??
                result['seasons'] as List? ??
                const [])
          DramaSeason.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
      setState(() {
        final currentSeason = intValue(result['currentSeason']);
        if (currentSeason > 0) _currentSeason = currentSeason;
        if (relatedWorks.isNotEmpty || _relatedWorks.isEmpty) {
          _seasons = seasons;
          _relatedWorks = relatedWorks;
        }
        _seasonsFetchedAt = DateTime.now();
        final warning = result['warning'] as String? ?? '';
        _seasonsError = warning.isEmpty ? null : warning;
      });
    } catch (error) {
      if (mounted &&
          !_closed &&
          generation == _seasonsGeneration &&
          widget.store.profileEpoch == _profileEpoch) {
        setState(() => _seasonsError = '$error');
      }
    } finally {
      if (mounted && !_closed && generation == _seasonsGeneration) {
        setState(() => _seasonsLoading = false);
        if (_seasonsError != null && _seasonsRetryCount < 3) {
          final delay = [2, 5, 10][_seasonsRetryCount++];
          _seasonsRetryTimer = Timer(Duration(seconds: delay), () {
            if (!_closed && widget.store.profileEpoch == _profileEpoch) {
              unawaited(_loadSeasons(automatic: true));
            }
          });
        }
      }
    }
  }

  void _refreshSeasonsIfNeeded() {
    final fetched = _seasonsFetchedAt;
    if (_seasonsError != null ||
        fetched == null ||
        DateTime.now().difference(fetched) >= const Duration(seconds: 30)) {
      unawaited(_loadSeasons());
    }
  }

  bool get _showSeasonActions =>
      widget.store.profileEpoch == _profileEpoch &&
      !widget.store.locked &&
      !widget.localOnly &&
      widget.mediaId == null &&
      _index == widget.detail.episodes.length - 1;

  DramaSeason? get _nextSeason {
    if (!_showSeasonActions) return null;
    final candidates =
        _seasons
            .where(
              (season) =>
                  season.drama.id != widget.detail.drama.id &&
                  season.playable &&
                  (_currentSeason > 0
                      ? season.number > _currentSeason
                      : season.next),
            )
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number));
    return candidates.firstOrNull;
  }

  DramaSeason? get _upcomingSeason {
    if (!_showSeasonActions || _currentSeason < 1 || _nextSeason != null) {
      return null;
    }
    if (_seasons.any(
      (season) =>
          season.number > _currentSeason &&
          (season.playable || season.drama.episodes > 0),
    )) {
      return null;
    }
    final candidates =
        _seasons
            .where(
              (season) =>
                  season.drama.id != widget.detail.drama.id &&
                  season.number > _currentSeason &&
                  !season.playable &&
                  season.reservable,
            )
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number));
    return candidates.firstOrNull;
  }

  Future<void> _openNextSeason(DramaSeason season) async {
    if (_openingSeason ||
        _closed ||
        !season.playable ||
        widget.store.profileEpoch != _profileEpoch) {
      return;
    }
    setState(() => _openingSeason = true);
    final wasPlaying = _playIntent;
    final generation = _generation;
    try {
      final detail = await widget.repository.detail(season.drama);
      if (!mounted ||
          _closed ||
          generation != _generation ||
          widget.store.profileEpoch != _profileEpoch) {
        return;
      }
      if (detail.episodes.isEmpty) throw AppFailure('该作品暂时没有可播放的集数');
      await _serialize(() async {
        if (_closed || generation != _generation) return;
        _playIntent = false;
        await _player.pause();
        await _saveProgress(flush: true);
      });
      if (!mounted ||
          _closed ||
          generation != _generation ||
          widget.store.profileEpoch != _profileEpoch) {
        return;
      }
      unawaited(
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) => PlayerScreen(
              detail: detail,
              initialIndex: 0,
              repository: widget.repository,
              store: widget.store,
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted &&
          !_closed &&
          generation == _generation &&
          widget.store.profileEpoch == _profileEpoch) {
        _notice('$error');
        _playIntent = wasPlaying;
        if (wasPlaying && _foreground) unawaited(_player.play());
      }
    } finally {
      if (mounted && !_closed) setState(() => _openingSeason = false);
    }
  }

  Widget _buildPlayer(BuildContext context) {
    final fullscreen = _showFullscreen;
    final pictureInPicture = _pictureInPictureVisible;
    return PopScope(
      canPop: !fullscreen && !_detailsSheetOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _leavingPlayback = true;
          unawaited(PlaybackContinuity.clear(_continuityOwner));
        } else if (fullscreen) {
          _rotate();
        } else if (_detailsSheetOpen) {
          _closeDetailsSheet();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _back,
          const SingleActivator(LogicalKeyboardKey.goBack): _back,
        },
        child: Focus(
          focusNode: _playerFocus,
          onKeyEvent: (_, event) {
            if (_panelOpen ||
                _detailsSheetOpen ||
                !_playerFocus.hasPrimaryFocus ||
                !(ModalRoute.of(context)?.isCurrent ?? true)) {
              return KeyEventResult.ignored;
            }
            return _interactions.key(event);
          },
          autofocus: true,
          child: Scaffold(
            backgroundColor: PlayerStyle.background,
            body: fullscreen || pictureInPicture
                ? _videoPane(context)
                : SafeArea(
                    bottom: false,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide =
                            !_coverWindow &&
                            (constraints.maxWidth >= 840 ||
                                constraints.maxWidth >
                                    constraints.maxHeight * 1.3);
                        if (wide) {
                          return Row(
                            children: [
                              Expanded(child: _videoPane(context)),
                              SizedBox(
                                width: constraints.maxWidth >= 840 ? 360 : 300,
                                child: Column(
                                  children: [
                                    Expanded(child: _mobilePlaybackPanel()),
                                    Theme(
                                      data: PlayerStyle.panelTheme,
                                      child: _seasonFooter(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }
                        return _portraitPlayer(constraints);
                      },
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  bool get _followed =>
      widget.store.isFavorite(widget.detail.drama.id) ||
      widget.repository.isAccountFavorite(widget.detail.drama.id);

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy ||
        _closed ||
        widget.store.profileEpoch != _profileEpoch) {
      return;
    }
    setState(() => _favoriteBusy = true);
    try {
      await updateLibraryFollowing(
        context,
        widget.repository,
        widget.store,
        widget.detail.drama,
      );
    } finally {
      if (mounted && !_closed) setState(() => _favoriteBusy = false);
    }
  }

  void _openDetailsSheet([int tab = 0]) {
    if (_closed || _panelOpen) return;
    _interactions.cancel();
    setState(() {
      _mobileTab = tab;
      _detailsSheetOpen = true;
    });
    if (tab == 3) _refreshSeasonsIfNeeded();
  }

  void _closeDetailsSheet() {
    if (_closed || !mounted) return;
    _interactions.cancel();
    setState(() => _detailsSheetOpen = false);
    _playerFocus.requestFocus();
  }

  Widget _portraitPlayer(BoxConstraints constraints) {
    final sheetHeight = (constraints.maxHeight * (_coverWindow ? .65 : .58))
        .clamp(
          (constraints.maxHeight - 64).clamp(0.0, 300.0),
          constraints.maxHeight,
        );
    final short = constraints.maxHeight < 620;
    final landscapeVideo = _aspectRatio > 1;
    final fullButtonTop =
        (constraints.maxHeight / 2 +
                constraints.maxWidth / _aspectRatio / 2 +
                8)
            .clamp(
              60.0,
              (constraints.maxHeight - 245).clamp(60.0, double.infinity),
            );
    return Theme(
      data: AppTheme.dark,
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            top: 0,
            left: 0,
            right: 0,
            bottom: _detailsSheetOpen ? sheetHeight : 0,
            child: _videoPane(context, immersive: true),
          ),
          if (!_detailsSheetOpen) ...[
            Positioned(top: 0, left: 0, right: 0, child: _portraitHeader()),
            if (landscapeVideo && !short)
              Positioned(
                top: fullButtonTop,
                left: 0,
                right: 0,
                child: Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black.withValues(alpha: .12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _rotate,
                    icon: const Icon(Icons.screen_rotation_outlined, size: 18),
                    label: const Text('全屏观看'),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _portraitFooter(short: short),
            ),
            Positioned(
              right: 8,
              bottom: short ? 100 : 122,
              child: _portraitActions(compact: short),
            ),
          ] else ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: sheetHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeDetailsSheet,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: sheetHeight,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: _mobilePlaybackPanel(sheet: true),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _portraitHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('player-back'),
          tooltip: '返回',
          color: Colors.white,
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 23),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('player-episodes'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              onPressed: () => _openDetailsSheet(),
              child: Text(
                '第 ${widget.detail.episodes[_index].number} 集',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
        ),
        TextButton.icon(
          key: const ValueKey('player-speed'),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          onPressed: () => _openPanel(PlayerMenuSection.speed),
          icon: const Icon(Icons.speed_rounded, size: 23),
          label: Text('${_speed}x', style: const TextStyle(fontSize: 16)),
        ),
        IconButton(
          key: const ValueKey('player-more'),
          tooltip: '播放设置与清晰度',
          color: Colors.white,
          onPressed: () => _openPanel(PlayerMenuSection.settings),
          icon: const Icon(Icons.more_vert_rounded),
        ),
      ],
    ),
  );

  Widget _portraitActions({required bool compact}) {
    Widget action(
      IconData icon,
      String label,
      VoidCallback? onPressed, {
      bool selected = false,
    }) => Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: label,
            color: selected ? PlayerStyle.accent : Colors.white,
            iconSize: compact ? 27 : 32,
            onPressed: onPressed,
            icon: Icon(icon),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .82),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        action(
          _followed ? Icons.star_rounded : Icons.star_border_rounded,
          _followed ? '已收藏' : '收藏',
          _favoriteBusy ? null : _toggleFavorite,
          selected: _followed,
        ),
        action(Icons.video_library_rounded, '系列剧', () => _openDetailsSheet(3)),
        if (widget.repository.supportsDownloads && widget.store.canDownload)
          action(Icons.download_rounded, '下载', () => _openDetailsSheet(2)),
        if (widget.mediaId == null && LanController.current != null && !compact)
          action(Icons.cast_rounded, '投屏', _pushToDevice),
      ],
    );
  }

  Widget _portraitFooter({required bool short}) {
    final drama = widget.detail.drama;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            PlayerStyle.background.withValues(alpha: 0),
            PlayerStyle.background.withValues(alpha: .94),
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!short && drama.source == 'hongguo')
                TextButton(
                  key: const ValueKey('player-danmaku-toggle'),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: .06),
                    foregroundColor: _danmakuEnabled
                        ? Colors.white
                        : Colors.white54,
                    minimumSize: const Size(34, 34),
                    padding: const EdgeInsets.all(6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _danmaku.canRetry
                      ? _retryDanmakuFromControls
                      : _toggleDanmaku,
                  child: Text(
                    _danmaku.canRetry ? '重试弹幕' : '弹',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 68),
                child: InkWell(
                  onTap: () => _openDetailsSheet(1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            drama.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!short && drama.category.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 68, bottom: 8),
                  child: Text(
                    drama.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ),
              SizedBox(
                height: 26,
                child: PlayerTimeline(
                  player: _player,
                  enabled: !_loading && _error == null,
                  onSeek: _seekTo,
                ),
              ),
              _seasonFooter(),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('player-open-details'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: .1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _openDetailsSheet(),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              [
                                '选集',
                                if (drama.releaseLabel != '状态未知')
                                  drama.releaseLabel,
                                '全${widget.detail.episodes.length}集',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_up_rounded, size: 22),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    key: const ValueKey('player-fullscreen'),
                    tooltip: '进入全屏',
                    color: Colors.white,
                    onPressed: _rotate,
                    icon: const Icon(Icons.fullscreen_rounded, size: 28),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seasonFooter() {
    if (!_showSeasonActions) return const SizedBox.shrink();
    final next = _nextSeason;
    final upcoming = _upcomingSeason;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_seasonsLoading) const LinearProgressIndicator(minHeight: 2),
        if (_seasonsError != null)
          Row(
            children: [
              const Expanded(
                child: Text(
                  '后续季暂未加载',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(onPressed: _loadSeasons, child: const Text('重试')),
            ],
          ),
        if (next != null)
          PlayerSeasonActions(
            key: ValueKey('footer-${next.drama.id}'),
            season: next,
            bottomInset: false,
            showReservation: false,
            repository: widget.repository,
            store: widget.store,
            opening: _openingSeason,
            onPlay: () => _openNextSeason(next),
          )
        else if (upcoming != null)
          PlayerSeasonActions(
            key: ValueKey('footer-${upcoming.drama.id}'),
            season: upcoming,
            label: '后续新季',
            bottomInset: false,
            repository: widget.repository,
            store: widget.store,
            onPlay: () => _openNextSeason(upcoming),
          ),
      ],
    );
  }

  Widget _videoPane(BuildContext context, {bool immersive = false}) {
    final title =
        '${widget.detail.drama.title} · 第 ${widget.detail.episodes[_index].number} 集${_plan?.local == true ? ' · 本地' : ''}${widget.detail.episodes[_index].vip ? ' · VIP 试看' : ''}${(_plan?.routeIndex ?? 0) > 0 ? ' · 线路 ${_plan!.routeIndex + 1}' : ''}';
    final hideOverlayForPictureInPicture = _pictureInPictureVisible;
    final Widget controls = hideOverlayForPictureInPicture
        ? const SizedBox.shrink()
        : PlayerControls(
            player: _player,
            interactions: _interactions,
            enabled: !_loading && _error == null,
            panelOpen: _panelOpen,
            fullscreen: _showFullscreen,
            compact: _coverWindow,
            immersive: immersive,
            showOnPlaybackReady: _showControlsOnPlaybackReady,
            title: title,
            episodeLabel: '第 ${widget.detail.episodes[_index].number} 集',
            onTogglePlayback: _togglePlayback,
            onFullscreen: _rotate,
            onBack: _back,
            onFocusSurface: _playerFocus.requestFocus,
            onSeek: _seekTo,
            speed: _speed,
            qualityLabel: _qualityLabel,
            showDanmaku: widget.detail.drama.source == 'hongguo',
            danmakuEnabled: _danmakuEnabled,
            danmakuStatus: _danmaku.status,
            onEpisodes: () async {
              if (immersive) {
                _openDetailsSheet();
              } else {
                await _openPanel(PlayerMenuSection.episodes);
              }
            },
            onSpeed: () => _openPanel(PlayerMenuSection.speed),
            onQuality: () => _openPanel(PlayerMenuSection.quality),
            onDanmaku: widget.detail.drama.source == 'hongguo'
                ? _toggleDanmaku
                : null,
            onRetryDanmaku: _danmaku.canRetry
                ? _retryDanmakuFromControls
                : null,
            onPush: widget.mediaId == null ? _pushToDevice : null,
          );
    final media = Stack(
      fit: StackFit.expand,
      children: [
        if (widget.videoBuilder != null)
          widget.videoBuilder!(const SizedBox.shrink())
        else
          Video(
            controller: _video!,
            fit: BoxFit.contain,
            fill: immersive ? PlayerStyle.background : Colors.black,
            controls: (_) => const SizedBox.shrink(),
            pauseUponEnteringBackgroundMode: false,
            resumeUponEnteringForegroundMode: false,
          ),
        if (!hideOverlayForPictureInPicture)
          DanmakuOverlay(controller: _danmaku, aspectRatio: _aspectRatio),
      ],
    );
    return KeyedSubtree(
      key: _videoSurfaceKey,
      child: Theme(
        data: AppTheme.dark,
        child: Stack(
          key: _videoPaneKey,
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: immersive ? PlayerStyle.background : Colors.black,
              child: PlayerEpisodeMotion(
                interactions: _interactions,
                child: media,
              ),
            ),
            controls,
            if (_loading &&
                !_fastEpisodeSwitch &&
                !hideOverlayForPictureInPicture)
              ColoredBox(
                color: Colors.black.withValues(alpha: .78),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(_loadingMessage),
                    ],
                  ),
                ),
              ),
            if (_error != null && !hideOverlayForPictureInPicture)
              ColoredBox(
                color: Colors.black.withValues(alpha: .9),
                child: StatusPanel(
                  title: '暂时无法播放',
                  message: _error!,
                  onRetry: () => _retry(),
                  action: _localFailure ? '重试本地播放' : '重试播放',
                  secondaryAction: Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => DiaryService.showDiaryDialog(context),
                        icon: const Icon(Icons.receipt_long_rounded),
                        label: const Text('查看播放日记'),
                      ),
                      if (_localFailure && widget.allowOnlineFallback)
                        TextButton.icon(
                          onPressed: _switchOnline,
                          icon: const Icon(Icons.cloud_outlined),
                          label: const Text('改为在线播放'),
                        )
                      else if (!_localFailure &&
                          !widget.localOnly &&
                          widget.repository.supportsSourceManagement)
                        SourceDiagnosticsButton(
                          repository: widget.repository,
                          store: widget.store,
                          drama: widget.detail.drama,
                        ),
                    ],
                  ),
                  icon: Icons.play_disabled_rounded,
                ),
              ),
            if ((_loading || _error != null) &&
                !hideOverlayForPictureInPicture &&
                _showFullscreen)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Row(
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _back,
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        label: const Text('后退'),
                      ),
                      Container(
                        height: 18,
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: Colors.white.withValues(alpha: .5),
                      ),
                      Flexible(
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () =>
                              _openPanel(PlayerMenuSection.episodes),
                          child: Text(
                            '第 ${widget.detail.episodes[_index].number} 集',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mobilePlaybackPanel({bool sheet = false}) => Theme(
    data: PlayerStyle.panelTheme,
    child: ColoredBox(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: PlayerDetailsPanel(
          detail: widget.detail,
          repository: widget.repository,
          currentSeason: _currentSeason,
          tab: _mobileTab,
          onTab: (tab) {
            setState(() => _mobileTab = tab);
            if (tab == 3) _refreshSeasonsIfNeeded();
          },
          followed: _followed,
          favoriteBusy: _favoriteBusy,
          onFavorite: _toggleFavorite,
          onClose: sheet ? _closeDetailsSheet : null,
          onDownload:
              widget.repository.supportsDownloads && widget.store.canDownload
              ? () => setState(() => _mobileTab = 2)
              : null,
          child: _mobileTab == 0
              ? _episodePanel()
              : _mobileTab == 1
              ? _mobileSynopsis()
              : _mobileTab == 2
              ? _mobileDownload()
              : _relatedWorksPanel(),
        ),
      ),
    ),
  );

  Widget _relatedWorksPanel() {
    if (widget.localOnly ||
        widget.mediaId != null ||
        !widget.repository.supportsOfficialAccount ||
        widget.store.profileEpoch != _profileEpoch ||
        !widget.store.allowsSource(widget.detail.drama.source)) {
      return const StatusPanel(
        title: '系列剧不可用',
        message: '请在红果在线播放时查看系列与关联作品。',
        icon: Icons.video_library_outlined,
      );
    }
    final works = <String, DramaSeason>{
      for (final work in _relatedWorks) work.drama.id: work,
    };
    for (final season in _seasons) {
      final previous = works[season.drama.id];
      if (previous == null || previous.number < 1 && season.number > 0) {
        works[season.drama.id] = season;
      }
    }
    final later =
        works.values
            .where(
              (work) =>
                  work.drama.id != widget.detail.drama.id &&
                  work.number > 0 &&
                  (_currentSeason > 0
                      ? work.number > _currentSeason
                      : work.next),
            )
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number));
    final laterIDs = later.map((work) => work.drama.id).toSet();
    final related = works.values
        .where(
          (work) => work.number < 1 && work.drama.id != widget.detail.drama.id,
        )
        .toList();
    final previous =
        works.values
            .where(
              (work) =>
                  (work.number > 0 ||
                      work.drama.id == widget.detail.drama.id) &&
                  !laterIDs.contains(work.drama.id),
            )
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number));
    final groups = [('本剧后续季', later), ('关联剧', related), ('本剧其他季', previous)];
    return LayoutBuilder(
      builder: (context, constraints) {
        final colors = Theme.of(context).colorScheme;
        final scale = (constraints.maxWidth / 393).clamp(.8, 1.25);
        final inset = 18 * scale;
        return ColoredBox(
          color: colors.surface,
          child: ListView(
            padding: EdgeInsets.fromLTRB(inset, 0, inset, 16 * scale),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _currentSeason > 0 ? '按官方季号排列' : '当前季号待确认',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _seasonsLoading ? null : _loadSeasons,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('刷新'),
                  ),
                ],
              ),
              if (_seasonsLoading) const LinearProgressIndicator(minHeight: 2),
              if (_seasonsError != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('系列信息暂未完整加载'),
                  subtitle: Text(_seasonsError!),
                  trailing: TextButton(
                    onPressed: _seasonsLoading ? null : _loadSeasons,
                    child: const Text('重试'),
                  ),
                ),
              if (!_seasonsLoading && _seasonsError == null && works.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('暂无系列或关联作品'),
                ),
              for (final group in groups)
                if (group.$2.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.$1,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${group.$2.length} 部',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (var index = 0; index < group.$2.length; index++) ...[
                    if (index > 0)
                      Divider(
                        height: 1,
                        thickness: .7,
                        color: colors.outlineVariant,
                      ),
                    _relatedWorkCard(group.$2[index], scale),
                  ],
                ],
            ],
          ),
        );
      },
    );
  }

  Widget _relatedWorkCard(DramaSeason work, double scale) {
    final label = work.label.isNotEmpty
        ? work.label
        : work.number > 0
        ? '第 ${work.number} 季'
        : '相关作品';
    if (work.drama.id == widget.detail.drama.id) {
      return DramaListCard(
        key: ValueKey('related-${work.drama.id}'),
        drama: work.drama,
        repository: widget.repository,
        heading: label,
        scale: scale,
        expandToContent: true,
        footer: Text(
          '正在播放',
          style: TextStyle(
            color: PlayerStyle.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return PlayerSeasonActions(
      key: ValueKey('related-${work.drama.id}'),
      season: work,
      label: label,
      playLabel: '播放',
      bottomInset: false,
      listCard: true,
      scale: scale,
      repository: widget.repository,
      store: widget.store,
      opening: _openingSeason,
      onPlay: () => _openNextSeason(work),
    );
  }

  Widget _mobileSynopsis() {
    final drama = widget.detail.drama;
    return Builder(
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
          children: [
            if (drama.category.isNotEmpty || drama.releaseLabel != '状态未知')
              Text(
                [
                  if (drama.category.isNotEmpty) drama.category,
                  if (drama.releaseLabel != '状态未知') drama.releaseLabel,
                ].join(' · '),
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              ),
            if (drama.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in drama.tags.take(12))
                    Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(
              drama.description.trim().isEmpty ? '暂无简介' : drama.description,
              style: const TextStyle(fontSize: 15, height: 1.7),
            ),
            if (drama.onlineDate.isNotEmpty ||
                drama.heat.isNotEmpty ||
                drama.views.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                [
                  if (drama.onlineDate.isNotEmpty) '${drama.onlineDate} 上线',
                  if (drama.heat.isNotEmpty) '热度 ${drama.heat}',
                  if (drama.views.isNotEmpty) '播放 ${drama.views}',
                ].join(' · '),
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            _mobileFollowControl(drama),
            if (widget.detail.warning.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                widget.detail.warning,
                style: TextStyle(color: colors.error),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _mobileFollowControl(Drama drama) {
    final state = widget.store.following(drama.id);
    final followed =
        state != null || widget.repository.isAccountFavorite(drama.id);
    return PopupMenuButton<String>(
      key: const ValueKey('player-follow-status'),
      tooltip: '追剧与观看状态',
      onSelected: (value) async {
        if (_profileEpoch != widget.store.profileEpoch) return;
        if (value == 'remove') {
          await saveUserChange(
            context,
            () => updateLibraryFollowing(
              context,
              widget.repository,
              widget.store,
              drama,
            ),
          );
        } else {
          final status = FollowStatus.values.firstWhere(
            (status) => status.name == value,
          );
          await saveUserChange(
            context,
            () => updateLibraryFollowing(
              context,
              widget.repository,
              widget.store,
              drama,
              status: status,
            ),
          );
        }
        if (mounted && !_closed) setState(() {});
      },
      itemBuilder: (_) => [
        for (final status in FollowStatus.values)
          CheckedPopupMenuItem(
            value: status.name,
            checked: state?.status == status,
            child: Text(status.label),
          ),
        if (followed) const PopupMenuItem(value: 'remove', child: Text('取消追剧')),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: !followed
              ? PlayerStyle.panelTheme.colorScheme.surfaceContainerHighest
              : PlayerStyle.panelTheme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              !followed ? Icons.bookmark_add_outlined : Icons.bookmark_rounded,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(state?.label ?? (followed ? '已追剧' : '加入追剧')),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _mobileDownload() {
    final colors = Theme.of(context).colorScheme;
    if (!widget.repository.supportsDownloads || !widget.store.canDownload) {
      return ColoredBox(
        color: colors.surface,
        child: const StatusPanel(
          title: '下载不可用',
          message: '当前用户或当前环境未开放本地下载。',
          icon: Icons.download_outlined,
        ),
      );
    }
    return DownloadPicker(
      detail: widget.detail,
      preferences: widget.store.downloadPreferences,
      embedded: true,
      onSubmit: _submitDownloadSelection,
    );
  }

  Widget _episodePanel() => PlayerEpisodePicker(
    episodes: widget.detail.episodes,
    currentIndex: _index,
    playedNumbers: widget.store.playedEpisodes(widget.detail.drama.id),
    onSelected: (index) {
      _closeDetailsSheet();
      if (index != _index) unawaited(_play(index));
    },
  );
}
