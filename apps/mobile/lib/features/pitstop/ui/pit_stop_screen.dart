import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/pitstop/data/pit_stop_data.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Rows shown before "+ n more streets" (canvas R3-02).
const int _shownRows = 4;

/// Streets to review (canvas R3-02): due ones with their step, the last Pit
/// stop's tally and Start Pit stop; "All tuned up" when nothing is due.
class PitStopScreen extends ConsumerWidget {
  const PitStopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(pitStopProvider).value;
    if (data == null) return const Scaffold();
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final due = data.due;
    if (due.isEmpty) {
      return PageScaffold(
        title: l10n.pitStopTitle,
        children: [_AllTunedUp(next: data.next, today: data.today)],
      );
    }
    final settings = ref.watch(settingsProvider).value;
    final tally = data.lastTally;
    return PageScaffold(
      title: l10n.pitStopTitle,
      footer: PindoroButton(
        label: l10n.pitStopStart(min(due.length, ReviewRules.pitStopSize)),
        icon: PindoroGlyph.wrench,
        hero: true,
        onPressed: () => context.push(Routes.pitStopRound),
      ),
      children: [
        Row(
          spacing: PindoroSpace.s3,
          children: [
            const Pindo(PindoExpression.encouraging, height: 80),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: PindoroSpace.s1,
                children: [
                  Text(
                    l10n.pitStopToTuneUp(due.length),
                    style: PindoroType.titleLg.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    l10n.pitStopRule,
                    style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        ListGroup(
          children: [
            for (final entry in due.take(_shownRows))
              _PitStopRow(entry, today: data.today, settings: settings),
            if (due.length > _shownRows)
              Padding(
                padding: const EdgeInsets.all(PindoroSpace.s4),
                child: Text(
                  l10n.pitStopMore(due.length - _shownRows),
                  style: PindoroType.labelLg.copyWith(color: c.textSecondary),
                ),
              ),
          ],
        ),
        if (tally.isNotEmpty) ...[
          SectionTitle(l10n.pitStopLast),
          TierTally(
            counts: tally,
            labels: {for (final t in Tier.values) t: tierWord(l10n, t)},
            semanticLabel: l10n.pitStopLastA11y(
              tally[Tier.perfect] ?? 0,
              tally[Tier.great] ?? 0,
              tally[Tier.close] ?? 0,
              tally[Tier.miss] ?? 0,
            ),
          ),
        ],
      ],
    );
  }
}

/// A due street: its last tier, how long ago, and its step on the gauge.
class _PitStopRow extends StatelessWidget {
  const _PitStopRow(this.entry, {required this.today, required this.settings});

  final PitStopEntry entry;
  final DateTime today;
  final Settings? settings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final item = entry.item;
    final name = streetName(entry.street, settings);
    final word = tierWord(l10n, item.lastTier);
    final age = l10n.pitStopAge(
      today.difference(calendarDay(item.lastAt)).inDays,
    );
    final step = l10n.pitStopStep(item.step, ReviewRules.steps);
    return ListRow(
      title: name,
      subtitleSpan: TextSpan(
        children: [
          TextSpan(
            text: word,
            style: TextStyle(
              color: PindoroTheme.of(context).tier(item.lastTier).ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: ' · $age'),
        ],
      ),
      leading: TierBadge(item.lastTier),
      trailing: ReviewGauge(item.step, semanticLabel: step),
      semanticsLabel: '$name. $word, $age. $step.',
    );
  }
}

class _AllTunedUp extends StatelessWidget {
  const _AllTunedUp({required this.next, required this.today});

  final ({DateTime day, int count})? next;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final next = this.next;
    return Padding(
      padding: const EdgeInsets.only(top: PindoroSpace.s10),
      child: Column(
        spacing: PindoroSpace.s2,
        children: [
          const Pindo(PindoExpression.happy, height: 112),
          Text(
            l10n.pitStopEmptyTitle,
            textAlign: TextAlign.center,
            style: PindoroType.titleLg.copyWith(color: c.textPrimary),
          ),
          Text(
            l10n.pitStopEmptyBody,
            textAlign: TextAlign.center,
            style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
          ),
          if (next != null)
            Text(
              l10n.pitStopNext(
                next.day.difference(today).inDays,
                l10n.pitStopStreets(next.count),
              ),
              textAlign: TextAlign.center,
              style: PindoroType.labelMd.copyWith(color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}
