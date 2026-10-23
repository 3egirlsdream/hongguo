import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';

class CoverScreenViewport extends StatelessWidget {
  const CoverScreenViewport({
    super.key,
    required this.quarterTurns,
    required this.child,
  });

  final int quarterTurns;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        var size = constraints.biggest;
        var padding = media.padding;
        var viewPadding = media.viewPadding;
        var viewInsets = media.viewInsets;
        var systemGestureInsets = media.systemGestureInsets;
        var features = media.displayFeatures;
        for (var turn = 0; turn < quarterTurns % 4; turn++) {
          final width = size.width;
          features = features.map((feature) {
            final bounds = feature.bounds;
            return DisplayFeature(
              bounds: Rect.fromLTRB(
                bounds.top,
                width - bounds.right,
                bounds.bottom,
                width - bounds.left,
              ),
              type: feature.type,
              state: feature.state,
            );
          }).toList();
          padding = _rotateInsets(padding);
          viewPadding = _rotateInsets(viewPadding);
          viewInsets = _rotateInsets(viewInsets);
          systemGestureInsets = _rotateInsets(systemGestureInsets);
          size = Size(size.height, size.width);
        }
        return RotatedBox(
          quarterTurns: quarterTurns,
          child: MediaQuery(
            data: media.copyWith(
              size: size,
              padding: padding,
              viewPadding: viewPadding,
              viewInsets: viewInsets,
              systemGestureInsets: systemGestureInsets,
              displayFeatures: features,
            ),
            child: child,
          ),
        );
      },
    );
  }

  static EdgeInsets _rotateInsets(EdgeInsets insets) =>
      EdgeInsets.fromLTRB(insets.top, insets.right, insets.bottom, insets.left);
}
