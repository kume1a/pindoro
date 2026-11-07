import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Today's XP toward the goal, for Home's level card and the Streak screen.
class GoalRing extends StatelessWidget {
  const GoalRing(this.view, {super.key});

  final StreakView view;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final xp = formatNumber(view.todayXp);
    final goal = formatNumber(view.goal);
    return DailyGoalRing(
      progress: view.goalProgress,
      semanticLabel: view.summary.metToday
          ? l10n.dailyGoalA11yMet(xp, goal)
          : l10n.dailyGoalA11y(xp, goal),
    );
  }
}

/// "About two rounds", from the goal (250 XP is about one round).
String goalRounds(BuildContext context, int goal) =>
    context.l10n.dailyGoalRounds(goal ~/ StreakRules.goals.first);

/// The 250 / 500 / 1 000 XP choice; picking one saves it, marks today when
/// its XP already reaches the new goal, and closes the sheet.
Future<void> showDailyGoalSheet(BuildContext context, WidgetRef ref) {
  final current = ref.read(settingsProvider).value?.dailyGoal;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheet) {
      final l10n = sheet.l10n;
      final c = PindoroTheme.of(sheet).colors;
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          PindoroSpace.s4,
          0,
          PindoroSpace.s4,
          PindoroSpace.s6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroSpace.s3,
          children: [
            Text(
              l10n.dailyGoalSheetTitle,
              style: PindoroType.titleLg.copyWith(color: c.textPrimary),
            ),
            ListGroup(
              children: [
                for (final goal in StreakRules.goals)
                  ListRow(
                    title: l10n.dailyGoalPerDay(formatNumber(goal)),
                    subtitle: goalRounds(sheet, goal),
                    leading: const RowTile(PindoroGlyph.flame),
                    check: goal == current ? CheckState.on : CheckState.off,
                    onTap: () {
                      ref.read(feedbackProvider).tap();
                      Navigator.of(sheet).pop();
                      unawaited(_saveGoal(ref, goal));
                    },
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _saveGoal(WidgetRef ref, int goal) async {
  await ref.read(settingsDaoProvider).setDailyGoal(goal);
  await ref.read(progressDaoProvider).markGoalIfMet(DateTime.now());
}
