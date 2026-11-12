import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A checked answer's sheet (a pin or a road trip): the tier's [label], the
/// XP counting up (a Miss shows none), the [sentence], the [chips], Pindo
/// and the [action] that calls [onNext].
class TierRevealSheet extends StatelessWidget {
  const TierRevealSheet({
    super.key,
    required this.tier,
    required this.xp,
    required this.label,
    required this.sentence,
    required this.chips,
    required this.action,
    required this.onNext,
  });

  final Tier tier;
  final int xp;
  final String label;
  final String sentence;
  final List<Widget> chips;
  final String action;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CountUp(
      value: xp,
      builder: (context, xp) => RevealSheet(
        tier: tier,
        label: label,
        sentence: sentence,
        xpLabel: tier == Tier.miss ? null : l10n.commonXp(formatNumber(xp)),
        chips: chips,
        mascot: Pindo(switch (tier) {
          Tier.perfect || Tier.great => PindoExpression.cheering,
          Tier.close => PindoExpression.happy,
          Tier.miss => PindoExpression.encouraging,
        }, height: 80),
        action: PindoroButton(
          tier: tier,
          label: action,
          onPressed: () => unawaited(onNext()),
        ),
      ),
    );
  }
}

/// A map screen's reveal over its whole stack: the [sheet] rising in at the
/// bottom and the [celebration], both anew per [revealKey].
class RevealDock extends StatelessWidget {
  const RevealDock({
    super.key,
    required this.revealKey,
    required this.sheet,
    this.celebration,
  });

  final Object revealKey;
  final Widget sheet;
  final CelebrationSize? celebration;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Stack(
      children: [
        Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: RiseIn(key: ValueKey(revealKey), child: sheet),
          ),
        ),
        if (celebration case final size?)
          Positioned.fill(
            child: Celebration(
              key: ValueKey(revealKey),
              size: size,
              burstCenter: const Alignment(-0.78, 0.5),
            ),
          ),
      ],
    ),
  );
}
