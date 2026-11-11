import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/league/data/league_api.dart';
import 'package:pindoro/features/league/data/league_data.dart';
import 'package:pindoro/features/league/ui/league_screen.dart';
import 'package:pindoro/features/progress/data/streak.dart';
import 'package:pindoro/features/progress/ui/level_row.dart';
import 'package:pindoro/features/progress/ui/level_up_screen.dart';
import 'package:pindoro/features/results/data/results_data.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Close and Miss answers that make a round tough.
const int _toughRetries = 5;

/// When each part of the results arrival starts (canvas M-40).
abstract final class _Arrival {
  static const Duration reward = Duration(milliseconds: 200);
  static const Duration bar = Duration(milliseconds: 1100);
  static const Duration chips = Duration(milliseconds: 1520);
  static const Duration rows = Duration(milliseconds: 1640);
}

/// Round results: reward, level, tier tally, every answer, retry and play
/// again. They arrive in sequence; a level crossed in the round fills the bar,
/// opens the level-up moment from it once, then the bar refills in the new
/// level.
class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key, required this.roundId});

  final String roundId;

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  final _barKey = GlobalKey();
  bool _barFull = false;
  bool _levelUpOver = false;

  @override
  void initState() {
    super.initState();
    // Sends the round's XP to the league; the league chip reads the reply.
    ref.invalidate(standingProvider);
  }

  /// The full bar glows, then the level-up moment grows out of it.
  Future<void> _openLevelUp(int level, int totalXp) async {
    if (_barFull) return;
    setState(() => _barFull = true);
    await Future<void>.delayed(PindoroMotion.durationBase);
    if (!mounted) return;
    ref.read(feedbackProvider).levelUp();
    final bar = _barKey.currentContext?.findRenderObject() as RenderBox?;
    await Navigator.of(context).push(
      levelUpRoute(
        level: level,
        totalXp: totalXp,
        from: bar?.localToGlobal(bar.size.center(Offset.zero)),
      ),
    );
    if (mounted) setState(() => _levelUpOver = true);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(resultsProvider(widget.roundId)).value;
    if (data == null) return const Scaffold();
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final before = progressWithinLevel(data.totalXp - data.roundXp);
    final after = progressWithinLevel(data.totalXp);
    final crossed = after.level > before.level;
    // Until the level-up moment is over the bar fills the old level to its end.
    final inNewLevel = !crossed || _levelUpOver;
    final counts = <Tier, int>{};
    for (final e in data.entries) {
      counts.update(e.answer.tier, (n) => n + 1, ifAbsent: () => 1);
    }
    final streak = ref.watch(streakProvider).value;
    final streakDays = streak?.summary.days ?? 0;
    final metGoal = streak?.summary.metToday ?? false;
    // This round met today's goal: the streak grows by a day as it lands.
    final grewStreak = metGoal && streak?.goalRoundId == widget.roundId;
    // Chips pop in with the arrival; the level chip right after the level up.
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
      if (metGoal)
        PopIn(
          delay: _Arrival.chips,
          child: CountUp(
            value: streakDays,
            from: grewStreak ? streakDays - 1 : streakDays,
            delay: _Arrival.chips,
            onEnd: grewStreak ? ref.read(feedbackProvider).streak : null,
            builder: (context, days) => Pill(
              label: l10n.streakDays(formatNumber(days)),
              icon: PindoroGlyph.flame,
              iconColor: c.streakFlame,
              iconAccent: c.streakCore,
              semanticLabel: l10n.resultsStreakA11y(formatNumber(streakDays)),
            ),
          ),
        ),
      if (data.retryCount > 0)
        PopIn(
          delay: _Arrival.chips,
          child: PitStopChip(l10n.resultsToPitStop(data.retryCount)),
        ),
      if (_leagueRise(ref.watch(standingProvider).value, data) case (
        :final rank,
        :final tier,
      ))
        PopIn(
          delay: _Arrival.chips,
          child: Pill(
            label: l10n.resultsLeagueUp(
              formatOrdinal(rank, l10n),
              leagueTitle(l10n, tier),
            ),
            icon: PindoroGlyph.flag,
            iconColor: c.primaryText,
            onTap: () => context.go(Routes.leagues),
          ),
        ),
      if (_levelUpOver)
        PopIn(
          delay: PindoroMotion.durationSlow,
          child: Pill(
            label: l10n.levelUpTitle(after.level),
            icon: PindoroGlyph.xp,
            iconColor: c.xpFill,
          ),
        ),
    ];
    final RoundSummary summary = (
      roundId: data.round.id,
      startedAt: data.round.startedAt,
      roundXp: data.roundXp,
    );
    void goHome() => context.go(Routes.home, extra: summary);
    void playAgain() => context.go(Routes.round);
    void retry() => context.go(Routes.retry(widget.roundId));
    final pitStop = data.round.pitStop;
    // A retry or Pit stop replays streets: no retry of its own.
    final isRetry = data.round.retryOf != null || pitStop;
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
      title: pitStop
          ? l10n.resultsPitStopTitle
          : isRetry
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
        Row(
          spacing: PindoroSpace.s3,
          children: [
            PopIn(
              child: Pindo(
                tough ? PindoExpression.encouraging : PindoExpression.proud,
                height: 64,
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: PopIn(
                  delay: _Arrival.reward,
                  child: CountUp(
                    value: data.roundXp,
                    delay: _Arrival.reward,
                    onEnd: ref.read(feedbackProvider).reward,
                    builder: (context, xp) => RewardTotal(
                      value: l10n.commonXp(formatNumber(xp)),
                      semanticLabel: l10n.a11yRewardTotal(
                        formatNumber(data.roundXp),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (inNewLevel)
          LevelRow(
            key: const ValueKey('new level'),
            level: after,
            from: crossed ? 0 : before.fraction,
            delay: crossed ? Duration.zero : _Arrival.bar,
          )
        else
          LevelRow(
            level: before,
            value: 1,
            from: before.fraction,
            delay: _Arrival.bar,
            barKey: _barKey,
            ring: _barFull,
            // The bar's animation can end inside a frame (reduce motion).
            onFilled: () => WidgetsBinding.instance.addPostFrameCallback(
              (_) => _openLevelUp(after.level, data.totalXp),
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
                  child: _row(context, l10n, settings, i, e),
                ),
            ],
          ),
        ),
      ],
    );
    return Stack(
      children: [
        page,
        Positioned.fill(
          child: Celebration(
            size:
                data.firstPerfect ||
                    data.retryCount == 0 ||
                    (grewStreak && StreakRules.milestones.contains(streakDays))
                ? CelebrationSize.big
                : CelebrationSize.medium,
            burstCenter: const Alignment(-0.2, -0.6),
          ),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    AppLocalizations l10n,
    Settings? settings,
    int index,
    ResultEntry e,
  ) {
    final a = e.answer;
    final street = e.street;
    final name = street == null ? a.streetId : streetName(street, settings);
    final distance = formatDistance(a.distanceM, l10n);
    final word = tierWord(l10n, a.tier);
    final rest = a.tier == Tier.perfect
        ? ' · ${l10n.resultsOnStreet}'
        : ' · $distance'
              '${isRetryTier(a.tier) ? ' · ${l10n.resultsInPitStop}' : ''}';
    return ResultRow(
      tier: a.tier,
      street: name,
      detail: (tierWord: word, rest: rest),
      xp: a.xp,
      semanticLabel: l10n.a11yResultRow(
        index + 1,
        name,
        word,
        distance,
        formatNumber(a.xp),
      ),
      onTap: street == null
          ? null
          : () {
              ref.read(feedbackProvider).tap();
              context.push(Routes.resultStreet(widget.roundId, index));
            },
    );
  }
}

/// The rank this round's XP (its answers in this league week) moved the
/// player up to, with the league's tier; null when it moved them nowhere.
({int rank, int tier})? _leagueRise(Standing? standing, ResultsData data) {
  if (standing == null) return null;
  final start = leagueWeek(DateTime.now()).start;
  final gained = data.entries
      .where((e) => !e.answer.createdAt.isBefore(start))
      .fold(0, (sum, e) => sum + e.answer.xp);
  final me = standing.members.where((m) => m.you).firstOrNull;
  final before = gained == 0 ? null : rankBefore(standing.members, gained);
  if (me == null || before == null || me.rank >= before) return null;
  return (rank: me.rank, tier: standing.tier);
}
