import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'detail_screen.dart';
import 'drama_list_card.dart';
import 'local_store.dart';
import 'ranking_models.dart';
import 'widgets.dart';

class RankingsScreen extends StatefulWidget {
  const RankingsScreen({
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

  static ThemeData themeOf(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme.copyWith(
      primary: dark ? const Color(0xFFFF8875) : const Color(0xFFBD321F),
      surface: dark ? theme.colorScheme.surface : const Color(0xFFFAFAF9),
      onSurface: dark ? theme.colorScheme.onSurface : const Color(0xFF111116),
      onSurfaceVariant: dark
          ? theme.colorScheme.onSurfaceVariant
          : const Color(0xFF666666),
      outlineVariant: dark
          ? theme.colorScheme.outlineVariant
          : const Color(0xFFE4E4E4),
    );
    return theme.copyWith(
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      textTheme: theme.textTheme.apply(
        bodyColor: colors.onSurface,
        displayColor: colors.onSurface,
      ),
    );
  }

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  final _scroll = ScrollController();
  List<RankingBoard> _boards = [];
  RankingBoard? _board;
  List<RankingItem> _items = [];
  bool _loading = true;
  bool _more = false;
  bool _hasMore = false;
  bool _failedMore = false;
  int _page = 1;
  int _generation = 0;
  String? _error;
  String _updated = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    widget.repository.catalogUpdates.addListener(_metadataChanged);
    _initialize();
  }

  @override
  void dispose() {
    widget.repository.catalogUpdates.removeListener(_metadataChanged);
    _generation++;
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted ||
        !widget.active ||
        !_hasMore ||
        _loading ||
        _more ||
        !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final threshold = (position.viewportDimension * 1.2).clamp(260.0, 720.0);
    if (position.extentAfter <= threshold) {
      _load(more: true);
    }
  }

  void _metadataChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final boards = (await widget.repository.rankingBoards())
          .where((board) => widget.store.allowsSource(board.source))
          .toList();
      if (!mounted || generation != _generation) return;
      setState(() {
        _boards = boards;
        _board = boards.firstOrNull;
        _loading = false;
      });
      if (_board != null) await _load();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _load({bool more = false, bool force = false}) async {
    final board = _board;
    if (board == null || more && (_loading || _more || !_hasMore)) return;
    final generation = ++_generation;
    setState(() {
      _loading = !more;
      _more = more;
      _error = null;
      _failedMore = false;
    });
    try {
      final result = await widget.repository.rankings(
        board.id,
        page: more ? _page + 1 : 1,
        force: force,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final rows = <String, RankingItem>{
          if (more)
            for (final item in _items) item.drama.id: item,
          for (final item in result.items) item.drama.id: item,
        };
        _items = rows.values.toList()..sort((a, b) => a.rank.compareTo(b.rank));
        _page = result.page;
        _hasMore = result.hasMore;
        _updated = result.updatedText;
        _error = result.warning.isEmpty ? null : result.warning;
        _loading = false;
        _more = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error.toString();
          _failedMore = more;
          _loading = false;
          _more = false;
        });
      }
    }
  }

  void _select(RankingBoard board) {
    if (_board?.id == board.id) return;
    setState(() {
      _board = board;
      _items = [];
      _updated = '';
      _page = 1;
      _hasMore = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final boards = _boards;
    final items = _items
        .map(
          (item) => RankingItem(
            item.rank,
            widget.repository.catalogUpdates.current(item.drama),
            metric: item.metric,
          ),
        )
        .where((item) => widget.store.allowsSource(item.drama.source))
        .toList();
    return Theme(
      data: RankingsScreen.themeOf(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final colors = Theme.of(context).colorScheme;
          final scale = (constraints.maxWidth / 393).clamp(.8, 1.25);
          final inset = 19 * scale;
          return Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: !widget.embedded,
              toolbarHeight: 72 * scale,
              titleSpacing: inset,
              backgroundColor: colors.surface,
              foregroundColor: colors.onSurface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: Text(
                '排行榜',
                style: TextStyle(
                  fontSize: 28 * scale,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              actions: [
                Padding(
                  padding: EdgeInsets.only(right: 12 * scale),
                  child: IconTheme(
                    data: IconThemeData(
                      size: 24 * scale,
                      color: colors.onSurface,
                    ),
                    child: RefreshAction(
                      loading: _loading || _more,
                      tooltip: '更新榜单',
                      onPressed: _board == null
                          ? _initialize
                          : () => _load(force: true),
                    ),
                  ),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Column(
                children: [
                  if (boards.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: inset),
                      child: _RankingTabs(
                        boards: boards,
                        selected: _board?.id,
                        scale: scale,
                        onSelected: _select,
                      ),
                    ),
                  if (_board != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(inset, 11 * scale, inset, 0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _board!.description
                                      .replaceAll('；', ' · ')
                                      .replaceAll('。', '')
                                      .trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12 * scale,
                                    height: 1.35,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (_updated.trim().isNotEmpty) ...[
                                SizedBox(width: 10 * scale),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth * .32,
                                  ),
                                  child: Text(
                                    _updated.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 12 * scale,
                                      height: 1.35,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          SizedBox(height: 11 * scale),
                          Divider(
                            height: 1,
                            thickness: .7,
                            color: colors.outlineVariant,
                          ),
                        ],
                      ),
                    ),
                  if (_loading && items.isNotEmpty)
                    const LinearProgressIndicator(minHeight: 2),
                  if (_error != null && items.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: inset),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _error!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                          TextButton(
                            onPressed: _loading || _more
                                ? null
                                : () => _load(more: _failedMore, force: true),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _loading && items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: EdgeInsets.all(inset),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  if (_board?.source == 'hongguo') ...[
                                    const SizedBox(height: 16),
                                    const Text(
                                      '正在获取榜单，数据未完整返回时会自动重试',
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : items.isEmpty
                        ? StatusPanel(
                            title: _error == null ? '暂无榜单内容' : '榜单暂时无法加载',
                            message: _error ?? '暂无可显示的榜单。',
                            onRetry: _board == null
                                ? _initialize
                                : () => _load(force: true),
                          )
                        : RefreshIndicator(
                            onRefresh: () => _load(force: true),
                            child: ListView.separated(
                              key: ValueKey('ranking-${_board!.id}'),
                              controller: _scroll,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(
                                inset,
                                0,
                                inset,
                                16 * scale,
                              ),
                              itemCount: items.length + 1,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                thickness: .7,
                                color: colors.outlineVariant,
                              ),
                              itemBuilder: (context, index) {
                                if (index == items.length) {
                                  return Center(
                                    child: _more
                                        ? const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: CircularProgressIndicator(),
                                          )
                                        : _hasMore
                                        ? TextButton(
                                            onPressed: () => _load(more: true),
                                            child: const Text('加载更多'),
                                          )
                                        : Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Text(
                                              '已显示全部榜单',
                                              style: TextStyle(
                                                color: colors.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                  );
                                }
                                final item = items[index];
                                return _RankingCard(
                                  key: ValueKey(item.drama.id),
                                  item: item,
                                  repository: widget.repository,
                                  scale: scale,
                                  onTap: () => Navigator.push<void>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DetailScreen(
                                        drama: item.drama,
                                        repository: widget.repository,
                                        store: widget.store,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RankingTabs extends StatelessWidget {
  const _RankingTabs({
    required this.boards,
    required this.selected,
    required this.scale,
    required this.onSelected,
  });

  final List<RankingBoard> boards;
  final String? selected;
  final double scale;
  final ValueChanged<RankingBoard> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 35 * scale,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth =
              (constraints.maxWidth - (boards.length - 1) * 8 * scale) /
              boards.length;
          return Row(
            children: [
              for (final (index, board) in boards.indexed) ...[
                if (index > 0)
                  Expanded(
                    child: Center(
                      child: SizedBox(
                        height: 15 * scale,
                        child: VerticalDivider(
                          width: 1,
                          thickness: .7,
                          color: colors.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                Semantics(
                  button: true,
                  selected: board.id == selected,
                  child: InkWell(
                    key: ValueKey('category-${board.id}'),
                    onTap: () => onSelected(board),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: tabWidth),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                        child: IntrinsicWidth(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Center(
                                  child: Text(
                                    board.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15 * scale,
                                      height: 1.3,
                                      fontWeight: board.id == selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: board.id == selected
                                          ? colors.primary
                                          : colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                height: 2 * scale,
                                decoration: BoxDecoration(
                                  color: board.id == selected
                                      ? colors.primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    super.key,
    required this.item,
    required this.repository,
    required this.scale,
    required this.onTap,
  });

  final RankingItem item;
  final AppRepository repository;
  final double scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DramaListCard(
    key: ValueKey('rank-${item.rank}-${item.drama.id}'),
    drama: item.drama,
    repository: repository,
    scale: scale,
    heading: '第 ${item.rank} 名',
    metric: item.metric,
    onTap: onTap,
  );
}
