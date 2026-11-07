import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// "Level 3, 1 305 of 1 500 XP", for the XP bar.
String levelBarLabel(AppLocalizations l10n, LevelProgress level) =>
    l10n.a11yLevelProgress(
      level.level,
      formatNumber(level.xpIntoLevel),
      formatNumber(level.xpForLevel),
    );

/// "195 XP to level 4".
String toNextLevelLabel(AppLocalizations l10n, LevelProgress level) =>
    l10n.homeXpToNextLevel(
      formatNumber(level.xpForLevel - level.xpIntoLevel),
      level.level + 1,
    );

/// The level shield, "Level n" and [subtitle] ([trailing] ends that row);
/// the XP bar ([bar], or a still one); [caption] and the XP into the level.
class LevelCard extends StatelessWidget {
  const LevelCard({
    super.key,
    required this.level,
    required this.subtitle,
    required this.caption,
    this.trailing,
    this.bar,
  });

  final LevelProgress level;
  final String subtitle;
  final String caption;
  final Widget? trailing;
  final Widget? bar;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final secondary = PindoroType.labelMd.copyWith(color: c.textSecondary);
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
                    Text(subtitle, style: secondary),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          bar ??
              XpBar(
                value: level.fraction,
                semanticLabel: levelBarLabel(l10n, level),
              ),
          Row(
            children: [
              Expanded(child: Text(caption, style: secondary)),
              Text(
                '${formatNumber(level.xpIntoLevel)} / '
                '${formatNumber(level.xpForLevel)} XP',
                style: PindoroType.numericSm.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
