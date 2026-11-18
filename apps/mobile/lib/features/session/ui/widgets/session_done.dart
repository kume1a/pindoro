import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Session done, or a round done with more to come: the counts, City memory
/// counting up from the round's start, and what to watch out for (mix-ups,
/// streets Close twice).
class SessionDoneView extends ConsumerStatefulWidget {
  const SessionDoneView({
    super.key,
    required this.summary,
    required this.onDone,
    this.onNextRound,
    this.onLearnMore,
  });

  final SessionSummary summary;
  final VoidCallback onDone;

  /// "Next round", above "Done for now", while rounds are left.
  final VoidCallback? onNextRound;

  /// "Learn 10 more", above Done when offered.
  final VoidCallback? onLearnMore;

  @override
  ConsumerState<SessionDoneView> createState() => _SessionDoneViewState();
}

/// City memory counts up once the screen has risen in.
const Duration _countFrom = PindoroMotion.durationSlow;

class _SessionDoneViewState extends ConsumerState<SessionDoneView>
    with CountUpTicks {
  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final onDone = widget.onDone;
    final onNextRound = widget.onNextRound;
    final onLearnMore = widget.onLearnMore;
    final more = onNextRound ?? onLearnMore;
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final streak = ref.watch(streakProvider).value?.summary.days ?? 0;
    final s = summary;
    Widget tile(String label, String value) => Expanded(
      child: StatTile(label: label, value: value),
    );
    tickCountUp(
      (s.memoryAfter.round() - s.memoryBefore.round()).abs(),
      _countFrom,
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
          footer: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s1,
            children: [
              if (more != null)
                PindoroButton(
                  label: onNextRound != null
                      ? l10n.sessionNextRound
                      : l10n.todayLearnMore(LearningConfig.learnMoreCount),
                  onPressed: more,
                ),
              PindoroButton(
                label: onNextRound != null
                    ? l10n.sessionRoundLater
                    : l10n.commonDone,
                variant: more == null
                    ? PindoroButtonVariant.primary
                    : PindoroButtonVariant.secondary,
                onPressed: onDone,
              ),
            ],
          ),
          children: [
            const Center(child: Pindo(PindoExpression.proud, height: 120)),
            Text(
              onNextRound != null
                  ? l10n.sessionRoundDoneTitle(s.round, s.rounds)
                  : l10n.sessionDoneTitle,
              textAlign: TextAlign.center,
              style: PindoroType.headlineLg.copyWith(color: c.textPrimary),
            ),
            Text(
              s.cleared && onNextRound == null
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
                  trailing: CountUp(
                    value: s.memoryAfter.round(),
                    from: s.memoryBefore.round(),
                    delay: _countFrom,
                    onEnd: ref.read(feedbackProvider).reward,
                    builder: (context, memory) => Text(
                      l10n.sessionDoneMemoryChange(
                        formatNumber(s.memoryBefore.round()),
                        formatNumber(memory),
                      ),
                      style: PindoroType.numericSm.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
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
