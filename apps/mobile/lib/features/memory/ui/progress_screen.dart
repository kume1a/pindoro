import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/progress.dart';
import 'package:pindoro/features/learning/ui/city_memory_card.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Progress, overview (board V3-60): City memory over 10 weeks, recall, the
/// whole-city date, the 14-day forecast and the districts.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final animate = !MediaQuery.disableAnimationsOf(context);
    final now = ref.watch(clockProvider)();
    return PageScaffold(
      title: l10n.progressTitle,
      children: switch (ref.watch(progressProvider)) {
        AsyncData(:final value) => () {
          final p = value;
          final recall = p.recall;
          final by = p.wholeCityBy;
          final average = (p.forecast.fold(0, (a, b) => a + b) / 14).round();
          return [
            CityMemoryCard(memory: p.city, history: p.history),
            Row(
              spacing: PindoroSpace.s2,
              children: [
                Expanded(
                  child: StatTile(
                    glyph: PindoroGlyph.checkCircle,
                    label: l10n.progressRecall,
                    value: recall == null
                        ? l10n.progressNoValue
                        : l10n.sessionPercent((100 * recall).round()),
                  ),
                ),
                Expanded(
                  child: StatTile(
                    glyph: PindoroGlyph.flag,
                    label: l10n.progressWholeCity,
                    value: by == null
                        ? l10n.progressNoValue
                        : DateFormat.yMMM(locale).format(by),
                  ),
                ),
              ],
            ),
            ForecastBars(
              counts: p.forecast,
              title: l10n.progressForecastTitle,
              average: l10n.progressForecastAverage(formatNumber(average)),
              startLabel: l10n.progressToday,
              endLabel: DateFormat.MMMd(
                locale,
              ).format(now.add(const Duration(days: 13))),
              semanticsLabel: l10n.a11yForecast(
                formatNumber(average),
                formatNumber(p.forecast.first),
              ),
              animate: animate,
            ),
            ListGroup(
              children: [
                for (final d in p.districts)
                  _DistrictRow(
                    district: d,
                    learning: p.learning?.parentId == d.district.id
                        ? p.learning
                        : null,
                    name: districtName(d.district, settings),
                    learningName: switch (p.learning) {
                      final l? => districtName(l, settings),
                      null => null,
                    },
                  ),
              ],
            ),
          ];
        }(),
        _ => const [Center(child: LaneLoader())],
      },
    );
  }
}

class _DistrictRow extends StatelessWidget {
  const _DistrictRow({
    required this.district,
    required this.learning,
    required this.name,
    required this.learningName,
  });

  final RaionProgress district;
  final District? learning;
  final String name;
  final String? learningName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final m = district.memory;
    final mastered = m.counts[MemoryState.mastered]!;
    final subtitle = [
      l10n.commonXOfY(formatNumber(m.memory.round()), formatNumber(m.total)),
      if (learning != null && learningName != null)
        l10n.progressLearning(learningName!)
      else if (mastered > 0)
        l10n.progressMasteredCount(formatNumber(mastered)),
    ].join(' · ');
    final bar = memoryBarLabel(l10n, name, m);
    return ListRow(
      leading: const RowTile(PindoroGlyph.district),
      title: name,
      subtitle: subtitle,
      below: MemoryBar(
        counts: memoryCountsOf(m),
        semanticsLabel: bar,
        compact: true,
      ),
      trailing: const PindoroIcon(PindoroGlyph.chevronRight),
      semanticsLabel: '$name. $subtitle. $bar',
      onTap: () => context.push(Routes.progressOf(district.district.id)),
    );
  }
}
