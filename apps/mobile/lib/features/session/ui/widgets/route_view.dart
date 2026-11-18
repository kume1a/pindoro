import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/google_maps.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/ui/junction_name.dart';
import 'package:pindoro/features/learning/ui/landmark_glyph.dart';
import 'package:pindoro/features/map/data/map_style.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro/features/map/ui/widgets/geo_anchors.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/session/ui/session_controller.dart';
import 'package:pindoro/features/session/ui/widgets/place_intro.dart';
import 'package:pindoro/features/session/ui/widgets/task_scaffold.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

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
    required this.onHidePlace,
    this.chip,
  });

  final SessionPlaying play;

  final Widget topBar;
  final ValueChanged<Object> onChoose;
  final ValueChanged<LatLng> onPin;
  final ValueChanged<String> onAnswer;
  final Future<void> Function() onNext;

  /// "Can't find it?" on a pack place's result.
  final VoidCallback onHidePlace;

  /// The result's next-review chip.
  final Widget? chip;

  @override
  ConsumerState<RouteView> createState() => _RouteViewState();
}

class _RouteViewState extends ConsumerState<RouteView> {
  final _field = TextEditingController();
  final _projection = ValueNotifier<MapProjection?>(null);

  @override
  void dispose() {
    _field.dispose();
    _projection.dispose();
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
    String chunkName(String? chunk) =>
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
    Widget searchField(String placeholder) => SearchField(
      controller: _field,
      placeholder: placeholder,
      clearLabel: l10n.commonClear,
      glyph: PindoroGlyph.signpost,
      autocorrect: false,
      textInputAction: TextInputAction.done,
      onChanged: (_) => setState(() {}),
    );
    final field = searchField(l10n.sessionCrossingsHint);
    Widget confirm(String label, {required bool ready}) =>
        PindoroButton(label: label, onPressed: ready ? _answer : null);
    TaskResult result(
      String sentence, {
      String? label,
      StreetViewSpot? streetView,
      List<Widget> chips = const [],
    }) => TaskResult(
      resultKey: play.index,
      tier: tier!,
      label: label,
      streetView: streetView,
      chips: chips,
      chip: widget.chip,
      sentence: sentence,
      onNext: widget.onNext,
    );
    final map = ref.watch(pindoroMapBuilderProvider);

    switch (task.question) {
      case final TurnQuestion q:
        final chosen = task.choice as Turn?;
        final right = tier == null ? null : chosen == q.correct;
        final exitWord = _turnWord(l10n, q.correct);
        final scene = graph == null ? null : _turnScene(graph, q);
        final landmark = q.landmark;
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
                l10n.routeHeadingTo(chunkName(q.destChunk)),
              switch (landmark) {
                final l? => l10n.routeTurnAtLandmark(landmarkName(l, settings)),
                null => l10n.routeTurnAtJunction,
              },
            ].join('\n'),
          ),
          map: scene == null
              ? null
              : (insets) => map(
                  PindoroMap(
                    area: play.area,
                    bearing: scene.bearing,
                    frame: scene.frame,
                    truth: tier == null
                        ? null
                        : [scene.approach, scene.exits[q.correct]!],
                    hit: switch ((tier, chosen)) {
                      (null, _) => [scene.approach],
                      (_, final c?) when c != q.correct => [scene.exits[c]!],
                      _ => null,
                    },
                    // Asking: places, but none named after the way on.
                    names: tier == null
                        ? MapNames(
                            places: true,
                            placesNot: switch (q.exitStreet) {
                              final s? => nameStems(s),
                              null => const {},
                            },
                          )
                        : MapNames.all,
                    showControls: false,
                    onCamera: (p) => _projection.value = p,
                    topInset: insets.top,
                    bottomInset: insets.bottom,
                  ),
                ),
          overlays: [
            if (scene != null)
              Positioned.fill(
                child: GeoAnchors(
                  projection: _projection,
                  anchors: [
                    (
                      scene.car,
                      CarMarker(semanticsLabel: l10n.a11yJunctionYou),
                    ),
                    if (landmark != null)
                      (
                        landmark.at,
                        LandmarkBadge(
                          name: landmarkName(landmark, settings),
                          glyph: landmarkGlyph(landmark.kind),
                          semanticsLabel: l10n.a11yLandmark(
                            landmarkName(landmark, settings),
                          ),
                        ),
                      ),
                    if (tier == null)
                      for (final MapEntry(key: turn, value: at)
                          in scene.buttons.entries)
                        (
                          at,
                          ExitButton(
                            direction: _direction(turn),
                            selected: chosen == turn,
                            onTap: () => widget.onChoose(turn),
                            semanticsLabel: _turnWord(l10n, turn),
                          ),
                        ),
                  ],
                ),
              ),
          ],
          controls: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s2,
            children: [
              searchField(l10n.routeThenOn),
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
        final chunk = chunkName(q.chunk);
        return TaskScaffold(
          topBar: widget.topBar,
          map: (insets) => map(
            PindoroMap(
              area: play.area,
              frame: play.frame,
              pin: play.pin,
              onTap: tier == null ? widget.onPin : null,
              truth: tier == null ? null : q.exitStreet?.geometry,
              topInset: insets.top,
              bottomInset: insets.bottom,
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
          map: (insets) => map(
            PindoroMap(
              area: play.area,
              frame: play.frame,
              truth: tier == null ? null : q.bridge.geometry,
              onCamera: (p) => _projection.value = p,
              topInset: insets.top,
              bottomInset: insets.bottom,
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
            subline: l10n.routeBridgeAsk(chunkName(q.destChunk)),
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

      case final LandmarkQuestion q:
        final landmark = q.landmark;
        final shown = placeName(l10n, q, settings);
        final subline = landmark.personal
            ? l10n.routeLandmarkMine
            : landmarkKindName(l10n, landmark.kind);
        final pin = play.pin;
        final revealed = tier != null;
        final miss = pin == null ? null : q.distanceFrom(pin);
        final junction = junctionAt(q.junction ?? -1);
        return TaskScaffold(
          topBar: widget.topBar,
          map: q.n == 1
              ? (insets) => map(
                  PindoroMap(
                    area: play.area,
                    pin: pin,
                    onTap: revealed ? null : widget.onPin,
                    truthPoint: revealed ? landmark.at : null,
                    truth: revealed ? q.outlineLines : null,
                    measure: switch (miss) {
                      final m? when revealed && m.distanceM > 0 => (
                        from: pin!,
                        to: m.to,
                        label: formatDistance(m.distanceM, l10n),
                      ),
                      _ => null,
                    },
                    // Asking: known streets only, never the place's own.
                    names: revealed
                        ? MapNames.all
                        : MapNames(streets: play.knownNames),
                    topInset: insets.top,
                    bottomInset: insets.bottom,
                  ),
                )
              : null,
          header: q.n == 1
              ? StreetPlate(
                  shown,
                  key: ValueKey((play.index, 'landmark')),
                  prompt: l10n.routeLandmarkWhere,
                  promptGlyph: landmarkGlyph(landmark.kind),
                  compact: tier != null,
                  subline: subline,
                )
              : AskCard(
                  title: q.n == 2
                      ? l10n.routeLandmarkJunction(shown)
                      : l10n.routeLandmarkName(junction),
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
                          for (final l in q.places)
                            PindoroChip(
                              label: landmarkName(l, settings),
                              selected: task.choice == l.name,
                              onPressed: () => widget.onChoose(l.name),
                            ),
                      ],
                    ),
                    confirm(l10n.commonConfirm, ready: task.choice != null),
                  ],
                ),
          result: tier == null
              ? null
              : result(
                  junction.isEmpty
                      ? l10n.routeLandmarkResultOn(shown, name(play.street))
                      : l10n.routeLandmarkResult(shown, junction),
                  streetView: placeSpot(play.street, landmark.at),
                  chips: [
                    if (!landmark.personal)
                      CantFindItChip(name: shown, onHide: widget.onHidePlace),
                  ],
                ),
        );
    }
  }
}

ExitDirection _direction(Turn turn) => ExitDirection.values.byName(turn.name);

String _turnWord(AppLocalizations l10n, Turn turn) => switch (turn) {
  Turn.left => l10n.routeExitLeft,
  Turn.straight => l10n.routeExitStraight,
  Turn.right => l10n.routeExitRight,
  Turn.uTurn => l10n.routeExitUTurn,
};

/// A turn card on the real map, driving up the screen: the [approach] into
/// the junction and each exit's road out of it (ends at the junction), where
/// each exit's button and the car sit, and what the camera frames.
typedef _TurnScene = ({
  double bearing,
  List<LatLng> approach,
  Map<Turn, List<LatLng>> exits,
  Map<Turn, LatLng> buttons,
  LatLng car,
  List<LatLng> frame,
});

/// Metres of road drawn from the junction; buttons and the car sit
/// [_markM] out along each road's first stretch (a short edge still puts
/// its button clear of the junction).
const double _roadM = 90;
const double _markM = 50;

/// How far along a road its heading is read.
const double _headingM = 20;

_TurnScene _turnScene(RoadGraph graph, TurnQuestion q) {
  final at = graph.at(q.junction);
  final local = LocalProjection(at);
  List<LatLng> road(RoadEdge e, double metres) =>
      clipToCircle([e.lineFrom(q.junction)], at, metres).first;
  LatLng out(RoadEdge e) {
    final (x, y) = local.project(road(e, _headingM).last);
    final length = math.max(math.sqrt(x * x + y * y), 1);
    return local.unproject((x / length * _markM, y / length * _markM));
  }

  final car = out(q.approach);
  final buttons = {for (final e in q.exits.entries) e.key: out(e.value)};
  return (
    // The way the driver faces: from the approach towards the junction.
    bearing: bearingDegrees(road(q.approach, _headingM).last, at),
    approach: road(q.approach, _roadM).reversed.toList(),
    exits: {for (final e in q.exits.entries) e.key: road(e.value, _roadM)},
    buttons: buttons,
    car: car,
    frame: [at, car, ...buttons.values],
  );
}
