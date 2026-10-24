import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 应用内「日记」日志服务 — 实时记录播放与系统事件，方便在手机端快速排查问题。
class DiaryService {
  static final List<String> _entries = <String>[];
  static const int maxEntries = 500;
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static File? _file;
  static Future<void> _writes = Future<void>.value();
  static Future<void>? _initializing;
  static const maxFileBytes = 1024 * 1024;
  static const backups = 2;
  static bool _writeWarning = false;

  static String sanitize(String message) {
    var clean = message.replaceAll(
      RegExp(
        r'''\b(?:set-cookie|cookie|authorization)["']?\s*[:=]\s*[^\r\n]+''',
        caseSensitive: false,
        multiLine: true,
      ),
      '[credential header hidden]',
    );
    clean = clean.replaceAll(
      RegExp(
        r'''(?:https?|file|content|hongguo-cenc|socks5h?)://[^\s"'<>\\]+''',
        caseSensitive: false,
      ),
      '[address hidden]',
    );
    clean = clean.replaceAllMapped(
      RegExp(
        r'''(["']?(?:x-tt-token|token|access_token|refresh_token|sessionid|session_id|decryptionKey|decryption_key|secret|password|key)["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;}\]]+)''',
        caseSensitive: false,
      ),
      (match) => '${match[1]}[hidden]',
    );
    clean = clean.replaceAll(RegExp(r'\b[a-fA-F0-9]{32,}\b'), '[hex hidden]');
    return clean.length > 8192 ? '${clean.substring(0, 8192)}…' : clean;
  }

  static Future<void> initialize(String directory) =>
      _initializing ??= _initialize(directory);

  static Future<void> _initialize(String directory) async {
    try {
      final file = File('$directory/logs/playback.log');
      await file.parent.create(recursive: true);
      final saved = <String>[];
      for (final path in ['${file.path}.1', file.path]) {
        final previous = File(path);
        if (await previous.exists() &&
            await previous.length() <= maxFileBytes + 16384) {
          saved.addAll(await previous.readAsLines());
        }
      }
      final queued = List<String>.of(_entries);
      _entries
        ..clear()
        ..addAll([...saved, ...queued].map(sanitize));
      _trim();
      _file = file;
      for (final entry in queued) {
        _persist(entry);
      }
      revision.value++;
    } catch (_) {
      debugPrint('[Diary] 本机诊断日志暂时无法打开');
    }
  }

  static void _trim() {
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  static void _persist(String entry) {
    final file = _file;
    if (file == null) return;
    _writes = _writes
        .then((_) async {
          final data = '$entry\n';
          if (await file.exists() &&
              await file.length() + utf8.encode(data).length > maxFileBytes) {
            final oldest = File('${file.path}.$backups');
            if (await oldest.exists()) await oldest.delete();
            for (var index = backups; index > 0; index--) {
              final previous = File(
                index == 1 ? file.path : '${file.path}.${index - 1}',
              );
              if (await previous.exists()) {
                await previous.rename('${file.path}.$index');
              }
            }
          }
          await file.writeAsString(data, mode: FileMode.append, flush: true);
        })
        .catchError((Object _) {
          if (!_writeWarning) {
            _writeWarning = true;
            debugPrint('[Diary] 本机诊断日志写入失败，保留内存记录');
          }
        });
  }

  static Future<void> flush() async {
    await _initializing;
    await _writes;
  }

  static void add(String message) {
    final clean = sanitize(message);
    final entry = '[${DateTime.now().toIso8601String()}] $clean';
    _entries.add(entry);
    _trim();
    _persist(entry);
    revision.value++;
    debugPrint('[Diary] $clean');
  }

  /// 获取当前所有日记副本
  static List<String> get entries => List<String>.unmodifiable(_entries);

  /// 清空日记
  static void clear() {
    _entries.clear();
    revision.value++;
    final file = _file;
    if (file != null) {
      _writes = _writes
          .then((_) async {
            for (final path in [
              file.path,
              for (var i = 1; i <= backups; i++) '${file.path}.$i',
            ]) {
              final saved = File(path);
              if (await saved.exists()) await saved.delete();
            }
          })
          .catchError((Object _) {});
    }
  }

  /// 获取合并后的完整日志文本
  static String get fullText => _entries.join('\n');

  /// 复制全部日记到剪贴板
  static Future<void> copyToClipboard(BuildContext context) async {
    final text = fullText;
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('已复制播放日记到剪贴板'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// 在界面上弹出交互式日记弹窗
  static Future<void> showDiaryDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final scrollController = ScrollController();
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          title: Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: Colors.amberAccent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '播放调试日记',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: Colors.white70),
                tooltip: '复制全部日记',
                onPressed: () => copyToClipboard(dialogContext),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white70,
                ),
                tooltip: '清空日记',
                onPressed: () => clear(),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(dialogContext).size.height * 0.65,
            child: AnimatedBuilder(
              animation: revision,
              builder: (context, _) {
                final list = entries;
                if (list.isEmpty) {
                  return const Center(
                    child: Text(
                      '暂无日记记录',
                      style: TextStyle(color: Colors.white38),
                    ),
                  );
                }
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Scrollbar(
                    controller: scrollController,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final item = list[list.length - 1 - index]; // 倒序显示最新
                        Color textColor = Colors.white70;
                        final lower = item.toLowerCase();
                        if (lower.contains('err') ||
                            lower.contains('fail') ||
                            lower.contains('异常') ||
                            lower.contains('失败') ||
                            lower.contains('exception')) {
                          textColor = const Color(0xFFFF6B6B);
                        } else if (lower.contains('成功') ||
                            lower.contains('ok') ||
                            lower.contains('success')) {
                          textColor = const Color(0xFF51CF66);
                        } else if (lower.contains('open') ||
                            lower.contains('initialize') ||
                            lower.contains('play') ||
                            lower.contains('url')) {
                          textColor = const Color(0xFF74C0FC);
                        } else if (lower.contains('warn') ||
                            lower.contains('403') ||
                            lower.contains('404')) {
                          textColor = const Color(0xFFFCC419);
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: SelectableText(
                            item,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: textColor,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('一键复制'),
              onPressed: () => copyToClipboard(dialogContext),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}
