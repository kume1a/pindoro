import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Session done: the counts, City memory before and after, and what to watch
/// out for (mix-ups, streets Close twice). No XP.
class SessionDoneView extends ConsumerWidget {
  const SessionDoneView({
    super.key,
    required this.summary,
    required this.onDone,
  });

  final SessionSummary summary;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final streak = ref.watch(streakProvider).value?.summary.days ?? 0;
    final s = summary;
    Widget tile(String label, String value) => Expanded(
      child: StatTile(label: label, value: value),
    );
    final watch = [
      for (final (target, hit) in s.mixUps)
        ListRow(
          leading: const RowTile(PindoroGlyph.reroute),
          title:
              '${streetName(target, settings)} ↔ ${streetName(hit, settings)}',
          subtitle: l10n.sessionDoneMixedUp,
        ),
      for (final street in s.closeTwice)
        ListRow(
          leading: const RowTile(PindoroGlyph.target),
          title: streetName(street, settings),
          subtitle: l10n.sessionDoneCloseTwice,
        ),
    ];
    return Stack(
      children: [
        PageScaffold(
          showBack: false,
          footer: PindoroButton(label: l10n.commonDone, onPressed: onDone),
          children: [
            const Center(child: Pindo(PindoExpression.proud, height: 120)),
            Text(
              l10n.sessionDoneTitle,
              textAlign: TextAlign.center,
              style: PindoroType.headlineLg.copyWith(color: c.textPrimary),
            ),
            Text(
              s.cleared
                  ? l10n.sessionDoneCleared(s.minutes)
                  : l10n.sessionMinutes(s.minutes),
              textAlign: TextAlign.center,
              style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
            ),
            Row(
              spacing: PindoroSpace.s2,
              children: [
                tile(l10n.learnReviews, formatNumber(s.reviews)),
                tile(l10n.learnNewStreets, formatNumber(s.newStreets)),
              ],
            ),
            Row(
              spacing: PindoroSpace.s2,
              children: [
                tile(
                  l10n.sessionDoneRecalled,
                  l10n.sessionPercent(s.recalledPercent),
                ),
                tile(l10n.sessionDoneStreak, l10n.sessionStreakDays(streak)),
              ],
            ),
            ListGroup(
              children: [
                ListRow(
                  leading: const RowTile(PindoroGlyph.city),
                  title: l10n.sessionDoneMemory,
                  trailing: Text(
                    l10n.sessionDoneMemoryChange(
                      formatNumber(s.memoryBefore.round()),
                      formatNumber(s.memoryAfter.round()),
                    ),
                    style: PindoroType.numericSm.copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
            if (watch.isNotEmpty) ...[
              SectionTitle(l10n.sessionDoneWatchOut),
              ListGroup(children: watch),
            ],
          ],
        ),
        const Positioned.fill(
          child: IgnorePointer(child: Celebration(size: CelebrationSize.big)),
        ),
      ],
    );
  }
}
