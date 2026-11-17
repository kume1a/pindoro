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
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/progress.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/learning/ui/city_memory_card.dart';
import 'package:pindoro/features/learning/ui/city_tab_page.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Today, the first tab (canvas V31-10): `firstRun` offers placement until
/// the city is placed; then the one thing to do now (`ready`, `catching up`
/// or `done`), City memory as a row, and what comes next: the run to drive,
/// the neighbourhood being learnt, the gateways, the next 7 days and any
/// mix-up to watch.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    Future<void> open(String route) async {
      await context.push(route);
      refreshLearning(ref);
    }

    final learnCity = ref.watch(learnCityProvider);
    final plan = ref.watch(todayPlanProvider);
    final memory = ref.watch(cityMemoryProvider).value;
    final cards = switch ((learnCity, plan)) {
      (AsyncData(value: final c), _) when c?.placedAt == null => [
        _FirstRun(onOpen: open),
      ],
      (AsyncData(), AsyncData(value: final plan)) => () {
        // The day's minutes spent with reviews still due is a backlog with
        // nothing to start: done (SPEC §16.2).
        final done = plan.steps.isEmpty;
        final catchingUp = plan.backlog && !done;
        final run = catchingUp ? null : ref.watch(todayRunProvider).value;
        final learning = ref.watch(nowLearningProvider).value;
        final gateways = switch (learning) {
          final l? when !catchingUp && !done =>
            ref.watch(gatewaysProvider(l.raion.id)).value,
          _ => null,
        };
        final mixUps = catchingUp
            ? const <(NamedStreet, NamedStreet)>[]
            : ref.watch(mixUpsYesterdayProvider).value ?? const [];
        return [
          if (done)
            _DoneForToday(
              tomorrow: ref.watch(dueTomorrowProvider).value ?? 0,
              onLearnMore: () => open(Routes.learnMore),
            )
          else if (catchingUp)
            _CatchingUp(plan: plan, onStart: () => open(Routes.session))
          else
            _TodaysDrive(plan: plan, onStart: () => open(Routes.session)),
          if (catchingUp) const _MostOverdueFirst(),
          if (done) const _LastWeek(),
          if (memory != null)
            CityMemoryRow(
              memory: memory.city,
              change: catchingUp
                  ? (
                      value: memory.sinceWeek,
                      label: memoryChange(l10n, memory.sinceWeek, week: true),
                    )
                  : (
                      value: memory.sinceYesterday,
                      label: memoryChange(
                        l10n,
                        memory.sinceYesterday,
                        firstDay: memory.firstDay,
                      ),
                    ),
              onTap: () => context.go(Routes.progress),
            ),
          SectionTitle(l10n.todayComingUp),
          if (run != null)
            _DriveThisRun(run: run, onDrive: () => open(Routes.drive)),
          if (learning != null)
            _NowLearningCard(
              learning: learning,
              paused: catchingUp,
              onTap: () => open(Routes.progressOf(learning.raion.id)),
            ),
          if (gateways != null && gateways.started)
            _Gateways(
              gateways: gateways,
              onTap: () => open(Routes.progressOf(learning!.raion.id)),
            ),
          _NextWeek(plan: plan, done: done),
          if (mixUps.isNotEmpty) ...[
            SectionTitle(l10n.sessionDoneWatchOut),
            _WatchOut(mixUps),
          ],
        ];
      }(),
      _ => const [Center(child: LaneLoader())],
    };
    return CityTabPage(children: cards);
  }
}

/// Before placement (board V3-10 `firstRun`).
class _FirstRun extends ConsumerWidget {
  const _FirstRun({required this.onOpen});

  final Future<void> Function(String route) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final curriculum = ref.watch(curriculumProvider).value;
    final mainRoads = curriculum == null
        ? 0
        : curriculum
              .placement(0)
              .where((id) => curriculum.tierOf(id) == StreetTier.a)
              .length;
    final minutes = (mainRoads * LearningConfig.placementPinS / 60).ceil();
    Future<void> fromZero() async {
      final city = ref.read(settingsProvider).value?.cityId;
      if (city == null) return;
      await ref
          .read(learningDaoProvider)
          .markPlaced(city, ref.read(clockProvider)());
      ref.invalidate(learnCityProvider);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s4,
      children: [
        const Center(child: Pindo(PindoExpression.cheering, height: 120)),
        Semantics(
          header: true,
          child: Text(
            l10n.todayFirstRunTitle,
            textAlign: TextAlign.center,
            style: PindoroType.headlineMd.copyWith(color: c.textPrimary),
          ),
        ),
        Text(
          l10n.todayFirstRunBody,
          textAlign: TextAlign.center,
          style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
        ),
        ListGroup(
          children: [
            ListRow(
              leading: const RowTile(PindoroGlyph.road),
              title: l10n.todayFirstRunMainRoads,
              subtitle: l10n.todayFirstRunMainRoadsCount(
                formatNumber(mainRoads),
                formatNumber(minutes),
              ),
            ),
            ListRow(
              leading: const RowTile(PindoroGlyph.district),
              title: l10n.todayFirstRunSample,
              subtitle: l10n.todayFirstRunSampleCount(
                formatNumber(LearningConfig.placementSamplePerDistrict),
              ),
            ),
            ListRow(
              leading: const RowTile(PindoroGlyph.home),
              title: l10n.todayHomeWork,
              subtitle: l10n.todayHomeWorkSubtitle,
              trailing: const PindoroIcon(PindoroGlyph.chevronRight),
              onTap: () => onOpen(Routes.learnSettings),
            ),
          ],
        ),
        PindoroButton(
          label: l10n.todayStartPlacement,
          hero: true,
          onPressed: () => onOpen(Routes.placement),
        ),
        PindoroButton(
          label: l10n.todayStartFromZero,
          variant: PindoroButtonVariant.secondary,
          onPressed: fromZero,
        ),
      ],
    );
  }
}

/// The Today card (design system Today card): a head row with Pindo, the
/// plan tiles and the actions; [primary] rings it as today's one action.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.semanticLabel,
    required this.mascot,
    required this.title,
    required this.subtitle,
    required this.actions,
    this.tiles = const [],
    this.primary = false,
  });

  final String semanticLabel;
  final PindoExpression mascot;
  final String title;
  final String subtitle;
  final List<StatTile> tiles;
  final Widget actions;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LipBox(
      border: primary ? c.primaryBase : c.lineBase,
      lip: primary ? c.primaryLip : null,
      radius: PindoroRadius.xl,
      padding: const EdgeInsets.all(PindoroSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: [
          Semantics(
            container: true,
            label: semanticLabel,
            excludeSemantics: true,
            child: Row(
              spacing: PindoroSpace.s3,
              children: [
                Pindo(mascot, height: 56),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: PindoroType.titleLg.copyWith(
                          color: c.textPrimary,
                        ),
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
          if (tiles.isNotEmpty)
            TileGrid(tiles, columns: TileGrid.columnsFor(tiles.length, scale)),
          actions,
        ],
      ),
    );
  }
}

/// Today's plan tiles (canvas V31-90 Plan tiles): only the kinds today holds.
List<StatTile> _planTiles(AppLocalizations l10n, SessionPlan plan) {
  final drills = plan.drills;
  final drillKinds = [
    if (drills.sweep != null) l10n.todayDrillSweep,
    if (drills.crossings != null) l10n.todayDrillCrossings,
    if (drills.bearings.isNotEmpty) l10n.todayDrillBearings,
  ];
  final drillCount =
      (drills.sweep == null ? 0 : 1) +
      (drills.crossings == null ? 0 : 1) +
      drills.bearings.length;
  return [
    for (final (glyph, label, count, caption) in [
      (
        PindoroGlyph.retry,
        l10n.learnReviews,
        plan.reviewCount - plan.routeCount,
        null,
      ),
      (PindoroGlyph.plus, l10n.learnNew, plan.newCount, null),
      (PindoroGlyph.turnRight, l10n.todayTurns, plan.routeCount, null),
      (PindoroGlyph.bolt, l10n.todayDrills, drillCount, drillKinds.join(', ')),
    ])
      if (count > 0)
        StatTile(
          glyph: glyph,
          label: label,
          value: formatNumber(count),
          caption: caption,
        ),
  ];
}

class _TodaysDrive extends StatelessWidget {
  const _TodaysDrive({required this.plan, required this.onStart});

  final SessionPlan plan;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final minutes = (plan.estimatedS / 60).ceil();
    final tiles = _planTiles(l10n, plan);
    return _TodayCard(
      primary: true,
      semanticLabel: l10n.a11yTodayDrills(
        [for (final t in tiles) '${t.label} ${t.value}'].join(', '),
        minutes,
      ),
      mascot: PindoExpression.happy,
      title: l10n.todayDriveTitle,
      subtitle: l10n.todayDriveSubtitle(minutes),
      tiles: tiles,
      actions: PindoroButton(
        label: l10n.todayStart,
        icon: PindoroGlyph.play,
        hero: true,
        onPressed: () => onStart(),
      ),
    );
  }
}

/// Catching up (design system Today card): new streets pause while the due
/// reviews don't fit the day's minutes.
class _CatchingUp extends ConsumerWidget {
  const _CatchingUp({required this.plan, required this.onStart});

  final SessionPlan plan;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final minutes = ref.watch(settingsProvider).value?.minutesPerDay ?? 20;
    final days = catchUpDays(dueCount: plan.dueCount, minutesPerDay: minutes);
    return _TodayCard(
      primary: true,
      semanticLabel: l10n.a11yTodayBacklog(plan.dueCount, days, minutes),
      mascot: PindoExpression.encouraging,
      title: l10n.todayBacklogTitle(plan.dueCount, formatNumber(plan.dueCount)),
      subtitle: l10n.todayBacklogSubtitle(days, minutes),
      tiles: [
        StatTile(
          glyph: PindoroGlyph.retry,
          label: l10n.todayBacklogToday,
          value: formatNumber(plan.reviewCount),
        ),
        StatTile(
          glyph: PindoroGlyph.plus,
          label: l10n.learnNew,
          value: formatNumber(0),
          caption: l10n.todayNewPaused,
        ),
        StatTile(
          glyph: PindoroGlyph.timer,
          label: l10n.todayMinutes,
          value: formatNumber(minutes),
        ),
      ],
      actions: PindoroButton(
        label: l10n.todayCatchUp,
        icon: PindoroGlyph.play,
        hero: true,
        onPressed: () => onStart(),
      ),
    );
  }
}

/// "Drive this run today" (board V3-10): the run Today offers, and Drive.
class _DriveThisRun extends ConsumerWidget {
  const _DriveThisRun({required this.run, required this.onDrive});

  final RunToDrive run;
  final VoidCallback onDrive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    return LipBox(
      border: c.lineBase,
      radius: PindoroRadius.xl,
      padding: const EdgeInsets.symmetric(
        horizontal: PindoroSpace.s4,
        vertical: PindoroSpace.s3,
      ),
      child: Row(
        spacing: PindoroSpace.s3,
        children: [
          const ExcludeSemantics(child: RowTile(PindoroGlyph.car)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.todayRunTitle,
                  style: PindoroType.titleSm.copyWith(color: c.textPrimary),
                ),
                Text(
                  l10n.todayRunRoute(
                    streetName(run.ends.fromStreet, settings),
                    streetName(run.ends.toStreet, settings),
                    formatDistance(run.ends.best.lengthM, l10n),
                  ),
                  style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          PindoroButton(
            label: l10n.todayRunDrive,
            variant: PindoroButtonVariant.secondary,
            onPressed: onDrive,
          ),
        ],
      ),
    );
  }
}

/// The neighbourhood being learnt (Neighbourhood card): its mini map with the
/// streets the player knows, its seen count and bar, and what comes next.
/// [paused] while catching up. The map moves above the text at large text.
class _NowLearningCard extends ConsumerWidget {
  const _NowLearningCard({
    required this.learning,
    required this.paused,
    required this.onTap,
  });

  final NowLearning learning;
  final bool paused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final (:chunk, :raion, :next, :outline, :known) = learning;
    final name = districtName(chunk.chunk, settings);
    final seen = formatNumber(chunk.seen);
    final total = formatNumber(chunk.memory.total);
    final district = districtName(raion, settings);
    final sub = paused
        ? l10n.todayLearningPaused(district, seen, total)
        : l10n.todayLearningSeen(district, seen, total);
    final nextLine = next == null
        ? null
        : l10n.todayLearningNext(districtName(next.chunk, settings), name);
    final stack = MediaQuery.textScalerOf(context).scale(1) >= TileGrid.stackAt;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          l10n.todayNowLearning,
          style: PindoroType.labelMd.copyWith(color: c.textSecondary),
        ),
        Text(name, style: PindoroType.titleMd.copyWith(color: c.textPrimary)),
        Text(sub, style: PindoroType.bodySm.copyWith(color: c.textSecondary)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: PindoroSpace.s1),
          child: MemoryBar(
            counts: memoryCountsOf(chunk.memory),
            semanticsLabel: '',
            compact: true,
          ),
        ),
        if (nextLine != null)
          Text(
            nextLine,
            style: PindoroType.labelMd.copyWith(color: c.textSecondary),
          ),
      ],
    );
    final map = AreaMiniMap(area: outline, streets: known);
    return Tappable(
      onTap: onTap,
      label: [l10n.todayNowLearning, name, sub, ?nextLine].join('. '),
      child: LipBox(
        border: c.lineBase,
        padding: const EdgeInsets.all(PindoroSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroSpace.s1,
          children: [
            if (stack) ...[
              map,
              text,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: PindoroSpace.s3,
                children: [
                  map,
                  Expanded(child: text),
                ],
              ),
            Text(
              l10n.commonAttribution,
              style: PindoroType.labelSm.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The learning district's gateways, Solid of all.
class _Gateways extends StatelessWidget {
  const _Gateways({required this.gateways, required this.onTap});

  final GatewayCount gateways;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListGroup(
      children: [
        ListRow(
          leading: const RowTile(PindoroGlyph.route),
          title: l10n.todayGateways(
            formatNumber(gateways.solid),
            formatNumber(gateways.total),
          ),
          subtitle: l10n.todayGatewaysSubtitle,
          trailing: const PindoroIcon(PindoroGlyph.chevronRight),
          onTap: onTap,
        ),
      ],
    );
  }
}

/// What comes due on each of the next 7 days (Next 7 days strip), with how
/// the week reads: the daily average, the week's total, the catch-up day or
/// tomorrow's count.
class _NextWeek extends ConsumerWidget {
  const _NextWeek({required this.plan, required this.done});

  final SessionPlan plan;
  final bool done;

  static const int _days = 7;

  /// From this daily average the strip reads it as a rate, not a total.
  static const int _perDayFrom = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = ref.watch(clockProvider)();
    final cards = ref.watch(cityCardsProvider).value ?? const [];
    final counts = forecast(cards, now, days: _days);
    final days = [for (var d = 0; d < _days; d++) now.add(Duration(days: d))];
    final total = counts.fold(0, (a, b) => a + b);
    final average = (total / _days).round();
    final minutes = ref.watch(settingsProvider).value?.minutesPerDay ?? 20;
    final caughtUp = now.add(
      Duration(
        days: catchUpDays(dueCount: plan.dueCount, minutesPerDay: minutes),
      ),
    );
    final meta = done
        ? l10n.todayWeekTomorrow(formatNumber(counts[1]))
        : plan.backlog
        ? l10n.todayWeekCaughtUp(
            (caughtUp.difference(now).inDays < _days
                    ? DateFormat.EEEE(locale)
                    : DateFormat.MMMd(locale))
                .format(caughtUp),
          )
        : average >= _perDayFrom
        ? l10n.todayWeekPerDay(formatNumber(average))
        : l10n.todayWeekTotal(total);
    return WeekBars(
      counts: counts,
      labels: [
        l10n.progressToday,
        for (final day in days.skip(1)) DateFormat.E(locale).format(day),
      ],
      title: l10n.todayNextWeek,
      meta: meta,
      format: formatNumber,
      semanticsLabel: l10n.a11yNextWeek(
        [
          for (final (i, day) in days.indexed)
            '${i == 0 ? l10n.progressToday : DateFormat.EEEE(locale).format(day)} ${formatNumber(counts[i])}',
        ].join(', '),
      ),
    );
  }
}

/// Today's done state: the last 7 days of the streak.
class _LastWeek extends ConsumerWidget {
  const _LastWeek();

  static const int _days = 7;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final view = ref.watch(streakProvider).value;
    if (view == null) return const SizedBox.shrink();
    final today = view.summary.today;
    final days = [
      for (var d = _days - 1; d >= 0; d--)
        calendarDay(today.subtract(Duration(days: d))),
    ];
    final states = [
      for (final day in days)
        view.metDays.contains(day)
            ? StreakDay.met
            : view.summary.frozenDays.contains(day)
            ? StreakDay.frozen
            : StreakDay.missed,
    ];
    final counted = formatNumber(
      states.where((s) => s == StreakDay.met).length,
    );
    return StreakWeek(
      days: states,
      labels: [
        for (final day in days.take(_days - 1))
          DateFormat.E(locale).format(day),
        l10n.progressToday,
      ],
      title: l10n.todayLastWeek,
      meta: l10n.todayLastWeekCounted(counted),
      semanticsLabel: l10n.a11yLastWeek(counted),
    );
  }
}

/// Yesterday's mix-ups, each pair on a Miss-tinted row.
class _WatchOut extends ConsumerWidget {
  const _WatchOut(this.pairs);

  final List<(NamedStreet, NamedStreet)> pairs;

  static const int _shown = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = PindoroTheme.of(context);
    final miss = theme.tier(Tier.miss);
    final settings = ref.watch(settingsProvider).value;
    return ListGroup(
      children: [
        for (final (a, b) in pairs.take(_shown))
          ListRow(
            leading: RowTile(
              PindoroGlyph.reroute,
              face: miss.bg,
              ink: miss.ink,
            ),
            title: '${streetName(a, settings)} ↔ ${streetName(b, settings)}',
            subtitle: l10n.todayMixedUpYesterday,
          ),
      ],
    );
  }
}

/// Catching up's info card: why most overdue comes first.
class _MostOverdueFirst extends StatelessWidget {
  const _MostOverdueFirst();

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return LipBox(
      border: c.lineBase,
      radius: PindoroRadius.xl,
      padding: const EdgeInsets.symmetric(
        horizontal: PindoroSpace.s4,
        vertical: PindoroSpace.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: PindoroSpace.s3,
        children: [
          const ExcludeSemantics(child: RowTile(PindoroGlyph.info)),
          Expanded(
            child: Text(
              context.l10n.todayBacklogInfo,
              style: PindoroType.bodySm.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneForToday extends ConsumerWidget {
  const _DoneForToday({required this.tomorrow, required this.onLearnMore});

  final int tomorrow;
  final Future<void> Function() onLearnMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final streak = ref.watch(streakProvider).value?.summary;
    final kept = streak != null && streak.metToday ? streak.days : 0;
    final subtitle = [
      if (kept > 0) l10n.todayStreakKept(formatNumber(kept)),
      l10n.todayDueTomorrow(tomorrow),
    ].join(' · ');
    return _TodayCard(
      semanticLabel: '${l10n.todayDoneTitle}. $subtitle',
      mascot: PindoExpression.proud,
      title: l10n.todayDoneTitle,
      subtitle: subtitle,
      actions: OverflowBar(
        spacing: PindoroSpace.s2,
        overflowSpacing: PindoroSpace.s2,
        children: [
          PindoroButton(
            label: l10n.todayLearnMore(LearningConfig.learnMoreCount),
            variant: PindoroButtonVariant.secondary,
            onPressed: () => onLearnMore(),
          ),
          PindoroButton(
            label: l10n.todayFreePlay,
            variant: PindoroButtonVariant.secondary,
            onPressed: () => context.go(Routes.home),
          ),
        ],
      ),
    );
  }
}
