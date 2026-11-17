import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Leave · the 12-block session bar · the time left, counting down by the
/// second (design system Progress, Session bar).
class SessionTopBar extends ConsumerStatefulWidget {
  const SessionTopBar(
    this.play, {
    super.key,
    required this.onLeave,
    this.drills = Drills.none,
  });

  final SessionPlaying play;
  final VoidCallback onLeave;

  /// The plan's drills, for the minutes they take.
  final Drills drills;

  @override
  ConsumerState<SessionTopBar> createState() => _SessionTopBarState();
}

class _SessionTopBarState extends ConsumerState<SessionTopBar> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final play = widget.play;
    final answered = play.index + (play.answered ? 1 : 0);
    final blocks = finishedBlocks(
      total: play.steps.length,
      answered: answered,
      forgotten: play.forgotten,
    );
    final left = secondsLeft(
      play.steps,
      play.index,
      spentS: ref.read(clockProvider)().difference(play.startedAt).inSeconds,
      drills: widget.drills,
    );
    return Row(
      spacing: PindoroSpace.s3,
      children: [
        PindoroIconButton(
          glyph: PindoroGlyph.close,
          semanticLabel: play.step.kind == StepKind.placement
              ? l10n.placementLeave
              : l10n.sessionLeave,
          onPressed: widget.onLeave,
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
          label: formatCountdown(left),
          icon: PindoroGlyph.timer,
          iconColor: c.primaryText,
          floating: true,
          semanticLabel: l10n.sessionMinutesLeft((left / 60).ceil()),
        ),
      ],
    );
  }
}
