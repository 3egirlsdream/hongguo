import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'danmaku_controller.dart';
import 'danmaku_models.dart';

class DanmakuFlight {
  const DanmakuFlight(this.item, this.text, this.lane, this.width);
  final DanmakuItem item;
  final String text;
  final int lane;
  final double width;
}

List<DanmakuFlight> planDanmaku(
  List<DanmakuItem> items, {
  required double width,
  required int rows,
  required double Function(String) measure,
}) {
  if (!width.isFinite || width <= 0 || rows < 1) return const [];
  final lanes = List<DanmakuFlight?>.filled(rows.clamp(1, 4), null);
  final sorted = deduplicateDanmaku(items);
  final seen = <String>{};
  final flights = <DanmakuFlight>[];
  for (final item in sorted) {
    if (item.id.isEmpty ||
        item.text.trim().isEmpty ||
        item.timeMs < 0 ||
        !seen.add(item.id)) {
      continue;
    }
    if (flights.reversed
            .takeWhile(
              (flight) => item.timeMs - flight.item.timeMs < danmakuLifetimeMs,
            )
            .length >=
        24) {
      continue;
    }
    final runes = item.text.runes;
    final text =
        String.fromCharCodes(runes.take(100)) + (runes.length > 100 ? '…' : '');
    final size = measure(text).ceilToDouble() + 8;
    final lane = lanes.indexWhere((previous) {
      if (previous == null) return true;
      final gap = item.timeMs - previous.item.timeMs;
      if (gap >= danmakuLifetimeMs) return true;
      return (width + previous.width) * gap / danmakuLifetimeMs -
                  previous.width >=
              24 &&
          width -
                  (width + size) *
                      (danmakuLifetimeMs - gap) /
                      danmakuLifetimeMs >=
              24;
    });
    if (lane < 0) continue;
    final flight = DanmakuFlight(item, text, lane, size);
    lanes[lane] = flight;
    flights.add(flight);
  }
  return flights;
}

class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.controller,
    required this.aspectRatio,
    this.fillViewport = false,
  });
  final DanmakuController controller;
  final double aspectRatio;
  final bool fillViewport;

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  Object? _layout;
  final _widths = <String, double>{};
  List<DanmakuFlight> _schedule = const [];
  List<DanmakuFlight> _active = const [];
  late final Ticker _ticker = createTicker(_tick);
  final _position = ValueNotifier<double>(0);
  Timer? _transition;
  double _anchor = 0;
  double _rate = 1;
  int _motionRevision = -1;
  bool _moving = false;
  double _rowHeight = 0;
  final _gapClock = Stopwatch();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _layout = null;
      _motionRevision = -1;
    }
  }

  void _changed() {
    if (!mounted) return;
    final controller = widget.controller;
    _motionRevision = controller.motionRevision;
    _moving = controller.moving;
    _rate = controller.rate;
    _resetClock(controller.positionMs.toDouble());
    setState(() {});
  }

  void _resetClock(double position) {
    _ticker.stop();
    _gapClock
      ..stop()
      ..reset();
    _anchor = position;
    _position.value = position;
    if (_moving && _active.isNotEmpty) _ticker.start();
    _scheduleTransition();
  }

  void _tick(Duration elapsed) {
    _position.value = _anchor + elapsed.inMicroseconds / 1000 * _rate;
  }

  void _scheduleTransition() {
    _transition?.cancel();
    if (!_moving || !widget.controller.visible) return;
    final position = _position.value;
    double? next;
    for (final flight in _schedule) {
      for (final boundary in [
        flight.item.timeMs,
        flight.item.timeMs + danmakuLifetimeMs,
      ]) {
        if (boundary > position + .5 && (next == null || boundary < next)) {
          next = boundary.toDouble();
        }
      }
    }
    if (next == null) return;
    final deadline = next;
    final clock = Stopwatch()..start();
    _transition = Timer(
      Duration(
        microseconds: ((next - position) * 1000 / _rate).ceil().clamp(
          1,
          86400000000,
        ),
      ),
      () {
        if (!mounted || !_moving || !widget.controller.visible) return;
        final actual = math.max(
          deadline,
          position + clock.elapsedMicroseconds / 1000 * _rate,
        );
        _resetClock(actual);
        setState(() {});
      },
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _transition?.cancel();
    _ticker.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final controller = widget.controller;
            if (!controller.visible ||
                !constraints.hasBoundedWidth ||
                !constraints.hasBoundedHeight ||
                constraints.maxWidth <= 0 ||
                constraints.maxHeight <= 0) {
              _ticker.stop();
              _transition?.cancel();
              return const SizedBox.shrink();
            }
            final aspect = widget.aspectRatio.isFinite && widget.aspectRatio > 0
                ? widget.aspectRatio
                : 16 / 9;
            final width = widget.fillViewport
                ? constraints.maxWidth
                : math.min(
                    constraints.maxWidth,
                    constraints.maxHeight * aspect,
                  );
            final height = widget.fillViewport
                ? constraints.maxHeight
                : math.min(
                    constraints.maxHeight,
                    constraints.maxWidth / aspect,
                  );
            final fontSize = width < 600 ? 14.0 : 18.0;
            final scaler = MediaQuery.textScalerOf(context);
            final rowHeight = scaler.scale(fontSize) * 1.5;
            final rows = ((height * .55 - 8) / rowHeight).floor().clamp(0, 4);
            if (rows == 0) {
              _ticker.stop();
              _transition?.cancel();
              return const SizedBox.shrink();
            }
            final style = TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w300,
              color: Colors.white,
              height: 1.2,
              shadows: const [
                Shadow(
                  color: Colors.black,
                  blurRadius: 3,
                  offset: Offset(1, 1),
                ),
              ],
            );
            final layout = (
              controller,
              controller.dataRevision,
              width,
              rows,
              fontSize,
              scaler,
            );
            if (_layout != layout) {
              final old = _layout;
              if (old == null || _rowHeight != rowHeight) _widths.clear();
              _rowHeight = rowHeight;
              _layout = layout;
              _schedule = planDanmaku(
                controller.items,
                width: width,
                rows: rows,
                measure: (text) => _widths.putIfAbsent(text, () {
                  final painter = TextPainter(
                    text: TextSpan(text: text, style: style),
                    textDirection: TextDirection.ltr,
                    textScaler: scaler,
                    maxLines: 1,
                  )..layout();
                  final measured = painter.width;
                  painter.dispose();
                  return measured;
                }),
              );
              if (_widths.length > 600) _widths.clear();
            }
            if (_motionRevision != controller.motionRevision) {
              _motionRevision = controller.motionRevision;
              _moving = controller.moving;
              _rate = controller.rate;
              _resetClock(controller.positionMs.toDouble());
            }
            if (_gapClock.isRunning) {
              _position.value += _gapClock.elapsedMicroseconds / 1000 * _rate;
              _gapClock
                ..stop()
                ..reset();
            }
            _active = [
              for (final flight in _schedule)
                if (_position.value >= flight.item.timeMs &&
                    _position.value < flight.item.timeMs + danmakuLifetimeMs)
                  flight,
            ];
            if (_moving && _active.isNotEmpty && !_ticker.isActive) {
              _anchor = _position.value;
              _ticker.start();
            } else if ((!_moving || _active.isEmpty) && _ticker.isActive) {
              _ticker.stop();
            }
            if (_moving && _active.isEmpty) _gapClock.start();
            _scheduleTransition();
            return Center(
              child: SizedBox(
                width: width,
                height: height,
                child: ClipRect(
                  child: Flow(
                    delegate: DanmakuFlowDelegate(
                      flights: _active,
                      position: _position,
                      rowHeight: rowHeight,
                      width: width,
                    ),
                    children: [
                      for (final flight in _active)
                        RepaintBoundary(
                          key: ValueKey('danmaku-item-${flight.item.id}'),
                          child: SizedBox(
                            width: flight.width,
                            height: rowHeight,
                            child: Text(
                              flight.text,
                              style: style,
                              textScaler: scaler,
                              textDirection: TextDirection.ltr,
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class DanmakuFlowDelegate extends FlowDelegate {
  DanmakuFlowDelegate({
    required this.flights,
    required this.position,
    required this.rowHeight,
    required this.width,
  }) : super(repaint: position);
  final List<DanmakuFlight> flights;
  final ValueNotifier<double> position;
  final double rowHeight;
  final double width;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.tight(Size(flights[i].width, rowHeight));

  @override
  void paintChildren(FlowPaintingContext context) {
    for (var i = 0; i < flights.length; i++) {
      final flight = flights[i];
      final elapsed = (position.value - flight.item.timeMs).clamp(
        0,
        danmakuLifetimeMs,
      );
      final x = width - (width + flight.width) * elapsed / danmakuLifetimeMs;
      context.paintChild(
        i,
        transform: Matrix4.translationValues(x, 8 + flight.lane * rowHeight, 0),
      );
    }
  }

  @override
  bool shouldRepaint(DanmakuFlowDelegate oldDelegate) =>
      !identical(flights, oldDelegate.flights) ||
      width != oldDelegate.width ||
      rowHeight != oldDelegate.rowHeight ||
      position != oldDelegate.position;
}
