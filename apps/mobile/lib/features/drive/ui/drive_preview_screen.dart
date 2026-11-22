import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_levels.dart';
import 'package:pindoro/features/drive/ui/plan_map.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/map/ui/widgets/tier_reveal.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

enum _Phase { play, list, recite }

/// The route preview (board V32-11, SPEC §16.23 items 121 and 129), parked only: the whole route
/// north-up, then, as the player steps through them (Back, Next), each key turn with its landmark
/// and the street it turns onto; then the key turns listed, Start, and an optional "Recite the
/// turns": the way tapped at each, right or wrong shown at once. Reciting reviews no card (the
/// turns were just shown); the preview and each recited turn go in the drive log.
class DrivePreviewScreen extends ConsumerStatefulWidget {
  const DrivePreviewScreen({super.key});

  @override
  ConsumerState<DrivePreviewScreen> createState() => _DrivePreviewScreenState();
}

class _DrivePreviewScreenState extends ConsumerState<DrivePreviewScreen> {
  _Phase _phase = _Phase.play;

  /// The key turn on show while stepping through (-1: the whole route), or being recited.
  int _at = -1;
  late final DateTime _opened = ref.read(clockProvider)();

  /// The way tapped at the recited turn; null until tapped.
  Turn? _said;

  String get _driveId => ref.read(driveControllerProvider.notifier).driveId;

  void _log(DriveEventKind kind, {String? itemKey, double? value}) => unawaited(
    ref
        .read(driveLogDaoProvider)
        .addEvent(
          driveId: _driveId,
          at: ref.read(clockProvider)(),
          kind: kind,
          itemKey: itemKey,
          value: value,
        ),
  );

  /// Key turn [at] of [turns] (-1: the whole route); past the last, the list.
  void _step(int at, int turns) =>
      at >= turns ? _toList() : setState(() => _at = max(-1, at));

  void _toList() {
    if (_phase == _Phase.play) {
      final watched = ref.read(clockProvider)().difference(_opened);
      _log(DriveEventKind.preview, value: watched.inSeconds.toDouble());
    }
    setState(() {
      _phase = _Phase.list;
      _at = -1;
    });
  }

  void _recite(NavDecision d, Turn said, Map<Turn, RoadEdge> exits) {
    _log(
      DriveEventKind.recite,
      itemKey: d.key,
      value: exits[said]?.id == d.exit.id ? 1 : 0,
    );
    setState(() => _said = said);
  }

  void _nextRecital(List<NavDecision> recitable) {
    setState(() {
      _said = null;
      if (_at + 1 < recitable.length) {
        _at++;
      } else {
        _phase = _Phase.list;
        _at = -1;
      }
    });
  }

  Future<void> _start() async {
    final l10n = context.l10n;
    await ref
        .read(driveControllerProvider.notifier)
        .start(
          title: l10n.driveNotificationTitle,
          text: l10n.driveNotificationText,
        );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final graph = ref.watch(drivingGraphProvider).value;
    final streets = ref.watch(cityStreetsProvider).value ?? const {};
    final setup = ref.watch(driveControllerProvider);
    if (setup is! DriveSetup || graph == null) return const Scaffold();
    final suggestion = setup.suggestion;
    final target = setup.target;
    if (suggestion == null || target == null) return const Scaffold();
    final plan = suggestion.plan;
    final keyTurns = [
      for (final d in plan.decisions)
        if (suggestion.keys.contains(d.key)) d,
    ];
    final route = plan.route;
    final start = setup.here ?? graph.at(route.junctions.first);
    final end = graph.at(target.junction);

    String? landmarkLine(NavDecision d) => switch (d.landmark) {
      final l? => l10n.navAt(landmarkName(l, settings)),
      null when d.signals => l10n.navAtLights,
      null => null,
    };
    String action(NavDecision d) => [
      decisionAction(l10n, decisionGlyph(d)),
      switch (d.street ?? streets[d.exit.streetId]) {
        final s? => streetName(s, settings),
        null => null,
      },
    ].nonNulls.join(' ');
    List<LatLng> around(NavDecision d) => [
      ...?d.approach?.lineFrom(d.approach!.other(d.junction)),
      ...d.exit.lineFrom(d.junction),
    ];
    Widget number(int i, {bool current = false}) =>
        TurnNumber(i + 1, onMap: true, current: current);
    final numbers = [
      for (final (i, d) in keyTurns.indexed)
        (graph.at(d.junction), number(i, current: i == _at)),
    ];
    final summary = [
      formatDistance(route.lengthM, l10n),
      l10n.driveAboutMin((plan.seconds / 60).ceil()),
      l10n.previewKeyTurns(keyTurns.length),
    ].join(' · ');

    switch (_phase) {
      case _Phase.play:
        final d = _at < 0 ? null : keyTurns[_at];
        return Scaffold(
          body: PlanMapLayout(
            semanticsLabel: l10n.a11yPreviewMap,
            route: route.lines,
            start: start,
            end: end,
            pins: numbers,
            frame: d == null ? null : around(d),
            bottom: BottomPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: PindoroSpace.s3,
                children: [
                  if (d == null) ...[
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.previewTitle,
                        style: PindoroType.titleLg.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      summary,
                      style: PindoroType.labelMd.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  ] else ...[
                    StepDots(
                      count: keyTurns.length,
                      current: _at,
                      line: l10n.previewKeyTurnOf(_at + 1, keyTurns.length),
                      semanticsLabel: l10n.a11yPreviewTurns,
                      semanticsValue: l10n.a11yStepOf(_at + 1, keyTurns.length),
                    ),
                    if (landmarkLine(d) case final line?)
                      Text(
                        line,
                        style: PindoroType.labelLg.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        action(d),
                        style: PindoroType.titleMd.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                  Row(
                    spacing: PindoroSpace.s3,
                    children: d == null
                        ? [
                            Expanded(
                              child: PindoroButton(
                                label: l10n.previewShowTurns,
                                onPressed: keyTurns.isEmpty
                                    ? null
                                    : () => _step(0, keyTurns.length),
                              ),
                            ),
                            Expanded(
                              child: PindoroButton(
                                label: l10n.previewSkip,
                                variant: PindoroButtonVariant.tertiary,
                                onPressed: _toList,
                              ),
                            ),
                          ]
                        : [
                            Expanded(
                              child: PindoroButton(
                                label: l10n.commonBack,
                                icon: PindoroGlyph.back,
                                variant: PindoroButtonVariant.secondary,
                                onPressed: () =>
                                    _step(_at - 1, keyTurns.length),
                              ),
                            ),
                            Expanded(
                              child: PindoroButton(
                                label: l10n.commonNext,
                                onPressed: () =>
                                    _step(_at + 1, keyTurns.length),
                              ),
                            ),
                          ],
                  ),
                ],
              ),
            ),
          ),
        );

      case _Phase.list:
        return Scaffold(
          body: PlanMapLayout(
            semanticsLabel: l10n.a11yPreviewMap,
            route: route.lines,
            start: start,
            end: end,
            pins: numbers,
            bottom: BottomPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: PindoroSpace.s3,
                children: [
                  SectionTitle(
                    l10n.previewKeyTurns(keyTurns.length),
                    meta: summary,
                  ),
                  if (keyTurns.isNotEmpty)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.35,
                      ),
                      child: SingleChildScrollView(
                        child: ListGroup(
                          children: [
                            for (final (i, d) in keyTurns.indexed)
                              ListRow(
                                leading: SizedBox.square(
                                  dimension: 32,
                                  child: Center(child: TurnNumber(i + 1)),
                                ),
                                title: landmarkLine(d) ?? action(d),
                                subtitle: landmarkLine(d) == null
                                    ? null
                                    : action(d),
                                semanticsLabel: l10n.a11yKeyTurn(
                                  i + 1,
                                  keyTurns.length,
                                  [?landmarkLine(d), action(d)].join(', '),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (keyTurns.any((d) => _exits(graph, d) != null))
                    PindoroButton(
                      label: l10n.previewRecite,
                      variant: PindoroButtonVariant.secondary,
                      onPressed: () => setState(() {
                        _phase = _Phase.recite;
                        _at = 0;
                        _said = null;
                      }),
                    ),
                  PindoroButton(
                    label: l10n.driveStart,
                    icon: PindoroGlyph.car,
                    onPressed: () => unawaited(_start()),
                  ),
                ],
              ),
            ),
          ),
        );

      case _Phase.recite:
        final recitable = [
          for (final d in keyTurns)
            if (_exits(graph, d) != null) d,
        ];
        final d = recitable[_at];
        final exits = _exits(graph, d)!;
        final said = _said;
        final right = said != null && exits[said]?.id == d.exit.id;
        final index = keyTurns.indexOf(d);
        final upTo = [
          for (var k = 0; k < d.index && k < route.edges.length; k++)
            route.edges[k].lineFrom(route.junctions[k]),
        ];
        final dots = StepDots(
          count: recitable.length,
          current: _at,
          line: l10n.previewReciteOf(_at + 1, recitable.length),
          semanticsLabel: l10n.a11yPreviewTurns,
          semanticsValue: l10n.a11yStepOf(_at + 1, recitable.length),
        );
        final tier = right ? Tier.great : Tier.miss;
        return Scaffold(
          body: PlanMapLayout(
            semanticsLabel: l10n.a11yPreviewMap,
            route: said == null ? upTo : route.lines,
            start: start,
            end: said == null ? null : end,
            pins: [(graph.at(d.junction), number(index, current: true))],
            frame: around(d),
            bottom: said == null
                ? BottomPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: PindoroSpace.s3,
                      children: [
                        dots,
                        Semantics(
                          header: true,
                          child: Text(
                            l10n.previewWhichWay(
                              landmarkLine(d) ?? l10n.previewKeyTurn(index + 1),
                            ),
                            style: PindoroType.titleMd.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: PindoroSpace.s4,
                          runSpacing: PindoroSpace.s3,
                          children: [
                            for (final turn in Turn.values)
                              if (exits.containsKey(turn))
                                ExitButton(
                                  direction: ExitDirection.values.byName(
                                    turn.name,
                                  ),
                                  selected: false,
                                  semanticsLabel: exitLabel(l10n, turn),
                                  onTap: () => _recite(d, turn, exits),
                                ),
                          ],
                        ),
                      ],
                    ),
                  )
                : RevealDock(
                    revealKey: (d.junction, said),
                    sheet: TierRevealSheet(
                      tier: tier,
                      label: tierLabel(l10n, tier),
                      sentence: right
                          ? l10n.previewRight(action(d))
                          : l10n.previewWrong(action(d)),
                      chips: [dots],
                      action: l10n.commonNext,
                      onNext: () async => _nextRecital(recitable),
                    ),
                  ),
          ),
        );
    }
  }
}

/// [d]'s ways on by direction, for the exit buttons; null when two share one or it has no way
/// in.
Map<Turn, RoadEdge>? _exits(RoadGraph graph, NavDecision d) =>
    switch (d.approach) {
      final a? => exitsByTurn(graph, d.junction, a),
      null => null,
    };
