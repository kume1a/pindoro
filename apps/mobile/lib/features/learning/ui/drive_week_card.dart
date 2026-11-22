import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/features/learning/data/drive_history.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// The week's drive goal (SPEC §16.23 item 122; setup V32-10, Today V32-71): two drives at Quiet
/// or Off and one new place reached without help, Monday to Sunday, with the weeks done (never
/// a streak) and "Back on track" after a missed week; [below] under the goal lines.
class DriveWeekCard extends ConsumerWidget {
  const DriveWeekCard({super.key, this.below = const []});

  final List<Widget> below;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final goal = ref.watch(driveWeekProvider).value;
    if (goal == null) return const SizedBox.shrink();
    final week = goal.week;
    const quietGoal = LearningConfig.weekQuietDrives;
    const placesGoal = LearningConfig.weekNewPlaces;
    final quiet = math.min(week.quietDrives, quietGoal);
    final places = math.min(week.newPlaces, placesGoal);
    return TitledCard(
      title: goal.backOnTrack ? l10n.driveWeekBack : l10n.driveWeekTitle,
      meta: goal.weeksDone > 0 ? l10n.driveWeeksDone(goal.weeksDone) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s2,
        children: [
          GoalLine(
            done: quiet,
            goal: quietGoal,
            count: l10n.commonXOfY(
              formatNumber(quiet),
              formatNumber(quietGoal),
            ),
            text: l10n.driveGoalQuiet(quietGoal),
          ),
          GoalLine(
            done: places,
            goal: placesGoal,
            count: l10n.commonXOfY(
              formatNumber(places),
              formatNumber(placesGoal),
            ),
            text: l10n.driveGoalPlaces(placesGoal),
          ),
          if (weekDone(week))
            Text(
              l10n.driveWeekDone,
              style: PindoroType.bodySm.copyWith(color: c.successText),
            ),
          ...below,
        ],
      ),
    );
  }
}
