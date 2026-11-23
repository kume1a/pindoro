import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

import 'road_net.dart';

/// Junction at row [r] (0 north, 100 m apart) and column [c] (0 west, 100 m apart).
int j(int r, int c) => 100 + 10 * r + c;

/// The edge east from (r, c) and the one south from it.
int h(int r, int c) => 1000 + 10 * r + c;
int v(int r, int c) => 2000 + 10 * r + c;

/// A 4 × 4 grid: rows Paliashvili, Abashidze, Mosashvili (one-way east), Tamarashvili; columns
/// Chavchavadze, Kipshidze, Barnovi, Kazbegi. No left turn from Abashidze onto Kipshidze north.
/// Off the grid: Annex one connector north of (0, 3), Far three connectors east of (1, 3), Long
/// a 200 m connector east of (2, 3), Near two connectors east of (3, 3).
RoadNet _grid() {
  final net = RoadNet();
  const rows = ['pal', 'aba', 'mos', 'tam'];
  const cols = ['cha', 'kip', 'bar', 'kaz'];
  net
    ..street('pal', 'პალიაშვილის ქუჩა', 'Paliashvili Street')
    ..street('aba', 'აბაშიძის ქუჩა', 'Abashidze Street')
    ..street('mos', 'მოსაშვილის ქუჩა', 'Mosashvili Street')
    ..street('tam', 'თამარაშვილის ქუჩა', 'Tamarashvili Street')
    ..street('cha', 'ჭავჭავაძის გამზირი', 'Chavchavadze Avenue')
    ..street('kip', 'ყიფშიძის ქუჩა', 'Kipshidze Street')
    ..street('bar', 'ბარნოვის ქუჩა', 'Barnovi Street')
    ..street('kaz', 'ყაზბეგის გამზირი', 'Kazbegi Avenue')
    ..street('ane', 'ანექსის ქუჩა', 'Annex Street')
    ..street('far', 'შორეული ქუჩა', 'Far Street')
    ..street('lon', 'გრძელი ქუჩა', 'Long Street')
    ..street('nea', 'ახლო ქუჩა', 'Near Street');
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 4; c++) {
      net.junction(j(r, c), 100.0 * c, -100.0 * r);
    }
  }
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 3; c++) {
      net.edge(
        h(r, c),
        j(r, c),
        j(r, c + 1),
        rows[r],
        oneway: r == 2 ? Oneway.forward : Oneway.both,
      );
    }
  }
  for (var r = 0; r < 3; r++) {
    for (var c = 0; c < 4; c++) {
      net.edge(v(r, c), j(r, c), j(r + 1, c), cols[c]);
    }
  }
  net
    ..junction(150, 300, 100)
    ..junction(151, 400, 100)
    ..edge(3001, j(0, 3), 150, null)
    ..edge(3002, 150, 151, 'ane')
    ..junction(160, 350, -100)
    ..junction(161, 400, -100)
    ..junction(162, 450, -100)
    ..junction(163, 550, -100)
    ..edge(3011, j(1, 3), 160, null)
    ..edge(3012, 160, 161, null)
    ..edge(3013, 161, 162, null)
    ..edge(3014, 162, 163, 'far')
    ..junction(170, 500, -200)
    ..junction(171, 600, -200)
    ..edge(3021, j(2, 3), 170, null)
    ..edge(3022, 170, 171, 'lon')
    ..junction(180, 380, -300)
    ..junction(181, 460, -300)
    ..junction(182, 560, -300)
    ..edge(3031, j(3, 3), 180, null)
    ..edge(3032, 180, 181, null)
    ..edge(3033, 181, 182, 'nea');
  return net;
}

final _restrictions = <TurnRestriction>[
  (fromEdge: h(1, 0), via: j(1, 1), toEdge: v(0, 1), only: false),
];

RecitalStep _s(NamedStreet street, [Turn? turn]) =>
    (turn: turn, street: street, landmark: null);

RecitalStep _l(RouteLandmark landmark, [Turn? turn]) =>
    (turn: turn, street: null, landmark: landmark);

Route _path(RoadGraph graph, List<int> junctions) {
  final edges = [
    for (var i = 0; i + 1 < junctions.length; i++)
      graph
          .edgesAt(junctions[i])
          .firstWhere((e) => e.other(junctions[i]) == junctions[i + 1]),
  ];
  return Route(junctions, edges, edges.fold(0, (sum, e) => sum + e.lengthM));
}

void main() {
  final net = _grid();
  final graph = net.graph(restrictions: _restrictions);
  final s = net.named;

  group('tokenizeRecital', () {
    test('turn words split the names; fillers and punctuation drop', () {
      expect(
        tokenizeRecital(
          'Paliashvili, left onto Abashidze then right onto Mosashvili Street',
        ),
        const [
          NameToken('paliashvili'),
          TurnToken(Turn.left),
          NameToken('abashidze'),
          TurnToken(Turn.right),
          NameToken('mosashvili street'),
        ],
      );
    });

    test('Georgian and its Latin spelling, case endings kept for resolve', () {
      const expected = [
        NameToken('პალიაშვილი'),
        TurnToken(Turn.left),
        NameToken('აბაშიძეზე'),
        TurnToken(Turn.right),
        NameToken('მოსაშვილზე'),
      ];
      expect(
        tokenizeRecital(
          'პალიაშვილი, მარცხნივ აბაშიძეზე, მერე მარჯვნივ მოსაშვილზე',
        ),
        expected,
      );
      expect(
        tokenizeRecital(
          'paliashvili marcxniv abashidzeze mere marjvniv mosashvilze',
        ),
        const [
          NameToken('paliashvili'),
          TurnToken(Turn.left),
          NameToken('abashidzeze'),
          TurnToken(Turn.right),
          NameToken('mosashvilze'),
        ],
      );
    });

    test('two-word turns: u turn, turn around', () {
      expect(tokenizeRecital('U turn at Kazbegi; turn around'), const [
        TurnToken(Turn.uTurn),
        NameToken('kazbegi'),
        TurnToken(Turn.uTurn),
      ]);
    });
  });

  group('resolveRecital', () {
    final all = s.values.toList();

    test('names resolve in any script, with case endings, turns going with the '
        'next name', () {
      final steps = resolveRecital(
        tokenizeRecital(
          'პალიაშვილი, მარცხნივ აბაშიძეზე, მერე მარჯვნივ მოსაშვილზე',
        ),
        streets: all,
      );
      expect(steps.map((st) => (st.turn, st.street?.id)), [
        (null, s['pal']!.id),
        (Turn.left, s['aba']!.id),
        (Turn.right, s['mos']!.id),
      ]);
    });

    test('a run of words splits into the longest names; unknown words are '
        'skipped', () {
      final steps = resolveRecital(
        tokenizeRecital('blah chavchavadze avenue kipshidze'),
        streets: all,
      );
      expect(steps.map((st) => st.street?.id), [s['cha']!.id, s['kip']!.id]);
    });

    test('of two streets with one name, the one near the previous street '
        'wins', () {
      final far = RoadNet()
        ..street('aba', 'აბაშიძის ქუჩა', 'Abashidze Street')
        ..street('oth', 'სხვა ქუჩა', 'Other Street')
        ..junction(1, 5000, 0)
        ..junction(2, 5100, 0)
        ..junction(3, 5000, 100)
        ..edge(1, 1, 2, 'aba')
        ..edge(2, 1, 3, 'oth');
      final streets = [...all, ...far.named.values];
      final tokens = tokenizeRecital('abashidze');
      expect(
        resolveRecital(tokens, streets: streets, from: s['kip']).single.street,
        s['aba'],
      );
      expect(
        resolveRecital(
          tokens,
          streets: streets,
          from: far.named['oth'],
        ).single.street,
        far.named['aba'],
      );
    });

    test('a landmark resolves with its turn word', () {
      final fuel = (
        id: 'osm:n1',
        name: 'ლუკოილი',
        nameEn: null,
        kind: 'fuel',
        at: graph.at(j(0, 2)),
        personal: false,
        junction: j(0, 2),
        onLeft: true,
      );
      final steps = resolveRecital(
        tokenizeRecital('Paliashvili, right at Lukoil, Barnovi'),
        streets: all,
        landmarks: [fuel],
      );
      expect(steps.map((st) => (st.turn, st.street?.id, st.landmark?.id)), [
        (null, s['pal']!.id, null),
        (Turn.right, null, 'osm:n1'),
        (null, s['bar']!.id, null),
      ]);
    });
  });

  group('RecitalGrader.grade', () {
    RecitalResult grade(List<RecitalStep> steps, int from, int to) =>
        RecitalGrader.grade(
          graph,
          steps,
          from: from,
          to: to,
          streets: net.byPart,
        );

    test('the best route is Perfect, its street changes named decisions', () {
      final r = grade(
        [_s(s['pal']!), _s(s['bar']!, Turn.right), _s(s['mos']!, Turn.left)],
        j(0, 0),
        j(2, 3),
      );
      expect(r.path!.junctions, [
        j(0, 0),
        j(0, 1),
        j(0, 2),
        j(1, 2),
        j(2, 2),
        j(2, 3),
      ]);
      expect((r.tier, r.rating), (Tier.perfect, Rating.easy));
      expect(r.stretch, closeTo(1, 1e-3));
      expect(r.drivable, isTrue);
      expect(r.decisions.every((d) => d.correct), isTrue);
      expect(
        [
          for (final d in r.decisions)
            if (d.newStreet) (d.junction, d.turn),
        ],
        [(j(0, 2), Turn.right), (j(2, 2), Turn.left)],
      );
      expect(r.score, 1);
      expect(r.extraM, closeTo(0, 0.5));
    });

    test('a hinted recital is capped at Great / Good', () {
      final r = RecitalGrader.grade(
        graph,
        [_s(s['pal']!), _s(s['bar']!, Turn.right), _s(s['mos']!, Turn.left)],
        from: j(0, 0),
        to: j(2, 3),
        hinted: true,
      );
      expect((r.tier, r.rating), (Tier.great, Rating.good));
    });

    test('A\'s and B\'s streets may go unsaid', () {
      final r = grade([_s(s['bar']!, Turn.right)], j(0, 0), j(2, 3));
      expect(r.path!.junctions, [
        j(0, 0),
        j(0, 1),
        j(0, 2),
        j(1, 2),
        j(2, 2),
        j(2, 3),
      ]);
      expect(r.tier, Tier.perfect);
    });

    test('against a one-way: Not drivable, the offending move named', () {
      final r = grade([_s(s['mos']!)], j(2, 3), j(2, 0));
      expect(r.drivable, isFalse);
      expect(r.path!.junctions, [j(2, 3), j(2, 2), j(2, 1), j(2, 0)]);
      expect(r.illegal, (
        junction: j(2, 3),
        edge: graph.edgesAt(j(2, 3)).firstWhere((e) => e.id == h(2, 2)),
        reason: IllegalReason.oneway,
        approach: null,
      ));
      expect((r.tier, r.rating), (Tier.miss, Rating.again));
    });

    test('a restricted turn is driven legally with a U-turn when the street '
        'allows one', () {
      final r = grade(
        [_s(s['aba']!), _s(s['kip']!, Turn.left)],
        j(1, 0),
        j(0, 1),
      );
      expect(r.drivable, isTrue);
      expect(r.path!.junctions, [j(1, 0), j(1, 1), j(2, 1), j(1, 1), j(0, 1)]);
      expect(
        r.stretch,
        closeTo((400 + RoutingConfig.uTurnPenaltyM) / 200, 1e-3),
      );
      expect(r.tier, Tier.miss);
    });

    test('streets that don\'t meet: a Miss with no path', () {
      final r = grade([_s(s['pal']!), _s(s['tam']!)], j(0, 0), j(3, 3));
      expect(r.path, isNull);
      expect(r.illegal, isNull);
      expect((r.tier, r.rating, r.score), (Tier.miss, Rating.again, 0.0));
      expect(r.best, isNotNull);
    });

    test('up to two silent connectors of at most 150 m join streets', () {
      final one = grade([_s(s['pal']!), _s(s['ane']!)], j(0, 0), 151);
      expect(one.path!.edges.map((e) => e.id), [
        h(0, 0),
        h(0, 1),
        h(0, 2),
        3001,
        3002,
      ]);
      expect(one.tier, Tier.perfect);
      final two = grade([_s(s['tam']!), _s(s['nea']!)], j(3, 0), 182);
      expect(
        two.path!.edges.map((e) => e.id),
        containsAllInOrder([3031, 3032]),
      );
      expect(grade([_s(s['aba']!), _s(s['far']!)], j(1, 0), 163).path, isNull);
      expect(grade([_s(s['mos']!), _s(s['lon']!)], j(2, 0), 171).path, isNull);
    });

    test('a turn word picks between near-equal ways onto the next street', () {
      final side = RoadNet()
        ..street('main', 'მთავარი ქუჩა', 'Main Street')
        ..street('side', 'გვერდითი ქუჩა', 'Side Street')
        ..junction(0, 0, 0)
        ..junction(1, 100, 0)
        ..junction(2, 200, 0)
        ..junction(11, 100, 100)
        ..junction(12, 200, -100)
        ..edge(1, 0, 1, 'main')
        ..edge(2, 1, 2, 'main')
        ..edge(11, 1, 11, 'side')
        ..edge(13, 2, 12, 'side')
        ..edge(12, 12, 11, 'side', m: 50);
      final g = side.graph();
      List<int> walk(Turn? turn) => RecitalGrader.grade(
        g,
        [_s(side.named['main']!), _s(side.named['side']!, turn)],
        from: 0,
        to: 11,
      ).path!.junctions;
      expect(walk(null), [0, 1, 11]);
      expect(walk(Turn.left), [0, 1, 11]);
      expect(walk(Turn.right), [0, 1, 2, 12, 11]);
    });

    test('a landmark named at a decision adds to the score', () {
      final fuel = (
        id: 'osm:n1',
        name: 'ლუკოილი',
        nameEn: null,
        kind: 'fuel',
        at: graph.at(j(1, 1)),
        personal: false,
        junction: j(1, 1),
        onLeft: true,
      );
      final plain = grade(
        [_s(s['aba']!), _s(s['kip']!, Turn.left)],
        j(1, 0),
        j(0, 1),
      );
      final named = grade(
        [_s(s['aba']!), _l(fuel), _s(s['kip']!, Turn.left)],
        j(1, 0),
        j(0, 1),
      );
      expect(named.score, closeTo(plain.score + 0.1, 1e-9));
    });
  });

  group('RecitalGrader.score', () {
    RoadGraph triangle(double viaM) {
      final net = RoadNet()
        ..street('ab', 'ა', 'A')
        ..street('ac', 'ბ', 'B')
        ..street('cb', 'გ', 'C')
        ..junction(1, 0, 0)
        ..junction(2, 100, 0)
        ..junction(3, 50, 50)
        ..edge(1, 1, 2, 'ab', m: 100)
        ..edge(2, 1, 3, 'ac', m: viaM / 2)
        ..edge(3, 3, 2, 'cb', m: viaM / 2);
      return net.graph();
    }

    (Tier, Rating) via(double viaM, {bool hinted = false}) {
      final g = triangle(viaM);
      final r = RecitalGrader.score(
        g,
        _path(g, [1, 3, 2]),
        from: 1,
        to: 2,
        hinted: hinted,
      );
      return (r.tier, r.rating);
    }

    test('stretch tiers (SPEC §5.3 step 5): 1.03 Perfect, 1.25 Great, 1.26 '
        'Close, past 1.60 Miss', () {
      expect(via(103), (Tier.perfect, Rating.easy));
      expect(via(103, hinted: true), (Tier.great, Rating.good));
      expect(via(125), (Tier.great, Rating.good));
      expect(via(126), (Tier.close, Rating.hard));
      expect(via(160), (Tier.close, Rating.hard));
      expect(via(161), (Tier.miss, Rating.again));
    });

    test('a restricted turn is named; decisions judge the way on from each '
        'junction', () {
      final turn = RecitalGrader.score(
        graph,
        _path(graph, [j(1, 0), j(1, 1), j(0, 1)]),
        from: j(1, 0),
        to: j(0, 1),
      );
      expect(turn.illegal?.reason, IllegalReason.restriction);
      expect(turn.illegal?.junction, j(1, 1));
      expect(turn.illegal?.edge.id, v(0, 1));
      expect(
        turn.illegal?.approach?.id,
        h(1, 0),
        reason: 'the way in is the edge driven, not searched for again',
      );

      final uTurn = RecitalGrader.score(
        graph,
        _path(graph, [j(1, 0), j(1, 1), j(2, 1), j(1, 1), j(0, 1)]),
        from: j(1, 0),
        to: j(0, 1),
        landmarksNamed: 1,
      );
      expect(uTurn.decisions.map((d) => (d.junction, d.correct)), [
        (j(1, 0), false),
        (j(1, 1), false),
        (j(2, 1), true),
        (j(1, 1), true),
      ]);
      expect(uTurn.decisions[2].turn, Turn.uTurn);
      expect(uTurn.score, closeTo(0.6, 1e-9));
      expect(uTurn.divergence, j(1, 0));
      expect(uTurn.extraM, closeTo(200, 0.5));
      final capped = RecitalGrader.score(
        graph,
        uTurn.path!,
        from: j(1, 0),
        to: j(0, 1),
        landmarksNamed: 5,
      );
      expect(capped.score, closeTo(0.8, 1e-9));
    });

    test(
      'a U-turn weighs RoutingConfig.uTurnPenaltyM in the stretch, as in the best '
      'route: a short way round by a U-turn is never shorter than the best',
      () {
        // No left from A–B into B–Z: turn round at the spur S, or go round by D (400 m).
        final net = RoadNet()
          ..street('ab', 'ა', 'A')
          ..street('bz', 'ბ', 'Z')
          ..junction(1, 0, 0)
          ..junction(2, 100, 0)
          ..junction(3, 125, 0)
          ..junction(4, 100, 50)
          ..junction(5, 0, 200)
          ..edge(1, 1, 2, 'ab', m: 100)
          ..edge(2, 2, 3, 'ab', m: 25)
          ..edge(3, 2, 4, 'bz', m: 50)
          ..edge(4, 1, 5, null, m: 200)
          ..edge(5, 5, 4, null, m: 200);
        final g = net.graph(
          restrictions: [(fromEdge: 1, via: 2, toEdge: 3, only: false)],
        );
        final r = RecitalGrader.score(
          g,
          _path(g, [1, 2, 3, 2, 4]),
          from: 1,
          to: 4,
        );
        expect(r.best?.lengthM, 400);
        expect(
          r.stretch,
          closeTo((200 + RoutingConfig.uTurnPenaltyM) / 400, 1e-9),
        );
      },
    );

    test('a path that doesn\'t arrive at B is a Miss', () {
      final r = RecitalGrader.score(
        graph,
        _path(graph, [j(0, 0), j(0, 1)]),
        from: j(0, 0),
        to: j(0, 2),
      );
      expect((r.tier, r.stretch), (Tier.miss, null));
    });
  });

  test('recitalEvidence: a right decision for its J item, a wrong one against '
      'every J item from that approach', () {
    final nodes = {for (final id in graph.junctions.keys) id: id + 9000};
    String jId(int at, int from, int to) =>
        RouteIds.junction(at + 9000, from + 9000, to + 9000);
    final items = {
      jId(j(2, 1), j(1, 1), j(1, 1)),
      jId(j(1, 1), j(1, 0), j(1, 2)),
      jId(j(1, 1), j(1, 0), j(2, 1)),
      jId(j(1, 1), j(2, 1), j(0, 1)),
      jId(j(1, 1), j(0, 1), j(1, 0)),
    };
    final r = RecitalGrader.score(
      graph,
      _path(graph, [j(1, 0), j(1, 1), j(2, 1), j(1, 1), j(0, 1)]),
      from: j(1, 0),
      to: j(0, 1),
    );
    expect(recitalEvidence(r, nodes, items), [
      (itemId: jId(j(1, 1), j(1, 0), j(1, 2)), ok: false),
      (itemId: jId(j(1, 1), j(1, 0), j(2, 1)), ok: false),
      (itemId: jId(j(2, 1), j(1, 1), j(1, 1)), ok: true),
      (itemId: jId(j(1, 1), j(2, 1), j(0, 1)), ok: true),
    ]);
  });
}
