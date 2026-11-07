import 'dart:async';
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
import '../pack/pack_pending.dart';
import '../pack/sqlite_pack_repository.dart';
import '../quiz/setup_states.dart';

/// What a finished round changed, for Home's one-time intro (canvas M-43).
typedef RoundSummary = ({String roundId, DateTime startedAt, int roundXp});

/// Rounds whose intro Home has played.
// ponytail: lives as long as the process; a restart never replays an intro
// anyway, because the summary only travels with Results' Done.
final _introsPlayed = <String>{};

typedef _DistrictCount = ({District district, KnownCount count});

typedef _Saved = ({Round round, int answered, int total, int xp, DateTime at});

typedef _Counts = ({KnownCount city, Map<String, KnownCount> byDistrict});

typedef _Home = ({
  PackRepository pack,
  int totalXp,
  _Saved? saved,
  KnownCount cityKnown,
  List<_DistrictCount> districts,
  List<_DistrictCount> recent,
  _Counts? before,
});

/// Home's data; with [introBefore], also the counts before that moment, where
/// the intro's numbers start.
final _homeProvider = FutureProvider.autoDispose.family<_Home, DateTime?>((
  ref,
  introBefore,
) async {
  final db = ref.watch(databaseProvider);
  final pack = await ref.watch(packRepositoryProvider.future);
  final city = pack.city();
  final round = await db.savedRound(DateTime.now());
  final progress = round == null ? null : await db.roundProgress(round.id);
  final streets = await ref.watch(cityStreetsProvider.future);
  final partsByDistrict = pack.partsByDistrict();
  Future<_Counts> countsAt({DateTime? before}) async => knownCounts(
    streets: streets,
    partsByDistrict: partsByDistrict,
    known: {
      for (final MapEntry(key: id, value: tier) in bestTierPerStreet(
        await db.bestTierByPart(city.id, before: before),
        streets,
      ).entries)
        if (isKnownTier(tier)) id,
    },
  );
  final counts = await countsAt();
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
    before: introBefore == null ? null : await countsAt(before: introBefore),
  );
});

extension on KnownCount {
  double get fraction => total == 0 ? 0 : known / total;
}

DistrictProgress _progress(KnownCount c) => c.known == 0
    ? DistrictProgress.notStarted
    : c.known >= c.total
    ? DistrictProgress.complete
    : DistrictProgress.inProgress;

/// The city's districts (not neighbourhoods), filled by each one's [count].
DistrictMiniMap _miniMap(
  List<_DistrictCount> districts,
  KnownCount Function(_DistrictCount d) count,
) => DistrictMiniMap(
  districts: [
    for (final d in districts)
      if (d.district.kind == DistrictKind.district)
        (boundary: d.district.boundary, progress: _progress(count(d))),
  ],
);

/// When each part of Home's intro after a round starts (canvas M-43).
abstract final class _IntroAt {
  static const Duration xp = Duration(milliseconds: 300);
  static const Duration bar = Duration(milliseconds: 450);
  static const Duration streets = Duration(milliseconds: 950);
  static const Duration settle = Duration(milliseconds: 2600);
}

/// Where the intro's numbers start, and whether its ring and tip still show.
typedef _Intro = ({int xpBefore, int roundXp, _Counts before, bool settled});

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

  _Intro? _intro(_Home home) {
    final summary = _summary;
    final before = home.before;
    if (summary == null || before == null) return null;
    _settle ??= Timer(
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : _IntroAt.settle,
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
    final home = ref.watch(_homeProvider(_summary?.startedAt)).value;
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
                    CountUp(
                      value: home.totalXp,
                      from: intro?.xpBefore ?? home.totalXp,
                      delay: _IntroAt.xp,
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
                    _LevelCard(
                      level: level,
                      totalXp: home.totalXp,
                      intro: intro,
                    ),
                    if (saved != null) _SavedCard(saved: saved),
                    _CityCard(
                      home: home,
                      intro: intro,
                      settings: settings,
                      onDistrict: openDistrict,
                      onAll: () => open(Routes.area),
                      onCoachClosed: () => ref
                          .read(databaseProvider)
                          .updateSettings(
                            const UserSettingsCompanion(
                              homeCoachSeen: Value(true),
                            ),
                          ),
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
  const _LevelCard({required this.level, required this.totalXp, this.intro});

  final LevelProgress level;
  final int totalXp;
  final _Intro? intro;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final into = formatNumber(level.xpIntoLevel);
    final needed = formatNumber(level.xpForLevel);
    final secondary = PindoroType.labelMd.copyWith(color: c.textSecondary);
    final intro = this.intro;
    final start = intro == null ? null : progressWithinLevel(intro.xpBefore);
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
            value: level.fraction,
            from: start == null
                ? null
                : start.level == level.level
                ? start.fraction
                : 0,
            delay: intro == null ? Duration.zero : _IntroAt.bar,
            tip: intro == null || intro.roundXp == 0
                ? null
                : l10n.commonXp(formatNumber(intro.roundXp)),
            tipShown: !(intro?.settled ?? true),
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
    required this.onCoachClosed,
    this.intro,
  });

  final _Home home;
  final _Intro? intro;
  final Settings? settings;
  final VoidCallback onCoachClosed;
  final ValueChanged<String> onDistrict;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final known = home.cityKnown;
    final before = intro?.before;
    final newlyKnown = known.known - (before?.city.known ?? known.known);
    return LipBox(
      border: c.lineBase,
      padding: const EdgeInsets.all(PindoroSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: [
          Row(
            spacing: PindoroSpace.s2,
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _Coach(
                    show: !(settings?.homeCoachSeen ?? true),
                    onClose: onCoachClosed,
                    child: Text(
                      l10n.homeKnownTitle,
                      style: PindoroType.titleMd.copyWith(color: c.textPrimary),
                    ),
                  ),
                ),
              ),
              if (newlyKnown > 0)
                PopIn(
                  delay: _IntroAt.streets,
                  child: Pill(label: '+${formatNumber(newlyKnown)}'),
                ),
              CountUp(
                value: known.known,
                from: before?.city.known ?? known.known,
                delay: _IntroAt.streets,
                builder: (context, n) => Text(
                  l10n.homeKnownOf(formatNumber(n), formatNumber(known.total)),
                  style: PindoroType.numericMd.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
          if (home.districts.isNotEmpty) ...[
            if (before == null)
              _miniMap(home.districts, (d) => d.count)
            else
              // Districts that changed state fade in with the streets.
              Stack(
                children: [
                  _miniMap(
                    home.districts,
                    (d) =>
                        before.byDistrict[d.district.id] ??
                        (known: 0, total: 0),
                  ),
                  Builder(
                    builder: (context) {
                      final (duration, curve) = delayedMotion(
                        context,
                        _IntroAt.streets,
                        PindoroMotion.durationQuick,
                        Curves.linear,
                      );
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: duration,
                        curve: curve,
                        builder: (_, t, child) =>
                            Opacity(opacity: t, child: child),
                        child: _miniMap(home.districts, (d) => d.count),
                      );
                    },
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
                          value: d.count.fraction,
                          from: before?.byDistrict[d.district.id]?.fraction,
                          delay: _IntroAt.streets,
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

/// The first Home's coach mark (canvas M-13), hanging under [child] while
/// [show]. Any tap closes it.
class _Coach extends StatefulWidget {
  const _Coach({
    required this.show,
    required this.onClose,
    required this.child,
  });

  final bool show;
  final VoidCallback onClose;
  final Widget child;

  @override
  State<_Coach> createState() => _CoachState();
}

class _CoachState extends State<_Coach> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  @override
  void initState() {
    super.initState();
    // The overlay can't change while the tree builds.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(_Coach oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show != oldWidget.show) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  void _sync() {
    if (!mounted) return;
    widget.show ? _portal.show() : _portal.hide();
  }

  void _close() {
    _portal.hide();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => Positioned.fill(
        child: Semantics(
          button: true,
          label: l10n.homeCoachTitle,
          hint: l10n.homeCoachBody,
          onTap: _close,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: Stack(
              children: [
                CompositedTransformFollower(
                  link: _link,
                  targetAnchor: Alignment.bottomLeft,
                  offset: const Offset(-PindoroSpace.s2, PindoroSpace.s2),
                  child: CoachBubble(
                    title: l10n.homeCoachTitle,
                    body: l10n.homeCoachBody,
                    pointsUp: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      child: CompositedTransformTarget(link: _link, child: widget.child),
    );
  }
}
