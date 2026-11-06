import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/area_label.dart';
import '../../app/database.dart';
import '../../app/format.dart';
import '../../app/page_scaffold.dart';
import '../../app/router.dart';
import '../../app/settings.dart';
import '../pack/sqlite_pack_repository.dart';
import '../quiz/setup_states.dart';

typedef _DistrictCount = ({District district, KnownCount count});

typedef _Saved = ({Round round, int answered, int total, int xp, DateTime at});

typedef _Home = ({
  PackRepository pack,
  int totalXp,
  _Saved? saved,
  KnownCount cityKnown,
  List<_DistrictCount> districts,
  List<_DistrictCount> recent,
});

final _homeProvider = FutureProvider.autoDispose<_Home>((ref) async {
  final db = ref.watch(databaseProvider);
  final pack = await ref.watch(packRepositoryProvider.future);
  final city = pack.city();
  final round = await db.savedRound(DateTime.now());
  final progress = round == null ? null : await db.roundProgress(round.id);
  final streets = await ref.watch(cityStreetsProvider.future);
  final counts = knownCounts(
    streets: streets,
    partsByDistrict: pack.partsByDistrict(),
    known: {
      for (final MapEntry(key: id, value: tier) in bestTierPerStreet(
        await db.bestTierByPart(city.id),
        streets,
      ).entries)
        if (isKnownTier(tier)) id,
    },
  );
  final districts = [
    for (final d in pack.districts())
      (district: d, count: counts.byDistrict[d.id] ?? (known: 0, total: 0)),
  ];
  final byId = {for (final d in districts) d.district.id: d};
  return (
    pack: pack,
    totalXp: await db.totalXp(),
    saved: progress == null
        ? null
        : (
            round: progress.round,
            answered: progress.answers.length,
            total: progress.planned.length,
            xp: progress.answers.fold(0, (sum, a) => sum + a.xp),
            at:
                progress.answers.lastOrNull?.createdAt ??
                progress.round.startedAt,
          ),
    cityKnown: counts.city,
    districts: districts,
    recent: [
      for (final id in await db.recentDistrictIds(city.id)) ?byId[id],
    ].take(2).toList(),
  );
});

DistrictProgress _progress(KnownCount c) => c.known == 0
    ? DistrictProgress.notStarted
    : c.known >= c.total
    ? DistrictProgress.complete
    : DistrictProgress.inProgress;

/// Level, XP and the streets you know in the city, district by district;
/// Play (or Continue round) pinned in the thumb zone.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(_homeProvider).value;
    final settings = ref.watch(settingsProvider).value;
    if (home == null) return const Scaffold();
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final locale = Localizations.localeOf(context);
    final city = home.pack.city();
    final cityName = locale.languageCode == 'ka' ? city.nameKa : city.nameEn;
    final level = progressWithinLevel(home.totalXp);
    final area = settings?.area;
    final difficulty = settings?.lastDifficulty;
    final saved = home.saved;

    // Back from a pushed screen: the round or progress may have changed.
    Future<void> open(String location) async {
      await context.push(location);
      if (context.mounted) ref.invalidate(_homeProvider);
    }

    Future<void> openDistrict(String id) async {
      await ref
          .read(databaseProvider)
          .updateSettings(
            UserSettingsCompanion(
              lastAreaJson: Value(jsonEncode(DistrictsArea({id}).toJson())),
            ),
          );
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
                    Pill(
                      label: formatNumber(home.totalXp),
                      icon: PindoroGlyph.xp,
                      iconColor: c.xpFill,
                      semanticLabel: l10n.homeXpTotal(
                        formatNumber(home.totalXp),
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
                    _LevelCard(level: level, totalXp: home.totalXp),
                    if (saved != null) _SavedCard(saved: saved),
                    _CityCard(
                      home: home,
                      settings: settings,
                      onDistrict: openDistrict,
                      onAll: () => open(Routes.area),
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

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.level, required this.totalXp});

  final LevelProgress level;
  final int totalXp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final into = formatNumber(level.xpIntoLevel);
    final needed = formatNumber(level.xpForLevel);
    final secondary = PindoroType.labelMd.copyWith(color: c.textSecondary);
    return LipBox(
      border: c.lineBase,
      padding: const EdgeInsets.all(PindoroSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: [
          Row(
            spacing: PindoroSpace.s3,
            children: [
              LevelBadge(level.level),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.homeLevel(level.level),
                      style: PindoroType.titleLg.copyWith(color: c.textPrimary),
                    ),
                    Text(
                      l10n.homeXpToNextLevel(
                        formatNumber(level.xpForLevel - level.xpIntoLevel),
                        level.level + 1,
                      ),
                      style: secondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          XpBar(
            value: level.xpIntoLevel / level.xpForLevel,
            semanticLabel: l10n.a11yLevelProgress(level.level, into, needed),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.homeXpTotal(formatNumber(totalXp)),
                  style: secondary,
                ),
              ),
              Text(
                '$into / $needed XP',
                style: PindoroType.numericSm.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  const _SavedCard({required this.saved});

  final _Saved saved;

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
            l10n.homeSavedAgo(
              formatAgo(DateTime.now().difference(saved.at), l10n),
            ),
            style: PindoroType.bodySm.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CityCard extends StatelessWidget {
  const _CityCard({
    required this.home,
    required this.settings,
    required this.onDistrict,
    required this.onAll,
  });

  final _Home home;
  final Settings? settings;
  final ValueChanged<String> onDistrict;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final known = home.cityKnown;
    return LipBox(
      border: c.lineBase,
      padding: const EdgeInsets.all(PindoroSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.homeKnownTitle,
                  style: PindoroType.titleMd.copyWith(color: c.textPrimary),
                ),
              ),
              Text(
                l10n.homeKnownOf(
                  formatNumber(known.known),
                  formatNumber(known.total),
                ),
                style: PindoroType.numericMd.copyWith(color: c.textPrimary),
              ),
            ],
          ),
          if (home.districts.isNotEmpty) ...[
            DistrictMiniMap(
              districts: [
                for (final d in home.districts)
                  if (d.district.kind == DistrictKind.district)
                    (
                      boundary: d.district.boundary,
                      progress: _progress(d.count),
                    ),
              ],
            ),
            Wrap(
              spacing: PindoroSpace.s4,
              runSpacing: PindoroSpace.s1,
              children: [
                Swatch(
                  progress: DistrictProgress.inProgress,
                  label: l10n.homeLegendInProgress,
                ),
                Swatch(
                  progress: DistrictProgress.complete,
                  label: l10n.homeLegendComplete,
                ),
                Swatch(
                  progress: DistrictProgress.notStarted,
                  label: l10n.homeLegendNotStarted,
                ),
              ],
            ),
          ],
          if (known.known == 0)
            Text(
              l10n.homeEmptyCity,
              style: PindoroType.bodySm.copyWith(color: c.textSecondary),
            ),
          for (final d in home.recent)
            Semantics(
              button: true,
              child: InkWell(
                onTap: () => onDistrict(d.district.id),
                mouseCursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: PindoroSpace.s2,
                  ),
                  child: Row(
                    spacing: PindoroSpace.s3,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          districtName(d.district, settings),
                          style: PindoroType.titleSm.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Minibar(
                          value: d.count.total == 0
                              ? 0
                              : d.count.known / d.count.total,
                        ),
                      ),
                      Text(
                        '${formatNumber(d.count.known)} / '
                        '${formatNumber(d.count.total)}',
                        style: PindoroType.numericSm.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (home.districts.isNotEmpty)
            PindoroButton(
              label: l10n.homeAllDistricts(home.districts.length),
              variant: PindoroButtonVariant.tertiary,
              onPressed: onAll,
            ),
        ],
      ),
    );
  }
}
