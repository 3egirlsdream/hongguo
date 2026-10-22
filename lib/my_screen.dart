import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_layout.dart';
import 'core_bridge.dart';
import 'downloads_screen.dart';
import 'hongguo_account_screen.dart';
import 'lan_screen.dart';
import 'local_store.dart';
import 'profiles_screen.dart';
import 'settings_screen.dart';
import 'catalog_management_screen.dart';
import 'theme_settings_screen.dart';
import 'widgets.dart';

class MyScreen extends StatefulWidget {
  const MyScreen({
    super.key,
    required this.repository,
    required this.store,
    required this.onSearch,
    required this.onSort,
    required this.onRankings,
    required this.onSelectDownloads,
    required this.onRefresh,
    required this.onDisplayMode,
    this.active = true,
  });
  final AppRepository repository;
  final LocalStore store;
  final bool active;
  final VoidCallback onSearch,
      onSort,
      onRankings,
      onSelectDownloads,
      onRefresh,
      onDisplayMode;
  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  Map<String, dynamic> _account = {};
  int _libraryTab = 1;
  int _librarySelection = 0;
  int _accountRevision = 0;
  String? _accountError;
  late final int _epoch = widget.store.profileEpoch;
  @override
  void initState() {
    super.initState();
    widget.repository.accountStatus.addListener(_accountChanged);
    _refreshAccount();
  }

  void _accountChanged() {
    if (mounted && widget.store.profileEpoch == _epoch) {
      setState(() {
        _account = widget.repository.accountStatus.value;
        _accountError = null;
        _accountRevision++;
      });
    }
  }

  @override
  void didUpdateWidget(covariant MyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _accountRevision++;
      _refreshAccount();
    }
  }

  @override
  void dispose() {
    widget.repository.accountStatus.removeListener(_accountChanged);
    super.dispose();
  }

  Future<void> _refreshAccount() async {
    if (!widget.repository.supportsOfficialAccount) return;
    try {
      final result = await widget.repository.hongguoAccount('status');
      if (mounted && widget.store.profileEpoch == _epoch) {
        setState(() {
          _account = result;
          _accountError = null;
        });
      }
    } catch (_) {
      if (mounted && widget.store.profileEpoch == _epoch) {
        setState(() => _accountError = '账号状态暂不可用，点击重试');
      }
    }
  }

  Future<void> _accountPage() async {
    await openHongguoAccount(context, widget.repository, widget.store);
    if (mounted) {
      await _refreshAccount();
      if (mounted) setState(() => _accountRevision++);
    }
  }

  void _library(int tab) => setState(() {
    _libraryTab = tab;
    _librarySelection++;
  });

  void _page(Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  Widget _tool(
    IconData icon,
    String title,
    VoidCallback action, {
    String? subtitle,
  }) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: action,
  );
  Future<void> _menu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        void run(VoidCallback action) {
          Navigator.pop(sheetContext);
          action();
        }

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            24 + MediaQuery.paddingOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tool(Icons.search_rounded, '搜索', () => run(widget.onSearch)),
              _tool(Icons.sort_rounded, '排序与筛选', () => run(widget.onSort)),
              _tool(
                Icons.leaderboard_outlined,
                '榜单',
                () => run(widget.onRankings),
              ),
              if (widget.store.canDownload &&
                  widget.repository.supportsDownloads)
                _tool(
                  Icons.checklist_rounded,
                  '批量下载',
                  () => run(widget.onSelectDownloads),
                ),
              _tool(Icons.refresh_rounded, '更新内容', () => run(widget.onRefresh)),
              if (widget.repository.supportsSourceManagement)
                _tool(
                  Icons.storage_outlined,
                  '内容管理',
                  () => run(
                    () => _page(
                      CatalogManagementScreen(
                        repository: widget.repository,
                        store: widget.store,
                      ),
                    ),
                  ),
                ),
              const Divider(),
              _tool(
                Icons.devices_outlined,
                '设备互联',
                () => run(() => openLanSync(context)),
              ),
              _tool(
                Icons.people_outline,
                '本地用户',
                () => run(() => _page(ProfilesScreen(store: widget.store))),
                subtitle: '当前：${widget.store.profile.name}',
              ),
              _tool(
                Icons.palette_outlined,
                '外观设置',
                () =>
                    run(() => _page(ThemeSettingsScreen(store: widget.store))),
              ),
              _tool(
                Icons.settings_outlined,
                '设置与备份',
                () => run(
                  () => _page(
                    SettingsScreen(
                      repository: widget.repository,
                      store: widget.store,
                    ),
                  ),
                ),
              ),
              _tool(
                Icons.devices_other_outlined,
                '界面模式',
                () => run(widget.onDisplayMode),
              ),
              _tool(
                Icons.info_outline,
                '关于',
                () => run(
                  () => showAboutDialog(
                    context: context,
                    applicationName: appName,
                    applicationVersion: AppLayout.versionOf(context),
                    children: const [Text('独立运行，观看记录与片单按当前本地用户保存。')],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String value, String label, VoidCallback onTap) => SizedBox(
    width: 60,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: (MediaQuery.textScalerOf(context).scale(12) * 3 + 4).clamp(
              40.0,
              60.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _shortcut(String title, String subtitle, VoidCallback action) =>
      SizedBox(
        width: 80,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: action,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.1,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> _copyUID(String uid) async {
    await Clipboard.setData(ClipboardData(text: uid));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制红果号')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final profile = _account['profile'] as Map?;
    final logged = _account['loggedIn'] == true;
    final uid = '${profile?['uid'] ?? ''}';
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.store,
        widget.repository.accountFavorites,
      ]),
      builder: (context, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ColoredBox(
            color: dark
                ? colors.surfaceContainerLowest
                : const Color(0xFFF6F6F6),
            child: NestedScrollView(
              headerSliverBuilder: (context, innerScrolled) => [
                SliverToBoxAdapter(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: dark
                          ? null
                          : const LinearGradient(
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                              colors: [
                                Color(0xFFE8F6F2),
                                Color(0xFFF8F7F3),
                                Color(0xFFF6F6F6),
                              ],
                              stops: [0, .35, .7],
                            ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 44,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  tooltip: '切换深浅色',
                                  onPressed: () => saveUserChange(
                                    context,
                                    () => widget.store.setThemeMode(
                                      dark ? 'light' : 'dark',
                                    ),
                                  ),
                                  icon: Icon(
                                    dark
                                        ? Icons.light_mode_outlined
                                        : Icons.dark_mode_outlined,
                                    size: 25,
                                  ),
                                  color: colors.onSurface,
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: '更多功能',
                                  onPressed: _menu,
                                  color: colors.onSurface,
                                  icon: const Icon(
                                    Icons.menu_rounded,
                                    size: 25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _accountError != null
                                ? _refreshAccount
                                : _accountPage,
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 31,
                                  backgroundColor: dark
                                      ? colors.surfaceContainerHigh
                                      : const Color(0xFFE7E8E8),
                                  foregroundColor: colors.onSurfaceVariant,
                                  child: const Icon(
                                    Icons.person_rounded,
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        logged
                                            ? '${profile?['name'] ?? '红果用户'}'
                                            : '登录账号',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 20,
                                          height: 1.25,
                                          fontWeight: FontWeight.w500,
                                          color: colors.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              _accountError ??
                                                  (logged
                                                      ? '红果号：$uid'
                                                      : '登录同步追剧、历史与预约'),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                height: 1.2,
                                                color: colors.onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                          if (logged && uid.isNotEmpty)
                                            IconButton(
                                              tooltip: '复制红果号',
                                              onPressed: () => _copyUID(uid),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              constraints: const BoxConstraints(
                                                minWidth: 28,
                                                minHeight: 28,
                                              ),
                                              padding: const EdgeInsets.all(4),
                                              color: colors.onSurfaceVariant,
                                              icon: const Icon(
                                                Icons.copy_outlined,
                                                size: 13,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _stat(
                                '${{...widget.store.favorites.map((d) => d.id), ...widget.repository.accountFavorites.value}.length}',
                                '追剧',
                                () => _library(0),
                              ),
                              _stat(
                                '${widget.store.history.length}',
                                '历史',
                                () => _library(1),
                              ),
                              _stat(
                                '${widget.store.history.where((e) => e.finished && e.drama.episodes > 0 && e.episode >= e.drama.episodes).length}',
                                '已看完',
                                () => _library(1),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: _accountPage,
                                style: TextButton.styleFrom(
                                  backgroundColor: dark
                                      ? colors.surfaceContainer
                                      : const Color(0xFFEFEFEF),
                                  foregroundColor: colors.onSurface,
                                  minimumSize: const Size(0, 30),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                ),
                                child: Text(logged ? '账号管理' : '立即登录'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              spacing: 8,
                              children: [
                                if (widget.store.canDownload)
                                  _shortcut(
                                    '下载',
                                    '离线观看',
                                    () => _page(
                                      DownloadsScreen(
                                        repository: widget.repository,
                                        store: widget.store,
                                      ),
                                    ),
                                  ),
                                _shortcut(
                                  '追更',
                                  '${widget.store.favorites.where((d) => widget.store.following(d.id)?.hasUpdates == true).length}部更新',
                                  () => _library(0),
                                ),
                                _shortcut('预约', '待看新剧', () => _library(2)),
                                _shortcut('上新', '即将上线', () => _library(3)),
                                _shortcut('榜单', '热门好剧', widget.onRankings),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              body: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: Material(
                  color: colors.surface,
                  child: HongguoAccountScreen(
                    key: ValueKey('my-library-$_librarySelection'),
                    repository: widget.repository,
                    store: widget.store,
                    collections: true,
                    embedded: true,
                    refreshToken: _accountRevision,
                    initialTab: _libraryTab,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
