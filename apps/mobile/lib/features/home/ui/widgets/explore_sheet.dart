import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/badges/data/badge_data.dart';
import 'package:pindoro/features/badges/ui/badge_look.dart';
import 'package:pindoro/features/home/data/home_data.dart';
import 'package:pindoro/features/home/ui/widgets/home_coach.dart';
import 'package:pindoro/features/learning/data/cards.dart';
import 'package:pindoro/features/learning/data/progress.dart';
import 'package:pindoro/features/learning/ui/city_memory_card.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// When the City memory figure starts counting up after a round.
const Duration _introDelay = Duration(milliseconds: 950);

/// Explore's sheet under its play card: City memory, the quick starts as a
/// sideways row of cards, the last round, the areas played, every area, and
/// the next badge.
List<Widget> exploreSheet({
  required BuildContext context,
  required HomeData home,
  required Map<String, MemorySummary> areas,
  required List<District> raions,
  required Settings? settings,
  required Difficulty? difficulty,
  required Future<void> Function(Area area) onPlay,
  required Future<void> Function(String location) onOpen,
  required VoidCallback onCoachClosed,
}) {
  final l10n = context.l10n;
  final c = PindoroTheme.of(context).colors;
  final pack = home.pack;
  final last = home.last;
  final played = last != null || home.recent.isNotEmpty;
  String inMemory(MemorySummary? m) => l10n.meCityStreets(
    formatNumber(m?.memory.round() ?? 0),
    formatNumber(m?.total ?? 0),
  );
  return [
    _InMemoryHeader(
      home: home,
      showCoach: !(settings?.homeCoachSeen ?? true),
      onCoachClosed: onCoachClosed,
    ),
    if (!played)
      Text(
        l10n.exploreIntro,
        style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
      ),
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s2,
      children: [
        SectionTitle(l10n.exploreQuickStarts),
        _Sideways(
          children: [
            if (home.learned >= QuestionSelector.roundSize)
              _QuickCard(
                glyph: PindoroGlyph.book,
                title: l10n.exploreYourStreets,
                subtitle: l10n.exploreLearnedCount(formatNumber(home.learned)),
                onTap: () => onOpen(Routes.yourStreets),
              ),
            if (last != null && last.missed > 0)
              _QuickCard(
                glyph: PindoroGlyph.retry,
                title: l10n.resultsRetryMissed(last.missed),
                subtitle: l10n.exploreFromLastRound(
                  last.area == null
                      ? ''
                      : areaLabel(context, last.area!, pack, settings),
                ),
                onTap: () => onOpen(Routes.retry(last.round.id)),
              ),
            if (home.recent.firstOrNull case final area?)
              _QuickCard(
                glyph: PindoroGlyph.pin,
                title: l10n.exploreAgain(districtName(area, settings)),
                subtitle: inMemory(areas[area.id]),
                onTap: () => onPlay(DistrictsArea({area.id})),
              ),
            if (raions.isNotEmpty)
              _QuickCard(
                glyph: PindoroGlyph.compass,
                title: l10n.exploreRandomDistrict,
                subtitle: l10n.exploreRoundSize(
                  difficultyName(l10n, difficulty ?? Difficulty.medium),
                  formatNumber(QuestionSelector.roundSize),
                ),
                onTap: () => onPlay(
                  DistrictsArea({raions[Random().nextInt(raions.length)].id}),
                ),
              ),
            if (!played)
              _NearHome(
                pack: pack,
                settings: settings,
                onPlay: onPlay,
                onOpen: onOpen,
              ),
          ],
        ),
      ],
    ),
    if (last != null)
      TitledCard(
        title: l10n.exploreLastRound,
        meta: [
          if (last.area case final area?)
            areaLabel(context, area, pack, settings),
          difficultyName(l10n, last.round.difficulty),
        ].join(' · '),
        child: MiniTally(
          counts: last.tally,
          format: formatNumber,
          semanticLabel: l10n.a11yTierTally(
            last.tally[Tier.perfect] ?? 0,
            last.tally[Tier.great] ?? 0,
            last.tally[Tier.close] ?? 0,
            last.tally[Tier.miss] ?? 0,
          ),
        ),
      ),
    if (home.recent.isNotEmpty)
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s2,
        children: [
          SectionTitle(l10n.exploreAreasPlayed),
          ListGroup(
            children: [
              for (final area in home.recent)
                _AreaRow(
                  area: area,
                  memory: areas[area.id],
                  name: districtName(area, settings),
                  onTap: () => onOpen(Routes.areaFrom(area.id)),
                ),
            ],
          ),
        ],
      ),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: PindoroButton(
        label: l10n.homeAllDistricts(pack.districts().length),
        variant: PindoroButtonVariant.tertiary,
        onPressed: () => onOpen(Routes.area),
      ),
    ),
    const _NextBadge(),
  ];
}

/// "Tbilisi in memory" and City memory; right after a round the figure counts
/// up from where it was, with the gain in a pill.
class _InMemoryHeader extends ConsumerWidget {
  const _InMemoryHeader({
    required this.home,
    required this.showCoach,
    required this.onCoachClosed,
  });

  final HomeData home;
  final bool showCoach;
  final VoidCallback onCoachClosed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final city = home.pack.city();
    final memory = ref.watch(cityMemoryProvider).value?.city;
    final now = memory?.memory.round() ?? 0;
    final before = home.before?.round() ?? now;
    final total = formatNumber(memory?.total ?? 0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: PindoroSpace.s2,
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: HomeCoach(
              show: showCoach,
              onClose: onCoachClosed,
              child: Semantics(
                header: true,
                child: Text(
                  l10n.exploreInMemory(cityName(context, city)),
                  style: PindoroType.titleMd.copyWith(color: c.textPrimary),
                ),
              ),
            ),
          ),
        ),
        if (now > before)
          PopIn(
            delay: _introDelay,
            child: Pill(label: '+${formatNumber(now - before)}'),
          ),
        CountUp(
          value: now,
          from: before,
          delay: _introDelay,
          builder: (context, n) => Text(
            l10n.commonXOfY(formatNumber(n), total),
            style: PindoroType.numericSm.copyWith(color: c.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// Cards side by side, as tall as the tallest, scrolling sideways when they
/// don't fit.
class _Sideways extends StatelessWidget {
  const _Sideways({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s2,
        children: children,
      ),
    ),
  );
}

/// A quick start: its glyph beside what it plays and a detail line.
class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  /// One and a half cards on a phone, so the row reads as scrollable.
  static const double _width = 236;

  final PindoroGlyph glyph;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Tappable(
      label: '$title. $subtitle',
      onTap: onTap,
      child: SizedBox(
        width: _width,
        child: LipBox(
          border: c.lineBase,
          padding: const EdgeInsets.all(PindoroSpace.s3),
          child: Row(
            spacing: PindoroSpace.s3,
            children: [
              RowTile(glyph),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: PindoroType.titleSm.copyWith(color: c.textPrimary),
                    ),
                    Text(
                      subtitle,
                      style: PindoroType.bodySm.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Before any play: start where you live, or set home first.
class _NearHome extends ConsumerWidget {
  const _NearHome({
    required this.pack,
    required this.settings,
    required this.onPlay,
    required this.onOpen,
  });

  final PackRepository pack;
  final Settings? settings;
  final Future<void> Function(Area area) onPlay;
  final Future<void> Function(String location) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final homeId = ref.watch(learnCityProvider).value?.homeId;
    final home = pack.districts().where((d) => d.id == homeId).firstOrNull;
    return _QuickCard(
      glyph: PindoroGlyph.home,
      title: l10n.exploreNearHome,
      subtitle: home == null
          ? l10n.exploreNearHomeUnset
          : districtName(home, settings),
      onTap: () => home == null
          ? onOpen(Routes.anchorOf('home'))
          : onPlay(DistrictsArea({home.id})),
    );
  }
}

/// An area played recently, with its City memory.
class _AreaRow extends StatelessWidget {
  const _AreaRow({
    required this.area,
    required this.memory,
    required this.name,
    required this.onTap,
  });

  final District area;
  final MemorySummary? memory;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final memory = this.memory;
    final subtitle = l10n.memoryInMemory(
      formatNumber(memory?.memory.round() ?? 0),
      formatNumber(memory?.total ?? 0),
    );
    return ListRow(
      leading: RowTile(
        area.isRaion ? PindoroGlyph.district : PindoroGlyph.neighbourhood,
      ),
      title: name,
      subtitle: subtitle,
      below: memory == null
          ? null
          : MemoryBar(
              counts: memoryCountsOf(memory),
              semanticsLabel: '',
              compact: true,
            ),
      trailing: const PindoroIcon(PindoroGlyph.chevronRight),
      semanticsLabel: '$name. $subtitle',
      onTap: onTap,
    );
  }
}

/// The locked badge closest to being earned, with its condition and bar.
class _NextBadge extends ConsumerWidget {
  const _NextBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locked = [
      for (final b in ref.watch(badgesProvider).value ?? const <BadgeView>[])
        if (!b.earned && !b.retired && b.progress.target > 0) b,
    ];
    if (locked.isEmpty) return const SizedBox.shrink();
    double share(BadgeView b) => b.progress.value / b.progress.target;
    final next = locked.reduce((a, b) => share(b) > share(a) ? b : a);
    final look = badgeLook(context, next.id);
    final meta = l10n.commonXOfY(
      formatNumber(next.progress.value),
      formatNumber(next.progress.target),
    );
    return TitledCard(
      title: l10n.exploreNextBadge(look.name),
      meta: meta,
      semanticsLabel:
          '${l10n.exploreNextBadge(look.name)}, $meta. '
          '${look.condition}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s2,
        children: [
          Text(
            look.condition,
            style: PindoroType.bodySm.copyWith(
              color: PindoroTheme.of(context).colors.textSecondary,
            ),
          ),
          Minibar(value: share(next)),
        ],
      ),
    );
  }
}
