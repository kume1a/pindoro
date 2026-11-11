import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// "© OpenStreetMap contributors, Protomaps" on every map: `label.sm` on a
/// raised chip. Not interactive; the full credits are in Settings.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  /// Between the chip and whatever covers the map's bottom.
  static const double gap = PindoroSpace.s2;

  static const double _paddingY = 2;

  /// How far above the bottom inset the map's content must stay to be clear
  /// of the chip (one line at the current text size), with a gap above it.
  static double clearance(BuildContext context) =>
      gap +
      MediaQuery.textScalerOf(context).scale(PindoroType.labelSm.fontSize!) *
          PindoroType.labelSm.height! +
      2 * _paddingY +
      gap;

  @override
  Widget build(BuildContext context) {
    final colors = PindoroTheme.of(context).colors;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - 2 * PindoroSpace.s4,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.mapAttributionBg,
          borderRadius: BorderRadius.circular(PindoroRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PindoroSpace.s2,
            vertical: _paddingY,
          ),
          child: Text(
            context.l10n.commonAttribution,
            style: PindoroType.labelSm.copyWith(
              color: colors.mapAttributionText,
            ),
          ),
        ),
      ),
    );
  }
}
