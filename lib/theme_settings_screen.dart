import 'package:flutter/material.dart';

import 'app_design.dart';
import 'app_theme.dart';
import 'local_store.dart';
import 'theme_appearance.dart';

class ThemeSettingsScreen extends StatefulWidget {
  const ThemeSettingsScreen({super.key, required this.store});
  final LocalStore store;

  @override
  State<ThemeSettingsScreen> createState() => _ThemeSettingsScreenState();
}

class _ThemeSettingsScreenState extends State<ThemeSettingsScreen> {
  late ThemeAppearance _appearance = widget.store.themeAppearance;
  bool _saving = false;

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _update(ThemeAppearance next, {bool notify = true}) async {
    next = ThemeAppearance.fromJson(next.toJson());
    if (notify) setState(() => _appearance = next);
    setState(() => _saving = true);
    try {
      await widget.store.setThemeAppearance(next);
    } catch (_) {
      _error('外观设置保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _switch(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) => SwitchListTile.adaptive(
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: _saving ? null : onChanged,
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('主题设置'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppDesign.formWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                AppSection(
                  title: '外观',
                  children: [
                    ListTile(
                      title: const Text('主题'),
                      subtitle: Text(AppTheme.label(widget.store.themeMode)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        final mode = await showModalBottomSheet<String>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (context) => AppSheet(
                            title: '主题外观',
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final mode in ['system', 'light', 'dark'])
                                  ListTile(
                                    title: Text(AppTheme.label(mode)),
                                    trailing: widget.store.themeMode == mode
                                        ? Icon(
                                            Icons.check_rounded,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          )
                                        : null,
                                    onTap: () => Navigator.pop(context, mode),
                                  ),
                              ],
                            ),
                          ),
                        );
                        if (mode == null) return;
                        try {
                          await widget.store.setThemeMode(mode);
                        } catch (_) {
                          _error('主题设置保存失败，请重试');
                        }
                      },
                    ),
                    _switch(
                      '模糊',
                      '顶栏和底栏使用半透明背景',
                      _appearance.blurBars,
                      (value) => _update(
                        _appearance.copyWith(
                          blurBars: value,
                          floatingBar: value ? _appearance.floatingBar : false,
                        ),
                      ),
                    ),
                  ],
                ),
                AppSection(
                  title: '底栏样式',
                  children: [
                    _switch(
                      '悬浮底栏',
                      '在页面底部留出间距',
                      _appearance.floatingBar,
                      (value) => _update(
                        _appearance.copyWith(
                          floatingBar: value,
                          liquidGlass: value ? _appearance.liquidGlass : false,
                        ),
                      ),
                    ),
                    _switch(
                      '液态玻璃',
                      '为悬浮底栏增加通透效果',
                      _appearance.liquidGlass,
                      (value) => _update(
                        _appearance.copyWith(
                          liquidGlass: value,
                          floatingBar: value ? true : _appearance.floatingBar,
                        ),
                      ),
                    ),
                  ],
                ),
                AppSection(
                  title: '手势',
                  children: [
                    _switch(
                      '全屏返回手势',
                      '横移返回上一页',
                      _appearance.predictiveBack,
                      (value) =>
                          _update(_appearance.copyWith(predictiveBack: value)),
                    ),
                    _switch(
                      '横移返回手势',
                      '从屏幕边缘横移返回',
                      _appearance.swipeBack,
                      (value) =>
                          _update(_appearance.copyWith(swipeBack: value)),
                    ),
                  ],
                ),
                AppSection(
                  title: '显示',
                  children: [
                    ListTile(
                      title: const Text('界面缩放'),
                      trailing: Text('${(_appearance.scale * 100).round()}%'),
                    ),
                    Slider(
                      value: _appearance.scale,
                      min: ThemeAppearance.minScale,
                      max: ThemeAppearance.maxScale,
                      divisions: 10,
                      label: '${(_appearance.scale * 100).round()}%',
                      onChanged: _saving
                          ? null
                          : (value) => setState(
                              () => _appearance = _appearance.copyWith(
                                scale: (value * 100).roundToDouble() / 100,
                              ),
                            ),
                      onChangeEnd: (_) => _update(_appearance, notify: false),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
