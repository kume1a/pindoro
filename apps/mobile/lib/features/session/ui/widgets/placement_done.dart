import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The placement result (design system Placement): what placement found and
/// where new streets start.
class PlacementDoneView extends ConsumerWidget {
  const PlacementDoneView({
    super.key,
    required this.summary,
    required this.onStart,
  });

  final PlacementSummary summary;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final s = summary;
    final startIn = switch ((s.startBand, s.startIn)) {
      (final band?, _) => l10n.roadBand(band.name),
      (_, final d?) => districtName(d, settings),
      _ => null,
    };
    final tiles = [
      (
        PindoroGlyph.road,
        l10n.placementMainRoads,
        l10n.commonXOfY(
          formatNumber(s.mainRoads.passed),
          formatNumber(s.mainRoads.of),
        ),
      ),
      (
        PindoroGlyph.district,
        l10n.placementDistricts,
        l10n.placementSampled(formatNumber(s.raions)),
      ),
      (
        PindoroGlyph.checkCircle,
        l10n.placementInReview,
        formatNumber(s.passed),
      ),
      if (startIn != null)
        (
          s.startBand == null ? PindoroGlyph.home : PindoroGlyph.road,
          l10n.placementStartIn,
          startIn,
        ),
    ];
    return PageScaffold(
      showBack: false,
      footer: PindoroButton(
        label: l10n.placementStartLearning,
        hero: true,
        onPressed: onStart,
      ),
      children: [
        const Center(child: Pindo(PindoExpression.proud, height: 120)),
        Semantics(
          header: true,
          child: Text(
            l10n.placementDoneTitle(s.passed, formatNumber(s.passed)),
            textAlign: TextAlign.center,
            style: PindoroType.headlineMd.copyWith(color: c.textPrimary),
          ),
        ),
        Text(
          [
            if (s.passed > 0) l10n.placementDoneReview,
            if (s.startBand case final band?)
              l10n.placementDoneStartBand(band.name)
            else if (startIn != null)
              l10n.placementDoneStart(startIn),
          ].join(' '),
          textAlign: TextAlign.center,
          style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
        ),
        Column(
          spacing: PindoroSpace.s2,
          children: [
            for (var row = 0; row < tiles.length; row += 2)
              Row(
                spacing: PindoroSpace.s2,
                children: [
                  for (final (i, (glyph, label, value))
                      in tiles.indexed.skip(row).take(2))
                    Expanded(
                      child: RiseIn(
                        delay: PindoroMotion.stagger * i,
                        distance: PindoroSpace.s2,
                        child: StatTile(
                          glyph: glyph,
                          label: label,
                          value: value,
                        ),
                      ),
                    ),
                  if (row + 1 == tiles.length) const Spacer(),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
