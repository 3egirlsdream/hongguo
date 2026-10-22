import 'core_bridge.dart';
import 'models.dart';

String categoryName(String name) {
  final compact = name.trim().replaceAll(RegExp(r'\s+'), '');
  return switch (compact) {
    'AI成人短剧' || 'AI短剧' => 'AI 短剧',
    'AI成人漫剧' || 'AI漫剧' => 'AI 漫剧',
    'AI换脸' => 'AI 换脸',
    'AI魔改' => 'AI 魔改',
    'AI剧' => 'AI 剧',
    '' => '未分类',
    _ => name.trim(),
  };
}

class _CatalogEntry {
  List<Drama> items = [];
  int page = 0;
  int nextPage = 1;
  bool hasMore = true;
  bool fresh = false;
}

class CatalogBrowser {
  CatalogBrowser(this.repository);
  final AppRepository repository;
  static const _source = 'hongguo';
  final _library = <String, Drama>{};
  final _sessions = <String, _CatalogEntry>{};
  List<CatalogCategory> _menus = [];
  int _generation = 0;

  Future<void> cancel() {
    _generation++;
    return repository.cancelCatalog();
  }

  void _remember(Iterable<Drama> items) {
    for (final drama in items) {
      if (drama.source == _source) {
        _library[drama.id] = _library[drama.id]?.merge(drama) ?? drama;
      }
    }
  }

  void updateDrama(Drama drama) => updateDramas([drama]);
  void updateDramas(Iterable<Drama> dramas) {
    final updates = {for (final drama in dramas) drama.id: drama};
    for (final entry in _sessions.values) {
      entry.items = [
        for (final item in entry.items)
          updates[item.id] == null ? item : item.merge(updates[item.id]!),
      ];
    }
    for (final drama in updates.values) {
      if (_library.containsKey(drama.id)) {
        _library[drama.id] = _library[drama.id]!.merge(drama);
      }
    }
  }

  Future<String?> loadCategories({
    bool force = false,
    bool cacheOnly = false,
  }) async {
    try {
      _remember((await repository.cached(_source)).items);
    } catch (_) {}
    if (cacheOnly) return null;
    try {
      _menus = await repository.categories(_source, force: force);
      return null;
    } catch (_) {
      return '分类暂未加载，点击重试';
    }
  }

  List<CatalogCategory> categories() {
    final rows = <String, CatalogCategory>{};
    for (final menu in _menus) {
      if (menu.id.isEmpty) continue;
      final name = categoryName(menu.name);
      rows[name] = CatalogCategory('category:$name', name);
    }
    final names =
        _library.values
            .map((drama) => categoryName(drama.category))
            .toSet()
            .toList()
          ..sort();
    for (final name in names) {
      rows.putIfAbsent(
        name,
        () => CatalogCategory('local:$name', name, local: true),
      );
    }
    return [CatalogCategory.all, ...rows.values];
  }

  Future<CatalogPage> load({
    String category = '',
    String query = '',
    bool more = false,
    bool force = false,
    bool useCache = false,
    bool cacheOnly = false,
    void Function(CatalogPage)? onCached,
  }) async {
    if (cacheOnly && (more || force || query.trim().isNotEmpty)) {
      throw AppFailure('缓存读取不能同时请求搜索或续页');
    }
    final generation = ++_generation;
    await repository.cancelCatalog();
    if (generation != _generation) throw AppFailure('已取消加载');
    final choice = query.isEmpty
        ? categories().where((c) => c.id == category).firstOrNull
        : null;
    final remote = choice == null || choice.local
        ? ''
        : _menus
                  .where((c) => categoryName(c.name) == choice.name)
                  .firstOrNull
                  ?.id ??
              '';
    final entry = _sessions.putIfAbsent('$category|$query', _CatalogEntry.new);
    String warning = '';
    CatalogPage snapshot() {
      final items = {for (final item in entry.items) item.id: item};
      if (choice != null) {
        for (final item in _library.values) {
          if (categoryName(item.category) == choice.name) {
            items.putIfAbsent(item.id, () => item);
          }
        }
      }
      final rows = items.values
          .where(
            (item) =>
                choice?.local != true ||
                categoryName(item.category) == choice!.name,
          )
          .toList();
      return CatalogPage(
        rows,
        page: entry.page,
        hasMore: entry.hasMore,
        fresh: entry.fresh,
        warning: warning,
      );
    }

    if ((useCache || cacheOnly) && !force && !more && query.isEmpty) {
      try {
        final cached = await repository.cached(_source, category: remote);
        if (generation != _generation) throw AppFailure('已取消加载');
        entry.items = cached.items;
        entry.page = cached.page;
        entry.nextPage = cached.page + 1;
        entry.hasMore = cached.hasMore || cached.warning.isNotEmpty;
        entry.fresh = cached.fresh && cached.warning.isEmpty;
        warning = cached.warning;
        _remember(cached.items);
      } catch (error) {
        if (cacheOnly) warning = error.toString();
      }
      if (generation != _generation) throw AppFailure('已取消加载');
      final cached = snapshot();
      if (cached.items.isNotEmpty) onCached?.call(cached);
      if (cacheOnly || cached.fresh && cached.items.isNotEmpty) return cached;
    }
    if (more && !entry.hasMore) return snapshot();
    final page = more ? entry.nextPage : 1;
    try {
      final result = await repository.catalog(
        _source,
        category: remote,
        query: query,
        page: page,
        force: force,
      );
      if (generation != _generation) throw AppFailure('已取消加载');
      entry.items = {
        if (more)
          for (final item in entry.items) item.id: item,
        for (final item in result.items) item.id: item,
      }.values.toList();
      entry.page = result.page;
      entry.nextPage = result.warning.isEmpty ? result.page + 1 : page;
      entry.hasMore =
          query.isEmpty && (result.hasMore || result.warning.isNotEmpty);
      entry.fresh = result.fresh && result.warning.isEmpty;
      warning = result.warning;
      if (query.isEmpty) _remember(result.items);
    } catch (error) {
      if (generation != _generation) throw AppFailure('已取消加载');
      entry.nextPage = page;
      entry.hasMore = query.isEmpty;
      entry.fresh = false;
      warning = error.toString();
    }
    final result = snapshot();
    if (result.items.isEmpty && warning.isNotEmpty) throw AppFailure(warning);
    return result;
  }
}
