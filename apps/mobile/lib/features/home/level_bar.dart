import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Level and progress towards the next one.
class LevelBar extends StatelessWidget {
  const LevelBar(this.totalXp, {super.key});

  final int totalXp;

  @override
  Widget build(BuildContext context) {
    final p = progressWithinLevel(totalXp);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s1,
      children: [
        Text('Level ${p.level}', style: text.titleLarge),
        LinearProgressIndicator(value: p.xpIntoLevel / p.xpForLevel),
        Text('${p.xpIntoLevel} / ${p.xpForLevel} xp', style: text.bodySmall),
      ],
    );
  }
}
