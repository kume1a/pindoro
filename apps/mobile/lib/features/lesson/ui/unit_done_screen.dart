import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/lesson/data/unit_done_data.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The trophy shield on Unit complete (canvas LessonDoneScreen `unit`).
const double _trophySize = 110;

/// Unit complete (canvas R4-40 step 4): the trophy pops with a burst, the
/// unit's streets, road trips and XP, the next unit's signpost and Continue,
/// which goes back to the Path and plays the next unit opening (R4-61).
class UnitDoneScreen extends ConsumerWidget {
  const UnitDoneScreen({super.key, required this.unitId});

  final String unitId;

  void _continue(BuildContext context, WidgetRef ref) {
    ref.read(pathUnlockProvider.notifier).play((
      unitId: unitId,
      kind: StopKind.finalDrive,
      lesson: null,
    ));
    context.go(Routes.path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = ref.watch(unitDoneProvider(unitId)).value;
    if (done == null) return const Scaffold();
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final unit = done.unit;
    final next = done.next;
    final district = districtName(unit.district, settings);
    final nextDistrict = next == null
        ? null
        : districtName(next.district, settings);
    final tiles = [
      StatTile(
        glyph: PindoroGlyph.signpost,
        label: l10n.unitDoneStreets,
        value: formatNumber(unit.streets.length),
      ),
      StatTile(
        glyph: PindoroGlyph.car,
        label: l10n.meRoadTrips,
        value: formatNumber(done.summary.trips),
      ),
      StatTile(
        glyph: PindoroGlyph.xp,
        glyphColor: c.xpFill,
        label: l10n.unitDoneXp,
        value: formatNumber(done.summary.xp),
      ),
    ];
    final page = PageScaffold(
      title: l10n.unitDoneTitle(district),
      showBack: false,
      footer: PindoroButton(
        label: nextDistrict == null
            ? l10n.commonContinue
            : l10n.unitDoneContinueTo(nextDistrict),
        onPressed: () => _continue(context, ref),
      ),
      children: [
        Center(
          child: PopIn(
            child: Semantics(
              label: l10n.a11yUnitTrophy(unit.number),
              child: const LevelBadge.glyph(
                PindoroGlyph.trophy,
                size: _trophySize,
              ),
            ),
          ),
        ),
        Text(
          l10n.unitDoneKicker(unit.number),
          style: PindoroType.labelLg.copyWith(color: c.textSecondary),
        ),
        Text(
          l10n.unitDoneBody(unit.streets.length, district),
          style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s2,
            children: [
              for (final (i, tile) in tiles.indexed)
                Expanded(
                  child: RiseIn(
                    delay: PindoroMotion.stagger * (i + 1),
                    distance: PindoroSpace.s4,
                    child: tile,
                  ),
                ),
            ],
          ),
        ),
        if (next != null)
          Signpost(
            number: next.number,
            line: l10n.unitDoneNext(next.number),
            title: nextDistrict!,
            semanticLabel: '${l10n.unitDoneNext(next.number)} $nextDistrict',
          ),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _continue(context, ref);
      },
      child: Stack(
        children: [
          page,
          const Positioned.fill(
            child: Celebration(
              size: CelebrationSize.medium,
              burstCenter: Alignment(0, -0.62),
            ),
          ),
        ],
      ),
    );
  }
}
