import 'package:flutter/material.dart';

import 'app_design.dart';
import 'danmaku_filter.dart';

class DanmakuFilterDialog extends StatefulWidget {
  const DanmakuFilterDialog({super.key, required this.keywords});
  final List<String> keywords;
  @override
  State<DanmakuFilterDialog> createState() => _DanmakuFilterDialogState();
}

class _DanmakuFilterDialogState extends State<DanmakuFilterDialog> {
  late final _input = TextEditingController(text: widget.keywords.join('\n'));
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final words = normalizeDanmakuKeywords(
        _input.text.split(RegExp(r'[\n\r,，]+')),
      );
      Navigator.pop(context, words);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: const Text('屏蔽关键词'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('弹幕包含任一关键词即隐藏，忽略大小写、空格和全角差异。'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('danmaku-filter-editor'),
            controller: _input,
            minLines: 3,
            maxLines: 6,
            maxLength: 6000,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: '关键词',
              hintText: '每行一个，也可用逗号分隔',
              errorText: _error,
              counterText: '',
              helperText: '最多 100 个，每个最多 50 个字符',
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          _input.clear();
          setState(() => _error = null);
        },
        child: const Text('清空'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey('danmaku-filter-save'),
        onPressed: _save,
        child: const Text('保存'),
      ),
    ],
  );
}
