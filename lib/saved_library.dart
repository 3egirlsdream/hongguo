import 'package:flutter/material.dart';

import 'catalog_sort.dart';
import 'core_bridge.dart';
import 'drama_actions.dart';
import 'follow_state.dart';
import 'local_store.dart';
import 'models.dart';
import 'widgets.dart';

class SavedLibrary extends StatefulWidget {
  const SavedLibrary({
    super.key,
    required this.repository,
    required this.store,
    required this.history,
    required this.onOpen,
    required this.onContinue,
    this.onDownload,
    this.remoteHistory = const [],
    this.remoteFavorites = const [],
    this.onHistoryContinue,
    this.onRemoteUnfollow,
    this.compact = false,
    this.searchVisible,
    this.filterOptions,
    this.filterValue,
    this.onFilterChanged,
    this.onManage,
    this.subtitle,
    this.onLoadMore,
    this.hasMore = false,
    this.loadingMore = false,
  });

  final AppRepository repository;
  final LocalStore store;
  final bool history;
  final bool compact;
  final bool? searchVisible;
  final List<(String, String)>? filterOptions;
  final String? filterValue;
  final ValueChanged<String>? onFilterChanged;
  final ValueChanged<Drama>? onManage;
  final String Function(Drama)? subtitle;
  final VoidCallback? onLoadMore;
  final bool hasMore, loadingMore;
  final List<WatchEntry> remoteHistory;
  final List<Drama> remoteFavorites;
  final ValueChanged<WatchEntry>? onHistoryContinue;
  final ValueChanged<Drama>? onRemoteUnfollow;
  final ValueChanged<Drama> onOpen;
  final ValueChanged<Drama> onContinue;
  final ValueChanged<Drama>? onDownload;

  @override
  State<SavedLibrary> createState() => _SavedLibraryState();
}

class _SavedLibraryState extends State<SavedLibrary> {
  final _search = TextEditingController();
  String _filter = '';
  String _completion = '';
  bool _searchVisible = false, _editing = false;
  Map<String, WatchEntry> _historyIndex = {};
  String get _selectedFilter =>
      widget.filterValue ?? (widget.history ? _completion : _filter);
  void _selectFilter(String value) {
    if (widget.onFilterChanged != null) {
      widget.onFilterChanged!(value);
    } else {
      setState(() {
        if (widget.history) {
          _completion = value;
        } else {
          _filter = value;
        }
      });
    }
  }

  List<(String, String)> get _filters =>
      widget.filterOptions ??
      (widget.history
          ? const [('', '全部'), ('finished', '已看完'), ('unfinished', '未看完')]
          : const [
              ('', '全部'),
              ('planned', '想看'),
              ('watching', '在看'),
              ('watched', '已看'),
              ('updates', '有更新'),
            ]);

  @override
  void didUpdateWidget(covariant SavedLibrary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchVisible == true && widget.searchVisible == false) {
      _search.clear();
    }
  }

  Future<void> _chooseFilter() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                widget.filterOptions != null
                    ? '筛选预约'
                    : widget.history
                    ? '筛选观看记录'
                    : '筛选追剧',
              ),
            ),
            for (final filter in _filters)
              ListTile(
                title: Text(filter.$2),
                selected: _selectedFilter == filter.$1,
                trailing: _selectedFilter == filter.$1
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, filter.$1),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    _selectFilter(selected);
  }

  List<WatchEntry> get _history {
    final rows = <String, WatchEntry>{};
    for (final entry in [...widget.store.history, ...widget.remoteHistory]) {
      final old = rows[entry.drama.id];
      final chosen = old == null || entry.updatedAt.isAfter(old.updatedAt)
          ? entry
          : old;
      rows[entry.drama.id] = WatchEntry(
        drama: old?.drama.merge(entry.drama) ?? entry.drama,
        episode: chosen.episode,
        videoId: chosen.videoId,
        position: chosen.position,
        duration: chosen.duration,
        updatedAt: chosen.updatedAt,
      );
    }
    return rows.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  WatchEntry? _watched(String id) => _historyIndex[id];
  void _continue(Drama drama) {
    final entry = _watched(drama.id);
    if (entry != null && widget.onHistoryContinue != null) {
      widget.onHistoryContinue!(entry);
    } else {
      widget.onContinue(drama);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _clearHistory() async {
    final epoch = widget.store.profileEpoch;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空观看记录？'),
        content: const Text('仅清空本机观看记录，账号云端记录会保留。追剧状态和手动已看标记不变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted && epoch == widget.store.profileEpoch) {
      await saveUserChange(context, widget.store.clearHistory);
    }
  }

  void _actions(Drama drama) {
    if (widget.onManage != null) {
      widget.onManage!(drama);
      return;
    }
    showDramaActions(
      context,
      drama: drama,
      store: widget.store,
      repository: widget.repository,
      history: widget.history,
      onContinue: () => _continue(drama),
      remoteFollowed: widget.remoteFavorites.any((d) => d.id == drama.id),
      onToggleFollow:
          widget.remoteFavorites.any((d) => d.id == drama.id) &&
              widget.onRemoteUnfollow != null
          ? () => widget.onRemoteUnfollow!(drama)
          : null,
      onDownload: widget.onDownload == null
          ? null
          : () => widget.onDownload!(drama),
    );
  }

  Widget _tile(Drama drama) {
    final watched = _watched(drama.id);
    final state = widget.store.following(drama.id);
    final badge = state == null
        ? null
        : '${state.label}${state.hasUpdates ? ' · ${state.updateLabel}' : ''}';
    return DramaTile(
      key: ValueKey('saved-${drama.id}'),
      drama: drama,
      repository: widget.repository,
      onTap: () => widget.history ? _continue(drama) : widget.onOpen(drama),
      onMore: () => _actions(drama),
      actions: DramaActionButton(
        drama: drama,
        onPressed: () => _actions(drama),
      ),
      badge:
          badge ??
          (widget.remoteFavorites.any((d) => d.id == drama.id) ? '已追剧' : null),
      subtitle: watched == null
          ? '点击开始观看'
          : '第 ${watched.episode} 集 · ${formatPosition(watched.position)}',
    );
  }

  bool _completed(WatchEntry? entry) =>
      entry != null &&
      entry.finished &&
      entry.drama.episodes > 0 &&
      entry.episode >= entry.drama.episodes;

  Widget _poster(Drama drama) {
    final watched = _watched(drama.id);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editing
            ? _actions(drama)
            : widget.history
            ? _continue(drama)
            : widget.onOpen(drama),
        onLongPress: () => _actions(drama),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (DramaCover.imagesDisabled)
                      ColoredBox(
                        color: colors.surfaceContainerHighest,
                        child: Icon(
                          Icons.movie_outlined,
                          color: colors.onSurfaceVariant,
                        ),
                      )
                    else
                      CachedCoverImage(
                        key: ValueKey('${drama.id}\u0000${drama.cover}'),
                        drama: drama,
                        repository: widget.repository,
                        placeholder: ColoredBox(
                          color: colors.surfaceContainerHighest,
                          child: Icon(
                            Icons.movie_outlined,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (drama.category.isNotEmpty)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            drama.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    if (_editing)
                      const Positioned(
                        bottom: 6,
                        right: 6,
                        child: CircleAvatar(
                          radius: 14,
                          child: Icon(Icons.more_horiz, size: 18),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              drama.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              widget.subtitle?.call(drama) ??
                  (watched == null
                      ? (drama.episodes > 0 ? '共${drama.episodes}集' : '点击观看')
                      : '${watched.episode}集/${drama.episodes > 0 ? '${drama.episodes}集' : '连载中'}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactToolbar() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 6,
                children: [
                  for (final filter in _filters)
                    ChoiceChip(
                      label: Text(filter.$2),
                      showCheckmark: false,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      labelPadding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? colors.surfaceContainerLow
                          : const Color(0xFFF7F7F7),
                      selectedColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF4A3020)
                          : const Color(0xFFFFF1E3),
                      labelStyle: TextStyle(
                        fontSize: 14,
                        height: 1.2,
                        color: _selectedFilter == filter.$1
                            ? const Color(0xFFF47925)
                            : colors.onSurfaceVariant.withValues(alpha: .7),
                      ),
                      selected: _selectedFilter == filter.$1,
                      onSelected: (_) => _selectFilter(filter.$1),
                    ),
                ],
              ),
            ),
          ),
          if (widget.searchVisible == null)
            IconButton(
              tooltip: '搜索片单',
              icon: const Icon(Icons.search_rounded, size: 20),
              onPressed: () => setState(() {
                _searchVisible = !_searchVisible;
                if (!_searchVisible) _search.clear();
              }),
            ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: colors.onSurface,
              minimumSize: const Size(40, 34),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            onPressed: _chooseFilter,
            child: const Text('筛选'),
          ),
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            color: colors.outlineVariant,
          ),
          PopupMenuButton<String>(
            tooltip: '编辑片单',
            onSelected: (action) {
              if (action == 'clear') {
                _clearHistory();
              } else {
                setState(() => _editing = !_editing);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(_editing ? '完成编辑' : '编辑片单'),
              ),
              if (widget.history && widget.store.history.isNotEmpty)
                const PopupMenuItem(value: 'clear', child: Text('清空本机历史')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text(
                _editing ? '完成' : '编辑',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final history = _history;
      _historyIndex = {for (final entry in history) entry.drama.id: entry};
      final all = widget.history
          ? history.map((entry) => entry.drama).toList()
          : {
              for (final drama in widget.remoteFavorites) drama.id: drama,
              if (widget.filterOptions == null)
                for (final drama in widget.store.favorites) drama.id: drama,
            }.values.toList();
      final items = all.where((drama) {
        if (!matchesDramaQuery(drama, _search.text)) return false;
        if (widget.filterOptions != null) return true;
        final state = widget.store.following(drama.id);
        if (widget.history) {
          return _completion.isEmpty ||
              (_completion == 'finished') == _completed(_watched(drama.id));
        }
        return _filter.isEmpty ||
            (_filter == 'updates'
                ? state?.hasUpdates == true
                : state?.status.name == _filter);
      }).toList();
      final ids = items.map((drama) => drama.id).toSet();
      final resume = history
          .where(
            (entry) =>
                ids.contains(entry.drama.id) &&
                (!entry.finished ||
                    entry.drama.episodes <= 0 ||
                    entry.episode < entry.drama.episodes),
          )
          .firstOrNull;
      final header = [
        if (!widget.compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.history ? '最近观看' : '我的追剧'} · ${all.length}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (widget.history && widget.store.history.isNotEmpty)
                  IconButton(
                    tooltip: '清空本机记录',
                    onPressed: _clearHistory,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
          ),
        if (!widget.compact || (widget.searchVisible ?? _searchVisible))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: ValueKey(
                widget.history ? 'history-search' : 'favorites-search',
              ),
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.filterOptions != null
                    ? '搜索预约'
                    : widget.history
                    ? '搜索观看记录'
                    : '搜索追剧',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空搜索',
                        onPressed: () => setState(_search.clear),
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
        if (!widget.history && !widget.compact)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                for (final filter in [
                  ('', '全部'),
                  for (final status in FollowStatus.values)
                    (status.name, status.label),
                  ('updates', '有更新'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('follow-filter-${filter.$1}'),
                      label: Text(filter.$2),
                      selected: _filter == filter.$1,
                      onSelected: (_) => setState(() => _filter = filter.$1),
                    ),
                  ),
              ],
            ),
          ),
        if (resume != null && !widget.compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                key: const ValueKey('continue-watching'),
                leading: const Icon(Icons.play_circle_outline),
                title: Text(
                  '继续观看 · ${resume.drama.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '第 ${resume.episode} 集 · ${formatPosition(resume.position)}',
                ),
                onTap: () => _continue(resume.drama),
              ),
            ),
          ),
      ];
      if (widget.compact) {
        header.insert(0, _compactToolbar());
      }
      final empty = StatusPanel(
        title: all.isEmpty
            ? widget.filterOptions != null
                  ? '暂无预约记录'
                  : widget.history
                  ? '还没有观看记录'
                  : '还没有追剧'
            : '没有匹配的记录',
        message: all.isEmpty ? '去首页，挑一部喜欢的短剧。' : '可以更换搜索词或筛选条件。',
        icon: widget.history
            ? Icons.history_rounded
            : Icons.bookmark_border_rounded,
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          final padding = constraints.maxWidth < 600 ? 16.0 : 24.0;
          final columns = constraints.maxWidth < 340
              ? 2
              : ((constraints.maxWidth - 2 * padding) / 180).floor().clamp(
                  3,
                  6,
                );
          final tileWidth =
              (constraints.maxWidth -
                  2 * padding -
                  (columns - 1) * (widget.compact ? 8 : 12)) /
              columns;
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            key: PageStorageKey(
              'saved-${widget.history}-$_filter-$_completion-${_search.text}',
            ),
            slivers: [
              SliverToBoxAdapter(child: Column(children: header)),
              if (items.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: empty)
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 0, padding, 20),
                  sliver: SliverGrid(
                    gridDelegate: widget.compact
                        ? SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 18,
                            mainAxisExtent:
                                tileWidth / .72 +
                                16 +
                                MediaQuery.textScalerOf(context).scale(36),
                          )
                        : dramaGridDelegate(
                            context,
                            constraints.maxWidth - 2 * padding,
                          ),
                    delegate: SliverChildBuilderDelegate(
                      (_, index) => widget.compact
                          ? _poster(items[index])
                          : _tile(items[index]),
                      childCount: items.length,
                    ),
                  ),
                ),
              if (widget.onLoadMore != null &&
                  (widget.hasMore || widget.loadingMore))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: widget.loadingMore
                          ? const CircularProgressIndicator()
                          : TextButton(
                              onPressed: widget.onLoadMore,
                              child: const Text('加载更多'),
                            ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}
