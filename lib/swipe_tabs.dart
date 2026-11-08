import 'package:flutter/material.dart';

class SwipeTabs extends StatefulWidget {
  const SwipeTabs({
    super.key,
    required this.index,
    required this.count,
    required this.onChanged,
    required this.child,
    this.enabled = true,
  });

  final int index;
  final int count;
  final ValueChanged<int> onChanged;
  final Widget child;
  final bool enabled;

  @override
  State<SwipeTabs> createState() => _SwipeTabsState();
}

class _SwipeTabsState extends State<SwipeTabs> {
  Offset _distance = Offset.zero;
  Offset _origin = Offset.zero;
  int? _startIndex;
  bool _multiplePointers = false;
  final _pointers = <int>{};

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final enabled = widget.enabled && widget.count > 1;
      return Listener(
        onPointerDown: (event) {
          if (_pointers.isEmpty) _multiplePointers = false;
          _pointers.add(event.pointer);
          if (_pointers.length > 1) _multiplePointers = true;
        },
        onPointerUp: (event) => _pointers.remove(event.pointer),
        onPointerCancel: (event) => _pointers.remove(event.pointer),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: enabled
              ? (event) {
                  _origin = event.localPosition;
                  _distance = Offset.zero;
                  _startIndex = widget.index;
                }
              : null,
          onHorizontalDragUpdate: enabled
              ? (event) => _distance = event.localPosition - _origin
              : null,
          onHorizontalDragCancel: enabled ? () => _startIndex = null : null,
          onHorizontalDragEnd: enabled
              ? (event) {
                  final start = _startIndex;
                  _startIndex = null;
                  final width = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : MediaQuery.sizeOf(context).width;
                  if (_multiplePointers ||
                      start == null ||
                      start != widget.index ||
                      _distance.dx.abs() <= _distance.dy.abs() * 1.5) {
                    return;
                  }
                  final velocity = event.velocity.pixelsPerSecond.dx;
                  final fling =
                      _distance.dx.abs() >= width * .04 &&
                      velocity.abs() >= width * 1.5 &&
                      velocity.sign == _distance.dx.sign;
                  if (_distance.dx.abs() < width * .16 && !fling) return;
                  final direction = _distance.dx < 0 ? 1 : -1;
                  final next =
                      start +
                      (Directionality.of(context) == TextDirection.rtl
                          ? -direction
                          : direction);
                  if (next < 0 || next >= widget.count) return;
                  widget.onChanged(next);
                }
              : null,
          child: widget.child,
        ),
      );
    },
  );
}
