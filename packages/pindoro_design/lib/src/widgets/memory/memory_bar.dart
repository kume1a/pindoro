import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../graphics.dart';
import '../motion.dart';
import '../surfaces.dart';
import '../tappable.dart';
import 'memory_parts.dart';

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
              child: GrowOnce(
                animate: animate,
                duration: PindoroMotion.durationSlow,
                curve: PindoroMotion.easeStandard,
                builder: bar,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The memory bar's legend: a swatch, the state's name and its count, in the
/// bar's order. Hidden from screen readers: the bar's label says it all.
class MemoryLegend extends StatelessWidget {
  const MemoryLegend({
    super.key,
    required this.counts,
    required this.names,
    this.format = plainNumber,
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

/// City memory at row size (City memory row, Today): `title.sm` [label],
/// [value] in `numeric.sm`, [of] in secondary text, the [change] at the end
/// (`color.success.text` up, secondary [down], never red; it wraps under the
/// figure when space runs out), a chevron, and the compact [MemoryBar] under
/// them. The whole row opens [onTap]; it reads as [semanticsLabel].
class MemoryRow extends StatelessWidget {
  const MemoryRow({
    super.key,
    required this.label,
    required this.value,
    required this.of,
    required this.counts,
    required this.semanticsLabel,
    required this.onTap,
    this.change,
    this.down = false,
  });

  final String label;
  final String value;
  final String of;
  final String? change;
  final bool down;
  final MemoryCounts counts;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final change = this.change;
    return Tappable(
      onTap: onTap,
      label: semanticsLabel,
      child: LipBox(
        border: c.lineBase,
        padding: const EdgeInsets.symmetric(
          horizontal: PindoroSpace.s4,
          vertical: PindoroSpace.s3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroSpace.s2,
          children: [
            Row(
              spacing: PindoroSpace.s2,
              children: [
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: PindoroSpace.s2,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$label  ',
                              style: PindoroType.titleSm.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                            TextSpan(
                              text: value,
                              style: PindoroType.numericSm.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                            TextSpan(
                              text: ' $of',
                              style: PindoroType.bodySm.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (change != null)
                        Text(
                          change,
                          style: PindoroType.labelMd.copyWith(
                            color: down ? c.textSecondary : c.successText,
                          ),
                        ),
                    ],
                  ),
                ),
                PindoroIcon(
                  PindoroGlyph.chevronRight,
                  size: PindoroSize.iconSm,
                  color: c.textSecondary,
                ),
              ],
            ),
            MemoryBar(counts: counts, semanticsLabel: '', compact: true),
          ],
        ),
      ),
    );
  }
}
