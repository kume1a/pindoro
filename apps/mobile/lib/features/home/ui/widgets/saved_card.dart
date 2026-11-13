import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/features/home/data/home_data.dart';
import 'package:pindoro_design/pindoro_design.dart';

class SavedCard extends StatelessWidget {
  const SavedCard({super.key, required this.saved});

  final HomeSavedRound saved;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    return LipBox(
      face: c.primarySoft,
      lip: c.primaryBase,
      border: c.primaryBase,
      padding: const EdgeInsets.all(PindoroSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.homeSavedTitle,
            style: PindoroType.titleMd.copyWith(color: c.primaryText),
          ),
          Text(
            l10n.homeSavedProgress(
              saved.answered + 1,
              saved.total,
              formatNumber(saved.xp),
            ),
            style: PindoroType.bodyMd.copyWith(color: c.textPrimary),
          ),
          Text(
            l10n.homeSavedAgo(formatSince(saved.at, l10n)),
            style: PindoroType.bodySm.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}
