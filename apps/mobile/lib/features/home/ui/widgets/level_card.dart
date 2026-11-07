import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/features/home/ui/widgets/home_intro.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/features/progress/ui/daily_goal.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

class LevelCard extends StatelessWidget {
  const LevelCard({
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
    final c = PindoroTheme.of(context).colors;
    final into = formatNumber(level.xpIntoLevel);
    final needed = formatNumber(level.xpForLevel);
    final secondary = PindoroType.labelMd.copyWith(color: c.textSecondary);
    final intro = this.intro;
    final start = intro == null ? null : progressWithinLevel(intro.xpBefore);
    return LipBox(
      border: c.lineBase,
      padding: const EdgeInsets.all(PindoroSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: [
          Row(
            spacing: PindoroSpace.s3,
            children: [
              LevelBadge(level.level),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.homeLevel(level.level),
                      style: PindoroType.titleLg.copyWith(color: c.textPrimary),
                    ),
                    Text(
                      l10n.homeXpToNextLevel(
                        formatNumber(level.xpForLevel - level.xpIntoLevel),
                        level.level + 1,
                      ),
                      style: secondary,
                    ),
                  ],
                ),
              ),
              if (streak case final streak?) GoalRing(streak),
            ],
          ),
          XpBar(
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
            semanticLabel: l10n.a11yLevelProgress(level.level, into, needed),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.homeXpTotal(formatNumber(totalXp)),
                  style: secondary,
                ),
              ),
              Text(
                '$into / $needed XP',
                style: PindoroType.numericSm.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
