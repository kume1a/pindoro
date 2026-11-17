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
import 'package:pindoro/features/home/ui/widgets/saved_card.dart';
import 'package:pindoro/features/learning/data/progress.dart';
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

/// Explore (canvas V31-20): the city map leads, its districts filled by how
/// much of each is in memory and the play area outlined; the sheet under it
/// lists ways in; Play (or Continue round) is pinned in the thumb zone. Right
/// after a round ([summary]) City memory counts up from where it was, once.
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

  /// Where the sheet rests: its top this far down the screen when it peeks
  /// and when it is pulled up (canvas V31-90 Explore layout).
  static const double _peekTop = 404;
  static const double _openTop = 232;

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
    final area = switch (settings?.area) {
      DistrictsArea(:final ids)
          when !pack.districts().any((d) => ids.contains(d.id)) =>
        null,
      final area => area,
    };
    final difficulty = settings?.lastDifficulty;
    final saved = home.saved;
    final raions = [
      for (final d in pack.districts())
        if (d.isRaion) d,
    ];

    Future<void> open(String location) async {
      await context.push(location);
      refreshLearning(ref);
    }

    Future<void> play(Area area) async {
      await ref.read(settingsDaoProvider).chooseArea(area, cityId: city.id);
      await open(difficulty == null ? Routes.difficulty : Routes.round);
    }

    final resumes = area == null || difficulty == null
        ? null
        : resumeLabel(context, pack, area, difficulty, settings);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final height = box.maxHeight;
                double share(double top) =>
                    ((height - top) / height).clamp(0.25, 0.9);
                final peek = share(_peekTop);
                final covered = height * peek;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Semantics(
                        label: l10n.a11yExploreMap(
                          context.localName(ka: city.nameKa, en: city.nameEn),
                        ),
                        child: ref.watch(exploreMapBuilderProvider)(
                          ExploreMap(
                            districts: [
                              for (final d in raions)
                                (
                                  district: d,
                                  progress: _fill(areas[d.id]),
                                  name: districtName(d, settings),
                                ),
                            ],
                            playArea: area?.shapeIn(pack)?.boundary ?? const [],
                            bounds: city.bbox,
                            bottomInset: covered,
                            onTap: (at) {
                              final hit = raions.where(
                                (d) => boundaryContains(d.boundary, at),
                              );
                              if (hit.isNotEmpty) {
                                open(Routes.areaFrom(hit.first.id));
                              }
                            },
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
                      maxChildSize: max(peek, share(_openTop)),
                      snap: true,
                      builder: (context, scroll) => DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.surfaceBase,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(PindoroRadius.r2xl),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: c.lineBase,
                              width: PindoroStroke.base,
                            ),
                          ),
                        ),
                        child: ListView(
                          controller: scroll,
                          padding: const EdgeInsets.fromLTRB(
                            PindoroSpace.s4,
                            PindoroSpace.s2,
                            PindoroSpace.s4,
                            PindoroSpace.s4,
                          ),
                          children: [
                            const Center(child: SheetHandle()),
                            for (final card in [
                              if (ref.watch(offlineVakeProvider))
                                OfflineCard(
                                  city: context.localName(
                                    ka: city.nameKa,
                                    en: city.nameEn,
                                  ),
                                  onDownload: () => ref
                                      .read(offlineVakeProvider.notifier)
                                      .set(false),
                                ),
                              if (saved != null) SavedCard(saved: saved),
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
                    ),
                  ],
                );
              },
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
                    style: PindoroType.labelMd.copyWith(color: c.textSecondary),
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
                    icon: PindoroGlyph.map,
                    hero: true,
                    onPressed: () => open(Routes.area),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A district's fill step for its City memory (District fills).
DistrictProgress _fill(MemorySummary? m) => m == null || m.total == 0
    ? DistrictProgress.notStarted
    : DistrictProgress.of(
        m.memory / m.total,
        mastered: m.counts[MemoryState.mastered] == m.total,
      );
