import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// "© OpenStreetMap contributors, Protomaps" on every map: `label.sm` on a
/// raised chip. Not interactive; the full credits are in Settings.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

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
            vertical: 2,
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
