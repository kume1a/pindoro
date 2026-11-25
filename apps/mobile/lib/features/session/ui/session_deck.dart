import 'dart:math';

import 'package:pindoro/features/session/ui/session_state.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// A session's city and what each of its steps shows (SPEC §6.4, §7): the step's street, its
/// task and its map's frame, from the pack, the curriculum, the day's [drills] and the route
/// book.
class SessionDeck {
  SessionDeck({
    required this.streets,
    required this.pack,
    required this.curriculum,
    required RouteBook routes,
    required this.drills,
    required this.graph,
    required Iterable<Run> runs,
    required this.confusable,
    required this.seed,
  }) : all = streets.values.toSet(),
       nodes = pack.junctionNodes(),
       _routes = routes,
       _runs = {for (final r in runs) r.id: r} {
    _byNode = {for (final e in nodes.entries) e.value: e.key};
  }

  /// The city's streets by part id, and each once.
  final Map<String, NamedStreet> streets;
  final Set<NamedStreet> all;
  final PackRepository pack;
  final Curriculum curriculum;
  final Drills drills;

  /// Recitals are graded on the graph with the player's reported moves (SPEC §5.3).
  final RoadGraph? graph;

  /// Each pack junction's OSM node.
  final Map<int, int> nodes;

  /// The streets a pin for a street can land on by mistake.
  final Set<String> Function(NamedStreet target) confusable;
  final int seed;

  RouteBook _routes;
  final Map<String, Run> _runs;
  late final Map<int, int> _byNode;

  /// Each R item's recital as first built.
  final Map<String, RecitalTask?> _recitals = {};

  RouteBook get routes => _routes;

  /// The route book's landmarks, each once: what a recital can name.
  Iterable<RouteLandmark> get landmarks => {
    for (final q in _routes.questions.values)
      if (q is LandmarkQuestion) q.landmark.id: q.landmark,
  }.values;

  /// The cards of pack landmark [id] leave the session's route book.
  void hideLandmark(String id) => _routes = (
    candidates: _routes.candidates,
    questions: Map.of(_routes.questions)
      ..removeWhere((_, q) => q is LandmarkQuestion && q.landmark.id == id),
  );

  /// The street a step's plate names: its own, or a route card's street.
  NamedStreet? streetOf(SessionStep step) =>
      streets[itemKey(step.itemId)] ??
      switch (_routes.questions[step.itemId]) {
        final TurnQuestion q => q.approachStreet ?? q.exitStreet,
        final GatewayQuestion q => q.exitStreet ?? _nearest(q.at),
        final BridgeQuestion q => q.approachStreet ?? _nearest(q.at),
        final ConnectionQuestion q => q.street,
        final LandmarkQuestion q =>
          q.street ?? q.approachStreet ?? _nearest(q.landmark.at),
        null => _recitalTask(step.itemId)?.fromStreet,
      };

  /// What [step] asks of [street]; null for a drill whose streets are gone.
  SessionTask? taskFor(SessionStep step, NamedStreet street) =>
      switch (step.kind) {
        StepKind.familySweep => switch ([
          for (final id in drills.sweep?.children ?? const <String>[])
            ?streets[itemKey(id)],
        ]) {
          final lanes when lanes.length >= 2 => SweepTask(lanes: lanes),
          _ => null,
        },
        StepKind.crossings => _crossingsTask(street),
        StepKind.bearing => BearingTask(
          trueBearing: bearingDegrees(
            curriculum.centre,
            street.parts.first.midpoint,
          ),
          distanceM: distanceBetween(
            curriculum.centre,
            street.parts.first.midpoint,
          ),
        ),
        _ when step.kind == StepKind.intro && !isRouteItem(step.itemId) =>
          const PinTask(),
        _ when CardType.ofItem(step.itemId) == CardType.r => _recitalTask(
          step.itemId,
        ),
        _ when _routes.questions[step.itemId] != null => RouteTask(
          _routes.questions[step.itemId]!,
        ),
        _ => switch (CardType.ofItem(step.itemId)) {
          CardType.n => NameTask(
            choices: nameChoices(
              target: street,
              streets: all,
              confusable: confusable(street),
              random: Random(
                seed + stableSeed('${step.kind.name}:${step.itemId}'),
              ),
            ),
          ),
          CardType.e => const ExtentTask(),
          _ => const PinTask(),
        },
      };

  /// What the map frames for [task] on [street]: the street, a sweep's lanes, a route card's
  /// area, a first retrieval's or a guess's district; null frames the city.
  List<LatLng>? frameOf(
    SessionTask task,
    SessionStep step,
    NamedStreet street, {
    required bool guessing,
  }) => switch (task) {
    NameTask() || CrossingsTask() => street.geometry.expand((l) => l).toList(),
    SweepTask(:final lanes) => [
      for (final s in [street, ...lanes]) ...s.geometry.expand((l) => l),
    ],
    RouteTask(:final question) => _routeFrame(question),
    _ when step.kind == StepKind.retrieval1 || guessing => _districtFrame(
      street,
    ),
    _ => null,
  };

  /// A family member's intro chip.
  SessionFamily? familyOf(NamedStreet street) {
    final chip = curriculum.familyChip(street.id);
    final parent = streets[chip?.parentId];
    return chip == null || parent == null
        ? null
        : (parent: parent, children: chip.children);
  }

  /// R item [itemId]'s recital: its run's ends in this pack, A's and B's
  /// streets from the best route between them; null when the run or a
  /// legal route is gone.
  RecitalTask? _recitalTask(String itemId) => _recitals.putIfAbsent(itemId, () {
    final run = _runs[itemKey(itemId)];
    final graph = this.graph;
    final ends = run == null || graph == null
        ? null
        : runEnds(run, graph, _byNode, streets);
    return ends == null
        ? null
        : RecitalTask(
            run!,
            from: ends.from,
            to: ends.to,
            fromStreet: ends.fromStreet,
            toStreet: ends.toStreet,
            draft: RouteDraft(graph!, ends.from, {ends.to}),
          );
  });

  CrossingsTask? _crossingsTask(NamedStreet street) {
    final drill = drills.crossings;
    final from = streets[drill?.fromId];
    if (drill == null || from == null) return null;
    final along = {for (final c in crossingsAlong(street, all)) c.street.id: c};
    final crossings = [
      for (final id in drill.crossings) ?along[streets[id]?.id],
    ];
    final start = along[from.id]?.at;
    return crossings.isEmpty || start == null
        ? null
        : CrossingsTask(from: from, start: start, crossings: crossings);
  }

  NamedStreet? _nearest(LatLng at) {
    NamedStreet? best;
    var bestM = double.infinity;
    for (final s in all) {
      final m = distanceBetween(at, s.parts.first.midpoint);
      if (m < bestM) (best, bestM) = (s, m);
    }
    return best;
  }

  /// What a route card's map frames: a gateway's neighbourhood, a bridge
  /// question's bridges and start; the city otherwise.
  List<LatLng>? _routeFrame(RouteQuestion q) => switch (q) {
    GatewayQuestion(:final chunk) => pack.district(chunk)?.bbox.diagonal,
    BridgeQuestion(:final at, :final options) => [
      at,
      for (final b in options) b.midpoint,
    ],
    _ => null,
  };

  /// The bounds of the raion holding most of [street]'s length.
  List<LatLng>? _districtFrame(NamedStreet street) {
    final parts = {for (final p in street.parts) p.id};
    final raions = {
      for (final d in pack.districts())
        if (d.isRaion) d.id: d,
    };
    String? best;
    var bestM = 0.0;
    for (final MapEntry(key: id, value: lengths)
        in pack.lengthsByDistrict().entries) {
      if (!raions.containsKey(id)) continue;
      final m = lengths.entries
          .where((e) => parts.contains(e.key))
          .fold(0.0, (sum, e) => sum + e.value);
      if (m > bestM) (best, bestM) = (id, m);
    }
    return raions[best]?.bbox.diagonal;
  }
}
