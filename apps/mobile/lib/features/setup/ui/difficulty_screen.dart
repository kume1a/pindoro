import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Four difficulty cards in a 2 × 2 radio group, how close counts at the
/// selected level, and Start.
class DifficultyScreen extends ConsumerStatefulWidget {
  const DifficultyScreen({super.key});

  @override
  ConsumerState<DifficultyScreen> createState() => _DifficultyScreenState();
}

class _DifficultyScreenState extends ConsumerState<DifficultyScreen> {
  Difficulty? _picked;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final locale = Localizations.localeOf(context);
    final selected =
        _picked ??
        ref.watch(settingsProvider).value?.lastDifficulty ??
        Difficulty.medium;
    final f = ScoringConfig.difficultyFactor(selected);
    final great = formatDistance(ScoringConfig.greatMaxM * f, locale);
    final close = formatDistance(ScoringConfig.closeMaxM * f, locale);

    return PageScaffold(
      title: l10n.difficultyTitle,
      footer: PindoroButton(
        label: l10n.difficultyStart,
        onPressed: () async {
          await ref
              .read(databaseProvider)
              .updateSettings(
                UserSettingsCompanion(lastDifficulty: Value(selected)),
              );
          if (context.mounted) context.go(Routes.round);
        },
      ),
      children: [
        for (final pair in [
          [Difficulty.easy, Difficulty.medium],
          [Difficulty.hard, Difficulty.expert],
        ])
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: PindoroSpace.s3,
              children: [
                for (final d in pair)
                  Expanded(
                    child: DifficultyCard(
                      difficulty: d,
                      name: difficultyName(l10n, d),
                      description: _description(l10n, d),
                      selected: d == selected,
                      onPressed: () {
                        ref.read(feedbackProvider).tap();
                        setState(() => _picked = d);
                      },
                    ),
                  ),
              ],
            ),
          ),
        LipBox(
          border: c.lineBase,
          padding: const EdgeInsets.all(PindoroSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: PindoroSpace.s3,
            children: [
              Text(
                l10n.difficultyScoringTitle(difficultyName(l10n, selected)),
                style: PindoroType.titleSm.copyWith(color: c.textPrimary),
              ),
              for (final (tier, text) in [
                (Tier.perfect, l10n.resultsOnStreet),
                (Tier.great, l10n.difficultyWithin(great)),
                (Tier.close, l10n.difficultyWithin(close)),
              ])
                Row(
                  spacing: PindoroSpace.s3,
                  children: [
                    TierBadge(tier, size: PindoroSize.iconLg),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: PindoroMotion.durationQuick,
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.centerLeft,
                          children: [...previous, ?current],
                        ),
                        child: Text(
                          text,
                          key: ValueKey(text),
                          style: PindoroType.bodyMd.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _description(AppLocalizations l10n, Difficulty d) => switch (d) {
    Difficulty.easy => l10n.difficultyEasyDescription,
    Difficulty.medium => l10n.difficultyMediumDescription,
    Difficulty.hard => l10n.difficultyHardDescription,
    Difficulty.expert => l10n.difficultyExpertDescription,
  };
}
