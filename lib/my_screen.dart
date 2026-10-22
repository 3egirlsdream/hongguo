import 'package:flutter/material.dart';

import 'app_layout.dart';
import 'core_bridge.dart';
import 'downloads_screen.dart';
import 'hongguo_account_screen.dart';
import 'lan_screen.dart';
import 'local_store.dart';
import 'profiles_screen.dart';
import 'settings_screen.dart';
import 'catalog_management_screen.dart';

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
  });
  final AppRepository repository;
  final LocalStore store;
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
  String? _accountError;
  late final int _epoch = widget.store.profileEpoch;
  @override
  void initState() {
    super.initState();
    _refreshAccount();
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
    if (mounted) await _refreshAccount();
  }

  Future<void> _library(int tab) async {
    await openPersonalLibrary(
      context,
      widget.repository,
      widget.store,
      initialTab: tab,
    );
    if (mounted) await _refreshAccount();
  }

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
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profile = _account['profile'] as Map?;
    final logged = _account['loggedIn'] == true;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Text(
              '我的',
              style: Theme.of(context).textTheme.headlineLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  child: const Icon(Icons.person_rounded),
                ),
                title: Text(logged ? '${profile?['name'] ?? '已登录'}' : '登录账号'),
                subtitle: Text(
                  _accountError ??
                      (logged
                          ? '${profile?['phone'] ?? ''}\n历史与预约已关联此账号'
                          : '同步观看进度，管理预约与片单'),
                ),
                isThreeLine: logged,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _accountError != null ? _refreshAccount : _accountPage,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, box) {
                final entries = [
                  (Icons.bookmark_outline_rounded, '追剧', () => _library(0)),
                  (Icons.event_available_outlined, '预约', () => _library(2)),
                  (Icons.history_rounded, '历史', () => _library(1)),
                  if (widget.store.canDownload)
                    (
                      Icons.download_outlined,
                      '下载',
                      () => _page(
                        DownloadsScreen(
                          repository: widget.repository,
                          store: widget.store,
                        ),
                      ),
                    ),
                ];
                final columns = box.maxWidth < 280 ? 2 : entries.length;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in entries)
                      SizedBox(
                        width: (box.maxWidth - 8 * (columns - 1)) / columns,
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: entry.$3,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Column(
                                children: [
                                  Icon(entry.$1),
                                  const SizedBox(height: 8),
                                  Text(entry.$2),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Text('浏览工具', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  _tool(Icons.search_rounded, '搜索', widget.onSearch),
                  _tool(Icons.sort_rounded, '排序与筛选', widget.onSort),
                  _tool(Icons.leaderboard_outlined, '榜单', widget.onRankings),
                  if (widget.store.canDownload &&
                      widget.repository.supportsDownloads)
                    _tool(
                      Icons.checklist_rounded,
                      '批量下载',
                      widget.onSelectDownloads,
                    ),
                  _tool(Icons.refresh_rounded, '更新内容', widget.onRefresh),
                  if (widget.repository.supportsSourceManagement)
                    _tool(
                      Icons.storage_outlined,
                      '内容管理',
                      () => _page(
                        CatalogManagementScreen(
                          repository: widget.repository,
                          store: widget.store,
                        ),
                      ),
                      subtitle: '缓存更新、资料补齐与连接检测',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('应用与设备', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  _tool(
                    Icons.devices_outlined,
                    '设备互联',
                    () => openLanSync(context),
                  ),
                  _tool(
                    Icons.people_outline,
                    '本地用户',
                    () => _page(ProfilesScreen(store: widget.store)),
                    subtitle: '当前：${widget.store.profile.name}',
                  ),
                  _tool(
                    Icons.settings_outlined,
                    '设置与备份',
                    () => _page(
                      SettingsScreen(
                        repository: widget.repository,
                        store: widget.store,
                      ),
                    ),
                  ),
                  _tool(
                    Icons.devices_other_outlined,
                    '界面模式',
                    widget.onDisplayMode,
                  ),
                  _tool(
                    Icons.info_outline,
                    '关于',
                    () => showAboutDialog(
                      context: context,
                      applicationName: appName,
                      applicationVersion: AppLayout.versionOf(context),
                      children: const [Text('独立运行，观看记录与片单按当前本地用户保存。')],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
