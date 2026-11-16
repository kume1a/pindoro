import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/progress.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/learning/ui/city_memory_card.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/features/progress/ui/play_top_bar.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Today, the first tab (design system Today card): `firstRun` offers
/// placement until the city is placed; then `ready`, `catching up` or
/// `done` over the City memory card.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> open(String route) async {
      await context.push(route);
      ref
        ..invalidate(learnCityProvider)
        ..invalidate(cityCardsProvider)
        ..invalidate(todayPlanProvider)
        ..invalidate(cityMemoryProvider);
    }

    final city = ref.watch(packRepositoryProvider).value?.city();
    final learnCity = ref.watch(learnCityProvider);
    final plan = ref.watch(todayPlanProvider);
    final memory = ref.watch(cityMemoryProvider).value;
    final cards = switch ((learnCity, plan)) {
      (AsyncData(value: final c), _) when c?.placedAt == null => [
        _FirstRun(onOpen: open),
      ],
      (AsyncData(), AsyncData(value: final plan)) => [
        if (plan.backlog)
          _CatchingUp(plan: plan, onStart: () => open(Routes.session))
        else if (plan.steps.isNotEmpty)
          _TodaysDrive(plan: plan, onStart: () => open(Routes.session))
        else
          _DoneForToday(
            tomorrow: ref.watch(dueTomorrowProvider).value ?? 0,
            onLearnMore: () => open(Routes.learnMore),
          ),
        if (memory != null)
          CityMemoryCard(
            memory: memory.city,
            sinceYesterday: plan.backlog ? null : memory.sinceYesterday,
            sinceWeek: plan.backlog ? memory.sinceWeek : null,
            onTap: () => context.go(Routes.progress),
          ),
        if (plan.backlog) const _MostOverdueFirst(),
      ],
      _ => const [Center(child: LaneLoader())],
    };
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (city != null)
              PlayTopBar(city: city, trailing: const StreakPillButton()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(PindoroSpace.s4),
                children: [
                  for (final card in cards)
                    ContentColumn(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: PindoroSpace.s4),
                        child: card,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
/// stat tiles and the actions; [primary] rings it as today's one action.
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
            Row(
              spacing: PindoroSpace.s2,
              children: [for (final t in tiles) Expanded(child: t)],
            ),
          actions,
        ],
      ),
    );
  }
}

class _TodaysDrive extends StatelessWidget {
  const _TodaysDrive({required this.plan, required this.onStart});

  final SessionPlan plan;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final minutes = (plan.estimatedS / 60).ceil();
    return _TodayCard(
      primary: true,
      semanticLabel: l10n.a11yTodayReady(
        plan.reviewCount,
        plan.newCount,
        minutes,
      ),
      mascot: PindoExpression.happy,
      title: l10n.todayDriveTitle,
      subtitle: l10n.todayDriveSubtitle(minutes),
      tiles: [
        StatTile(
          glyph: PindoroGlyph.retry,
          label: l10n.learnReviews,
          value: formatNumber(plan.reviewCount),
        ),
        StatTile(
          glyph: PindoroGlyph.plus,
          label: l10n.learnNew,
          value: formatNumber(plan.newCount),
        ),
      ],
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
