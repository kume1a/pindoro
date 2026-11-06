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
import 'level_up_screen.dart';
import 'results_data.dart';

/// Round results: reward, level, tier tally, every answer, retry and play
/// again. A level crossed in the round opens the level-up moment once.
class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key, required this.roundId});

  final String roundId;

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  bool _levelUpShown = false;

  void _maybeLevelUp(ResultsData data) {
    final before = levelForXp(data.totalXp - data.roundXp);
    final after = levelForXp(data.totalXp);
    if (_levelUpShown || after <= before) return;
    _levelUpShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(feedbackProvider).levelUp();
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => LevelUpScreen(level: after, totalXp: data.totalXp),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(resultsProvider(widget.roundId)).value;
    if (data == null) return const Scaffold();
    _maybeLevelUp(data);
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final locale = Localizations.localeOf(context);
    final settings = ref.watch(settingsProvider).value;
    final level = progressWithinLevel(data.totalXp);
    final counts = <Tier, int>{};
    for (final e in data.entries) {
      counts.update(e.answer.tier, (n) => n + 1, ifAbsent: () => 1);
    }
    return PageScaffold(
      title: data.round.retryOf != null
          ? l10n.resultsRetryTitle
          : data.retryCount == 0
          ? l10n.resultsFlawless
          : l10n.resultsTitle,
      trailing: PindoroIconButton(
        glyph: PindoroGlyph.close,
        semanticLabel: l10n.commonDone,
        onPressed: () => context.go(Routes.home),
      ),
      showBack: false,
      footer: Row(
        spacing: PindoroSpace.s3,
        children: [
          Expanded(
            child: PindoroButton(
              label: l10n.commonChangeSettings,
              variant: PindoroButtonVariant.secondary,
              onPressed: () => context.go(Routes.area),
            ),
          ),
          Expanded(
            child: PindoroButton(
              label: l10n.resultsPlayAgain,
              onPressed: () => context.go(Routes.round),
            ),
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
            const Pindo(PindoExpression.proud, height: 64),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: PopIn(
                  child: CountUp(
                    value: data.roundXp,
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
        _LevelRow(level: level),
        if (data.newlyKnown > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: Pill(
              label: l10n.resultsStreetsKnown(data.newlyKnown),
              icon: PindoroGlyph.checkCircle,
              iconColor: c.successBase,
            ),
          ),
        TierTally(
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
        Row(
          children: [
            Expanded(child: SectionTitle(l10n.resultsYourStreets)),
            if (data.retryCount > 0)
              PindoroButton(
                label: l10n.resultsRetryMissed(data.retryCount),
                icon: PindoroGlyph.reroute,
                variant: PindoroButtonVariant.secondary,
                onPressed: () => context.go(Routes.retry(widget.roundId)),
              )
            else
              Text(
                l10n.resultsNoRetry,
                style: PindoroType.bodySm.copyWith(color: c.textSecondary),
              ),
          ],
        ),
        ListGroup(
          children: [
            for (final (i, e) in data.entries.indexed)
              _row(context, l10n, locale, settings, i, e),
          ],
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

/// "Level 3" with the XP bar and "1 305 / 1 500".
class _LevelRow extends StatelessWidget {
  const _LevelRow({required this.level});

  final LevelProgress level;

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
                value: level.xpIntoLevel / level.xpForLevel,
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
