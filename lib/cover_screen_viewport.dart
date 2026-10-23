import 'dart:math' as math;

import 'package:flutter/material.dart';

class CoverScreenViewport extends StatelessWidget {
  const CoverScreenViewport({
    super.key,
    required this.enabled,
    required this.innerSize,
    required this.child,
  });

  final bool enabled;
  final Size innerSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: enabled,
        bottom: enabled,
        left: enabled,
        right: enabled,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final media = MediaQuery.of(context);
            final viewport = enabled ? innerSize : constraints.biggest;
            final scale = math.min(
              constraints.maxWidth / viewport.width,
              constraints.maxHeight / viewport.height,
            );
            return Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: viewport.width,
                  height: viewport.height,
                  child: MediaQuery(
                    data: !enabled
                        ? media
                        : media.copyWith(
                            size: viewport,
                            devicePixelRatio: media.devicePixelRatio * scale,
                            padding: EdgeInsets.zero,
                            viewPadding: EdgeInsets.zero,
                            viewInsets: EdgeInsets.fromLTRB(
                              media.viewInsets.left / scale,
                              media.viewInsets.top / scale,
                              media.viewInsets.right / scale,
                              media.viewInsets.bottom / scale,
                            ),
                          ),
                    child: child,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
