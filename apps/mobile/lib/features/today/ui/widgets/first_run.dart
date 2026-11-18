import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/learning/data/cards.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Before placement (board V3-10 `firstRun`).
class FirstRun extends ConsumerWidget {
  const FirstRun({super.key, required this.onOpen});

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
          onPressed: () => startFromZero(ref),
        ),
      ],
    );
  }
}
