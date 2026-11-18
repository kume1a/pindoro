import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

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
  final drillCount = Planner.drillSteps(drills).length;
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

class TodaysDrive extends StatelessWidget {
  const TodaysDrive({super.key, required this.plan, required this.onStart});

  final SessionPlan plan;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rounds = plan.rounds.length;
    final tiles = _planTiles(l10n, plan);
    return _TodayCard(
      primary: true,
      semanticLabel: l10n.a11yTodayDrills(
        [for (final t in tiles) '${t.label} ${t.value}'].join(', '),
        rounds,
      ),
      mascot: PindoExpression.happy,
      title: l10n.todayDriveTitle,
      subtitle: l10n.todayDriveSubtitle(rounds),
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
class CatchingUp extends ConsumerWidget {
  const CatchingUp({super.key, required this.plan, required this.onStart});

  final SessionPlan plan;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final minutes = ref.watch(settingsProvider).value?.minutesPerDay ?? 20;
    final days = catchUpDays(dueCount: plan.dueCount, minutesPerDay: minutes);
    return _TodayCard(
      primary: true,
      semanticLabel: l10n.a11yTodayBacklog(
        plan.dueCount,
        formatNumber(plan.dueCount),
        days,
        minutes,
      ),
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

class DoneForToday extends ConsumerWidget {
  const DoneForToday({
    super.key,
    required this.tomorrow,
    required this.onLearnMore,
  });

  final int tomorrow;
  final Future<void> Function() onLearnMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final streak = ref.watch(streakProvider).value?.summary;
    final kept = streak != null && streak.metToday ? streak.days : 0;
    final subtitle = [
      if (kept > 0) l10n.todayStreakKept(formatNumber(kept)),
      l10n.todayDueTomorrow(tomorrow, formatNumber(tomorrow)),
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
