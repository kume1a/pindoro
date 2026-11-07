import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'reveal.dart';
import 'surfaces.dart';

/// One round answer on the results list: tier tile, street name, tier word
/// and distance, XP. Tapping opens it on the map.
class ResultRow extends StatelessWidget {
  const ResultRow({
    super.key,
    required this.tier,
    required this.street,
    required this.detail,
    required this.xp,
    required this.semanticLabel,
    this.onTap,
  });

  final Tier tier;
  final String street;

  /// "Great · 84 m"; the tier word is drawn in the tier ink.
  final ({String tierWord, String rest}) detail;
  final int xp;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    return ListRow(
      title: street,
      subtitleSpan: TextSpan(
        children: [
          TextSpan(
            text: detail.tierWord,
            style: TextStyle(
              color: theme.tier(tier).ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: detail.rest),
        ],
      ),
      leading: TierBadge(tier),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: PindoroSpace.s3,
        children: [
          Text(
            xp > 0 ? '+$xp' : '0',
            style: PindoroType.numericSm.copyWith(
              color: xp > 0 ? c.rewardText : c.textSecondary,
            ),
          ),
          if (onTap != null)
            PindoroIcon(
              PindoroGlyph.chevronRight,
              size: PindoroSize.iconSm,
              color: c.textSecondary,
            ),
        ],
      ),
      onTap: onTap,
      semanticsLabel: semanticLabel,
    );
  }
}

/// The round's XP total on the lane-yellow reward plate.
class RewardTotal extends StatelessWidget {
  const RewardTotal({
    super.key,
    required this.value,
    required this.semanticLabel,
  });

  /// "+695 XP".
  final String value;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: LipBox(
        face: c.rewardBase,
        lip: c.rewardLip,
        lipHeight: PindoroElevation.e3,
        padding: const EdgeInsets.symmetric(
          horizontal: PindoroSpace.s6,
          vertical: PindoroSpace.s3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: PindoroSpace.s2,
          children: [
            PindoroIcon(
              PindoroGlyph.xp,
              size: PindoroSize.iconLg,
              color: c.rewardOn,
              cut: c.rewardBase,
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: PindoroType.numericXl.copyWith(color: c.rewardOn),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Four tiles counting the round's answers by tier.
class TierTally extends StatelessWidget {
  const TierTally({
    super.key,
    required this.counts,
    required this.labels,
    required this.semanticLabel,
  });

  final Map<Tier, int> counts;
  final Map<Tier, String> labels;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        spacing: PindoroSpace.s2,
        children: [
          for (final tier in Tier.values)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: PindoroSpace.s1,
                  vertical: PindoroSpace.s2,
                ),
                decoration: BoxDecoration(
                  color: theme.tier(tier).bg,
                  borderRadius: BorderRadius.circular(PindoroRadius.lg),
                ),
                child: Column(
                  spacing: PindoroSpace.s1,
                  children: [
                    TierBadge(tier, size: PindoroSize.iconLg),
                    Text(
                      '${counts[tier] ?? 0}',
                      style: PindoroType.numericMd.copyWith(
                        color: theme.colors.textPrimary,
                      ),
                    ),
                    Text(
                      labels[tier]!,
                      textAlign: TextAlign.center,
                      style: PindoroType.labelMd.copyWith(
                        color: theme.tier(tier).ink,
                      ),
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
