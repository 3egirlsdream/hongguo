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
    this.expandToContent = false,
    this.onTap,
  });

  final Drama drama;
  final AppRepository repository;
  final String heading;
  final double scale;
  final String metric;
  final String publishText;
  final Widget? footer;
  final bool expandToContent;
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
      fontSize: 14 * scale,
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
            fontSize: 15 * scale,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 8 * scale),
        Text(
          drama.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 18 * scale,
            height: 1.25,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (drama.category.trim().isNotEmpty) ...[
          SizedBox(height: 10 * scale),
          Text(
            drama.category.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: secondaryStyle,
          ),
        ],
        if (metadata.isNotEmpty) ...[
          SizedBox(height: 5 * scale),
          Text(
            metadata,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: secondaryStyle,
          ),
        ],
        if (publishText.isNotEmpty) ...[
          SizedBox(height: 5 * scale),
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
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 24 * scale,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
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
          padding: EdgeInsets.symmetric(vertical: 12 * scale),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final coverWidth = (constraints.maxWidth * .35).clamp(0.0, 176.0);
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
                      radius: 3 * scale,
                      showOverlay: false,
                      fit: BoxFit.cover,
                    ),
                  ),
                  SizedBox(width: 14 * scale),
                  Expanded(
                    child: expandToContent
                        ? ConstrainedBox(
                            constraints: BoxConstraints(minHeight: coverHeight),
                            child: Padding(
                              padding: EdgeInsets.only(top: 3 * scale),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  information,
                                  if (bottom != null)
                                    Padding(
                                      padding: EdgeInsets.only(top: 8 * scale),
                                      child: bottom,
                                    ),
                                ],
                              ),
                            ),
                          )
                        : SizedBox(
                            height: coverHeight,
                            child: ClipRect(
                              child: Stack(
                                children: [
                                  Positioned(
                                    top: 3 * scale,
                                    left: 0,
                                    right: 0,
                                    bottom: (bottom == null ? 0 : 43) * scale,
                                    child: ClipRect(
                                      child: OverflowBox(
                                        alignment: Alignment.topLeft,
                                        minHeight: 0,
                                        maxHeight: double.infinity,
                                        child: information,
                                      ),
                                    ),
                                  ),
                                  if (bottom != null)
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 5 * scale,
                                      height: 32 * scale,
                                      child: ClipRect(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: bottom,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
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
