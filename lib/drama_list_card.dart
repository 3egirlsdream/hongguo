import 'package:flutter/material.dart';

import 'core_bridge.dart';
import 'models.dart';
import 'widgets.dart';

class DramaListCard extends StatelessWidget {
  const DramaListCard({
    super.key,
    required this.drama,
    required this.repository,
    required this.heading,
    this.scale = 1,
    this.metric = '',
    this.publishText = '',
    this.footer,
    this.compact = false,
    this.onTap,
  });

  final Drama drama;
  final AppRepository repository;
  final String heading;
  final double scale;
  final String metric;
  final String publishText;
  final Widget? footer;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final metadata = [
      if (drama.episodes > 0) '共 ${drama.episodes} 集',
      if (drama.releaseLabel != '状态未知') drama.releaseLabel,
      if (drama.vip) 'VIP',
    ].join(' · ');
    final secondaryStyle = TextStyle(
      color: colors.onSurfaceVariant,
      fontSize: (compact ? 11 : 12) * scale,
      height: 1.3,
    );
    final information = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.primary,
            fontSize: 12 * scale,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: (compact ? 4 : 5) * scale),
        Text(
          drama.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: (compact ? 14 : 16) * scale,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (!compact && drama.category.trim().isNotEmpty) ...[
          SizedBox(height: 6 * scale),
          Text(
            drama.category.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: secondaryStyle,
          ),
        ],
        if (metadata.isNotEmpty) ...[
          SizedBox(height: (compact ? 3 : 5) * scale),
          Text(
            metadata,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: secondaryStyle,
          ),
        ],
        if (publishText.isNotEmpty) ...[
          SizedBox(height: (compact ? 3 : 5) * scale),
          Text(publishText, style: secondaryStyle),
        ],
      ],
    );
    final metricText = metric.trim();
    final hasHeatLabel = metricText.endsWith('热度');
    final metricValue = hasHeatLabel
        ? metricText.substring(0, metricText.length - 2).trim()
        : metricText;
    final bottom =
        footer ??
        (metricText.isEmpty
            ? null
            : Text.rich(
                TextSpan(
                  text: metricValue,
                  children: [
                    if (hasHeatLabel)
                      TextSpan(
                        text: ' 热度',
                        style: TextStyle(
                          fontSize: 12 * scale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 16 * scale,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ));

    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onFocusChange: (focused) {
          if (focused) Scrollable.ensureVisible(context, alignment: .4);
        },
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: (compact ? 8 : 12) * scale),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final coverWidth = compact
                  ? (constraints.maxWidth * .25).clamp(0.0, 76.0)
                  : (constraints.maxWidth * .28).clamp(0.0, 96.0);
              final coverHeight = coverWidth / .72;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: coverWidth,
                    height: coverHeight,
                    child: DramaCover(
                      drama: drama,
                      repository: repository,
                      radius: 6 * scale,
                      showOverlay: false,
                      fit: BoxFit.cover,
                    ),
                  ),
                  SizedBox(width: 14 * scale),
                  Expanded(
                    child: compact
                        ? SizedBox(
                            height: coverHeight,
                            child: LayoutBuilder(
                              builder: (context, contentConstraints) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.topLeft,
                                      child: SizedBox(
                                        width: contentConstraints.maxWidth,
                                        child: information,
                                      ),
                                    ),
                                  ),
                                  if (bottom != null) ...[
                                    SizedBox(height: 4 * scale),
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxHeight: coverHeight * .4,
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.bottomLeft,
                                        child: bottom,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : ConstrainedBox(
                            constraints: BoxConstraints(minHeight: coverHeight),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                information,
                                if (bottom != null) ...[
                                  SizedBox(height: 8 * scale),
                                  bottom,
                                ],
                              ],
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
