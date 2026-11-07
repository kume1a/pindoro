import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/results/data/results_data.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// One answer of a round on the map: its street, the pin and the distance
/// line, with Previous / Next to step through the round.
class ResultStreetScreen extends ConsumerWidget {
  const ResultStreetScreen({
    super.key,
    required this.roundId,
    required this.index,
  });

  final String roundId;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(resultsProvider(roundId)).value;
    final shape = data?.shape;
    final entry = data?.entries.elementAtOrNull(index);
    final street = entry?.street;
    if (data == null || shape == null || entry == null || street == null) {
      return const Scaffold();
    }
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final answer = entry.answer;
    // Steps skip answers whose street was retired from the pack since.
    int? step(int from, int by) {
      for (var i = from + by; i >= 0 && i < data.entries.length; i += by) {
        if (data.entries[i].street != null) return i;
      }
      return null;
    }

    final previous = step(index, -1);
    final next = step(index, 1);
    final pin = LatLng(answer.pinLat, answer.pinLon);
    final nearest = street.nearest(pin).nearestPoint;
    final name = streetName(street, settings);
    final other = name == street.name ? street.nameEn : street.name;
    final tier = PindoroTheme.of(context).tier(answer.tier);
    final distance = formatDistance(answer.distanceM, l10n);
    void go(int i) => context.pushReplacement(Routes.resultStreet(roundId, i));

    return Scaffold(
      body: Stack(
        children: [
          ref.watch(pindoroMapBuilderProvider)(
            PindoroMap(
              area: shape,
              pin: pin,
              truth: street.geometry,
              measure: (from: pin, to: nearest, label: distance),
              topInset: MediaQuery.paddingOf(context).top + 80,
              bottomInset: 260 + MediaQuery.paddingOf(context).bottom,
              showControls: false,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(PindoroSpace.s4),
              child: Row(
                spacing: PindoroSpace.s3,
                children: [
                  MapControl(
                    glyph: PindoroGlyph.back,
                    semanticLabel: l10n.resultsBackToResults,
                    onPressed: context.pop,
                  ),
                  Expanded(child: StreetPlate(name, compact: true)),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: BoxDecoration(
                color: c.surfaceOverlay,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(PindoroRadius.r2xl),
                ),
                border: Border(
                  top: BorderSide(color: tier.fill, width: PindoroElevation.e2),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                PindoroSpace.s4,
                PindoroSpace.s5,
                PindoroSpace.s4,
                PindoroSpace.s4 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: PindoroSpace.s3,
                children: [
                  Row(
                    spacing: PindoroSpace.s3,
                    children: [
                      TierBadge(answer.tier, size: 44),
                      Expanded(
                        child: Text(
                          tierWord(l10n, answer.tier),
                          style: PindoroType.headlineSm.copyWith(
                            color: tier.ink,
                          ),
                        ),
                      ),
                      if (answer.xp > 0)
                        XpChip(l10n.commonXp(formatNumber(answer.xp))),
                    ],
                  ),
                  Text(
                    name,
                    style: PindoroType.titleLg.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    [?other, distance].join(' · '),
                    style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
                  ),
                  Row(
                    spacing: PindoroSpace.s3,
                    children: [
                      Expanded(
                        child: PindoroButton(
                          label: l10n.resultsPreviousStreet,
                          variant: PindoroButtonVariant.secondary,
                          onPressed: previous == null
                              ? null
                              : () => go(previous),
                        ),
                      ),
                      Expanded(
                        child: PindoroButton(
                          label: l10n.resultsNextStreet,
                          variant: PindoroButtonVariant.secondary,
                          onPressed: next == null ? null : () => go(next),
                        ),
                      ),
                    ],
                  ),
                  PindoroButton(
                    label: l10n.resultsBackToResults,
                    onPressed: context.pop,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
