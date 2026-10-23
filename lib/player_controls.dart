import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'lan_controller.dart';
import 'player_interactions.dart';
import 'widgets.dart';

class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.interactions,
    required this.enabled,
    required this.fullscreen,
    required this.showOnPlaybackReady,
    required this.onFullscreen,
    required this.onBack,
    required this.title,
    required this.episodeLabel,
    required this.onTogglePlayback,
    required this.onEpisodes,
    required this.onSpeed,
    required this.onQuality,
    required this.speed,
    required this.qualityLabel,
    required this.onFocusSurface,
    this.showDanmaku = false,
    this.danmakuEnabled = false,
    this.danmakuStatus = '',
    this.panelOpen = false,
    this.compact = false,
    this.onSeek,
    this.onDanmaku,
    this.onRetryDanmaku,
    this.onPush,
  });

  final Player player;
  final PlayerInteractions interactions;
  final bool enabled;
  final bool fullscreen;
  final bool showOnPlaybackReady;
  final VoidCallback onFullscreen;
  final VoidCallback onBack;
  final String title;
  final String episodeLabel;
  final VoidCallback onTogglePlayback;
  final Future<void> Function() onEpisodes;
  final Future<void> Function() onSpeed;
  final Future<void> Function() onQuality;
  final double speed;
  final String qualityLabel;
  final VoidCallback onFocusSurface;
  final bool showDanmaku;
  final bool danmakuEnabled;
  final String danmakuStatus;
  final bool panelOpen;
  final bool compact;
  final Future<void> Function(Duration)? onSeek;
  final Future<void> Function()? onDanmaku;
  final Future<void> Function()? onRetryDanmaku;
  final Future<void> Function()? onPush;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _hideTimer;
  bool _visible = true;
  bool _suppressAutoPlaybackStart = false;
  bool _lastPlaying = false;
  double? _seekValue;

  @override
  void initState() {
    super.initState();
    _visible = widget.showOnPlaybackReady;
    _suppressAutoPlaybackStart = !widget.showOnPlaybackReady;
    _lastPlaying = widget.player.state.playing;
    for (final stream in [
      widget.player.stream.position,
      widget.player.stream.duration,
      widget.player.stream.buffer,
      widget.player.stream.playing,
      widget.player.stream.buffering,
      widget.player.stream.volume,
    ]) {
      _subscriptions.add(
        stream.listen((_) {
          if (mounted) setState(() {});
        }),
      );
    }
    _subscriptions.add(
      widget.player.stream.playing.listen((playing) {
        final wasPlaying = _lastPlaying;
        _lastPlaying = playing;
        if (!mounted || !widget.enabled) return;
        if (!playing) {
          _show();
        } else if (!wasPlaying) {
          if (_suppressAutoPlaybackStart) {
            _suppressAutoPlaybackStart = false;
            _scheduleHide();
          } else {
            _show();
          }
        }
      }),
    );
    widget.interactions.addListener(_interactionChanged);
    _scheduleHide();
  }

  @override
  void didUpdateWidget(PlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled ||
        widget.panelOpen != oldWidget.panelOpen ||
        widget.fullscreen != oldWidget.fullscreen ||
        widget.showOnPlaybackReady != oldWidget.showOnPlaybackReady) {
      _seekValue = null;
      if (widget.showOnPlaybackReady) {
        _suppressAutoPlaybackStart = false;
      } else if (widget.enabled && !oldWidget.enabled) {
        _suppressAutoPlaybackStart = !widget.player.state.playing;
      } else if (!widget.enabled && oldWidget.enabled) {
        _suppressAutoPlaybackStart = true;
        _visible = false;
      }
      if (widget.enabled && !oldWidget.enabled) {
        if (widget.showOnPlaybackReady || !widget.player.state.playing) {
          _visible = true;
        } else {
          _visible = false;
        }
      } else if (widget.panelOpen != oldWidget.panelOpen ||
          widget.fullscreen != oldWidget.fullscreen) {
        _visible = true;
      }
      _scheduleHide();
    }
  }

  void _interactionChanged() {
    if (mounted && widget.interactions.feedback.isNotEmpty) _show();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.enabled ||
        widget.panelOpen ||
        !widget.player.state.playing ||
        _seekValue != null) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted &&
          widget.enabled &&
          !widget.panelOpen &&
          widget.player.state.playing &&
          !widget.player.state.buffering &&
          !widget.interactions.boosting &&
          _seekValue == null) {
        setState(() => _visible = false);
      }
    });
  }

  void _show() {
    if (!mounted) return;
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void _tap() {
    if (widget.interactions.suppressTap) return;
    widget.onFocusSurface();
    setState(() => _visible = !_visible);
    _scheduleHide();
  }

  Future<void> _panel(Future<void> Function() open) async {
    _hideTimer?.cancel();
    widget.interactions.cancel();
    await open();
    _show();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.interactions.removeListener(_interactionChanged);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.player.state;
    final duration = state.duration.inMilliseconds / 1000;
    final position = state.position.inMilliseconds / 1000;
    final buffered = state.buffer.inMilliseconds / 1000;
    final visible = _visible || widget.panelOpen;
    return MouseRegion(
      onHover: (_) => _show(),
      cursor: visible ? SystemMouseCursors.basic : SystemMouseCursors.none,
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          onDoubleTap: () {
            if (!widget.enabled || widget.interactions.suppressTap) return;
            widget.onTogglePlayback();
            _show();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                key: const ValueKey('player-gesture-surface'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  widget.onFocusSurface();
                  widget.interactions.pointerDown(
                    event,
                    swipeEnabled: true,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  );
                },
                onPointerMove: widget.interactions.pointerMove,
                onPointerUp: widget.interactions.pointerUp,
                onPointerCancel: widget.interactions.pointerCancel,
                child: const SizedBox.expand(),
              ),
              if (state.buffering && widget.enabled)
                const IgnorePointer(
                  child: Center(child: CircularProgressIndicator()),
                ),
              IgnorePointer(
                ignoring: !visible,
                child: ExcludeFocus(
                  excluding: !visible,
                  child: AnimatedOpacity(
                    opacity: visible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xAA000000),
                                  Colors.transparent,
                                  Color(0xE6000000),
                                ],
                                stops: [0, .45, 1],
                              ),
                            ),
                          ),
                        ),
                        _controlsChrome(
                          constraints.biggest,
                          playing: state.playing,
                          buffering: state.buffering,
                          duration: duration,
                          position: position,
                          buffered: buffered,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _gestureFeedback(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controlsChrome(
    Size viewport, {
    required bool playing,
    required bool buffering,
    required double duration,
    required double position,
    required double buffered,
  }) {
    final compact = widget.compact || viewport.height < 240;
    final horizontal = (viewport.width * .028).clamp(8.0, 28.0);
    final top = (viewport.height * .035).clamp(6.0, 20.0);
    final bottom = (viewport.height * .045).clamp(4.0, 24.0);
    final centerSize = (viewport.shortestSide * .18).clamp(40.0, 84.0);
    return IconTheme(
      data: const IconThemeData(color: Colors.white),
      child: DefaultTextStyle(
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 14 : 16,
          fontWeight: FontWeight.w400,
        ),
        child: Stack(
          children: [
            if (widget.enabled && !buffering)
              Align(
                alignment: const Alignment(0, -.05),
                child: _centerPlayback(playing, centerSize),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom),
              child: Stack(
                children: [
                  _topBar(compact: compact),
                  _bottomControls(
                    compact: compact,
                    duration: duration,
                    position: position,
                    buffered: buffered,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar({required bool compact}) => Align(
    alignment: Alignment.topCenter,
    child: Row(
      children: [
        _chromeButton(
          key: const ValueKey('player-back'),
          tooltip: widget.fullscreen ? '返回（退出全屏）' : '返回',
          onPressed: widget.onBack,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
              const SizedBox(width: 6),
              const Text('后退'),
            ],
          ),
        ),
        Container(
          height: 18,
          width: 1,
          margin: EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
          color: Colors.white.withValues(alpha: .5),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _chromeButton(
              key: const ValueKey('player-episodes'),
              tooltip: '${widget.title}，点击选集',
              onPressed: widget.enabled
                  ? () => _panel(widget.onEpisodes)
                  : null,
              child: Text(
                widget.episodeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        if (widget.onPush != null)
          _lanPushTool(const ValueKey('fullscreen-lan-push')),
      ],
    ),
  );

  Widget _centerPlayback(bool playing, double size) => Tooltip(
    message: playing ? '暂停播放' : '开始播放',
    child: Semantics(
      button: true,
      label: playing ? '暂停播放' : '开始播放',
      child: Material(
        color: Colors.black.withValues(alpha: .55),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: .2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('player-playback-toggle'),
          customBorder: const CircleBorder(),
          onTap: () {
            widget.onTogglePlayback();
            _show();
          },
          child: SizedBox.square(
            dimension: size,
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: size * .64,
              color: Colors.white,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _bottomControls({
    required bool compact,
    required double duration,
    required double position,
    required double buffered,
  }) => Align(
    alignment: Alignment.bottomCenter,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _progressRow(
          compact: compact,
          duration: duration,
          position: position,
          buffered: buffered,
        ),
        _playbackTools(compact: compact),
      ],
    ),
  );

  Widget _progressRow({
    required bool compact,
    required double duration,
    required double position,
    required double buffered,
  }) {
    final timeStyle = TextStyle(
      fontSize: compact ? 11 : 13,
      color: Colors.white,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatPosition(_seekValue ?? position), style: timeStyle),
            Text(formatPosition(duration), style: timeStyle),
          ],
        ),
        SizedBox(
          height: compact ? 16 : 20,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              padding: EdgeInsets.zero,
              trackHeight: 4,
              activeTrackColor: const Color(0xFF35DED8),
              thumbColor: const Color(0xFF35DED8),
              inactiveTrackColor: Colors.white.withValues(alpha: .3),
              secondaryActiveTrackColor: Colors.white.withValues(alpha: .5),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              key: const ValueKey('player-progress'),
              padding: EdgeInsets.zero,
              value: (_seekValue ?? position).clamp(
                0,
                duration > 0 ? duration : 1,
              ),
              max: duration > 0 ? duration : 1,
              secondaryTrackValue: buffered.clamp(
                0,
                duration > 0 ? duration : 1,
              ),
              semanticFormatterCallback: formatPosition,
              onChangeStart: widget.enabled && duration > 0
                  ? (_) {
                      widget.interactions.cancel();
                      _hideTimer?.cancel();
                    }
                  : null,
              onChanged: !widget.enabled || duration <= 0
                  ? null
                  : (value) {
                      _hideTimer?.cancel();
                      setState(() => _seekValue = value);
                    },
              onChangeEnd: (value) {
                if (widget.enabled && duration > 0) {
                  (widget.onSeek ?? widget.player.seek)(
                    Duration(milliseconds: (value * 1000).round()),
                  );
                }
                setState(() => _seekValue = null);
                _show();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _chromeButton({
    required Key key,
    required String tooltip,
    required Widget child,
    required VoidCallback? onPressed,
    bool selected = false,
  }) => Builder(
    builder: (context) => Tooltip(
      message: tooltip,
      child: TextButton(
        key: key,
        style: TextButton.styleFrom(
          foregroundColor: selected ? const Color(0xFF35DED8) : Colors.white,
          disabledForegroundColor: Colors.white.withValues(alpha: .38),
          backgroundColor: Colors.transparent,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: DefaultTextStyle.of(context).style,
          shape: const RoundedRectangleBorder(),
        ),
        onPressed: onPressed,
        child: child,
      ),
    ),
  );

  Widget _dropdownTool({
    required Key key,
    required String tooltip,
    required String label,
    required VoidCallback? onPressed,
    required bool compact,
  }) => _chromeButton(
    key: key,
    tooltip: tooltip,
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        SizedBox(width: compact ? 2 : 6),
        Icon(Icons.keyboard_arrow_down_rounded, size: compact ? 18 : 22),
      ],
    ),
  );

  Widget _lanPushTool(Key key) {
    final link = LanController.current;
    Widget button() => _chromeButton(
      key: key,
      tooltip: link?.connection == null
          ? '广播到其他设备'
          : '广播到 ${link!.connection!.peer.name}',
      onPressed: widget.enabled && link != null
          ? () => _panel(widget.onPush!)
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (link?.pushing == true)
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else
            Icon(
              link?.connection == null
                  ? Icons.cast_rounded
                  : Icons.cast_connected_rounded,
              size: 26,
            ),
          const SizedBox(width: 6),
          const Text('广播'),
        ],
      ),
    );
    if (link == null) return button();
    return AnimatedBuilder(animation: link, builder: (context, _) => button());
  }

  Widget _danmakuTool() => _chromeButton(
    key: const ValueKey('player-danmaku-toggle'),
    tooltip: widget.danmakuStatus.isEmpty
        ? (widget.danmakuEnabled ? '关闭弹幕' : '打开弹幕')
        : widget.danmakuStatus,
    selected: widget.danmakuEnabled,
    onPressed:
        widget.enabled &&
            (widget.onRetryDanmaku != null || widget.onDanmaku != null)
        ? () => _panel(widget.onRetryDanmaku ?? widget.onDanmaku!)
        : null,
    child: widget.onRetryDanmaku != null
        ? const Icon(Icons.refresh_rounded, size: 22)
        : const Text('弹'),
  );

  Widget _playbackTools({required bool compact}) => Align(
    alignment: Alignment.centerRight,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showDanmaku) ...[
            _danmakuTool(),
            SizedBox(width: compact ? 2 : 10),
          ],
          _dropdownTool(
            key: const ValueKey('player-speed'),
            tooltip: '倍速',
            label: '${widget.speed}×',
            onPressed: widget.enabled ? () => _panel(widget.onSpeed) : null,
            compact: compact,
          ),
          SizedBox(width: compact ? 2 : 10),
          _dropdownTool(
            key: const ValueKey('player-quality'),
            tooltip: '清晰度',
            label: widget.qualityLabel,
            onPressed: widget.enabled ? () => _panel(widget.onQuality) : null,
            compact: compact,
          ),
          if (!widget.fullscreen) ...[
            SizedBox(width: compact ? 2 : 10),
            _chromeButton(
              key: const ValueKey('player-fullscreen'),
              tooltip: '进入全屏',
              onPressed: widget.onFullscreen,
              child: const Icon(Icons.fullscreen_rounded, size: 26),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _gestureFeedback() => AnimatedBuilder(
    animation: widget.interactions,
    builder: (context, _) {
      final hud = widget.interactions.hudState;
      final feedback = widget.interactions.feedback;
      if (hud.type == SwipeAction.brightness ||
          hud.type == SwipeAction.volume) {
        final volume = hud.type == SwipeAction.volume;
        final value = hud.value.clamp(0.0, 1.0);
        final percent = (value * 100).round();
        final icon = volume
            ? value == 0
                  ? Icons.volume_off_rounded
                  : value < 0.5
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded
            : value < 0.33
            ? Icons.brightness_low_rounded
            : value < 0.66
            ? Icons.brightness_medium_rounded
            : Icons.brightness_high_rounded;
        return IgnorePointer(
          child: Center(
            child: Container(
              width: 120,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .75),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .15),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .4),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 36),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: 70,
                    height: 6,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: value,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${volume ? '音量' : '亮度'} $percent%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (feedback.isEmpty) return const SizedBox.shrink();
      return IgnorePointer(
        child: Align(
          alignment: const Alignment(0, -.5),
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              feedback,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      );
    },
  );
}
