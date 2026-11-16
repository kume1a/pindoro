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

/// The City memory card (design system City memory card): on Today the change
/// since yesterday and a note; with [history], the Progress overview's share
/// and 10-week chart.
class CityMemoryCard extends StatelessWidget {
  const CityMemoryCard({
    super.key,
    required this.memory,
    this.sinceYesterday,
    this.history,
    this.onTap,
  });

  final MemorySummary memory;
  final double? sinceYesterday;
  final ({DateTime start, List<double> values})? history;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final animate = !MediaQuery.disableAnimationsOf(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final number = formatNumber(memory.memory.round());
    final total = formatNumber(memory.total);
    final change = sinceYesterday;
    final history = this.history;
    final percent = memory.total == 0
        ? 0
        : (100 * memory.memory / memory.total).round();
    final card = LipBox(
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
              signedNumber(change ?? 0),
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
                      history == null
                          ? l10n.sessionDoneMemory
                          : l10n.progressCityMemory,
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
                                ' ${history == null ? l10n.memoryOfStreets(total) : l10n.progressOfShare(total, formatNumber(percent))}',
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
                    l10n.memorySinceYesterday(signedNumber(change)),
                    style: PindoroType.labelMd.copyWith(
                      color: change.round() < 0
                          ? c.textSecondary
                          : c.successText,
                    ),
                  ),
              ],
            ),
          ),
          if (history != null)
            MemoryChart(
              values: history.values,
              startLabel: DateFormat.MMMd(locale).format(history.start),
              endLabel: l10n.progressToday,
              semanticsLabel: l10n.a11yMemoryChart(
                formatNumber(history.values.first.round()),
                formatNumber(history.values.last.round()),
              ),
              animate: animate,
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
          if (history == null)
            Text(
              l10n.memoryNote,
              style: PindoroType.bodySm.copyWith(color: c.textSecondary),
            ),
        ],
      ),
    );
    final onTap = this.onTap;
    return onTap == null ? card : Tappable(onTap: onTap, child: card);
  }
}
