import 'package:flutter/material.dart';

class EpisodeButton extends StatelessWidget {
  const EpisodeButton({
    super.key,
    required this.number,
    required this.onPressed,
    this.vip = false,
    this.current = false,
    this.played = false,
    this.showPlaybackState = false,
    this.compact = false,
  });
  final int number;
  final bool vip;
  final bool current;
  final bool played;
  final bool showPlaybackState;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: current,
    label:
        '第 $number 集${showPlaybackState ? '，${current
                  ? '正在播放'
                  : played
                  ? '已播放'
                  : '未播放'}' : ''}${vip ? '，VIP 试看' : ''}',
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        backgroundColor: current
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        minimumSize: Size.zero,
        padding: EdgeInsets.all(compact ? 2 : 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          color: current
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: compact ? 1.2 : 2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 8 : 14),
        ),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showPlaybackState && (played || current)) ...[
              Icon(
                current ? Icons.play_arrow_rounded : Icons.check_rounded,
                size: compact ? 11 : 15,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 1),
            ],
            Flexible(
              child: Text(
                '$number',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 14 : 20,
                  color: played && !current
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (vip) ...[
              SizedBox(width: compact ? 2 : 4),
              Icon(
                Icons.workspace_premium_rounded,
                color: Theme.of(context).colorScheme.tertiary,
                size: compact ? 15 : 18,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
