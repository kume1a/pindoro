import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/ui/junction_name.dart';
import 'package:pindoro/features/learning/ui/landmark_glyph.dart';
import 'package:pindoro/features/map/ui/pin_drop_view.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro/features/map/ui/widgets/geo_anchors.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/widgets/scene_view.dart';
import 'package:pindoro/features/session/ui/widgets/task_scaffold.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Metres of each road the junction map draws out from the junction.
const double _armM = 160;

/// A route card (RouteItemScreen `junction`, `gateway`, `bridge`,
/// `landmarkQuiz`, and the typed connection): its question, the answer
/// controls, then the result sheet.
class RouteView extends ConsumerStatefulWidget {
  const RouteView({
    super.key,
    required this.play,
    required this.topBar,
    required this.onChoose,
    required this.onPin,
    required this.onAnswer,
    required this.onNext,
    this.chip,
  });

  final SessionPlaying play;
  final Widget topBar;
  final ValueChanged<Object> onChoose;
  final ValueChanged<LatLng> onPin;
  final ValueChanged<String> onAnswer;
  final Future<void> Function() onNext;

  /// The result's next-review chip.
  final Widget? chip;

  @override
  ConsumerState<RouteView> createState() => _RouteViewState();
}

class _RouteViewState extends ConsumerState<RouteView> {
  final _field = TextEditingController();
  MapProjection? _projection;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _answer() => widget.onAnswer(_field.text);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final pack = ref.watch(packRepositoryProvider).value;
    final play = widget.play;
    final task = play.task as RouteTask;
    final graph = pack?.roadGraph();
    String placeName(String? chunk) =>
        switch (pack?.districts().where((d) => d.id == chunk).firstOrNull) {
          final d? => districtName(d, settings),
          null => l10n.routeCityCentre,
        };
    String name(NamedStreet? s) => s == null ? '' : streetName(s, settings);
    final streets = ref.watch(cityStreetsProvider).value ?? const {};
    String junctionAt(int junction) => graph == null
        ? ''
        : junctionName(graph, junction, streets, settings) ?? '';
    final tier = task.result;
    final field = SearchField(
      controller: _field,
      placeholder: l10n.sessionCrossingsHint,
      clearLabel: l10n.commonClear,
      glyph: PindoroGlyph.signpost,
      autocorrect: false,
      textInputAction: TextInputAction.done,
      onChanged: (_) => setState(() {}),
    );
    Widget confirm(String label, {required bool ready}) =>
        PindoroButton(label: label, onPressed: ready ? _answer : null);
    Widget result(String sentence, {String? label}) => TaskResult(
      resultKey: play.index,
      tier: tier!,
      label: label,
      chip: widget.chip,
      sentence: sentence,
      onNext: widget.onNext,
    );
    final map = ref.watch(pindoroMapBuilderProvider);
    final mapTop = MediaQuery.paddingOf(context).top + 180;

    switch (task.question) {
      case final TurnQuestion q:
        final graphOk = graph != null;
        final chosen = task.choice as Turn?;
        final right = tier == null ? null : chosen == q.correct;
        final exitWord = turnWord(l10n, q.correct);
        return TaskScaffold(
          topBar: widget.topBar,
          header: StreetPlate(
            name(q.approachStreet),
            key: ValueKey((play.index, 'turn')),
            prompt: l10n.routeTurnOn,
            promptGlyph: PindoroGlyph.route,
            compact: tier != null,
            subline: [
              if (q.destChunk != null)
                l10n.routeHeadingTo(placeName(q.destChunk)),
              switch (q.landmark) {
                final l? => l10n.routeTurnAtLandmark(l.name),
                null => l10n.routeTurnAtJunction,
              },
            ].join(' · '),
          ),
          body: !graphOk
              ? null
              : Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 140),
                    child: JunctionMap(
                      geometry: junctionGeometry(graph, q, ref),
                      state: switch (right) {
                        null => JunctionState.choosing,
                        true => JunctionState.right,
                        false => JunctionState.wrong,
                      },
                      chosen: chosen == null ? null : _direction(chosen),
                      correct: tier == null ? null : _direction(q.correct),
                      onChoose: (d) =>
                          widget.onChoose(Turn.values.byName(d.name)),
                      exitLabel: (d) =>
                          turnWord(l10n, Turn.values.byName(d.name)),
                      semanticsLabel: l10n.a11yJunctionMap,
                      carLabel: l10n.a11yJunctionYou,
                      animate: !MediaQuery.disableAnimationsOf(context),
                      landmark: switch (q.landmark) {
                        final l? => LandmarkBadge(
                          name: l.name,
                          glyph: landmarkGlyph(l.kind),
                          semanticsLabel: l10n.a11yLandmark(l.name),
                        ),
                        null => null,
                      },
                    ),
                  ),
                ),
          controls: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s2,
            children: [
              field,
              confirm(l10n.commonConfirm, ready: chosen != null),
            ],
          ),
          result: tier == null
              ? null
              : result(
                  right!
                      ? l10n.routeTurnRight(exitWord, name(q.exitStreet))
                      : l10n.routeTurnWrong(exitWord, name(q.exitStreet)),
                  label: right ? l10n.routeRight : l10n.routeWrong,
                ),
        );

      case final GatewayQuestion q:
        final chunk = placeName(q.chunk);
        return TaskScaffold(
          topBar: widget.topBar,
          map: map(
            PindoroMap(
              area: play.area,
              frame: play.frame,
              pin: play.pin,
              onTap: tier == null ? widget.onPin : null,
              truth: tier == null ? null : q.exitStreet?.geometry,
              topInset: mapTop,
              bottomInset: PinDropView.confirmInset(context) + 64,
            ),
          ),
          header: StreetPlate(
            chunk,
            key: ValueKey((play.index, 'gateway')),
            prompt: q.out ? l10n.routeGatewayOut : l10n.routeGatewayIn,
            promptGlyph: PindoroGlyph.neighbourhood,
            compact: tier != null,
            subline: q.out ? l10n.routeGatewayOutAsk : l10n.routeGatewayInAsk,
          ),
          controls: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s2,
            children: [
              field,
              confirm(l10n.commonConfirm, ready: play.pin != null),
            ],
          ),
          result: tier == null
              ? null
              : result(
                  l10n.routeGatewayResult(
                    name(q.exitStreet),
                    formatDistance(distanceBetween(play.pin!, q.at), l10n),
                  ),
                ),
        );

      case final BridgeQuestion q:
        final chosen = task.choice as Bridge?;
        final number = chosen == null ? 0 : q.options.indexOf(chosen) + 1;
        return TaskScaffold(
          topBar: widget.topBar,
          map: map(
            PindoroMap(
              area: play.area,
              frame: play.frame,
              truth: tier == null ? null : q.bridge.geometry,
              onCamera: (p) => setState(() => _projection = p),
              topInset: mapTop,
              bottomInset: PinDropView.confirmInset(context),
            ),
          ),
          overlays: [
            Positioned.fill(
              child: GeoAnchors(
                projection: _projection,
                anchors: [
                  for (final (i, b) in q.options.indexed)
                    (
                      b.midpoint,
                      Semantics(
                        button: true,
                        selected: b == chosen,
                        label: l10n.a11yBridgeOption(i + 1),
                        child: GestureDetector(
                          onTap: tier == null ? () => widget.onChoose(b) : null,
                          child: MapTip('${i + 1}', selected: b == chosen),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          header: StreetPlate(
            name(q.approachStreet),
            key: ValueKey((play.index, 'bridge')),
            prompt: l10n.routeBridgeFrom,
            promptGlyph: PindoroGlyph.route,
            compact: tier != null,
            subline: l10n.routeBridgeAsk(placeName(q.destChunk)),
          ),
          controls: PindoroButton(
            label: chosen == null
                ? l10n.commonConfirm
                : l10n.routeBridgeConfirm(number),
            onPressed: chosen == null ? null : _answer,
          ),
          result: tier == null
              ? null
              : result(l10n.routeBridgeResult(q.bridge.nameKa)),
        );

      case final ConnectionQuestion q:
        return TaskScaffold(
          topBar: widget.topBar,
          header: AskCard(
            title: l10n.routeConnectionAsk(name(q.street), name(q.from)),
            note: l10n.routeConnectionNote,
          ),
          controls: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s2,
            children: [
              field,
              confirm(l10n.commonCheck, ready: _field.text.trim().isNotEmpty),
            ],
          ),
          result: tier == null
              ? null
              : result(l10n.routeConnectionResult(name(q.street), name(q.to))),
        );

      case SceneQuestion():
        return SceneView(
          play: play,
          topBar: widget.topBar,
          onChoose: widget.onChoose,
          onPin: widget.onPin,
          onAnswer: widget.onAnswer,
          onNext: widget.onNext,
          chip: widget.chip,
        );

      case final LandmarkQuestion q:
        final landmark = q.landmark;
        final subline = landmark.personal
            ? l10n.routeLandmarkMine
            : landmarkKindName(l10n, landmark.kind);
        return TaskScaffold(
          topBar: widget.topBar,
          map: q.n == 1
              ? map(
                  PindoroMap(
                    area: play.area,
                    pin: play.pin,
                    onTap: tier == null ? widget.onPin : null,
                    topInset: mapTop,
                    bottomInset: PinDropView.confirmInset(context),
                  ),
                )
              : null,
          header: q.n == 1
              ? StreetPlate(
                  landmark.name,
                  key: ValueKey((play.index, 'landmark')),
                  prompt: l10n.routeLandmarkWhere,
                  promptGlyph: landmarkGlyph(landmark.kind),
                  compact: tier != null,
                  subline: subline,
                )
              : AskCard(
                  title: q.n == 2
                      ? l10n.routeLandmarkJunction(landmark.name)
                      : l10n.routeLandmarkName(junctionAt(q.junction ?? -1)),
                  note: subline,
                ),
          controls: q.n == 1
              ? confirm(l10n.commonConfirm, ready: play.pin != null)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: PindoroSpace.s2,
                  children: [
                    Wrap(
                      spacing: PindoroSpace.s2,
                      runSpacing: PindoroSpace.s1,
                      alignment: WrapAlignment.center,
                      children: [
                        if (q.n == 2)
                          for (final j in q.junctions)
                            PindoroChip(
                              label: junctionAt(j),
                              selected: task.choice == j,
                              onPressed: () => widget.onChoose(j),
                            )
                        else
                          for (final n in q.names)
                            PindoroChip(
                              label: n,
                              selected: task.choice == n,
                              onPressed: () => widget.onChoose(n),
                            ),
                      ],
                    ),
                    confirm(l10n.commonConfirm, ready: task.choice != null),
                  ],
                ),
          result: tier == null
              ? null
              : result(
                  l10n.routeLandmarkResult(
                    landmark.name,
                    junctionAt(q.junction ?? -1),
                  ),
                ),
        );
    }
  }
}

ExitDirection _direction(Turn turn) => ExitDirection.values.byName(turn.name);

/// The exit button's word for [turn].
String turnWord(AppLocalizations l10n, Turn turn) => switch (turn) {
  Turn.left => l10n.routeExitLeft,
  Turn.straight => l10n.routeExitStraight,
  Turn.right => l10n.routeExitRight,
  Turn.uTurn => l10n.routeExitUTurn,
};

/// The junction map's drawing (Junction map): every road at the junction
/// out to [_armM], the approach and the legal exits, in metres east and north
/// of the junction.
JunctionGeometry junctionGeometry(
  RoadGraph graph,
  TurnQuestion q,
  WidgetRef ref,
) {
  final at = graph.at(q.junction);
  final local = LocalProjection(at);
  List<Offset> out(RoadEdge e) {
    final points = <Offset>[];
    var walked = 0.0;
    LatLng? last;
    for (final p in e.lineFrom(q.junction)) {
      if (last != null) walked += distanceBetween(last, p);
      final (x, y) = local.project(p);
      points.add(Offset(x, y));
      if (walked >= _armM) break;
      last = p;
    }
    return points;
  }

  final streets = ref.read(cityStreetsProvider).value ?? const {};
  JunctionRoadClass classOf(RoadEdge e) =>
      switch (streets[e.streetId]?.parts.first.roadClass) {
        'motorway' || 'trunk' || 'primary' => JunctionRoadClass.main,
        'secondary' || 'tertiary' => JunctionRoadClass.secondary,
        null => JunctionRoadClass.local,
        _ => JunctionRoadClass.minor,
      };
  final landmark = q.landmark;
  return JunctionGeometry(
    roads: [
      for (final e in graph.edgesAt(q.junction))
        (line: out(e), roadClass: classOf(e)),
    ],
    approach: out(q.approach).reversed.toList(),
    exits: {
      for (final MapEntry(key: turn, value: e) in q.exits.entries)
        _direction(turn): out(e),
    },
    landmarkAt: landmark == null
        ? null
        : switch (local.project(landmark.at)) {
            (final x, final y) => Offset(x, y),
          },
  );
}
