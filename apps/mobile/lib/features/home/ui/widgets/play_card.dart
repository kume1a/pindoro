import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/features/home/data/home_data.dart';
import 'package:pindoro/features/learning/data/memory_summary.dart';
import 'package:pindoro/features/learning/ui/city_memory_card.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// What Play starts, at the top of Explore's sheet: the round in progress
/// (Continue), the area picked on the map or last played with its City
/// memory (once a difficulty is set, what a round there can ask and how
/// much of it is known), the difficulty and Play; or, with no area yet, how
/// to pick one.
class PlayCard extends StatelessWidget {
  const PlayCard({
    super.key,
    required this.saved,
    required this.area,
    required this.memory,
    this.pool,
    required this.difficulty,
    required this.playLabel,
    required this.onPlay,
    required this.onChangeArea,
    required this.onChangeDifficulty,
    required this.onContinue,
    required this.onNewRound,
  });

  /// Shown instead of the area while no district is picked.
  final HomeSavedRound? saved;

  /// The area's name; null asks for one.
  final String? area;
  final MemorySummary? memory;

  /// What a round at [difficulty] can ask here and how much is in memory;
  /// shown instead of [memory] once known.
  final MemorySummary? pool;
  final Difficulty? difficulty;

  /// "Tbilisi · Vake · Medium", for screen readers.
  final String? playLabel;
  final VoidCallback onPlay;
  final VoidCallback onChangeArea;
  final VoidCallback onChangeDifficulty;
  final VoidCallback onContinue;
  final VoidCallback onNewRound;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final saved = this.saved;
    final area = this.area;
    final pool = this.pool;
    final memory = pool ?? this.memory;
    final difficulty = this.difficulty;

    Widget card(List<Widget> children, {bool primary = false}) => LipBox(
      face: primary ? c.primarySoft : null,
      lip: primary ? c.primaryBase : null,
      border: primary ? c.primaryBase : c.lineBase,
      padding: const EdgeInsets.all(PindoroSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: children,
      ),
    );

    Widget heading(String title, String? subtitle, {Color? ink}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: PindoroType.titleMd.copyWith(color: ink ?? c.textPrimary),
        ),
        if (subtitle != null)
          Text(
            subtitle,
            style: PindoroType.bodySm.copyWith(color: c.textSecondary),
          ),
      ],
    );

    if (saved != null) {
      return card(primary: true, [
        heading(
          l10n.homeSavedTitle,
          [
            l10n.commonQuestionProgress(saved.answered + 1, saved.total),
            l10n.homeSavedAgo(formatSince(saved.at, l10n)),
          ].join(' · '),
          ink: c.primaryText,
        ),
        PindoroButton(
          label: l10n.homeContinueRound,
          icon: PindoroGlyph.play,
          hero: true,
          onPressed: onContinue,
        ),
        PindoroButton(
          label: l10n.homeNewRound,
          variant: PindoroButtonVariant.tertiary,
          onPressed: onNewRound,
        ),
      ]);
    }

    if (area == null) {
      return card([
        heading(l10n.explorePickTitle, l10n.explorePickHint),
        PindoroButton(
          label: l10n.homeChooseArea,
          icon: PindoroGlyph.map,
          hero: true,
          onPressed: onChangeArea,
        ),
      ]);
    }

    final inMemory = switch ((pool, difficulty, memory)) {
      (final p?, final d?, _) => l10n.explorePool(
        p.total,
        formatNumber(p.total),
        difficultyName(l10n, d),
        formatNumber(knownOf(p)),
      ),
      (_, _, final m?) => l10n.memoryInMemory(
        formatNumber(m.memory.round()),
        formatNumber(m.total),
      ),
      _ => null,
    };
    return card([
      Tappable(
        label: l10n.a11yPlayArea(area),
        onTap: onChangeArea,
        child: Row(
          spacing: PindoroSpace.s2,
          children: [
            Expanded(child: heading(area, inMemory)),
            PindoroIcon(PindoroGlyph.chevronRight, color: c.textSecondary),
          ],
        ),
      ),
      if (memory != null)
        MemoryBar(
          counts: memoryCountsOf(memory),
          semanticsLabel: memoryBarLabel(l10n, area, memory),
          compact: true,
        ),
      Row(
        spacing: PindoroSpace.s2,
        children: [
          if (difficulty != null)
            Semantics(
              button: true,
              label: l10n.a11yDifficulty(difficultyName(l10n, difficulty)),
              onTap: onChangeDifficulty,
              excludeSemantics: true,
              child: PindoroChip.action(
                label: difficultyName(l10n, difficulty),
                onPressed: onChangeDifficulty,
              ),
            ),
          Expanded(
            child: Semantics(
              label: playLabel == null ? null : l10n.a11yPlay(playLabel!),
              child: PindoroButton(
                label: l10n.commonPlay,
                icon: PindoroGlyph.play,
                hero: true,
                onPressed: onPlay,
              ),
            ),
          ),
        ],
      ),
    ]);
  }
}
