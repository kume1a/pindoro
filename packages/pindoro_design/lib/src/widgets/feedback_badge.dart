import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';

/// Tier pill on its lip: colour + icon + label, so the tier never relies on
/// colour alone.
class FeedbackBadge extends StatelessWidget {
  const FeedbackBadge(this.tier, {super.key, this.label});

  final Tier tier;

  /// Defaults to the tier name.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final style = PindoroTheme.of(context).tier(tier);
    final radius = BorderRadius.circular(PindoroRadius.lg);
    return Container(
      padding: const EdgeInsets.only(bottom: PindoroElevation.e1),
      decoration: BoxDecoration(color: style.lip, borderRadius: radius),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PindoroSpace.s4,
          vertical: PindoroSpace.s2,
        ),
        decoration: BoxDecoration(color: style.fill, borderRadius: radius),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: PindoroSpace.s2,
          children: [
            PindoroIcon(style.icon, color: style.on, cut: style.fill),
            Text(
              label ?? tier.name,
              style: PindoroType.labelLg.copyWith(color: style.on),
            ),
          ],
        ),
      ),
    );
  }
}
