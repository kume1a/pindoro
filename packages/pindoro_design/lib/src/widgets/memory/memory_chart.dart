import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../motion.dart';
import 'memory_parts.dart';

/// The top of the memory chart's y range: the largest value plus 5 %,
/// rounded up to a step one decade below it; never under 100, so a first
/// day's few streets sit low instead of filling the chart.
@visibleForTesting
double chartTop(double max) {
  if (max <= 0) return _minTop;
  final step = math.pow(10, (math.log(max) / math.ln10).floor() - 1).toDouble();
  return math.max(_minTop, (max * 1.05 / step).ceil() * step);
}

const double _minTop = 100;

/// The plot's height; labels sit [PindoroSpace.s1] below it (132 dp in all).
const double _plotHeight = 110;

/// A point of the memory chart: [at] from 0 (the start label) to 1 (now).
typedef ChartPoint = ({double at, double value});

/// City memory over time (Memory chart): [points] oldest first, the last one
/// now, a line over its area, a dot per point and a ringed dot for now;
/// gridlines at half and full height labelled with [format]; [days] ticks
/// along the base for a daily window (0: none); [startLabel] and [endLabel]
/// under the ends. With [animate] the line draws in, then the area fades and
/// the dot pops; never under reduce motion.
class MemoryChart extends StatelessWidget {
  const MemoryChart({
    super.key,
    required this.points,
    required this.startLabel,
    required this.endLabel,
    required this.semanticsLabel,
    this.days = 0,
    this.format = plainNumber,
    this.animate = false,
  });

  final List<ChartPoint> points;
  final int days;
  final String Function(int value) format;
  final String startLabel;
  final String endLabel;
  final String semanticsLabel;
  final bool animate;

  static final Duration _line = PindoroMotion.durationSlow * 2;
  static final Duration _total = _line + PindoroMotion.durationSlow;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final label = PindoroType.labelMd.copyWith(color: c.textSecondary);
    final grid = PindoroType.labelSm.copyWith(color: c.textSecondary);
    Widget plot(double t) {
      double phase(Duration from, Duration span) =>
          ((t * _total.inMicroseconds - from.inMicroseconds) /
                  span.inMicroseconds)
              .clamp(0, 1);
      return CustomPaint(
        size: const Size(double.infinity, _plotHeight),
        painter: _MemoryChartPainter(
          points: points,
          days: days,
          gridLabel: (v) => TextSpan(text: format(v), style: grid),
          colors: c,
          line: PindoroMotion.easeStandard.transform(
            phase(Duration.zero, _line),
          ),
          area: phase(_line, PindoroMotion.durationBase),
          dot: PindoroMotion.easeOvershoot.transform(
            phase(_line, PindoroMotion.durationSlow),
          ),
        ),
      );
    }

    return Semantics(
      image: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroSpace.s1,
          children: [
            GrowOnce(animate: animate, duration: _total, builder: plot),
            EndLabels(startLabel, endLabel, style: label),
          ],
        ),
      ),
    );
  }
}

class _MemoryChartPainter extends CustomPainter {
  _MemoryChartPainter({
    required this.points,
    required this.days,
    required this.gridLabel,
    required this.colors,
    required this.line,
    required this.area,
    required this.dot,
  });

  final List<ChartPoint> points;
  final int days;
  final TextSpan Function(int value) gridLabel;
  final PindoroColors colors;

  /// Progress of the line drawing in, the area fading and the dot popping.
  final double line;
  final double area;
  final double dot;

  static const double _dot = 3.5;
  static const double _now = 5;
  static const double _tick = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height;
    const left = 2.0;
    final right = size.width - _now - 2;
    final top = chartTop(points.map((p) => p.value).fold<double>(0, math.max));
    double y(double v) => bottom * (1 - v.clamp(0, top) / top);
    for (final v in [top / 2, top]) {
      canvas.drawLine(
        Offset(0, y(v)),
        Offset(size.width, y(v)),
        Paint()
          ..color = colors.lineBase
          ..strokeWidth = PindoroStroke.hairline,
      );
      TextPainter(text: gridLabel(v.round()), textDirection: TextDirection.ltr)
        ..layout()
        ..paint(canvas, Offset(0, y(v) + 2))
        ..dispose();
    }
    canvas.drawLine(
      Offset(0, bottom),
      Offset(size.width, bottom),
      Paint()
        ..color = colors.lineStrong
        ..strokeWidth = PindoroStroke.base,
    );
    double x(double at) => left + (right - left) * at.clamp(0, 1);
    final tick = Paint()
      ..color = colors.chartLine.withValues(alpha: PindoroOpacity.mask)
      ..strokeWidth = PindoroStroke.base
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < days; i++) {
      final at = x(days == 1 ? 1 : i / (days - 1));
      canvas.drawLine(Offset(at, bottom - _tick), Offset(at, bottom), tick);
    }
    if (points.isEmpty) return;
    final offsets = [for (final p in points) Offset(x(p.at), y(p.value))];
    final path = Path()..addPolygon(offsets, false);
    if (offsets.length > 1) {
      canvas.drawPath(
        Path.from(path)
          ..lineTo(offsets.last.dx, bottom)
          ..lineTo(offsets.first.dx, bottom)
          ..close(),
        Paint()..color = colors.chartArea.withValues(alpha: area),
      );
      final drawn = Path();
      for (final metric in path.computeMetrics()) {
        drawn.addPath(metric.extractPath(0, metric.length * line), Offset.zero);
      }
      canvas.drawPath(
        drawn,
        Paint()
          ..color = colors.chartLine
          ..style = PaintingStyle.stroke
          ..strokeWidth = PindoroStroke.thick
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    final fill = Paint()..color = colors.chartLine;
    for (final p in offsets.take(offsets.length - 1)) {
      canvas.drawCircle(p, _dot * line, fill);
    }
    if (dot > 0) {
      canvas
        ..drawCircle(
          offsets.last,
          (_now + PindoroStroke.thick / 2) * dot,
          Paint()..color = colors.surfaceRaised,
        )
        ..drawCircle(offsets.last, _now * dot, fill);
    }
  }

  @override
  bool shouldRepaint(_MemoryChartPainter old) =>
      old.points != points ||
      old.days != days ||
      old.colors != colors ||
      old.line != line ||
      old.area != area ||
      old.dot != dot;
}
