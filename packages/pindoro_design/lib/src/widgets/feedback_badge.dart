import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';

typedef _T = PindoroTokens;

/// Tier pill: colour + icon + label, so the tier never relies on colour alone.
class FeedbackBadge extends StatelessWidget {
  const FeedbackBadge(this.tier, {super.key, this.label});

  final Tier tier;

  /// Defaults to the tier name.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final style = PindoroTheme.of(context).tier(tier);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _T.spaceMd,
        vertical: _T.spaceSm,
      ),
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: BorderRadius.circular(_T.radiusLg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: _T.spaceSm,
        children: [
          Icon(style.icon, color: style.on),
          Text(
            label ?? tier.name,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: style.on),
          ),
        ],
      ),
    );
  }
}
