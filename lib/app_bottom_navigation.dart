import 'dart:ui';

import 'package:flutter/material.dart';

class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.floating = false,
    this.blurred = false,
    this.liquidGlass = false,
  });
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  final bool floating;
  final bool blurred;
  final bool liquidGlass;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final glass = blurred || liquidGlass;
    final radius = floating ? 18.0 : 0.0;
    Widget bar = Material(
      color: glass ? colors.surface.withValues(alpha: .78) : colors.surface,
      child: Row(
        children: [
          for (final (index, destination) in destinations.indexed)
            Expanded(
              child: Semantics(
                container: true,
                button: true,
                selected: index == selectedIndex,
                child: InkWell(
                  key: ValueKey('bottom-nav-$index'),
                  onTap: () => onDestinationSelected(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconTheme(
                          data: IconThemeData(
                            size: 23,
                            color: index == selectedIndex
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          child: index == selectedIndex
                              ? destination.selectedIcon ?? destination.icon
                              : destination.icon,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          destination.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            fontWeight: index == selectedIndex
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: index == selectedIndex
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (glass) {
      bar = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: liquidGlass ? 20 : 12,
          sigmaY: liquidGlass ? 20 : 12,
        ),
        child: bar,
      );
    }
    return Material(
      color: floating ? Colors.transparent : colors.surface,
      child: SafeArea(
        top: false,
        minimum: floating
            ? const EdgeInsets.fromLTRB(16, 0, 16, 10)
            : EdgeInsets.zero,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: colors.outlineVariant, width: .5),
          ),
          clipBehavior: Clip.antiAlias,
          child: bar,
        ),
      ),
    );
  }
}
