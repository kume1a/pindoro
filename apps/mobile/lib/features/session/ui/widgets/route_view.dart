import 'dart:async';

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
import 'package:pindoro/features/session/ui/widgets/cant_find_it_chip.dart';
import 'package:pindoro/features/session/ui/widgets/task_scaffold.dart';
import 'package:pindoro/features/session/ui/widgets/turn_scene.dart';
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
    required this.onDontKnow,
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

  /// "I don't know": the step graded as a miss, its answer shown.
  final VoidCallback onDontKnow;

  /// The result's next-review chip.
  final Widget? chip;

  @override
  ConsumerState<RouteView> createState() => _RouteViewState();
}

class _RouteViewState extends ConsumerState<RouteView>
    with MapProjectionHost<RouteView> {
  final _field = TextEditingController();
  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _answer() => widget.onAnswer(_field.text);

  /// The tray's choice confirmed, shown for [answerResultDelay] before it is
  /// graded.
  int? _confirmed;

  @override
  void didUpdateWidget(RouteView old) {
    super.didUpdateWidget(old);
    // Route cards in a row share this state: a new card starts blank.
    if (old.play.index != widget.play.index) {
      _confirmed = null;
      _field.clear();
    }
  }

  Future<void> _confirm(int i, Object choice) async {
    setState(() => _confirmed = i);
    widget.onChoose(choice);
    await Future<void>.delayed(answerResultDelay);
    if (mounted) _answer();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final pack = ref.watch(packRepositoryProvider).value;
    final play = widget.play;
    final task = play.task as RouteTask;
    final graph = pack?.roadGraph();
    String chunkName(String? chunk) => switch (pack?.district(chunk)) {
      final d? => districtName(d, settings),
      null => l10n.routeCityCentre,
    };
    // A way with no name is "a link road", never a blank in the sentence.
    String name(NamedStreet? s) =>
        s == null ? l10n.debriefLinkRoad : streetName(s, settings);
    final streets = ref.watch(cityStreetsProvider).value ?? const {};
    String junctionAt(int junction) => graph == null
        ? ''
        : junctionName(graph, junction, streets, settings) ?? '';
    final tier = task.result;
    Widget searchField(String placeholder, {bool submits = false}) =>
        SearchField(
          controller: _field,
          placeholder: placeholder,
          clearLabel: l10n.commonClear,
          glyph: PindoroGlyph.signpost,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          // The typed answer alone: Enter checks it, as Check does.
          onSubmitted: submits
              ? (text) {
                  if (text.trim().isNotEmpty) _answer();
                }
              : null,
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
        final exitWord = exitLabel(l10n, q.correct);
        final scene = graph == null ? null : turnScene(graph, q);
        final landmark = q.landmark;
        return TaskScaffold(
          onDontKnow: widget.onDontKnow,
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
                        ? MapNames.asking(q.exitStreet)
                        : MapNames.all,
                    showControls: false,
                    onCamera: onCamera,
                    topInset: insets.top,
                    bottomInset: insets.bottom,
                  ),
                ),
          overlays: [
            if (scene != null)
              Positioned.fill(
                child: GeoAnchors(
                  projection: projection,
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
                            semanticsLabel: exitLabel(l10n, turn),
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
          onDontKnow: widget.onDontKnow,
          topBar: widget.topBar,
          map: (insets) => map(
            PindoroMap(
              area: play.area,
              frame: play.frame,
              pin: play.pin,
              onTap: tier == null ? widget.onPin : null,
              truth: tier == null ? null : q.exitStreet?.geometry,
              // Asking: places, but none named after the way out.
              names: tier == null
                  ? MapNames.asking(q.exitStreet)
                  : MapNames.all,
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
              : result(switch (play.pin) {
                  final pin? => l10n.routeGatewayResult(
                    name(q.exitStreet),
                    formatDistance(distanceBetween(pin, q.at), l10n),
                  ),
                  null => l10n.routeGatewayResultHere(name(q.exitStreet)),
                }),
        );

      case final BridgeQuestion q:
        final chosen = task.choice as Bridge?;
        final number = chosen == null ? 0 : q.options.indexOf(chosen) + 1;
        return TaskScaffold(
          onDontKnow: widget.onDontKnow,
          topBar: widget.topBar,
          map: (insets) => map(
            PindoroMap(
              area: play.area,
              frame: play.frame,
              truth: tier == null ? null : q.bridge.geometry,
              names: tier == null ? const MapNames(places: true) : MapNames.all,
              onCamera: onCamera,
              topInset: insets.top,
              bottomInset: insets.bottom,
            ),
          ),
          overlays: [
            Positioned.fill(
              child: GeoAnchors(
                projection: projection,
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
          onDontKnow: widget.onDontKnow,
          topBar: widget.topBar,
          header: AskCard(
            title: l10n.routeConnectionAsk(name(q.street), name(q.from)),
            note: l10n.routeConnectionNote,
          ),
          controls: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s2,
            children: [
              searchField(l10n.sessionCrossingsHint, submits: true),
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
          onDontKnow: widget.onDontKnow,
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
              : null,
          tray: q.n == 1
              ? null
              : () {
                  final choices = <Object>[
                    if (q.n == 2)
                      ...q.junctions
                    else
                      ...q.places.map((l) => l.name),
                  ];
                  final confirmed = _confirmed;
                  return AnswerTray(
                    key: ValueKey((play.index, 'tray')),
                    question: q.n == 2
                        ? l10n.answerPickJunction
                        : l10n.answerPickPlace,
                    meta: q.n == 2
                        ? l10n.answerJunctions(choices.length)
                        : l10n.answerPlaces(choices.length),
                    choices: [
                      if (q.n == 2)
                        for (final j in q.junctions)
                          (label: junctionAt(j), sublabel: null)
                      else
                        for (final l in q.places)
                          (label: landmarkName(l, settings), sublabel: null),
                    ],
                    confirmLabel: l10n.commonConfirm,
                    confirmHint: l10n.answerPickFirst,
                    skip: (
                      label: l10n.commonDontKnow,
                      onSkip: widget.onDontKnow,
                    ),
                    // Not known: only the right one shows.
                    result: confirmed == null && tier == null
                        ? null
                        : (
                            picked: confirmed ?? -1,
                            right: q.n == 2
                                ? q.junctions.indexOf(q.junction ?? -1)
                                : q.places.indexWhere(
                                    (l) => l.name == landmark.name,
                                  ),
                          ),
                    onConfirm: (i) => unawaited(_confirm(i, choices[i])),
                  );
                }(),
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
