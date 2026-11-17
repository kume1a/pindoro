import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A checked pin's sheet: the tier's [label], the [headerChip] (the next
/// review), the [sentence], the [chips], Pindo and the [action] that calls
/// [onNext].
class TierRevealSheet extends StatelessWidget {
  const TierRevealSheet({
    super.key,
    required this.tier,
    required this.label,
    required this.sentence,
    required this.chips,
    required this.action,
    required this.onNext,
    this.headerChip,
  });

  final Tier tier;
  final Widget? headerChip;
  final String label;
  final String sentence;
  final List<Widget> chips;
  final String action;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) => RevealSheet(
    tier: tier,
    label: label,
    sentence: sentence,
    headerChip: headerChip,
    chips: chips,
    mascot: Pindo(switch (tier) {
      Tier.perfect || Tier.great => PindoExpression.cheering,
      Tier.close => PindoExpression.happy,
      Tier.miss => PindoExpression.encouraging,
    }, height: 56),
    action: PindoroButton(
      tier: tier,
      label: action,
      onPressed: () => unawaited(onNext()),
    ),
  );
}

/// A map screen's reveal [sheet] (a MapLayout's bottom): at most 600 dp wide,
/// rising in anew per [revealKey].
class RevealDock extends StatelessWidget {
  const RevealDock({super.key, required this.revealKey, required this.sheet});

  final Object revealKey;
  final Widget sheet;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 600),
    child: RiseIn(key: ValueKey(revealKey), child: sheet),
  );
}

/// The reveal's celebration over the whole map (a MapLayout's front layer),
/// anew per [revealKey].
class RevealCelebration extends StatelessWidget {
  const RevealCelebration({
    super.key,
    required this.revealKey,
    required this.size,
  });

  final Object revealKey;
  final CelebrationSize size;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Celebration(
      key: ValueKey(revealKey),
      size: size,
      burstCenter: const Alignment(-0.78, 0.5),
    ),
  );
}
