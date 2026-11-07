import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/database.dart';
import '../../app/format.dart';
import '../../app/page_scaffold.dart';
import '../../app/router.dart';
import '../../app/settings.dart';
import '../../l10n/app_localizations.dart';
import '../home/home_screen.dart';
import 'level_up_screen.dart';
import 'results_data.dart';

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
    final locale = Localizations.localeOf(context);
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
        if (data.shape?.name case final name?)
          Text(
            name,
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
          _LevelRow(
            key: const ValueKey('new level'),
            level: after,
            from: crossed ? 0 : before.fraction,
            delay: crossed ? Duration.zero : _Arrival.bar,
          )
        else
          _LevelRow(
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
            labels: {
              Tier.perfect: l10n.tierPerfectWord,
              Tier.great: l10n.tierGreatWord,
              Tier.close: l10n.tierClose,
              Tier.miss: l10n.tierMissWord,
            },
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
                  child: _row(context, l10n, locale, settings, i, e),
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
            size: data.firstPerfect || data.retryCount == 0
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
    Locale locale,
    Settings? settings,
    int index,
    ResultEntry e,
  ) {
    final a = e.answer;
    final street = e.street;
    final name = street == null
        ? a.streetId
        : settings?.streetName(street) ?? street.name;
    final distance = formatDistance(a.distanceM, locale);
    final word = tierWord(l10n, a.tier);
    final rest = a.tier == Tier.perfect
        ? ' · ${l10n.resultsOnStreet}'
        : ' · $distance'
              '${a.tier == Tier.close || a.tier == Tier.miss ? ' · ${l10n.resultsToRetry}' : ''}';
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

String tierWord(AppLocalizations l10n, Tier tier) => switch (tier) {
  Tier.perfect => l10n.tierPerfectWord,
  Tier.great => l10n.tierGreatWord,
  Tier.close => l10n.tierClose,
  Tier.miss => l10n.tierMissWord,
};

/// "Level 3" with the XP bar and "1 305 / 1 500"; the bar fills from [from]
/// to [value] (default: the level's progress) after [delay] and calls
/// [onFilled] when it gets there.
class _LevelRow extends StatelessWidget {
  const _LevelRow({
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
