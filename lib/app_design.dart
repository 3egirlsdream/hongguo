import 'package:flutter/material.dart';

abstract final class AppDesign {
  static const pageInset = 16.0;
  static const formWidth = 680.0;
  static const radius = 10.0;
  static const controlHeight = 48.0;
}

class AppSection extends StatelessWidget {
  const AppSection({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.labelMedium),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (index, child) in children.indexed) ...[
                if (index > 0)
                  const Divider(height: 1, indent: 16, endIndent: 16),
                child,
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.scrollable = true,
  });
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final bool scrollable;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: title,
    content: content,
    actions: actions,
    scrollable: scrollable,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    actionsPadding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
    buttonPadding: const EdgeInsets.symmetric(horizontal: 4),
  );
}

class AppChoiceDialog extends StatelessWidget {
  const AppChoiceDialog({
    super.key,
    required this.title,
    required this.children,
  });
  final Widget title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: title,
    titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    contentPadding: const EdgeInsets.symmetric(vertical: 8),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    children: children,
  );
}

class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });
  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: child,
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: actions,
              ),
            ),
        ],
      ),
    ),
  );
}
