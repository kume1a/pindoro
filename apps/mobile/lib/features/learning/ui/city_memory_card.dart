import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/features/learning/data/progress.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// The memory bar's counts for [m].
MemoryCounts memoryCountsOf(MemorySummary m) => (
  mastered: m.counts[MemoryState.mastered]!,
  solid: m.counts[MemoryState.solid]!,
  known: m.counts[MemoryState.known]!,
  seen: m.counts[MemoryState.seen]!,
  total: m.total,
);

MemoryNames memoryNames(AppLocalizations l10n) => (
  mastered: l10n.memoryMastered,
  solid: l10n.memorySolid,
  known: l10n.memoryKnown,
  seen: l10n.memorySeen,
);

/// The memory bar's one label: "[name]: 412 mastered, … of 3 282".
String memoryBarLabel(AppLocalizations l10n, String name, MemorySummary m) {
  final c = memoryCountsOf(m);
  return l10n.a11yMemoryBar(
    name,
    formatNumber(c.mastered),
    formatNumber(c.solid),
    formatNumber(c.known),
    formatNumber(c.seen),
    formatNumber(c.total),
  );
}

/// "+8", "−41".
String signedNumber(double change) {
  final n = change.round();
  return n >= 0 ? '+${formatNumber(n)}' : formatNumber(n);
}

/// "+8 since yesterday", "−41 this week" ([week] set), or "+20 today" on
/// the [firstDay]; null when it rounds to no change.
String? memoryChange(
  AppLocalizations l10n,
  double change, {
  bool week = false,
  bool firstDay = false,
}) {
  if (change.round() == 0) return null;
  final signed = signedNumber(change);
  return week
      ? l10n.memoryThisWeek(signed)
      : firstDay
      ? l10n.memoryToday(signed)
      : l10n.memorySinceYesterday(signed);
}

/// City memory at row size (City memory row, Today): the figure, its
/// [change] and the thin bar; it opens Progress ([onTap]).
class CityMemoryRow extends StatelessWidget {
  const CityMemoryRow({
    super.key,
    required this.memory,
    required this.change,
    required this.onTap,
  });

  final MemorySummary memory;
  final ({double value, String? label}) change;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final number = formatNumber(memory.memory.round());
    final total = formatNumber(memory.total);
    return MemoryRow(
      label: l10n.sessionDoneMemory,
      value: number,
      of: l10n.memoryOf(total),
      change: change.label,
      down: change.value.round() < 0,
      counts: memoryCountsOf(memory),
      semanticsLabel: l10n.a11yCityMemory(
        number,
        total,
        signedNumber(change.value),
      ),
      onTap: onTap,
    );
  }
}

/// The City memory card (Progress): the figure and its share, the change
/// since yesterday, the chart over [history] with the caption naming its
/// window, the memory bar, its legend and the note.
class CityMemoryCard extends StatelessWidget {
  const CityMemoryCard({
    super.key,
    required this.memory,
    required this.history,
    required this.sinceYesterday,
  });

  final MemorySummary memory;
  final MemoryHistory history;
  final double sinceYesterday;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final animate = !MediaQuery.disableAnimationsOf(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final number = formatNumber(memory.memory.round());
    final total = formatNumber(memory.total);
    final percent = memory.total == 0
        ? 0
        : (100 * memory.memory / memory.total).round();
    final firstDay =
        history.window == MemoryWindow.daily && history.points.length == 1;
    final change = memoryChange(l10n, sinceYesterday, firstDay: firstDay);
    final points = history.points;
    return LipBox(
      border: c.lineBase,
      radius: PindoroRadius.xl,
      padding: const EdgeInsets.all(PindoroSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: [
          Semantics(
            container: true,
            label: l10n.a11yCityMemory(
              number,
              total,
              signedNumber(sinceYesterday),
            ),
            excludeSemantics: true,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: PindoroSpace.s3,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.progressCityMemory,
                      style: PindoroType.labelMd.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: number,
                            style: PindoroType.headlineLg.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                          TextSpan(
                            text:
                                ' ${l10n.progressOfShare(total, formatNumber(percent))}',
                            style: PindoroType.bodySm.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (change != null)
                  Text(
                    change,
                    style: PindoroType.labelMd.copyWith(
                      color: sinceYesterday.round() < 0
                          ? c.textSecondary
                          : c.successText,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s1,
            children: [
              MemoryChart(
                points: points,
                days: history.days,
                format: formatNumber,
                startLabel: DateFormat.MMMd(locale).format(history.start),
                endLabel: l10n.progressToday,
                semanticsLabel: l10n.a11yMemoryChart(
                  formatNumber(points.first.value.round()),
                  formatNumber(points.last.value.round()),
                ),
                animate: animate,
              ),
              Text(switch (history.window) {
                MemoryWindow.daily when firstDay => l10n.memoryChartFirstDay,
                MemoryWindow.daily => l10n.memoryChartDaily,
                MemoryWindow.weekly => l10n.memoryChartWeekly,
                MemoryWindow.lastWeeks => l10n.memoryChartLastWeeks,
              }, style: PindoroType.bodySm.copyWith(color: c.textSecondary)),
            ],
          ),
          MemoryBar(
            counts: memoryCountsOf(memory),
            semanticsLabel: memoryBarLabel(
              l10n,
              l10n.sessionDoneMemory,
              memory,
            ),
            animate: animate,
          ),
          MemoryLegend(
            counts: memoryCountsOf(memory),
            names: memoryNames(l10n),
            format: formatNumber,
          ),
          Text(
            l10n.memoryNote,
            style: PindoroType.bodySm.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}
