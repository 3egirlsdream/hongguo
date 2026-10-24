import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app_theme.dart';
import 'core_bridge.dart';
import 'catalog_sort.dart';
import 'models.dart';
import 'player_interactions.dart';
import 'widgets.dart';

abstract final class PlayerStyle {
  static const background = Color(0xFF22211D);
  static const accent = Color(0xFFFF8514);
  static double landscapeLift(double height) =>
      (height * .045).clamp(0.0, 36.0);

  static ThemeData get panelTheme => AppTheme.light.copyWith(
    colorScheme: AppTheme.light.colorScheme.copyWith(
      primary: accent,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFFFF0E2),
      onPrimaryContainer: const Color(0xFFB84F00),
      surface: Colors.white,
      surfaceContainer: const Color(0xFFF6F6F6),
      onSurface: const Color(0xFF181818),
      onSurfaceVariant: const Color(0xFF999999),
    ),
    scaffoldBackgroundColor: Colors.white,
  );
}

String playerFavoriteCount(String raw) {
  final count = catalogMetric(raw);
  if (count == null || count < 0) return '';
  final unit = count >= 100000000
      ? 100000000
      : count >= 10000
      ? 10000
      : 1;
  if (unit == 1) return count.floor().toString();
  final value = ((count / unit * 10).floor() / 10).toStringAsFixed(1);
  return '${value.replaceFirst(RegExp(r'\.0$'), '')}${unit == 10000 ? '万' : '亿'}';
}

class PlayerMediaPlacement extends StatelessWidget {
  const PlayerMediaPlacement({
    super.key,
    required this.raised,
    required this.child,
  });
  final bool raised;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Transform.translate(
      key: const ValueKey('player-media-placement'),
      offset: Offset(
        0,
        raised ? -PlayerStyle.landscapeLift(constraints.maxHeight) : 0,
      ),
      child: child,
    ),
  );
}

class PlayerEpisodeMotion extends StatelessWidget {
  const PlayerEpisodeMotion({
    super.key,
    required this.interactions,
    required this.child,
  });
  final PlayerInteractions interactions;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: AnimatedBuilder(
      animation: interactions,
      child: child,
      builder: (context, child) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: interactions.episodeDragOffset),
        duration:
            interactions.episodeDragging ||
                MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: child,
        builder: (context, offset, child) => Transform.translate(
          key: const ValueKey('player-episode-motion'),
          offset: Offset(0, offset),
          child: child,
        ),
      ),
    ),
  );
}

class PlayerDetailsPanel extends StatefulWidget {
  const PlayerDetailsPanel({
    super.key,
    required this.detail,
    required this.repository,
    required this.currentSeason,
    required this.tab,
    required this.onTab,
    required this.followed,
    required this.onFavorite,
    required this.child,
    this.favoriteBusy = false,
    this.onClose,
    this.onDownload,
  });

  final DramaDetail detail;
  final AppRepository repository;
  final int currentSeason;
  final int tab;
  final ValueChanged<int> onTab;
  final bool followed;
  final bool favoriteBusy;
  final VoidCallback onFavorite;
  final VoidCallback? onClose;
  final VoidCallback? onDownload;
  final Widget child;

  @override
  State<PlayerDetailsPanel> createState() => _PlayerDetailsPanelState();
}

class _PlayerDetailsPanelState extends State<PlayerDetailsPanel> {
  double _drag = 0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxHeight < 390;
      final tiny = constraints.maxHeight < 280;
      final drama = widget.detail.drama;
      final colors = Theme.of(context).colorScheme;
      return Material(
        color: colors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) => _drag = 0,
              onVerticalDragUpdate: (event) => _drag += event.delta.dy,
              onVerticalDragEnd: (event) {
                if (_drag > 48 || (event.primaryVelocity ?? 0) > 250) {
                  widget.onClose?.call();
                }
              },
              child: Column(
                children: [
                  if (widget.onClose != null)
                    SizedBox(
                      height: 24,
                      child: Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5E5E5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(18, compact ? 4 : 12, 6, 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: tiny
                              ? 28
                              : compact
                              ? 38
                              : 48,
                          height: tiny
                              ? 38
                              : compact
                              ? 52
                              : 66,
                          child: DramaCover(
                            drama: drama,
                            repository: widget.repository,
                            radius: 7,
                            showOverlay: false,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: InkWell(
                            onTap: () => widget.onTab(1),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  drama.title,
                                  maxLines: compact ? 1 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: compact ? 16 : 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (!tiny) ...[
                                  const SizedBox(height: 7),
                                  Text(
                                    [
                                      if (widget.currentSeason > 0)
                                        '第${widget.currentSeason}季',
                                      '全${widget.detail.episodes.length}集',
                                    ].join(' · '),
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (widget.onClose != null)
                          IconButton(
                            tooltip: '收起详情面板',
                            onPressed: widget.onClose,
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: compact ? 40 : 46,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  for (final item in [(1, '简介'), (0, '选集'), (3, '系列剧')])
                    Expanded(
                      child: TextButton(
                        key: ValueKey('player-detail-tab-${item.$1}'),
                        style: TextButton.styleFrom(
                          foregroundColor: widget.tab == item.$1
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          textStyle: TextStyle(
                            fontSize: 17,
                            fontWeight: widget.tab == item.$1
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        onPressed: () => widget.onTab(item.$1),
                        child: Text(
                          item.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  if (widget.onDownload != null)
                    IconButton(
                      tooltip: '下载选集',
                      color: widget.tab == 2
                          ? colors.primary
                          : colors.onSurfaceVariant,
                      onPressed: widget.onDownload,
                      icon: const Icon(Icons.download_outlined, size: 22),
                    ),
                ],
              ),
            ),
            Expanded(child: widget.child),
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF2F2F2))),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 30 : 48,
                  vertical: compact ? 8 : 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('player-panel-favorite'),
                      style: FilledButton.styleFrom(
                        backgroundColor: PlayerStyle.accent,
                        foregroundColor: Colors.white,
                        minimumSize: Size(0, compact ? 42 : 46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                        textStyle: const TextStyle(fontSize: 17),
                      ),
                      onPressed: widget.favoriteBusy ? null : widget.onFavorite,
                      icon: Icon(
                        widget.followed
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 24,
                      ),
                      label: Text(
                        widget.favoriteBusy
                            ? '保存中'
                            : widget.followed
                            ? '已收藏'
                            : '收藏',
                      ),
                    ),
                    if (playerFavoriteCount(widget.detail.drama.favoriteCount)
                        .isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          playerFavoriteCount(
                            widget.detail.drama.favoriteCount,
                          ),
                          key: const ValueKey('player-panel-favorite-count'),
                          semanticsLabel:
                              '收藏数 ${playerFavoriteCount(widget.detail.drama.favoriteCount)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF99652D),
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class PlayerEpisodePicker extends StatefulWidget {
  const PlayerEpisodePicker({
    super.key,
    required this.episodes,
    required this.currentIndex,
    required this.playedNumbers,
    required this.onSelected,
  });

  final List<Episode> episodes;
  final int currentIndex;
  final Set<int> playedNumbers;
  final ValueChanged<int> onSelected;

  @override
  State<PlayerEpisodePicker> createState() => _PlayerEpisodePickerState();
}

class _PlayerEpisodePickerState extends State<PlayerEpisodePicker> {
  final _scroll = ScrollController();
  final _ranges = ScrollController();
  int? _located;
  String _layout = '';

  @override
  void didUpdateWidget(PlayerEpisodePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex) _located = null;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _ranges.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.episodes.isEmpty) return const Center(child: Text('暂无分集'));
    final target = (_located ?? widget.currentIndex).clamp(
      0,
      widget.episodes.length - 1,
    );
    final range = target ~/ 30;
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView.builder(
            controller: _ranges,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: (widget.episodes.length / 30).ceil(),
            itemBuilder: (context, index) {
              final start = index * 30;
              final end = math.min(start + 30, widget.episodes.length) - 1;
              return SizedBox(
                width: 86,
                child: TextButton(
                  key: ValueKey('player-range-$index'),
                  onPressed: () => setState(() => _located = start),
                  style: TextButton.styleFrom(
                    foregroundColor: index == range
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                    textStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: index == range
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  child: Text(
                    '${widget.episodes[start].number}–${widget.episodes[end].number}',
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context);
              final digits = widget.episodes.last.number.toString().length;
              final minimum = math.max(
                49.0,
                textScale.scale(16) * digits * .62 + 20,
              );
              final columns = ((constraints.maxWidth - 36 + 8) / (minimum + 8))
                  .floor()
                  .clamp(1, 8);
              final extent = math.max(48.0, textScale.scale(17) + 28);
              final layout =
                  '$target:$columns:$extent:${constraints.maxHeight}';
              if (layout != _layout) {
                _layout = layout;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || _layout != layout) return;
                  if (_scroll.hasClients) {
                    _scroll.jumpTo(
                      (target ~/ columns * (extent + 8) -
                              constraints.maxHeight / 2 +
                              extent / 2)
                          .clamp(0.0, _scroll.position.maxScrollExtent),
                    );
                  }
                  if (_ranges.hasClients) {
                    _ranges.jumpTo(
                      (range * 86.0 - constraints.maxWidth / 2 + 43).clamp(
                        0.0,
                        _ranges.position.maxScrollExtent,
                      ),
                    );
                  }
                });
              }
              return GridView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                itemCount: widget.episodes.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: extent,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final episode = widget.episodes[index];
                  final current = index == widget.currentIndex;
                  final played = widget.playedNumbers.contains(episode.number);
                  return Semantics(
                    selected: current,
                    label:
                        '第 ${episode.number} 集，${current
                            ? '正在播放'
                            : played
                            ? '已播放'
                            : '未播放'}${episode.vip ? '，VIP 试看' : ''}',
                    child: TextButton(
                      key: ValueKey('play-episode-${episode.number}'),
                      onPressed: () => widget.onSelected(index),
                      style: TextButton.styleFrom(
                        foregroundColor: current
                            ? colors.primary
                            : played
                            ? colors.onSurfaceVariant
                            : colors.onSurface,
                        backgroundColor: current
                            ? colors.primaryContainer
                            : colors.surfaceContainer,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: Text(
                              '${episode.number}',
                              style: const TextStyle(fontSize: 17),
                            ),
                          ),
                          if (current || played)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Icon(
                                current
                                    ? Icons.equalizer_rounded
                                    : Icons.check_rounded,
                                size: 12,
                              ),
                            ),
                          if (episode.vip)
                            Positioned(
                              bottom: 3,
                              right: 3,
                              child: Icon(
                                Icons.workspace_premium_rounded,
                                size: 11,
                                color: colors.tertiary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class PlayerTimeline extends StatefulWidget {
  const PlayerTimeline({
    super.key,
    required this.player,
    required this.enabled,
    required this.onSeek,
  });
  final Player player;
  final bool enabled;
  final Future<void> Function(Duration) onSeek;

  @override
  State<PlayerTimeline> createState() => _PlayerTimelineState();
}

class _PlayerTimelineState extends State<PlayerTimeline> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  double? _value;

  @override
  void initState() {
    super.initState();
    for (final stream in [
      widget.player.stream.position,
      widget.player.stream.duration,
      widget.player.stream.buffer,
    ]) {
      _subscriptions.add(
        stream.listen((_) {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  @override
  void didUpdateWidget(PlayerTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) _value = null;
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.player.state.duration.inMilliseconds / 1000;
    final max = duration > 0 ? duration : 1.0;
    final active = widget.enabled && duration > 0;
    return Tooltip(
      message:
          '${formatPosition(_value ?? widget.player.state.position.inMilliseconds / 1000)} / ${formatPosition(duration)}',
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          padding: EdgeInsets.zero,
          trackHeight: 2,
          activeTrackColor: PlayerStyle.accent,
          thumbColor: Colors.white,
          inactiveTrackColor: Colors.white.withValues(alpha: .13),
          secondaryActiveTrackColor: Colors.white.withValues(alpha: .24),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 3),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
        ),
        child: Slider(
          key: const ValueKey('player-progress'),
          padding: EdgeInsets.zero,
          min: 0,
          max: max,
          value: (_value ?? widget.player.state.position.inMilliseconds / 1000)
              .clamp(0.0, max),
          secondaryTrackValue:
              (widget.player.state.buffer.inMilliseconds / 1000).clamp(
                0.0,
                max,
              ),
          semanticFormatterCallback: formatPosition,
          onChanged: active ? (value) => setState(() => _value = value) : null,
          onChangeEnd: active
              ? (value) {
                  unawaited(
                    widget.onSeek(
                      Duration(milliseconds: (value * 1000).round()),
                    ),
                  );
                  setState(() => _value = null);
                }
              : null,
        ),
      ),
    );
  }
}
