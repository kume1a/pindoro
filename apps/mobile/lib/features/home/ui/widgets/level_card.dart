import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/features/home/ui/widgets/home_intro.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/features/progress/ui/daily_goal.dart';
import 'package:pindoro/features/progress/ui/level_card.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Home's level card: XP to the next level, today's goal ring, and the XP
/// bar that fills from before the round during the intro.
class HomeLevelCard extends StatelessWidget {
  const HomeLevelCard({
    super.key,
    required this.level,
    required this.totalXp,
    this.intro,
    this.streak,
  });

  final LevelProgress level;
  final int totalXp;
  final HomeIntro? intro;

  /// Today's goal ring sits at the end of the first row.
  final StreakView? streak;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final intro = this.intro;
    final start = intro == null ? null : progressWithinLevel(intro.xpBefore);
    return LevelCard(
      level: level,
      subtitle: toNextLevelLabel(l10n, level),
      caption: l10n.homeXpTotal(formatNumber(totalXp)),
      trailing: switch (streak) {
        final streak? => GoalRing(streak),
        null => null,
      },
      bar: XpBar(
        value: level.fraction,
        from: start == null
            ? null
            : start.level == level.level
            ? start.fraction
            : 0,
        delay: intro == null ? Duration.zero : HomeIntroAt.bar,
        tip: intro == null || intro.roundXp == 0
            ? null
            : l10n.commonXp(formatNumber(intro.roundXp)),
        tipShown: !(intro?.settled ?? true),
        semanticLabel: levelBarLabel(l10n, level),
      ),
    );
  }
}
