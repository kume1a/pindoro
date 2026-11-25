import 'dart:math';

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
import 'package:pindoro/features/home/ui/widgets/explore_sheet.dart';
import 'package:pindoro/features/home/ui/widgets/offline_card.dart';
import 'package:pindoro/features/home/ui/widgets/play_card.dart';
import 'package:pindoro/features/learning/data/memory_summary.dart';
import 'package:pindoro/features/learning/data/refresh.dart';
import 'package:pindoro/features/learning/ui/city_memory_card.dart';
import 'package:pindoro/features/learning/ui/city_tab_page.dart';
import 'package:pindoro/features/map/data/area_levels.dart';
import 'package:pindoro/features/map/ui/explore_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/pack/ui/pack_pending.dart';
import 'package:pindoro/features/progress/ui/play_top_bar.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Rounds whose intro Explore has played.
// ponytail: lives as long as the process; a restart never replays an intro
// anyway, because the summary only travels with Results' Done.
final _introsPlayed = <String>{};

/// Explore: the city map leads, its districts filled by how much of each is
/// in memory, with a key over it. A tap on a district picks it, outlined in
/// cobalt; the sheet's pinned play card plays it (or the area last played,
/// or continues the round in progress), and the sheet under it lists other
/// ways in. Right after a round ([summary]) City memory counts up from where
/// it was, once.
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

  /// The district a tap on the map picked; Play starts it instead of the
  /// saved area.
  District? _picked;

  /// An area is being saved before its page opens.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (_summary != null) _refreshAfterRound();
  }

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (widget.summary != null && widget.summary != old.summary) {
      _refreshAfterRound();
    }
  }

  /// The round just played wrote to the learning tables.
  void _refreshAfterRound() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refreshLearning(ref);
      });

  /// The sheet's height when it peeks (the play card, City memory and the
  /// quick starts show; the map keeps the rest), and its top when it is
  /// pulled up.
  static const double _peekHeight = 400;
  static const double _openTop = 200;

  static const _sheetShape = BorderRadius.vertical(
    top: Radius.circular(PindoroRadius.r2xl),
  );

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeProvider(_summary?.startedAt)).value;
    final settings = ref.watch(settingsProvider).value;
    final packState = ref.watch(packRepositoryProvider);
    if (home == null || leavingFixture(packState)) {
      return PackPending(pack: packState);
    }
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final pack = home.pack;
    final city = pack.city();
    final areas = ref.watch(areaMemoryProvider).value ?? const {};
    // Areas picked in another pack (offline, the Vake one stands in) aren't
    // playable here, so Play asks for an area instead.
    final saved = switch (settings?.area) {
      DistrictsArea(:final ids)
          when !pack.districts().any((d) => ids.contains(d.id)) =>
        null,
      final area => area,
    };
    final picked = _picked;
    final area = picked == null ? saved : DistrictsArea({picked.id});
    final difficulty = settings?.lastDifficulty;
    final round = picked == null ? home.saved : null;
    final raions = [
      for (final d in pack.districts())
        if (d.isRaion) d,
    ];

    Future<void> open(String location) async {
      await context.push(location);
      if (mounted) refreshLearning(ref);
    }

    // Saves [area], then opens [location], once per tap: a double tap would
    // push two rounds. The guard ends with the push, not with the screen: a
    // round left with go never ends its push.
    Future<void> openWith(Area? area, String location) async {
      if (_saving) return;
      _saving = true;
      Future<void>? opened;
      try {
        if (area != null) {
          await ref.read(settingsDaoProvider).chooseArea(area, cityId: city.id);
        }
        if (mounted) opened = open(location);
      } finally {
        _saving = false;
      }
      await opened;
    }

    Future<void> play(Area area) =>
        openWith(area, difficulty == null ? Routes.difficulty : Routes.round);

    Future<void> changeDifficulty() => openWith(area, Routes.difficulty);

    final playCard = PlayCard(
      saved: round,
      area: area == null ? null : areaLabel(context, area, pack, settings),
      memory: _memoryOf(area, areas),
      pool: area == null || difficulty == null
          ? null
          : ref.watch(roundPoolProvider((area, difficulty))).value,
      difficulty: difficulty,
      playLabel: area == null || difficulty == null
          ? null
          : resumeLabel(context, pack, area, difficulty, settings),
      onPlay: () => area == null ? open(Routes.area) : play(area),
      onChangeArea: () =>
          open(picked == null ? Routes.area : Routes.areaFrom(picked.id)),
      onChangeDifficulty: changeDifficulty,
      onContinue: () => open(Routes.resume(home.saved!.round.id)),
      onNewRound: () => open(Routes.round),
    );

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) {
          final height = box.maxHeight;
          double share(double sheet) => (sheet / height).clamp(0.25, 0.9);
          final peek = share(_peekHeight);
          return Stack(
            children: [
              Positioned.fill(
                child: Semantics(
                  label: l10n.a11yExploreMap(cityName(context, city)),
                  child: ref.watch(exploreMapBuilderProvider)(
                    ExploreMap(
                      districts: [
                        for (final d in pack.districts())
                          (
                            district: d,
                            progress: districtFill(areas[d.id]),
                            name: districtName(d, settings),
                          ),
                      ],
                      playArea: area?.shapeIn(pack)?.boundary ?? const [],
                      bounds: city.bbox,
                      bottomInset: height * peek,
                      legend: const _MapKey(),
                      onTap: (at, zoom) => setState(
                        () => _picked = areaAt(pack.districts(), at, zoom),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: PlayTopBar(
                    city: city,
                    floating: true,
                    trailing: const StreakPillButton(),
                  ),
                ),
              ),
              DraggableScrollableSheet(
                initialChildSize: peek,
                minChildSize: peek,
                maxChildSize: max(peek, share(height - _openTop)),
                snap: true,
                builder: (context, scroll) => ClipRRect(
                  borderRadius: _sheetShape,
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: _sheetShape,
                      border: Border(
                        top: BorderSide(
                          color: c.lineBase,
                          width: PindoroStroke.base,
                        ),
                      ),
                    ),
                    child: ColoredBox(
                      color: c.surfaceBase,
                      child: CustomScrollView(
                        controller: scroll,
                        slivers: [
                          PinnedHeaderSliver(
                            child: ColoredBox(
                              color: c.surfaceBase,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  PindoroSpace.s4,
                                  PindoroSpace.s2,
                                  PindoroSpace.s4,
                                  PindoroSpace.s2,
                                ),
                                child: ContentColumn(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    spacing: PindoroSpace.s3,
                                    children: [
                                      const Center(child: SheetHandle()),
                                      playCard,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                              PindoroSpace.s4,
                              0,
                              PindoroSpace.s4,
                              PindoroSpace.s6,
                            ),
                            sliver: SliverList.list(
                              children: [
                                for (final card in [
                                  if (ref.watch(offlineVakeProvider))
                                    OfflineCard(
                                      city: cityName(context, city),
                                      onDownload: () => ref
                                          .read(offlineVakeProvider.notifier)
                                          .set(false),
                                    ),
                                  ...exploreSheet(
                                    context: context,
                                    home: home,
                                    areas: areas,
                                    raions: raions,
                                    settings: settings,
                                    difficulty: difficulty,
                                    onPlay: play,
                                    onOpen: open,
                                    onCoachClosed: () => ref
                                        .read(settingsDaoProvider)
                                        .markHomeCoachSeen(),
                                  ),
                                ])
                                  ContentColumn(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        top: PindoroSpace.s4,
                                      ),
                                      child: card,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The district fills' key, on a raised chip over the map.
class _MapKey extends StatelessWidget {
  const _MapKey();

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(PindoroRadius.md),
        border: Border.all(color: c.lineBase, width: PindoroStroke.hairline),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: PindoroSpace.s2,
          vertical: PindoroSpace.s1,
        ),
        child: DistrictLegend(dense: true),
      ),
    );
  }
}

/// City memory over an area's districts; null for a drawn area or one
/// without streets yet.
// ponytail: a part picked with its district counts twice; the area picker
// narrows such picks to the part, so it doesn't come up.
MemorySummary? _memoryOf(Area? area, Map<String, MemorySummary> areas) {
  if (area is! DistrictsArea) return null;
  final parts = [for (final id in area.ids) ?areas[id]];
  int sum(int Function(MemorySummary m) of) =>
      parts.fold(0, (n, m) => n + of(m));
  final total = sum((m) => m.total);
  if (total == 0) return null;
  return (
    memory: parts.fold(0.0, (n, m) => n + m.memory),
    total: total,
    counts: {
      for (final s in MemoryState.values) s: sum((m) => m.counts[s] ?? 0),
    },
  );
}
