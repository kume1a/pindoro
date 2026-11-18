import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Leave · the round's 12-block session bar · "Round 1 of 3" while the day
/// has more than one (design system Progress, Session bar).
class SessionTopBar extends StatelessWidget {
  const SessionTopBar(
    this.play, {
    super.key,
    required this.onLeave,
    required this.round,
  });

  final SessionPlaying play;
  final VoidCallback onLeave;
  final ({int index, int count}) round;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final answered = play.index + (play.answered ? 1 : 0);
    final blocks = finishedBlocks(
      total: play.steps.length,
      answered: answered,
      forgotten: play.forgotten,
    );
    return Row(
      spacing: PindoroSpace.s3,
      children: [
        PindoroIconButton(
          glyph: PindoroGlyph.close,
          semanticLabel: play.step.kind == StepKind.placement
              ? l10n.placementLeave
              : l10n.sessionLeave,
          onPressed: onLeave,
        ),
        Expanded(
          child: QuestionBar(
            tiers: [for (final miss in blocks) miss ? Tier.miss : Tier.great],
            total: 12,
            height: 14,
            semanticLabel: l10n.sessionProgress(
              (blocks.length + 1).clamp(1, 12),
            ),
          ),
        ),
        if (round.count > 1)
          Pill(
            label: l10n.sessionRound(round.index, round.count),
            floating: true,
          ),
      ],
    );
  }
}
