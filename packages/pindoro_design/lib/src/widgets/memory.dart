import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'surfaces.dart';

/// Counts per memory state for a set of streets; [total] is every street in
/// the set (the rest is track).
typedef MemoryCounts = ({
  int mastered,
  int solid,
  int known,
  int seen,
  int total,
});

/// The legend's names, in the app's language.
typedef MemoryNames = ({
  String mastered,
  String solid,
  String known,
  String seen,
});

/// The states strongest first, each with its count and colour.
List<(int, Color)> _states(MemoryCounts n, PindoroColors c) => [
  (n.mastered, c.memoryMastered),
  (n.solid, c.memorySolid),
  (n.known, c.memoryKnown),
  (n.seen, c.memorySeen),
];

bool _moving(BuildContext context, bool animate) =>
    animate && !MediaQuery.disableAnimationsOf(context);

/// Each non-empty segment's width in a bar [width] wide: its share of
/// [total], with [PindoroStroke.base] gaps between segments.
@visibleForTesting
List<double> memorySegmentWidths(List<int> counts, int total, double width) {
  final filled = counts.where((n) => n > 0).toList();
  if (filled.isEmpty || total <= 0) return const [];
  final room = math.max(0, width - PindoroStroke.base * (filled.length - 1));
  return [for (final n in filled) room * math.min(n, total) / total];
}

/// How well the player knows a set of streets (Memory bar): Mastered, Solid,
/// Known and Seen as shares of [counts]' total, the rest the track. Card
/// size 14 dp, [compact] 6 dp. With [animate] the segments grow from the left
/// on first show; never under reduce motion.
class MemoryBar extends StatelessWidget {
  const MemoryBar({
    super.key,
    required this.counts,
    required this.semanticsLabel,
    this.compact = false,
    this.animate = false,
  });

  final MemoryCounts counts;
  final String semanticsLabel;
  final bool compact;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final states = [
      for (final s in _states(counts, c))
        if (s.$1 > 0) s,
    ];
    Widget bar(double t) => LayoutBuilder(
      builder: (context, box) {
        final widths = memorySegmentWidths(
          [for (final s in states) s.$1],
          counts.total,
          box.maxWidth,
        );
        return Row(
          spacing: PindoroStroke.base,
          children: [
            for (final (i, (_, colour)) in states.indexed)
              SizedBox(
                width: widths[i],
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: SizedBox(
                    width: widths[i] * t,
                    height: double.infinity,
                    child: ColoredBox(color: colour),
                  ),
                ),
              ),
          ],
        );
      },
    );
    return Semantics(
      image: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(PindoroRadius.xs),
          child: ColoredBox(
            color: c.progressTrack,
            child: SizedBox(
              height: compact ? 6 : 14,
              width: double.infinity,
              child: _moving(context, animate)
                  ? TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: PindoroMotion.durationSlow,
                      curve: PindoroMotion.easeStandard,
                      builder: (_, t, _) => bar(t),
                    )
                  : bar(1),
            ),
          ),
        ),
      ),
    );
  }
}

String _plain(int n) => '$n';

/// The memory bar's legend: a swatch, the state's name and its count, in the
/// bar's order. Hidden from screen readers: the bar's label says it all.
class MemoryLegend extends StatelessWidget {
  const MemoryLegend({
    super.key,
    required this.counts,
    required this.names,
    this.format = _plain,
  });

  final MemoryCounts counts;
  final MemoryNames names;

  /// Writes a count (the app passes its number format).
  final String Function(int count) format;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final style = PindoroType.labelMd.copyWith(color: c.textPrimary);
    final named = [names.mastered, names.solid, names.known, names.seen];
    return ExcludeSemantics(
      child: Wrap(
        spacing: PindoroSpace.s3,
        runSpacing: PindoroSpace.s2,
        children: [
          for (final (i, (count, colour)) in _states(counts, c).indexed)
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: PindoroSpace.s1,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: colour,
                    borderRadius: BorderRadius.circular(PindoroRadius.xs),
                  ),
                ),
                Text.rich(
                  TextSpan(
                    text: '${named[i]} ',
                    children: [
                      TextSpan(
                        text: format(count),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  style: style,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The top of the memory chart's y range: the largest value plus 5 %,
/// rounded up to a step one decade below it; at least 10.
@visibleForTesting
double chartTop(double max) {
  if (max <= 0) return 10;
  final step = math.pow(10, (math.log(max) / math.ln10).floor() - 1).toDouble();
  return math.max(10, (max * 1.05 / step).ceil() * step);
}

/// The plot's height; labels sit [PindoroSpace.s1] below it (132 dp in all).
const double _plotHeight = 110;

/// City memory over the last weeks (Memory chart): [values] oldest first, the
/// last one today, a line over its area with today's dot; [startLabel] and
/// [endLabel] under the ends. With [animate] the line draws in, then the
/// area fades and the dot pops; never under reduce motion.
class MemoryChart extends StatelessWidget {
  const MemoryChart({
    super.key,
    required this.values,
    required this.startLabel,
    required this.endLabel,
    required this.semanticsLabel,
    this.animate = false,
  });

  final List<double> values;
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
    Widget plot(double t) {
      double phase(Duration from, Duration span) =>
          ((t * _total.inMicroseconds - from.inMicroseconds) /
                  span.inMicroseconds)
              .clamp(0, 1);
      return CustomPaint(
        size: const Size(double.infinity, _plotHeight),
        painter: _MemoryChartPainter(
          values: values,
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
            if (_moving(context, animate))
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: _total,
                builder: (_, t, _) => plot(t),
              )
            else
              plot(1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              spacing: PindoroSpace.s3,
              children: [
                Flexible(child: Text(startLabel, style: label)),
                Flexible(
                  child: Text(endLabel, style: label, textAlign: TextAlign.end),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryChartPainter extends CustomPainter {
  _MemoryChartPainter({
    required this.values,
    required this.colors,
    required this.line,
    required this.area,
    required this.dot,
  });

  final List<double> values;
  final PindoroColors colors;

  /// Progress of the line drawing in, the area fading and the dot popping.
  final double line;
  final double area;
  final double dot;

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height;
    canvas.drawLine(
      Offset(0, bottom),
      Offset(size.width, bottom),
      Paint()
        ..color = colors.lineBase
        ..strokeWidth = PindoroStroke.base,
    );
    if (values.isEmpty) return;
    const left = 2.0;
    final right = size.width - 5;
    final top = chartTop(values.reduce(math.max));
    final points = [
      for (final (i, v) in values.indexed)
        Offset(
          values.length == 1
              ? right
              : left + (right - left) * i / (values.length - 1),
          bottom * (1 - v.clamp(0, top) / top),
        ),
    ];
    final path = Path()..addPolygon(points, false);
    if (points.length > 1) {
      canvas.drawPath(
        Path.from(path)
          ..lineTo(right, bottom)
          ..lineTo(left, bottom)
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
    if (dot > 0) {
      canvas.drawCircle(
        points.last,
        5 * dot,
        Paint()..color = colors.chartLine,
      );
    }
  }

  @override
  bool shouldRepaint(_MemoryChartPainter old) =>
      old.values != values ||
      old.colors != colors ||
      old.line != line ||
      old.area != area ||
      old.dot != dot;
}

/// The bars' height.
const double _barsHeight = 56;

/// Each bar's height in the [ForecastBars] row: its share of the busiest
/// day's count, which fills the row.
@visibleForTesting
List<double> forecastBarHeights(List<int> counts) {
  final busiest = counts.fold(0, math.max);
  return [for (final n in counts) busiest == 0 ? 0 : _barsHeight * n / busiest];
}

/// Reviews coming due on each of the next days (Forecast bars): a card with
/// [title] and the daily [average], one bar a day with today's ([counts]
/// first) highlighted, [startLabel] and [endLabel] under the ends. One
/// screen-reader node, [semanticsLabel]. With [animate] the bars grow from
/// the bottom, today first; never under reduce motion.
class ForecastBars extends StatelessWidget {
  const ForecastBars({
    super.key,
    required this.counts,
    required this.title,
    required this.average,
    required this.startLabel,
    required this.endLabel,
    required this.semanticsLabel,
    this.animate = false,
    this.highlightFirst = true,
  });

  final List<int> counts;
  final String title;
  final String average;
  final String startLabel;
  final String endLabel;
  final String semanticsLabel;
  final bool animate;

  /// Paints the first bar as today; off where the bars aren't days.
  final bool highlightFirst;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final label = PindoroType.labelMd.copyWith(color: c.textSecondary);
    final heights = forecastBarHeights(counts);
    final total =
        PindoroMotion.durationBase +
        PindoroMotion.stagger * math.max(0, counts.length - 1);
    Widget bars(double t) => CustomPaint(
      size: const Size(double.infinity, _barsHeight),
      painter: _ForecastPainter(
        heights: [
          for (final (i, h) in heights.indexed)
            h *
                PindoroMotion.easeDecelerate.transform(
                  ((t * total.inMicroseconds -
                              (PindoroMotion.stagger * i).inMicroseconds) /
                          PindoroMotion.durationBase.inMicroseconds)
                      .clamp(0, 1),
                ),
        ],
        colors: c,
        highlightFirst: highlightFirst,
      ),
    );
    return Semantics(
      container: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: LipBox(
        border: c.lineBase,
        padding: const EdgeInsets.symmetric(
          horizontal: PindoroSpace.s4,
          vertical: PindoroSpace.s3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroSpace.s2,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              spacing: PindoroSpace.s3,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: PindoroType.titleSm.copyWith(color: c.textPrimary),
                  ),
                ),
                Text(average, style: label),
              ],
            ),
            if (_moving(context, animate))
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: total,
                builder: (_, t, _) => bars(t),
              )
            else
              bars(1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              spacing: PindoroSpace.s3,
              children: [
                Flexible(child: Text(startLabel, style: label)),
                Flexible(
                  child: Text(endLabel, style: label, textAlign: TextAlign.end),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ForecastPainter extends CustomPainter {
  _ForecastPainter({
    required this.heights,
    required this.colors,
    required this.highlightFirst,
  });

  final List<double> heights;
  final PindoroColors colors;
  final bool highlightFirst;

  @override
  void paint(Canvas canvas, Size size) {
    if (heights.isEmpty) return;
    const gap = PindoroSpace.s1;
    final width = (size.width - gap * (heights.length - 1)) / heights.length;
    for (final (i, h) in heights.indexed) {
      if (h <= 0) continue;
      final radius = math.min(PindoroRadius.xs, math.min(width, h) / 2);
      canvas.drawRRect(
        RRect.fromLTRBR(
          i * (width + gap),
          size.height - h,
          i * (width + gap) + width,
          size.height,
          Radius.circular(radius),
        ),
        Paint()
          ..color = highlightFirst && i == 0
              ? colors.chartBarToday
              : colors.chartBar,
      );
    }
  }

  @override
  bool shouldRepaint(_ForecastPainter old) =>
      !listEquals(old.heights, heights) ||
      old.colors != colors ||
      old.highlightFirst != highlightFirst;
}
