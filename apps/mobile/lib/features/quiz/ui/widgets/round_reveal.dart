import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/features/quiz/ui/round_controller.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

class RoundReveal extends StatelessWidget {
  const RoundReveal({super.key, required this.revealed, required this.onNext});

  final RoundRevealed revealed;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final answer = revealed.answer;
    final distance = formatDistance(answer.distanceM, l10n);
    final sentence = switch (answer.tier) {
      Tier.perfect => l10n.tierPerfectSentence,
      Tier.great => l10n.tierGreatSentence(distance),
      Tier.close => l10n.tierCloseSentence(distance),
      Tier.miss => l10n.tierMissSentence(
        distance,
        l10n.revealMissDirection(
          compassPoint(revealed.pin!, revealed.nearest).name,
        ),
      ),
    };
    return CountUp(
      value: answer.xp,
      builder: (context, xp) => _sheet(l10n, sentence, xp),
    );
  }

  Widget _sheet(AppLocalizations l10n, String sentence, int xp) {
    final answer = revealed.answer;
    final round = revealed.round;
    return RevealSheet(
      tier: answer.tier,
      label: tierLabel(l10n, answer.tier),
      sentence: sentence,
      xpLabel: answer.tier == Tier.miss
          ? null
          : l10n.commonXp(formatNumber(xp)),
      chips: [
        if (answer.tier == Tier.perfect && round.perfects > 1)
          l10n.revealPerfectRepeat(round.perfects),
        if (round.streak >= 2) l10n.revealStreak(round.streak),
      ],
      mascot: Pindo(switch (answer.tier) {
        Tier.perfect || Tier.great => PindoExpression.cheering,
        Tier.close => PindoExpression.happy,
        Tier.miss => PindoExpression.encouraging,
      }, height: 80),
      action: PindoroButton(
        tier: answer.tier,
        label: answer.tier == Tier.miss
            ? l10n.revealGotIt
            : round.isLast
            ? l10n.revealSeeResults
            : l10n.commonNext,
        onPressed: () => unawaited(onNext()),
      ),
    );
  }
}
