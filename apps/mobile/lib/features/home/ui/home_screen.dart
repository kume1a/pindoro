import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/home/data/home_data.dart';
import 'package:pindoro/features/home/ui/widgets/city_card.dart';
import 'package:pindoro/features/home/ui/widgets/home_intro.dart';
import 'package:pindoro/features/home/ui/widgets/level_card.dart';
import 'package:pindoro/features/home/ui/widgets/saved_card.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/pack/ui/pack_pending.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Rounds whose intro Home has played.
// ponytail: lives as long as the process; a restart never replays an intro
// anyway, because the summary only travels with Results' Done.
final _introsPlayed = <String>{};

/// Level, XP and the streets you know in the city, district by district;
/// Play (or Continue round) pinned in the thumb zone. Right after a round
/// ([summary]) the numbers count up from where they were, once.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.summary});

  final RoundSummary? summary;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final RoundSummary? _summary = switch (widget.summary) {
    final s? when _introsPlayed.add(s.roundId) => s,
    _ => null,
  };
  Timer? _settle;
  bool _settled = false;

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  HomeIntro? _intro(HomeData home) {
    final summary = _summary;
    final before = home.before;
    if (summary == null || before == null) return null;
    _settle ??= Timer(
      MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : HomeIntroAt.settle,
      () {
        if (mounted) setState(() => _settled = true);
      },
    );
    return (
      xpBefore: home.totalXp - summary.roundXp,
      roundXp: summary.roundXp,
      before: before,
      settled: _settled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeProvider(_summary?.startedAt)).value;
    final settings = ref.watch(settingsProvider).value;
    if (home == null) {
      return PackPending(pack: ref.watch(packRepositoryProvider));
    }
    final intro = _intro(home);
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final locale = Localizations.localeOf(context);
    final city = home.pack.city();
    final cityName = locale.languageCode == 'ka' ? city.nameKa : city.nameEn;
    final level = progressWithinLevel(home.totalXp);
    // Areas picked in another pack (offline, the Vake one stands in) aren't
    // playable here, so Play asks for an area instead.
    final area = switch (settings?.area) {
      DistrictsArea(:final ids)
          when !home.pack.districts().any((d) => ids.contains(d.id)) =>
        null,
      final area => area,
    };
    final difficulty = settings?.lastDifficulty;
    final saved = home.saved;

    // Back from a pushed screen: the round or progress may have changed.
    Future<void> open(String location) async {
      await context.push(location);
      if (context.mounted) ref.invalidate(homeProvider);
    }

    Future<void> openDistrict(String id) async {
      await ref.read(settingsDaoProvider).chooseArea(DistrictsArea({id}));
      await open(Routes.area);
    }

    final resumes = area == null || difficulty == null
        ? null
        : '$cityName · ${areaLabel(context, area, home.pack, settings)} · '
              '${difficultyName(l10n, difficulty)}';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ContentColumn(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  PindoroSpace.s4,
                  PindoroSpace.s2,
                  PindoroSpace.s4,
                  0,
                ),
                child: Row(
                  spacing: PindoroSpace.s2,
                  children: [
                    // The space after the name is reserved for the streak pill
                    // (release 2).
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: CitySwitcher(
                          city: cityName,
                          semanticLabel: l10n.a11yCitySwitcher(cityName),
                          onPressed: () => open(Routes.city),
                        ),
                      ),
                    ),
                    CountUp(
                      value: home.totalXp,
                      from: intro?.xpBefore ?? home.totalXp,
                      delay: HomeIntroAt.xp,
                      builder: (context, xp) => Pill(
                        label: formatNumber(xp),
                        icon: PindoroGlyph.xp,
                        iconColor: c.xpFill,
                        ring: intro != null && !intro.settled,
                        semanticLabel: l10n.homeXpTotal(
                          formatNumber(home.totalXp),
                        ),
                      ),
                    ),
                    PindoroIconButton(
                      glyph: PindoroGlyph.settings,
                      semanticLabel: l10n.a11ySettings,
                      onPressed: () => open(Routes.settings),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(PindoroSpace.s4),
                children: [
                  for (final card in [
                    LevelCard(
                      level: level,
                      totalXp: home.totalXp,
                      intro: intro,
                    ),
                    if (saved != null) SavedCard(saved: saved),
                    CityCard(
                      home: home,
                      intro: intro,
                      settings: settings,
                      onDistrict: openDistrict,
                      onAll: () => open(Routes.area),
                      onCoachClosed: () =>
                          ref.read(settingsDaoProvider).markHomeCoachSeen(),
                    ),
                  ])
                    ContentColumn(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: PindoroSpace.s4),
                        child: card,
                      ),
                    ),
                ],
              ),
            ),
            PinnedFooter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: PindoroSpace.s2,
                children: [
                  if (saved == null && resumes != null)
                    Text(
                      resumes,
                      textAlign: TextAlign.center,
                      style: PindoroType.labelMd.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  if (saved != null) ...[
                    PindoroButton(
                      label: l10n.homeContinueRound,
                      icon: PindoroGlyph.play,
                      hero: true,
                      onPressed: () => open(Routes.resume(saved.round.id)),
                    ),
                    PindoroButton(
                      label: l10n.homeNewRound,
                      variant: PindoroButtonVariant.tertiary,
                      onPressed: () => open(Routes.round),
                    ),
                  ] else if (resumes != null)
                    Semantics(
                      label: l10n.a11yPlay(resumes),
                      child: PindoroButton(
                        label: l10n.commonPlay,
                        icon: PindoroGlyph.play,
                        hero: true,
                        onPressed: () => open(Routes.round),
                      ),
                    )
                  else
                    PindoroButton(
                      label: l10n.homeChooseArea,
                      hero: true,
                      onPressed: () => open(Routes.area),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
