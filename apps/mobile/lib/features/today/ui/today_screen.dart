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
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Today (board V3-10): `firstRun` offers placement until the city is placed;
/// then `ready` shows the session's size and Start, `done` what tomorrow
/// holds, both over the City memory card. Backlog comes with M3.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    Future<void> open(String route) async {
      await context.push(route);
      ref
        ..invalidate(learnCityProvider)
        ..invalidate(cityCardsProvider)
        ..invalidate(todayPlanProvider)
        ..invalidate(cityMemoryProvider);
    }

    final city = ref.watch(learnCityProvider);
    final plan = ref.watch(todayPlanProvider);
    final memory = ref.watch(cityMemoryProvider).value;
    return PageScaffold(
      title: l10n.todayTitle,
      trailing: PindoroIconButton(
        glyph: PindoroGlyph.settings,
        semanticLabel: l10n.todayLearningSettings,
        onPressed: () => open(Routes.learnSettings),
      ),
      children: switch ((city, plan)) {
        (AsyncData(value: final c), _) when c?.placedAt == null => [
          _FirstRun(onOpen: open),
        ],
        (AsyncData(), AsyncData(:final value)) => [
          if (value.steps.isNotEmpty)
            _TodaysDrive(plan: value, onStart: () => open(Routes.session))
          else
            _DoneForToday(tomorrow: ref.watch(dueTomorrowProvider).value ?? 0),
          if (memory != null)
            CityMemoryCard(
              memory: memory.city,
              sinceYesterday: memory.sinceYesterday,
              onTap: () => open(Routes.progress),
            ),
        ],
        _ => const [Center(child: LaneLoader())],
      },
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

class _TodaysDrive extends StatelessWidget {
  const _TodaysDrive({required this.plan, required this.onStart});

  final SessionPlan plan;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    return LipBox(
      border: c.lineBase,
      radius: PindoroRadius.xl,
      padding: const EdgeInsets.all(PindoroSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: [
          Text(
            l10n.todayDriveTitle,
            style: PindoroType.titleLg.copyWith(color: c.textPrimary),
          ),
          Text(
            l10n.todayDriveSubtitle((plan.estimatedS / 60).ceil()),
            style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
          ),
          Row(
            spacing: PindoroSpace.s2,
            children: [
              Expanded(
                child: StatTile(
                  label: l10n.learnReviews,
                  value: formatNumber(plan.reviewCount),
                ),
              ),
              Expanded(
                child: StatTile(
                  label: l10n.learnNew,
                  value: formatNumber(plan.newCount),
                ),
              ),
            ],
          ),
          PindoroButton(
            label: l10n.todayStart,
            hero: true,
            onPressed: () => onStart(),
          ),
        ],
      ),
    );
  }
}

class _DoneForToday extends StatelessWidget {
  const _DoneForToday({required this.tomorrow});

  final int tomorrow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    return Column(
      spacing: PindoroSpace.s3,
      children: [
        const Pindo(PindoExpression.cheering, height: 120),
        Text(
          l10n.todayDoneTitle,
          textAlign: TextAlign.center,
          style: PindoroType.headlineMd.copyWith(color: c.textPrimary),
        ),
        Text(
          l10n.todayDueTomorrow(tomorrow),
          textAlign: TextAlign.center,
          style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}
