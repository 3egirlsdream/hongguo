import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'core_bridge.dart';
import 'app_theme.dart';
import 'background_downloads.dart';
import 'local_store.dart';
import 'profiles_screen.dart';
import 'app_build.dart';
import 'catalog_management_screen.dart';
import 'hongguo_account_screen.dart';
import 'widgets.dart';
import 'resource_settings_screen.dart';
import 'theme_settings_screen.dart';
import 'lan_screen.dart';
import 'diary_service.dart';
import 'about_screen.dart';
import 'catalog_sort_sheet.dart';
import 'downloads_screen.dart';
import 'rankings_screen.dart';
import 'search_screen.dart';

String storageSize(int bytes) {
  if (bytes < 0) return '暂不可用';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.store,
  });
  final AppRepository repository;
  final LocalStore store;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _backup(bool restore) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!restore) {
        final content = await widget.store.exportBackup();
        final saved = await FilePicker.saveFile(
          fileName:
              '$appSlug-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json',
          bytes: Uint8List.fromList(utf8.encode(content)),
          mimeType: 'application/json',
        );
        if (saved != null && mounted) setState(() => _message = '备份已保存');
      } else {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (file == null || !mounted) return;
        final size = await file.length();
        if (size == null || size > 8 * 1024 * 1024) {
          throw const FormatException('备份文件过大或无法读取');
        }
        final content = utf8.decode(await file.readAsBytes());
        final data = widget.store.validateBackup(content);
        if (!mounted) return;
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('恢复备份？'),
            content: Text(
              '包含 ${(data['profiles'] as List).length} 个用户。将替换本机的用户、追剧、观看记录和偏好设置；已下载视频保留。恢复后使用备份内的管理员密码登录。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('恢复'),
              ),
            ],
          ),
        );
        if (accepted != true || !mounted) return;
        await widget.store.importBackup(content);
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _displayModes = {
    'auto': '自动识别设备',
    'television': '电视 / 遥控器',
    'standard': '手机 / 电脑',
  };

  Future<void> _page(Widget page) =>
      Navigator.of(context)
          .push<void>(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _chooseDisplayMode() async {
    final selection = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('界面模式'),
        children: [
          RadioGroup<String>(
            groupValue: widget.store.displayMode,
            onChanged: (value) => Navigator.pop(dialogContext, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in _displayModes.entries)
                  RadioListTile<String>(
                    value: mode.key,
                    autofocus: mode.key == widget.store.displayMode,
                    title: Text(mode.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selection != null && mounted) {
      await saveUserChange(
        context,
        () => widget.store.setDisplayMode(selection),
      );
    }
  }

  Future<void> _chooseCatalogView() async {
    final selection = await chooseCatalogView(
      context,
      widget.store.catalogView,
    );
    if (selection != null && mounted) {
      await saveUserChange(
        context,
        () => widget.store.setCatalogView(selection),
      );
    }
  }

  Widget _tile({
    Key? key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback action,
  }) => ListTile(
    key: key,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: _busy ? null : action,
  );

  Widget _section(String title, List<Widget> rows) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < rows.length; index++) ...[
                if (index > 0)
                  const Divider(height: 1, indent: 56, endIndent: 16),
                rows[index],
              ],
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => PopScope<void>(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                key: const PageStorageKey('settings-list'),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _section('账号与同步', [
                    if (widget.repository.supportsOfficialAccount)
                      _tile(
                        icon: Icons.account_circle_outlined,
                        title: '账号与同步',
                        subtitle: '手机号登录、账号同步与待上传进度',
                        action: () => openHongguoAccount(
                          context,
                          widget.repository,
                          widget.store,
                        ),
                      ),
                    _tile(
                      key: const ValueKey('profiles-settings'),
                      icon: Icons.people_outline,
                      title: '本地用户',
                      subtitle: '当前：${widget.store.profile.name}',
                      action: () => _page(ProfilesScreen(store: widget.store)),
                    ),
                  ]),
                  _section('浏览与内容', [
                    _tile(
                      key: const ValueKey('search-settings'),
                      icon: Icons.search_rounded,
                      title: '搜索',
                      subtitle: '查找短剧、查看最近搜索',
                      action: () => _page(
                        SearchScreen(
                          repository: widget.repository,
                          store: widget.store,
                        ),
                      ),
                    ),
                    _tile(
                      key: const ValueKey('rankings-settings'),
                      icon: Icons.leaderboard_outlined,
                      title: '排行榜',
                      subtitle: '查看热门短剧与榜单分类',
                      action: () => _page(
                        RankingsScreen(
                          repository: widget.repository,
                          store: widget.store,
                        ),
                      ),
                    ),
                    _tile(
                      key: const ValueKey('sort-settings'),
                      icon: Icons.sort_rounded,
                      title: '排序与筛选',
                      subtitle: '设置搜索结果排序与连载状态筛选',
                      action: _chooseCatalogView,
                    ),
                    if (widget.repository.supportsSourceManagement) ...[
                      _tile(
                        key: const ValueKey('refresh-settings'),
                        icon: Icons.refresh_rounded,
                        title: '更新内容',
                        subtitle: '更新本机目录并查看进度',
                        action: () => _page(
                          CatalogManagementScreen(
                            repository: widget.repository,
                            store: widget.store,
                            updateOnOpen: true,
                          ),
                        ),
                      ),
                      _tile(
                        key: const ValueKey('catalog-settings'),
                        icon: Icons.dns_outlined,
                        title: '内容管理',
                        subtitle: '缓存维护、连接与播放检测',
                        action: () => _page(
                          CatalogManagementScreen(
                            repository: widget.repository,
                            store: widget.store,
                          ),
                        ),
                      ),
                    ],
                  ]),
                  _section('外观与操作', [
                    _tile(
                      key: const ValueKey('theme-setting'),
                      icon: Icons.palette_outlined,
                      title: '主题设置',
                      subtitle:
                          '${AppTheme.label(widget.store.themeMode)} · 模糊、悬浮底栏与界面缩放',
                      action: () =>
                          _page(ThemeSettingsScreen(store: widget.store)),
                    ),
                    _tile(
                      key: const ValueKey('display-settings'),
                      icon: Icons.devices_other_outlined,
                      title: '界面模式',
                      subtitle:
                          _displayModes[widget.store.displayMode] ??
                          _displayModes['auto']!,
                      action: _chooseDisplayMode,
                    ),
                  ]),
                  if (widget.store.canDownload)
                    _section('下载与存储', [
                      if (widget.repository.supportsDownloads) ...[
                        _tile(
                          icon: Icons.download_rounded,
                          title: '下载管理',
                          subtitle: '查看任务与已下载的分集',
                          action: () => _page(
                            DownloadsScreen(
                              repository: widget.repository,
                              store: widget.store,
                            ),
                          ),
                        ),
                        _tile(
                          key: const ValueKey('batch-download-settings'),
                          icon: Icons.checklist_rounded,
                          title: '批量下载',
                          subtitle: '搜索并选择多部短剧，一次最多 50 部',
                          action: () => _page(
                            SearchScreen(
                              repository: widget.repository,
                              store: widget.store,
                              startSelecting: true,
                            ),
                          ),
                        ),
                      ],
                      _tile(
                        icon: Icons.tune_rounded,
                        title: '下载偏好',
                        subtitle: widget.store.downloadPreferences.qualityLabel,
                        action: () => _page(
                          DownloadPreferencesScreen(store: widget.store),
                        ),
                      ),
                      _tile(
                        icon: Icons.folder_outlined,
                        title: '下载目录与空间',
                        subtitle: '查看存储用量、迁移已下载文件',
                        action: () => _page(
                          StorageScreen(
                            repository: widget.repository,
                            store: widget.store,
                          ),
                        ),
                      ),
                      if (widget.store.profile.admin) ...[
                        SwitchListTile(
                          secondary: const Icon(Icons.video_library_outlined),
                          value: widget.store.autoExport,
                          title: const Text('下载完成后自动导出 Emby'),
                          subtitle: const Text(
                            '在下载目录的 exports 中生成视频和海报 URL 元数据，可将该目录加入 Emby 媒体库。',
                          ),
                          onChanged: _busy
                              ? null
                              : (value) async {
                                  try {
                                    if (value)
                                      await BackgroundDownloads.ensureStarted();
                                    await widget.store.setAutoExport(value);
                                  } catch (error) {
                                    if (mounted)
                                      setState(
                                        () => _message = error.toString(),
                                      );
                                  }
                                },
                        ),
                        SwitchListTile(
                          secondary: const Icon(Icons.image_outlined),
                          value: widget.store.exportPosters,
                          title: const Text('同时导出海报文件'),
                          subtitle: const Text(
                            '默认只写海报 URL。源站海报需要解密或外部读取失败时可开启。',
                          ),
                          onChanged: _busy
                              ? null
                              : (value) => saveUserChange(
                                  context,
                                  () => widget.store.setExportPosters(value),
                                ),
                        ),
                      ],
                    ]),
                  _section('网络与设备', [
                    _tile(
                      key: const ValueKey('lan-settings'),
                      icon: Icons.devices_rounded,
                      title: '设备互联',
                      subtitle: '局域网自动同步追剧与推送播放',
                      action: () => openLanSync(context),
                    ),
                    if (widget.store.profile.admin)
                      _tile(
                        icon: Icons.settings_ethernet_rounded,
                        title: '网络与资源',
                        subtitle: '代理、目录请求间隔与下载并发',
                        action: () => _page(
                          ResourceSettingsScreen(
                            repository: widget.repository,
                            store: widget.store,
                          ),
                        ),
                      ),
                  ]),
                  if (widget.store.profile.admin)
                    _section('备份与恢复', [
                      _tile(
                        icon: Icons.backup_outlined,
                        title: '导出配置备份',
                        subtitle: '包含本地用户、追剧、历史和设置，不含视频文件',
                        action: () => _backup(false),
                      ),
                      _tile(
                        icon: Icons.restore_rounded,
                        title: '恢复配置备份',
                        subtitle: '从备份文件恢复本地用户、记录与偏好',
                        action: () => _backup(true),
                      ),
                    ]),
                  _section('关于与诊断', [
                    _tile(
                      key: const ValueKey('about-settings'),
                      icon: Icons.info_outline_rounded,
                      title: '关于$appName',
                      subtitle: '版本更新、开发者与下载地址',
                      action: () => _page(const AboutScreen()),
                    ),
                    _tile(
                      key: const ValueKey('diary-setting'),
                      icon: Icons.receipt_long_rounded,
                      title: '播放调试日记',
                      subtitle: '查看并复制应用运行与播放器的事件日志',
                      action: () => DiaryService.showDiaryDialog(context),
                    ),
                  ]),
                  if (Platform.isIOS)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('iOS 下载和媒体处理需要保持应用在前台；切到后台会暂停，回到前台后可继续。'),
                    ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(_message!),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class StorageScreen extends StatefulWidget {
  const StorageScreen({
    super.key,
    required this.repository,
    required this.store,
  });
  final AppRepository repository;
  final LocalStore store;
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  Map<String, dynamic>? _info;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final info = await widget.repository.storage();
      if (mounted) {
        setState(() {
          _info = info;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _move() async {
    String? parent;
    if (Platform.isAndroid || Platform.isIOS) {
      final support = await getApplicationSupportDirectory();
      final directories = <String, String>{support.path: '应用内部存储'};
      if (Platform.isAndroid) {
        final external = await getExternalStorageDirectories() ?? [];
        for (var i = 0; i < external.length; i++) {
          directories[external[i].path] = i == 0
              ? '设备共享存储（应用目录）'
              : 'SD 卡 ${i + 1}（应用目录）';
        }
      } else {
        final documents = await getApplicationDocumentsDirectory();
        directories[documents.path] = '文件 App 可见目录';
      }
      if (!mounted) return;
      parent = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择下载位置'),
          children: [
            for (final entry in directories.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, entry.key),
                child: Text(entry.value),
              ),
          ],
        ),
      );
    } else {
      parent = await FilePicker.getDirectoryPath(dialogTitle: '选择下载保存位置');
    }
    if (parent == null || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('迁移已下载内容？'),
        content: Text(
          '将视频、合并成品及导出内容迁移到：\n$parent\n\n下载会先暂停，复制成功后清理旧目录。请保证目标有足够空间，并在完成后继续下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('迁移'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.moveDownloads(parent);
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('下载目录与空间')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_info != null) ...[
                Text(
                  '已使用 ${storageSize((_info!['bytes'] as num?)?.toInt() ?? 0)}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '剩余 ${storageSize((_info!['free'] as num?)?.toInt() ?? -1)} · ${_info!['files'] ?? 0} 个文件',
                ),
                const SizedBox(height: 24),
                const Text('当前下载目录'),
                const SizedBox(height: 8),
                SelectableText(_info!['directory'] as String? ?? ''),
                TextButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: _info!['directory'] as String? ?? ''),
                  ),
                  icon: const Icon(Icons.copy),
                  label: const Text('复制路径'),
                ),
                const SizedBox(height: 20),
                const Text('在下载页删除不需要的分集，在本地媒体页删除合并成品或 Emby 导出，可释放空间。'),
              ],
              if (_busy || (_info == null && _error == null))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: LinearProgressIndicator(),
                ),
              if (_busy) const Text('正在迁移，请保持应用运行…'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_error!),
                ),
              if (widget.store.profile.admin)
                FilledButton.icon(
                  onPressed: _busy ? null : _move,
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: const Text('更改并迁移目录'),
                ),
              TextButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('刷新用量'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
