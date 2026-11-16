import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Leave · the 12-block session bar · the minutes left (design system
/// Progress, Session bar).
class SessionTopBar extends StatelessWidget {
  const SessionTopBar(this.play, {super.key, required this.onLeave});

  final SessionPlaying play;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final answered = play.index + (play.reveal == null ? 0 : 1);
    final blocks = finishedBlocks(
      total: play.steps.length,
      answered: answered,
      forgotten: play.forgotten,
    );
    final minutes = (remainingSeconds(play.steps.skip(answered)) / 60).ceil();
    return Row(
      spacing: PindoroSpace.s3,
      children: [
        PindoroIconButton(
          glyph: PindoroGlyph.close,
          semanticLabel: l10n.sessionLeave,
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
        Pill(
          label: l10n.sessionMinutes(minutes),
          icon: PindoroGlyph.timer,
          iconColor: c.primaryText,
          floating: true,
          semanticLabel: l10n.sessionMinutesLeft(minutes),
        ),
      ],
    );
  }
}
