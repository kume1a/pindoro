import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/badges/ui/badge_reward.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/features/results/data/results_data.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Close and Miss answers that make a round tough.
const int _toughRetries = 5;

/// When each part of the results arrival starts (canvas M-40).
abstract final class _Arrival {
  static const Duration chips = Duration(milliseconds: 1520);
  static const Duration rows = Duration(milliseconds: 1640);
}

/// An Explore round's results: Pindo and the title, what the round earned
/// (streets newly known, the streak), the tier tally, every answer, retry and
/// play again, arriving in sequence.
class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key, required this.roundId});

  final String roundId;

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen>
    with BadgeMoments {
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(resultsProvider(widget.roundId)).value;
    if (data == null) return const Scaffold();
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    showBadgesAfter(_Arrival.rows);
    final counts = <Tier, int>{};
    for (final e in data.entries) {
      counts.update(e.answer.tier, (n) => n + 1, ifAbsent: () => 1);
    }
    final streak = ref.watch(streakProvider).value;
    final streakDays = streak?.summary.days ?? 0;
    // This round made today count: the streak grows by a day as it lands.
    final grewStreak = streak?.todayRoundId == widget.roundId;
    final chips = [
      if (data.newlyKnown > 0)
        PopIn(
          delay: _Arrival.chips,
          child: Pill(
            label: l10n.resultsStreetsKnown(data.newlyKnown),
            icon: PindoroGlyph.checkCircle,
            iconColor: c.successBase,
          ),
        ),
      if (grewStreak)
        PopIn(
          delay: _Arrival.chips,
          child: CountUp(
            value: streakDays,
            from: streakDays - 1,
            delay: _Arrival.chips,
            onEnd: ref.read(feedbackProvider).streak,
            builder: (context, days) => Pill(
              label: l10n.streakDays(formatNumber(days)),
              icon: PindoroGlyph.flame,
              iconColor: c.streakFlame,
              iconAccent: c.streakCore,
              semanticLabel: l10n.resultsStreakA11y(formatNumber(streakDays)),
            ),
          ),
        ),
    ];
    final RoundSummary summary = (
      roundId: data.round.id,
      startedAt: data.round.startedAt,
    );
    void goHome() => context.go(Routes.home, extra: summary);
    void playAgain() => context.go(Routes.round);
    void retry() => context.go(Routes.retry(widget.roundId));
    // A retry replays streets: no retry of its own.
    final isRetry = data.round.retryOf != null;
    // A tough round (canvas M-42) makes Retry the main action.
    final tough = !isRetry && data.retryCount >= _toughRetries;
    final (secondary, primary) = isRetry
        ? ((l10n.commonDone, goHome), (l10n.resultsNewRound, playAgain))
        : tough
        ? (
            (l10n.resultsPlayAgain, playAgain),
            (l10n.resultsRetryMissed(data.retryCount), retry),
          )
        : (
            (l10n.commonChangeSettings, () => context.go(Routes.area)),
            (l10n.resultsPlayAgain, playAgain),
          );
    final page = PageScaffold(
      title: isRetry
          ? l10n.resultsRetryTitle
          : data.retryCount == 0
          ? l10n.resultsFlawless
          : l10n.resultsTitle,
      trailing: PindoroIconButton(
        glyph: PindoroGlyph.close,
        semanticLabel: l10n.commonDone,
        onPressed: goHome,
      ),
      showBack: false,
      footer: Row(
        spacing: PindoroSpace.s3,
        children: [
          Expanded(
            child: PindoroButton(
              label: secondary.$1,
              variant: PindoroButtonVariant.secondary,
              onPressed: secondary.$2,
            ),
          ),
          Expanded(
            child: PindoroButton(label: primary.$1, onPressed: primary.$2),
          ),
        ],
      ),
      children: [
        if (data.area case final area? when data.shape != null)
          Text(
            areaLabel(context, area, data.pack, settings),
            style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
          ),
        Center(
          child: PopIn(
            child: Pindo(
              tough ? PindoExpression.encouraging : PindoExpression.proud,
              height: 96,
            ),
          ),
        ),
        if (chips.isNotEmpty)
          Wrap(
            spacing: PindoroSpace.s2,
            runSpacing: PindoroSpace.s2,
            children: chips,
          ),
        RiseIn(
          delay: _Arrival.rows,
          distance: PindoroSpace.s4,
          child: TierTally(
            counts: counts,
            labels: {for (final t in Tier.values) t: tierWord(l10n, t)},
            semanticLabel: l10n.a11yTierTally(
              counts[Tier.perfect] ?? 0,
              counts[Tier.great] ?? 0,
              counts[Tier.close] ?? 0,
              counts[Tier.miss] ?? 0,
            ),
          ),
        ),
        RiseIn(
          delay: _Arrival.rows,
          distance: PindoroSpace.s4,
          child: Row(
            children: [
              Expanded(child: SectionTitle(l10n.resultsYourStreets)),
              if (tough)
                const SizedBox.shrink()
              else if (data.retryCount > 0)
                PindoroButton(
                  label: l10n.resultsRetryMissed(data.retryCount),
                  icon: PindoroGlyph.reroute,
                  variant: PindoroButtonVariant.secondary,
                  onPressed: retry,
                )
              else
                Text(
                  l10n.resultsNoRetry,
                  style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                ),
            ],
          ),
        ),
        RiseIn(
          delay: _Arrival.rows,
          distance: 0,
          child: ListGroup(
            children: [
              for (final (i, e) in data.entries.indexed)
                RiseIn(
                  delay: _Arrival.rows + PindoroMotion.stagger * i,
                  distance: PindoroSpace.s4,
                  child: _row(
                    context,
                    l10n,
                    settings,
                    i,
                    e,
                    // The street view frames the round's area.
                    opens: e.street != null && data.shape != null,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    // Results replaced the round, so nothing lies below it: back means Done.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) goHome();
      },
      child: Stack(
        children: [
          page,
          Positioned.fill(
            child: Celebration(
              size:
                  data.firstPerfect ||
                      data.retryCount == 0 ||
                      (grewStreak &&
                          StreakRules.milestones.contains(streakDays))
                  ? CelebrationSize.big
                  : CelebrationSize.medium,
              burstCenter: const Alignment(-0.2, -0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    Settings? settings,
    int index,
    ResultEntry e, {
    required bool opens,
  }) {
    final a = e.answer;
    final street = e.street;
    final name = street == null ? a.streetId : streetName(street, settings);
    final distance = formatDistance(a.distanceM, l10n);
    final word = tierWord(l10n, a.tier);
    final rest = a.tier == Tier.perfect
        ? ' · ${l10n.resultsOnStreet}'
        : ' · $distance';
    return ResultRow(
      tier: a.tier,
      street: name,
      detail: (tierWord: word, rest: rest),
      semanticLabel: l10n.a11yResultRow(index + 1, name, word, distance),
      onTap: !opens
          ? null
          : () {
              ref.read(feedbackProvider).tap();
              context.push(Routes.resultStreet(widget.roundId, index));
            },
    );
  }
}
