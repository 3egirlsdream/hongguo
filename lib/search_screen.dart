import 'dart:async';

import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'catalog_browser.dart';
import 'catalog_sort_sheet.dart';
import 'catalog_sort.dart';
import 'detail_screen.dart';
import 'playback_launch_screen.dart';
import 'local_store.dart';
import 'models.dart';
import 'widgets.dart';
import 'search_input.dart';
import 'catalog_management_screen.dart';
import 'batch_download_screen.dart';
import 'batch_downloads.dart';
import 'drama_actions.dart';
import 'library_updater.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.repository,
    required this.store,
    this.embedded = false,
    this.active = true,
    this.startSelecting = false,
    this.selectionMode,
  });

  final AppRepository repository;
  final LocalStore store;
  final bool embedded;
  final bool active;
  final bool startSelecting;
  final ValueNotifier<bool>? selectionMode;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Widget? _backgroundCache;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  List<Drama> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  int _generation = 0;
  String _submittedQuery = '';
  late final CatalogBrowser _browser;
  late final LibraryUpdater _updater;
  bool _cacheChanged = false;
  final _selectedDramas = <String, Drama>{};
  Timer? _cacheRefreshTimer;
  bool _refreshingUpdatedCache = false;
  late final ValueNotifier<bool> _selection;
  bool get _selectionMode => _selection.value;
  set _selectionMode(bool value) => _selection.value = value;
  bool _catalogLoadScheduled = false;

  bool get _onlineSearch => true;
  bool get _searchSuggestions => true;
  String get _searchHint => '搜索短剧';

  Future<void> _refreshCatalog() async {
    if (widget.repository.supportsSourceManagement) {
      if (_updater.busy('hongguo')) return;
      _pauseCatalog();
      await _updater.update();
      return;
    }
    if (mounted) await _load(force: true);
  }

  void _updateChanged() {
    if (mounted) setState(() {});
  }

  void _catalogUpdated(String source) {
    if (!mounted || source != 'hongguo') return;
    _cacheChanged = true;
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = Timer(const Duration(milliseconds: 100), () {
      unawaited(_reloadUpdatedCache());
    });
  }

  Future<void> _reloadUpdatedCache() async {
    if (_refreshingUpdatedCache) return;
    _refreshingUpdatedCache = true;
    final epoch = widget.store.profileEpoch;
    try {
      while (mounted && _cacheChanged && epoch == widget.store.profileEpoch) {
        _cacheChanged = false;
        final updates = <String, Drama>{};
        try {
          final cached = await widget.repository.cached('hongguo');
          for (final drama in cached.items) {
            if (widget.store.allowsSource(drama.source)) {
              updates[drama.id] = drama;
            }
          }
        } catch (error) {
          if (mounted && epoch == widget.store.profileEpoch) {
            setState(() => _error = '更新后读取缓存失败：$error');
          }
        }
        if (!mounted || epoch != widget.store.profileEpoch) return;
        _browser.updateDramas(updates.values);
        setState(() {
          _items = [
            for (final item in _items)
              updates[item.id] == null ? item : item.merge(updates[item.id]!),
          ];
          for (final id in _selectedDramas.keys.toList()) {
            if (updates[id] != null) {
              _selectedDramas[id] = _selectedDramas[id]!.merge(updates[id]!);
            }
          }
        });
        await saveUserChange(
          context,
          () => widget.store.refreshDramas(updates.values),
        );
        if (!mounted || epoch != widget.store.profileEpoch) return;
      }
    } finally {
      _refreshingUpdatedCache = false;
    }
  }

  Future<void> _manageSources() async {
    _pauseCatalog();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CatalogManagementScreen(
          repository: widget.repository,
          store: widget.store,
        ),
      ),
    );
    if (!mounted) return;
    if (mounted && (!_onlineSearch || _submittedQuery.isEmpty)) {
      await _load(useCache: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _selection =
        widget.selectionMode ??
        ValueNotifier(
          widget.startSelecting &&
              widget.store.canDownload &&
              widget.repository.supportsDownloads,
        );
    _scroll.addListener(_onCatalogScroll);
    _browser = CatalogBrowser(widget.repository);
    _updater = LibraryUpdater(
      widget.repository,
      widget.store,
      onCatalogChanged: _catalogUpdated,
    )..addListener(_updateChanged);
    _updater.startWatching();
    widget.repository.catalogUpdates.addListener(_metadataChanged);
    _loading = false;
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) {
      _pauseCatalog();
      _selectedDramas.clear();
    }
  }

  @override
  void dispose() {
    _updater.removeListener(_updateChanged);
    _updater.dispose();
    _cacheRefreshTimer?.cancel();
    widget.repository.catalogUpdates.removeListener(_metadataChanged);
    _generation++;
    unawaited(_browser.cancel());
    unawaited(widget.repository.cancelSuggestions());
    _debounce?.cancel();
    _search.dispose();
    _scroll.removeListener(_onCatalogScroll);
    _scroll.dispose();
    if (widget.selectionMode == null) _selection.dispose();
    super.dispose();
  }

  void _onCatalogScroll() {
    if (!mounted ||
        !widget.active ||
        ModalRoute.of(context)?.isCurrent == false ||
        !_hasMore ||
        _loading ||
        _loadingMore ||
        !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final threshold = (position.viewportDimension * 1.5).clamp(320.0, 900.0);
    if (position.extentAfter > threshold || _catalogLoadScheduled) return;
    _catalogLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _catalogLoadScheduled = false;
      if (!mounted ||
          !widget.active ||
          ModalRoute.of(context)?.isCurrent == false ||
          !_hasMore ||
          _loading ||
          _loadingMore ||
          !_scroll.hasClients) {
        return;
      }
      unawaited(_load(more: true));
    });
  }

  void _metadataChanged() {
    final drama = widget.repository.catalogUpdates.latest;
    if (!mounted || drama == null || !widget.store.allowsSource(drama.source)) {
      return;
    }
    _browser.updateDrama(drama);
    setState(() {
      _items = [
        for (final item in _items)
          item.id == drama.id ? item.merge(drama) : item,
      ];
    });
    unawaited(saveUserChange(context, () => widget.store.refreshDrama(drama)));
  }

  Future<void> _load({
    bool more = false,
    bool useCache = false,
    bool force = false,
    bool cacheOnly = false,
  }) async {
    if (more && (_loading || _loadingMore || !_hasMore)) return;
    final generation = ++_generation;
    final query = _onlineSearch ? _search.text.trim() : '';
    if (query.isEmpty) {
      setState(() {
        _items = [];
        _submittedQuery = '';
        _hasMore = _loading = _loadingMore = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _error = null;
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _loadingMore = false;
        if (query != _submittedQuery) _items = [];
      }
    });
    void accept(CatalogPage result, {bool cached = false}) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = result.items;
        _hasMore = result.hasMore;
        _submittedQuery = query;
        _loading = cached && !result.fresh;
        _loadingMore = false;
        _error = result.warning.isEmpty ? null : result.warning;
      });
      unawaited(
        saveUserChange(context, () => widget.store.refreshDramas(result.items)),
      );
    }

    try {
      final result = await _browser.load(
        query: query,
        more: more,
        useCache: useCache,
        force: force,
        cacheOnly: cacheOnly,
        onCached: (result) => accept(result, cached: true),
      );
      accept(result);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  void _searchChanged(String query) {
    _debounce?.cancel();
    _selectedDramas.clear();
    if (_onlineSearch && (_loading || _loadingMore)) {
      _generation++;
      unawaited(_browser.cancel());
      _loading = _loadingMore = false;
    }
    setState(() {});
    if (_onlineSearch && query.trim().isEmpty) {
      unawaited(_load());
    }
  }

  void _submitSearch(String query) {
    _selectedDramas.clear();
    _search.text = query.trim();
    _debounce?.cancel();
    if (_search.text.isNotEmpty) {
      unawaited(
        saveUserChange(
          context,
          () => widget.store.rememberSearch(_search.text),
        ),
      );
    }
    if (_onlineSearch) {
      _load();
    } else {
      setState(() {});
    }
  }

  Future<void> _chooseCatalogView() async {
    final selected = await chooseCatalogView(context, widget.store.catalogView);
    if (selected != null && mounted) {
      await saveUserChange(
        context,
        () => widget.store.setCatalogView(selected),
      );
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  void _openDrama(Drama drama, {bool resume = false, bool download = false}) {
    _pauseCatalog();
    if (download) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DetailScreen(
            drama: drama,
            repository: widget.repository,
            store: widget.store,
            downloadOnOpen: true,
          ),
        ),
      );
      return;
    }
    unawaited(
      openPlaybackDirectly(
        context,
        drama: drama,
        repository: widget.repository,
        store: widget.store,
      ),
    );
  }

  void _cancelSelection() => setState(() {
    _selectionMode = false;
    _selectedDramas.clear();
  });

  void _selectDrama(Drama drama) {
    if (!widget.store.canDownload ||
        !widget.repository.supportsDownloads ||
        !widget.store.allowsSource(drama.source)) {
      return;
    }
    if (!_selectedDramas.containsKey(drama.id) &&
        _selectedDramas.length >= BatchDownloads.maxDramas) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('一次最多选择 50 部短剧，请分批下载')));
      return;
    }
    setState(() {
      _selectionMode = true;
      if (_selectedDramas.remove(drama.id) == null) {
        _selectedDramas[drama.id] = drama;
      }
    });
  }

  void _downloadSelected() {
    if (!widget.store.canDownload || _selectedDramas.isEmpty) return;
    _pauseCatalog();
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BatchDownloadScreen(
          repository: widget.repository,
          store: widget.store,
          dramas: _selectedDramas.values.toList(),
        ),
      ),
    );
  }

  void _dramaActions(Drama drama) => showDramaActions(
    context,
    drama: drama,
    store: widget.store,
    repository: widget.repository,
    onContinue: () => _openDrama(drama, resume: true),
    onDownload: widget.repository.supportsDownloads && widget.store.canDownload
        ? () => _openDrama(drama, download: true)
        : null,
    onSelect: widget.repository.supportsDownloads && widget.store.canDownload
        ? () => _selectDrama(drama)
        : null,
  );

  Widget _catalogTile(Drama drama) {
    final following = widget.store.following(drama.id);
    final canSelect =
        widget.store.canDownload && widget.repository.supportsDownloads;
    return DramaTile(
      key: ValueKey(drama.id),
      drama: drama,
      repository: widget.repository,
      onTap: () => _selectionMode ? _selectDrama(drama) : _openDrama(drama),
      onLongPress: canSelect ? () => _selectDrama(drama) : null,
      onMore: () => _dramaActions(drama),
      actions: DramaActionButton(
        drama: drama,
        onPressed: () => _dramaActions(drama),
      ),
      selected: _selectionMode ? _selectedDramas.containsKey(drama.id) : null,
      badge: following == null
          ? null
          : '${following.status.label}${following.hasUpdates ? ' · ${following.updateLabel}' : ''}',
    );
  }

  void _pauseCatalog() {
    _debounce?.cancel();
    _generation++;
    unawaited(_browser.cancel());
    unawaited(widget.repository.cancelSuggestions());
    setState(() {
      _loading = false;
      _loadingMore = false;
    });
  }

  List<Drama> get _visible {
    final query = _search.text.trim().toLowerCase();
    return sortCatalog(
      _items.where((drama) {
        if (!widget.store.allowsSource(drama.source)) return false;
        return _onlineSearch ||
            query.isEmpty ||
            matchesDramaQuery(drama, query);
      }),
      widget.store.catalogView,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.store, _selection]),
    builder: (context, _) {
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent && _backgroundCache != null) {
        return _backgroundCache!;
      }
      final selecting = _selectionMode;
      final content = _catalog(selectionInBody: true);
      final child = PopScope<void>(
        canPop: !widget.active || !selecting,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop &&
              widget.active &&
              selecting &&
              ModalRoute.of(context)?.isCurrent != false) {
            _cancelSelection();
          }
        },
        child: widget.embedded
            ? content
            : Scaffold(
                appBar: AppBar(title: Text(selecting ? '批量下载' : '搜索')),
                body: SafeArea(top: false, bottom: false, child: content),
              ),
      );
      _backgroundCache = child;
      return child;
    },
  );

  Widget _catalog({required bool selectionInBody}) {
    final items = _visible;
    return Column(
      children: [
        if (_updater.busy('hongguo'))
          const LinearProgressIndicator(minHeight: 2),
        if (_selectionMode)
          Row(
            children: [
              const SizedBox(width: 16),
              const Expanded(child: Text('选择要下载的短剧')),
              TextButton(
                onPressed: () => setState(_selectedDramas.clear),
                child: const Text('清空'),
              ),
              TextButton(onPressed: _cancelSelection, child: const Text('取消')),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: SearchInput(
                  key: ValueKey('search-catalog'),
                  controller: _search,
                  autofocus: false,
                  hint: _searchHint,
                  suggestions: _searchSuggestions
                      ? widget.repository.suggestions
                      : null,
                  onChanged: _searchChanged,
                  onCancel: () =>
                      unawaited(widget.repository.cancelSuggestions()),
                  onSearch: _submitSearch,
                ),
              ),
              IconButton(
                tooltip: '排序与筛选',
                onPressed: _chooseCatalogView,
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
        ),
        if (_search.text.trim().isEmpty &&
            widget.store.recentSearches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final query in widget.store.recentSearches)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              avatar: const Icon(
                                Icons.history_rounded,
                                size: 16,
                              ),
                              label: Text(query),
                              onPressed: () => _submitSearch(query),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '清空最近搜索',
                  onPressed: () =>
                      saveUserChange(context, widget.store.clearRecentSearches),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
              ],
            ),
          ),
        ...[
          if (_loading && _items.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: GestureDetector(
              child: _loading && _items.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 18),
                          Text('正在加载剧集'),
                        ],
                      ),
                    )
                  : _items.isEmpty && _error != null
                  ? StatusPanel(
                      title: '暂时无法加载',
                      message: _error!,
                      onRetry: () => _load(force: true),
                      secondaryAction:
                          widget.repository.supportsSourceManagement
                          ? TextButton(
                              onPressed: _manageSources,
                              child: const Text('连接诊断'),
                            )
                          : null,
                      icon: Icons.wifi_off_rounded,
                    )
                  : items.isEmpty
                  ? StatusPanel(
                      title: _search.text.trim().isEmpty ? '搜索短剧' : '没有找到匹配的短剧',
                      message: _search.text.trim().isEmpty
                          ? '输入剧名开始搜索，或选择最近搜索。'
                          : '可以换个搜索词，或刷新后重试。',
                      onRetry: _hasMore && !_loadingMore && _search.text.isEmpty
                          ? () => _load(more: true)
                          : null,
                      action: '加载更多',
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final padding = constraints.maxWidth < 600
                            ? 16.0
                            : 24.0;
                        return RefreshIndicator(
                          onRefresh: _refreshCatalog,
                          child: CustomScrollView(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  padding,
                                  0,
                                  padding,
                                  16 + MediaQuery.paddingOf(context).bottom,
                                ),
                                sliver: SliverGrid(
                                  gridDelegate: dramaGridDelegate(
                                    context,
                                    constraints.maxWidth - 2 * padding,
                                  ),
                                  delegate: SliverChildBuilderDelegate(
                                    (_, index) => _catalogTile(items[index]),
                                    childCount: items.length,
                                  ),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom:
                                        24 +
                                        MediaQuery.paddingOf(context).bottom,
                                  ),
                                  child: Center(
                                    child: _loadingMore
                                        ? const CircularProgressIndicator()
                                        : _hasMore
                                        ? OutlinedButton.icon(
                                            onPressed: () => _load(more: true),
                                            icon: const Icon(
                                              Icons.expand_more_rounded,
                                            ),
                                            label: const Text('加载更多'),
                                          )
                                        : Text(
                                            '已经看到这里的全部剧集',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              fontSize: 12,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          if (_selectionMode && selectionInBody) _selectionBar(),
        ],
      ],
    );
  }

  Widget _selectionBar({bool safeBottom = true}) {
    final theme = Theme.of(context);
    final count = _selectedDramas.length;
    return Material(
      color: theme.colorScheme.surface,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: safeBottom,
          minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final summary = Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 0 ? '点选要下载的短剧' : '已选 $count 部',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count == 0
                          ? '最多 ${BatchDownloads.maxDramas} 部'
                          : '下一步选择分集和画质',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
              final next = FilledButton(
                key: const ValueKey('download-selected-dramas'),
                onPressed: count == 0 ? null : _downloadSelected,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(96, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: const Text('下一步'),
              );
              if (constraints.maxWidth < 320 ||
                  MediaQuery.textScalerOf(context).scale(14) > 21) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [summary, const SizedBox(height: 12), next],
                );
              }
              return Row(
                children: [
                  Expanded(child: summary),
                  const SizedBox(width: 16),
                  next,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
