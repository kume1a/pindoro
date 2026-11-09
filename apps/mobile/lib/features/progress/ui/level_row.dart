import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// "Level 3" with the XP bar and "1 305 / 1 500"; the bar fills from [from]
/// to [value] (default: the level's progress) after [delay] and calls
/// [onFilled] when it gets there.
class LevelRow extends StatelessWidget {
  const LevelRow({
    super.key,
    required this.level,
    required this.from,
    required this.delay,
    this.value,
    this.barKey,
    this.ring = false,
    this.onFilled,
  });

  final LevelProgress level;
  final double from;
  final double? value;
  final Duration delay;
  final Key? barKey;
  final bool ring;
  final VoidCallback? onFilled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final into = formatNumber(level.xpIntoLevel);
    final needed = formatNumber(level.xpForLevel);
    return Row(
      spacing: PindoroSpace.s3,
      children: [
        LevelBadge(level.level, size: 44),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s1,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.homeLevel(level.level),
                      style: PindoroType.titleSm.copyWith(color: c.textPrimary),
                    ),
                  ),
                  Text(
                    '$into / $needed',
                    style: PindoroType.numericSm.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
              XpBar(
                key: barKey,
                value: value ?? level.fraction,
                from: from,
                delay: delay,
                ring: ring,
                onEnd: onFilled,
                semanticLabel: l10n.a11yLevelProgress(
                  level.level,
                  into,
                  needed,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
