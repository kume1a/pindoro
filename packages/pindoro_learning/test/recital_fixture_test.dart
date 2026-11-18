import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

import 'vake_fixture.dart';

/// SPEC §14's recital vectors on the Vake fixture pack.
void main() {
  late RoadGraph graph;
  late Map<String, NamedStreet> streets;
  late Map<int, int> nodes;

  setUpAll(() {
    final vake = Vake.load();
    (graph, streets, nodes) = (vake.graph, vake.streets, vake.nodes);
  });

  /// Seeded legal routes of 800–2500 m on named streets only.
  Iterable<Route> routes(int seed) sync* {
    final random = Random(seed);
    final ids = graph.junctions.keys.toList()..sort();
    while (true) {
      final route = graph.shortestRoute(ids[random.nextInt(ids.length)], {
        ids[random.nextInt(ids.length)],
      });
      if (route != null &&
          route.lengthM >= 800 &&
          route.lengthM <= 2500 &&
          route.edges.every((e) => e.streetId != null)) {
        yield route;
      }
    }
  }

  List<RecitalStep> recite(Route route) => [
    for (final s in route.edges.map((e) => streets[e.streetId]!))
      (turn: null, street: s, landmark: null),
  ];

  test('the legal best route, recited street by street, is Perfect', () {
    for (final route in routes(3).take(5)) {
      final r = RecitalGrader.grade(
        graph,
        recite(route),
        from: route.junctions.first,
        to: route.junctions.last,
        streets: streets,
      );
      final why = '${route.junctions.first} → ${route.junctions.last}';
      expect(r.drivable, isTrue, reason: why);
      expect(r.stretch, closeTo(1, 1e-9), reason: why);
      expect((r.tier, r.rating), (Tier.perfect, Rating.easy), reason: why);
      expect(r.decisions.every((d) => d.correct), isTrue, reason: why);
    }
  });

  test('a legal detour about 26 % longer is Close', () {
    for (final best in routes(4).take(40)) {
      final a = best.junctions.first, b = best.junctions.last;
      for (final via in best.junctions.skip(1)) {
        for (final e in graph.legalExits(via)) {
          final out = graph.shortestRoute(a, {e.other(via)});
          if (out == null || out.junctions.contains(b)) continue;
          final back = graph.shortestRoute(out.junctions.last, {
            b,
          }, approach: out.edges.lastOrNull);
          if (back == null) continue;
          final length = out.lengthM + back.lengthM;
          final stretch = length / best.lengthM;
          if (stretch < 1.255 || stretch > 1.3) continue;
          final detour = Route(
            [...out.junctions, ...back.junctions.skip(1)],
            [...out.edges, ...back.edges],
            length,
          );
          final r = RecitalGrader.score(
            graph,
            detour,
            from: a,
            to: b,
            streets: streets,
          );
          expect(r.drivable, isTrue);
          expect(r.stretch, closeTo(stretch, 1e-9));
          expect((r.tier, r.rating), (Tier.close, Rating.hard));
          expect(r.decisions.any((d) => !d.correct), isTrue);
          expect(r.divergence, isNotNull);
          return;
        }
      }
    }
    fail('no detour of stretch 1.255–1.3 found');
  });

  test('a one-way street recited against its direction is Not drivable, '
      'and drivable once the player reports it', () {
    final oneways =
        graph.edges
            .where((e) => e.oneway == Oneway.forward && e.streetId != null)
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    for (final e in oneways) {
      final street = streets[e.streetId]!;
      final r = RecitalGrader.grade(
        graph,
        [(turn: null, street: street, landmark: null)],
        from: e.to,
        to: e.from,
        streets: streets,
      );
      if (r.illegal == null) continue;
      expect(r.drivable, isFalse);
      expect(r.illegal!.reason, IllegalReason.oneway);
      expect(street.parts.map((p) => p.id), contains(r.illegal!.edge.streetId));
      expect(r.illegal!.edge.oneway, isNot(Oneway.both));
      expect((r.tier, r.rating), (Tier.miss, Rating.again));
      final report = moveReport(r.illegal!, nodes);
      expect(report, startsWith('oneway:'));
      final reported = RecitalGrader.grade(
        allowingReports(graph, {report}, nodes),
        [(turn: null, street: street, landmark: null)],
        from: e.to,
        to: e.from,
        streets: streets,
      );
      expect(reported.illegal, isNull);
      return;
    }
    fail('no one-way street to drive against');
  });

  test('a street named in full resolves to it, kind word and "and" kept, '
      'wherever its name is the only one of its kind', () {
    final all = streets.values.toSet();
    final byName = <String, int>{};
    for (final s in all) {
      byName.update(s.name, (n) => n + 1, ifAbsent: () => 1);
    }
    final unique = all.where((s) => byName[s.name] == 1).toList();
    expect(unique.where((s) => s.name.contains(' და ')), isNotEmpty);
    for (final s in unique) {
      expect(
        resolveRecital(tokenizeRecital(s.name), streets: all).single.street,
        s,
        reason: s.name,
      );
    }
  });
}
