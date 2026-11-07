import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The streak in Home's top bar, in this moment's state; opens Streak.
class HomeStreakPill extends StatelessWidget {
  const HomeStreakPill(this.view, {super.key, required this.onPressed});

  final StreakView view;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final summary = view.summary;
    final days = formatNumber(summary.days);
    final state = summary.pillState(DateTime.now());
    return StreakPill(
      label: days,
      state: state,
      onPressed: onPressed,
      semanticLabel: switch (state) {
        StreakPillState.active => l10n.streakA11yActive(days),
        StreakPillState.atRisk => l10n.streakA11yRisk(days),
        StreakPillState.frozen => l10n.streakA11yFrozen(days),
        StreakPillState.off when summary.days == 0 => l10n.streakA11yNone,
        StreakPillState.off => l10n.streakA11yOpen(days),
      },
    );
  }
}
