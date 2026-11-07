import 'package:flutter/material.dart';

import 'app_build.dart';
import 'app_design.dart';
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
            .showSnackBar(const SnackBar(content: Text('暂时无法打开链接，请稍后重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于$appName')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppDesign.formWidth),
        child: AnimatedBuilder(
          animation: updates,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    leading: Icon(
                      Icons.play_circle_outline_rounded,
                      size: 36,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      appName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          updates.installedVersion.isEmpty
                              ? updates.message == null
                                    ? '正在读取版本…'
                                    : '版本读取失败'
                              : updates.installedVersion,
                        ),
                        const SizedBox(height: 4),
                        const Text('开发与维护：3egirlsdream'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline_rounded),
                      title: const Text('开发者主页'),
                      subtitle: const Text('3egirlsdream'),
                      trailing: const Icon(Icons.open_in_new_rounded),
                      onTap: () => _open(developerUrl),
                    ),
                    ListTile(
                      leading: const Icon(Icons.code_rounded),
                      title: const Text('软件源码仓库'),
                      subtitle: const Text('GitHub · hongguo'),
                      trailing: const Icon(Icons.open_in_new_rounded),
                      onTap: () => _open(appRepositoryUrl),
                    ),
                    ListTile(
                      leading: const Icon(Icons.download_outlined),
                      title: const Text('下载最新版本'),
                      subtitle: const Text('查看最新版本与更新内容'),
                      trailing: const Icon(Icons.open_in_new_rounded),
                      onTap: () => _open(appDownloadUrl),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.system_update_alt_rounded),
                title: const Text('检查更新'),
                subtitle: Text(updates.checking ? '正在查询最新版本…' : '查询可用的新版本'),
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
                    updates.package == null
                        ? '正在获取旧版更新包信息…'
                        : '${(updates.received / 1048576).toStringAsFixed(1)} / '
                              '${(updates.package!.size / 1048576).toStringAsFixed(1)} MB',
                  ),
                ),
                TextButton(
                  onPressed: updates.cancelDownload,
                  child: const Text('取消下载'),
                ),
              ],
              if (updates.canDownload && !updates.downloading)
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
              if (updates.installPermissionRequired)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '请允许安装此来源的应用，再继续安装。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
