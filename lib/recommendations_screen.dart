import 'dart:async';

import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'local_store.dart';
import 'models.dart';
import 'playback_launch_screen.dart';
import 'widgets.dart';

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({
    super.key,
    required this.repository,
    required this.store,
    this.embedded = false,
    this.active = true,
  });
  final AppRepository repository;
  final LocalStore store;
  final bool embedded;
  final bool active;

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  final _scroll = ScrollController();
  static const _genre = 'feed';
  static const _pageSize = 10;
  int _visibleCount = _pageSize;
  bool _nextScheduled = false;
  List<Drama> _items = [];
  bool _loading = false;
  bool _more = false;
  bool _hasMore = true;
  bool _failedMore = false;
  String? _error;
  int _generation = 0;
  bool get _canLoadMore => _hasMore || _visibleCount < _items.length;

  @override
  void initState() {
    super.initState();
    widget.repository.catalogUpdates.addListener(_metadataChanged);
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    widget.repository.catalogUpdates.removeListener(_metadataChanged);
    unawaited(widget.repository.cancelRecommendations());
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _metadataChanged() {
    final drama = widget.repository.catalogUpdates.latest;
    if (!mounted || drama == null) return;
    setState(() {
      _items = [
        for (final item in _items)
          item.id == drama.id ? item.merge(drama) : item,
      ];
    });
  }

  Future<void> _load({bool more = false, bool force = false}) async {
    if (!widget.store.allowsSource('hongguo')) return;
    if (more && (_loading || _more || !_canLoadMore)) return;
    if (more && _visibleCount < _items.length) {
      setState(
        () =>
            _visibleCount = (_visibleCount + _pageSize).clamp(0, _items.length),
      );
      return;
    }
    final generation = ++_generation;
    final genre = _genre;
    setState(() {
      _loading = !more;
      _more = more;
      _error = null;
      _failedMore = more;
    });
    try {
      await widget.repository.cancelRecommendations();
      if (!mounted || generation != _generation) return;
      final page = await widget.repository.recommendations(
        genre,
        more: more,
        force: force,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page.items;
        _visibleCount = more ? _visibleCount + _pageSize : _pageSize;
        _hasMore = page.hasMore;
        _error = page.warning.isEmpty ? null : page.warning;
        _loading = _more = false;
      });
      if (!more && _scroll.hasClients) _scroll.jumpTo(0);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = _more = false;
        _error = error.toString();
      });
    }
  }

  void _onScroll() {
    if (!widget.active ||
        !_scroll.hasClients ||
        _scroll.position.pixels <= 0 ||
        _loading ||
        _more ||
        !_canLoadMore ||
        _error != null ||
        _nextScheduled ||
        _scroll.position.extentAfter > 600) {
      return;
    }
    _nextScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nextScheduled = false;
      if (mounted &&
          widget.active &&
          !_loading &&
          !_more &&
          _canLoadMore &&
          _error == null) {
        unawaited(_load(more: true));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final refresh = RefreshAction(
      loading: _loading || _more,
      tooltip: '刷新推荐',
      onPressed: () => _load(force: true),
    );
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '为你推荐',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              refresh,
            ],
          ),
        ),
        if (_loading && _items.isNotEmpty)
          const LinearProgressIndicator(minHeight: 2),
        if (_error != null && _items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _loading || _more
                      ? null
                      : () => _load(more: _failedMore, force: !_failedMore),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => RefreshIndicator(
              onRefresh: () => _load(force: true),
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (!widget.store.allowsSource('hongguo'))
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: StatusPanel(title: '内容暂不可用', message: '请先解锁当前用户。'),
                    )
                  else if (_loading && _items.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: StatusPanel(
                        title: _error == null ? '暂无推荐' : '推荐暂时无法加载',
                        message: _error ?? '下拉刷新可获取新的推荐。',
                        onRetry: () => _load(force: true),
                      ),
                    )
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverGrid(
                        gridDelegate: dramaGridDelegate(
                          context,
                          constraints.maxWidth - 32,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final drama = _items[index];
                          return DramaTile(
                            key: ValueKey(drama.id),
                            drama: drama,
                            repository: widget.repository,
                            onTap: () => unawaited(
                              openPlaybackDirectly(
                                context,
                                drama: drama,
                                repository: widget.repository,
                                store: widget.store,
                              ),
                            ),
                          );
                        }, childCount: _items.length.clamp(0, _visibleCount)),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: Center(
                          child: _more
                              ? const CircularProgressIndicator()
                              : _canLoadMore
                              ? OutlinedButton.icon(
                                  onPressed: () => _load(more: true),
                                  icon: const Icon(Icons.auto_awesome_rounded),
                                  label: const Text('继续推荐'),
                                )
                              : TextButton(
                                  onPressed: () => _load(force: true),
                                  child: const Text('本轮推荐已看完，刷新获取新推荐'),
                                ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('为你推荐'), actions: [refresh]),
      body: SafeArea(top: false, child: content),
    );
  }
}
