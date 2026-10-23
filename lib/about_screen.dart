import 'package:flutter/material.dart';

import 'app_build.dart';
import 'app_update.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  final updates = AppUpdateService.instance;

  @override
  void initState() {
    super.initState();
    updates.loadInstalledVersion();
  }

  Future<void> _open(String url) async {
    try {
      await AppUpdateService.openLink(url);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开链接失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于$appName')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: AnimatedBuilder(
          animation: updates,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const ListTile(
                leading: Icon(Icons.play_circle_outline_rounded, size: 40),
                title: Text(appName),
                subtitle: Text('开发与维护：3egirlsdream'),
              ),
              ListTile(
                title: const Text('当前版本'),
                subtitle: SelectableText(
                  updates.installedVersion.isEmpty
                      ? '正在读取…'
                      : updates.installedVersion,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('开发者主页'),
                subtitle: const Text(developerUrl),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => _open(developerUrl),
              ),
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text('软件源码仓库'),
                subtitle: const Text(appRepositoryUrl),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => _open(appRepositoryUrl),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('下载最新版本'),
                subtitle: const Text('始终打开最新 Release'),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => _open(appDownloadUrl),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.system_update_alt_rounded),
                title: const Text('检查更新'),
                subtitle: Text(updates.checking ? '正在查询最新版本…' : '从版本后台获取更新'),
                onTap: updates.busy ? null : updates.check,
              ),
              if (updates.checking) const LinearProgressIndicator(),
              if (updates.message != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(updates.message!),
                ),
              if (updates.availableVersion != null && updates.notes.isNotEmpty)
                ExpansionTile(
                  title: Text('版本 ${updates.availableVersion!.text} 更新内容'),
                  initiallyExpanded: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(updates.notes),
                    ),
                  ],
                ),
              if (updates.downloading) ...[
                LinearProgressIndicator(value: updates.progress),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${(updates.received / 1048576).toStringAsFixed(1)} / '
                    '${(updates.package!.size / 1048576).toStringAsFixed(1)} MB',
                  ),
                ),
                TextButton(
                  onPressed: updates.cancelDownload,
                  child: const Text('取消下载'),
                ),
              ],
              if (updates.package != null && !updates.downloading)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: updates.busy
                        ? null
                        : updates.downloaded
                        ? updates.install
                        : updates.download,
                    icon: const Icon(Icons.system_update_rounded),
                    label: Text(
                      updates.installing
                          ? '正在准备安装…'
                          : updates.downloaded
                          ? updates.installPermissionRequired
                                ? '继续安装'
                                : '安装更新'
                          : '下载并安装更新',
                    ),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '当前发布 Android arm64 安装包。下载后自动打开系统安装界面；首次需允许安装此来源的应用，并确认安装。',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
