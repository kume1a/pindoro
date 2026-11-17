import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/progress.dart';
import 'package:pindoro/features/learning/ui/city_memory_card.dart';
import 'package:pindoro/features/learning/ui/city_tab_page.dart';
import 'package:pindoro/features/map/ui/widgets/map_attribution.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Progress (canvas V31-30): how memory grows (the City memory card, recall
/// and the whole-city date), what's coming (the 14-day forecast, the
/// neighbourhoods in teaching order) and where it grows (the district map
/// and the districts, the one being learnt first).
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final animate = !MediaQuery.disableAnimationsOf(context);
    final now = ref.watch(clockProvider)();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    Future<void> open(String id) => context.push(Routes.progressOf(id));
    return CityTabPage(
      children: switch (ref.watch(progressProvider)) {
        AsyncData(value: final p) => () {
          final recall = p.recall;
          final by = p.wholeCityBy;
          final average = (p.forecast.fold(0, (a, b) => a + b) / 14).round();
          final learning = p.coming
              .where((c) => c.stage == ChunkStage.now)
              .firstOrNull
              ?.chunk;
          final learningRaion = learning?.parentId;
          final districts = [
            ...p.districts.where((d) => d.district.id == learningRaion),
            ...p.districts.where((d) => d.district.id != learningRaion),
          ];
          return [
            CityMemoryCard(
              memory: p.city,
              history: p.history,
              sinceYesterday: p.sinceYesterday,
            ),
            TileGrid(columns: scale >= TileGrid.stackAt ? 1 : 2, [
              StatTile(
                glyph: PindoroGlyph.checkCircle,
                label: l10n.progressRecall,
                value: recall == null
                    ? l10n.progressNoValue
                    : l10n.sessionPercent((100 * recall).round()),
                caption: recall == null ? l10n.progressRecallWaiting : null,
              ),
              StatTile(
                glyph: PindoroGlyph.flag,
                label: l10n.progressWholeCity,
                value: by == null
                    ? l10n.progressNoValue
                    : DateFormat.yMMM(locale).format(by),
                caption: by == null
                    ? null
                    : l10n.progressWholeCityPace(
                        formatNumber(
                          LearningConfig.newPerDay[settings?.minutesPerDay] ??
                              0,
                        ),
                      ),
              ),
            ]),
            SectionTitle(l10n.progressComing),
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
            if (p.roads.isNotEmpty || p.coming.isNotEmpty)
              ListGroup(
                children: [
                  for (final (i, road) in p.roads.indexed)
                    _ComingRow(
                      title: l10n.roadBand(road.band.name),
                      subtitle:
                          (i == 0 ? l10n.progressLearningNow : l10n.commonXOfY)(
                            formatNumber(road.seen),
                            formatNumber(road.memory.total),
                          ),
                      now: i == 0,
                    ),
                  for (final chunk in p.coming)
                    _ComingRow(
                      title: districtName(chunk.chunk, settings),
                      subtitle: _chunkSubtitle(
                        l10n,
                        chunk,
                        after: switch ((chunk.after, p.roads.lastOrNull)) {
                          (final d?, _) => districtName(d, settings),
                          (null, final road?) => l10n.roadBand(road.band.name),
                          _ => null,
                        },
                      ),
                      now: chunk.stage == ChunkStage.now,
                      onTap: switch (chunk.chunk.parentId) {
                        final raion? => () => open(raion),
                        null => null,
                      },
                    ),
                ],
              ),
            if (districts.isNotEmpty) ...[
              SectionTitle(
                l10n.progressWhereItGrows,
                meta: _whereMeta(l10n, districts),
              ),
              _DistrictMap(
                districts: districts,
                settings: settings,
                onTap: open,
              ),
              const DistrictLegend(),
              ListGroup(
                children: [
                  for (final d in districts)
                    _DistrictRow(
                      district: d,
                      learning: d.district.id == learningRaion
                          ? learning
                          : null,
                      settings: settings,
                      onTap: () => open(d.district.id),
                    ),
                ],
              ),
            ],
          ];
        }(),
        _ => const [Center(child: LaneLoader())],
      },
    );
  }
}

bool _mastered(MemorySummary m) =>
    m.total > 0 && m.counts[MemoryState.mastered] == m.total;

DistrictProgress _fill(MemorySummary m) => DistrictProgress.of(
  m.total == 0 ? 0 : m.memory / m.total,
  mastered: _mastered(m),
);

/// "1 Mastered", "all 10 started" or "9 of 10 districts started".
String _whereMeta(AppLocalizations l10n, List<RaionProgress> districts) {
  final mastered = districts.where((d) => _mastered(d.memory)).length;
  final started = districts.where((d) => d.memory.memory.round() > 0).length;
  final total = formatNumber(districts.length);
  return mastered > 0
      ? l10n.progressDistrictsMastered(formatNumber(mastered))
      : started == districts.length
      ? l10n.progressAllStarted(total)
      : l10n.progressDistrictsStarted(formatNumber(started), total);
}

/// The districts in their fill steps, the attribution on the map.
class _DistrictMap extends ConsumerWidget {
  const _DistrictMap({
    required this.districts,
    required this.settings,
    required this.onTap,
  });

  final List<RaionProgress> districts;
  final Settings? settings;
  final void Function(String id) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final city = ref.watch(packRepositoryProvider).value?.city();
    final started = districts.where((d) => d.memory.memory.round() > 0);
    return DistrictMap(
      districts: [
        for (final d in districts)
          (
            boundary: d.district.boundary,
            progress: _fill(d.memory),
            name: districtName(d.district, settings),
            labelAt: d.district.center,
          ),
      ],
      semanticsLabel: l10n.a11yDistrictMap(
        city == null ? '' : context.localName(ka: city.nameKa, en: city.nameEn),
        formatNumber(started.length),
        formatNumber(districts.where((d) => _mastered(d.memory)).length),
      ),
      onTap: (i) => onTap(districts[i].district.id),
      overlay: const Positioned(
        left: PindoroSpace.s2,
        bottom: PindoroSpace.s2,
        child: MapAttribution(),
      ),
    );
  }
}

/// A neighbourhood's line in "What's coming": being learnt, or locked and the
/// step it starts [after].
String _chunkSubtitle(
  AppLocalizations l10n,
  ChunkProgress chunk, {
  required String? after,
}) {
  final total = formatNumber(chunk.memory.total);
  return chunk.stage == ChunkStage.now
      ? l10n.progressLearningNow(formatNumber(chunk.seen), total)
      : after == null
      ? l10n.commonXOfY(formatNumber(chunk.seen), total)
      : l10n.progressChunkAfter(after, total);
}

/// A step in teaching order, a road class or a neighbourhood: the one being
/// learnt ([now]), then locked ones.
class _ComingRow extends StatelessWidget {
  const _ComingRow({
    required this.title,
    required this.subtitle,
    required this.now,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return ListRow(
      leading: now
          ? RowTile(PindoroGlyph.play, face: c.primaryBase, ink: c.primaryOn)
          : RowTile(
              PindoroGlyph.lock,
              face: c.surfaceSunken,
              ink: c.textSecondary,
            ),
      title: title,
      subtitle: subtitle,
      trailing: onTap == null
          ? null
          : const PindoroIcon(PindoroGlyph.chevronRight),
      onTap: onTap,
    );
  }
}

class _DistrictRow extends StatelessWidget {
  const _DistrictRow({
    required this.district,
    required this.learning,
    required this.settings,
    required this.onTap,
  });

  final RaionProgress district;

  /// The neighbourhood being learnt, when it is in this district.
  final District? learning;
  final Settings? settings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final m = district.memory;
    final name = districtName(district.district, settings);
    final mastered = _mastered(m);
    final learning = this.learning;
    final subtitle = [
      l10n.memoryInMemory(
        formatNumber(m.memory.round()),
        formatNumber(m.total),
      ),
      if (mastered)
        l10n.memoryMastered
      else if (learning != null)
        l10n.progressLearning(districtName(learning, settings)),
    ].join(' · ');
    final bar = memoryBarLabel(l10n, name, m);
    return ListRow(
      leading: mastered
          ? RowTile(
              PindoroGlyph.checkCircle,
              face: c.primaryBase,
              ink: c.primaryOn,
            )
          : const RowTile(PindoroGlyph.district),
      title: name,
      subtitle: subtitle,
      below: MemoryBar(
        counts: memoryCountsOf(m),
        semanticsLabel: bar,
        compact: true,
      ),
      trailing: const PindoroIcon(PindoroGlyph.chevronRight),
      semanticsLabel: '$name. $subtitle. $bar',
      onTap: onTap,
    );
  }
}
