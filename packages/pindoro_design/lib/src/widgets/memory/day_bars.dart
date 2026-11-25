import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../motion.dart';
import '../surfaces.dart';
import '../whole_words.dart';
import 'memory_parts.dart';

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
    return TitledCard(
      title: title,
      meta: average,
      semanticsLabel: semanticsLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s2,
        children: [
          GrowOnce(animate: animate, duration: total, builder: bars),
          EndLabels(startLabel, endLabel, style: label),
        ],
      ),
    );
  }
}

/// The week strip's bar height.
const double _weekBar = 44;

/// What comes due on each of the next seven days (Next 7 days strip): a
/// [TitledCard] with seven columns, each the day's count over a bar sized
/// against the week's busiest day and the day's [labels] entry; today
/// ([counts] first) in `color.chart.bar-today`. A 0 day keeps its "0" and a
/// 2 dp stub. One screen-reader node, [semanticsLabel].
class WeekBars extends StatelessWidget {
  const WeekBars({
    super.key,
    required this.counts,
    required this.labels,
    required this.title,
    required this.meta,
    required this.semanticsLabel,
    this.format = plainNumber,
  });

  final List<int> counts;
  final List<String> labels;
  final String title;
  final String meta;
  final String semanticsLabel;
  final String Function(int count) format;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final busiest = counts.fold(0, math.max);
    return TitledCard(
      title: title,
      meta: meta,
      semanticsLabel: semanticsLabel,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: PindoroSpace.s1,
        children: [
          for (final (i, n) in counts.indexed)
            Expanded(
              child: Column(
                spacing: 2,
                children: [
                  WholeWords(
                    Text(
                      format(n),
                      style: PindoroType.labelMd.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: _weekBar,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: math.max(
                          PindoroStroke.base,
                          busiest == 0 ? 0 : _weekBar * n / busiest,
                        ),
                        decoration: BoxDecoration(
                          color: i == 0 ? c.chartBarToday : c.chartBar,
                          borderRadius: BorderRadius.circular(PindoroRadius.xs),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    style: PindoroType.labelSm.copyWith(
                      color: i == 0 ? c.textPrimary : c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
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
