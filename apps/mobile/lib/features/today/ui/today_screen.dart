import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Today (minimal, docs/learning/PLAN.md M1 step 7): `ready` shows the
/// session's size and Start; `done` says what tomorrow holds. The full tab
/// (City memory, backlog, placement) comes with M2 and M3.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    Future<void> start() async {
      await context.push(Routes.session);
      ref
        ..invalidate(cityCardsProvider)
        ..invalidate(todayPlanProvider);
    }

    return PageScaffold(
      title: l10n.todayTitle,
      children: switch (ref.watch(todayPlanProvider)) {
        AsyncData(:final value) when value.steps.isNotEmpty => [
          _TodaysDrive(plan: value, onStart: start),
        ],
        AsyncData() => [
          _DoneForToday(tomorrow: ref.watch(dueTomorrowProvider).value ?? 0),
        ],
        _ => const [Center(child: LaneLoader())],
      },
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
