import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

const _centre = LatLng(41.70, 44.80);
final _now = DateTime(2026, 3, 2, 9);

NamedStreet _street(
  String id, {
  StreetTier? tier = StreetTier.c,
  int ring = 0,
  RiverBank bank = RiverBank.left,
  String? chunk = 'c1',
  double length = 300,
}) => NamedStreet([
  Street(
    id: id,
    nameKa: id,
    nameEn: null,
    roadClass: 'residential',
    difficulty: Difficulty.expert,
    lengthM: length,
    midpoint: _centre,
    bbox: const Bbox(41.7, 44.8, 41.7, 44.8),
    geometry: const [
      [_centre, _centre],
    ],
    tier: tier,
    ring: ring,
    bank: bank,
    chunkId: chunk,
  ),
]);

/// A square chunk [km] east of the centre, in raion [raion].
District _chunk(String id, double km, {String raion = 'r1'}) {
  final lon = _centre.lon + km / 83.2 - 0.004;
  final ring = [
    LatLng(_centre.lat - 0.004, lon),
    LatLng(_centre.lat - 0.004, lon + 0.008),
    LatLng(_centre.lat + 0.004, lon + 0.008),
    LatLng(_centre.lat + 0.004, lon),
    LatLng(_centre.lat - 0.004, lon),
  ];
  return District(
    id: id,
    kind: DistrictKind.neighbourhood,
    osmRelationId: null,
    nameKa: id,
    nameEn: null,
    center: LatLng(_centre.lat, lon + 0.004),
    bbox: Bbox(ring[0].lat, ring[0].lon, ring[2].lat, ring[2].lon),
    areaM2: 1e6,
    boundary: [
      [ring],
    ],
    parentId: raion,
  );
}

/// c1 holds the centre; c2 and c3 lie 2 and 3 km east, c4 9 km east.
final _chunks = [
  _chunk('c1', 0),
  _chunk('c2', 2),
  _chunk('c3', 3, raion: 'r2'),
  _chunk('c4', 9, raion: 'r2'),
];

/// A card introduced [daysAgo] days ago at [stability] days.
CardState _card(
  String street, {
  double stability = 5,
  int daysAgo = 2,
  int reps = 0,
  bool priorKnown = false,
}) {
  final at = _now.subtract(Duration(days: daysAgo));
  return CardState(
    itemId: CardType.p.item(street),
    phase: CardPhase.review,
    memory: Memory(stability: stability, difficulty: 5, lastReview: at),
    dueAt: _now.add(const Duration(days: 1)),
    reps: reps,
    lastRating: Rating.good,
    priorKnown: priorKnown,
    introAt: at,
  );
}

FamilyLink _child(String parent, String child, int n, {bool orphan = false}) =>
    (
      parentId: parent,
      childId: child,
      kind: FamilyKind.lane,
      n: n,
      orphan: orphan,
    );

Curriculum _curriculum(
  List<NamedStreet> streets, {
  List<FamilyLink> families = const [],
  Map<String, Set<String>> neighbours = const {},
}) => Curriculum(
  streets: streets,
  districts: _chunks,
  centre: _centre,
  families: families,
  chunkNeighbours: neighbours,
);

List<String> _next(
  Curriculum curriculum, {
  Map<String, CardState> cards = const {},
  int count = 20,
  List<String> anchors = const [],
}) => curriculum.next(cards: cards, now: _now, count: count, anchors: anchors);

void main() {
  test('the skeleton, then the grid: ring by ring, banks alternating, '
      'longest first', () {
    final trunk = [
      _street('b2', tier: StreetTier.b, length: 400),
      _street('b4', tier: StreetTier.b, ring: 1, bank: RiverBank.right),
      _street('a3', tier: StreetTier.a, ring: 1, length: 1000),
      _street('b3', tier: StreetTier.b, bank: RiverBank.right, length: 450),
      _street('a2', tier: StreetTier.a, bank: RiverBank.right, length: 800),
      _street('b1', tier: StreetTier.b, length: 500),
      _street('a1', tier: StreetTier.a, length: 900),
    ];
    expect(_next(_curriculum(trunk), count: 7), [
      'a1',
      'a2',
      'a3',
      'b1',
      'b3',
      'b2',
      'b4',
    ]);
  });

  test('60 % of the slots go to the skeleton and grid, in groups of 3, '
      'while any of their core streets is unseen', () {
    final streets = [
      for (var i = 0; i < 12; i++)
        _street('t$i', tier: StreetTier.b, length: 1000.0 - i),
      for (var i = 0; i < 12; i++) _street('c$i', length: 1000.0 - i),
    ];
    final curriculum = _curriculum(streets);
    expect(
      _next(curriculum, count: 10).map((id) => id[0]).join(),
      'tttccctttc',
    );
    final trunkSeen = {for (var i = 0; i < 12; i++) 't$i': _card('t$i')};
    expect(
      _next(curriculum, cards: trunkSeen, count: 5).map((id) => id[0]).join(),
      'ccccc',
    );
  });

  group('chunks', () {
    final streets = [
      for (final c in ['c1', 'c2', 'c3', 'c4'])
        for (var i = 0; i < 4; i++)
          _street('$c-$i', chunk: c, length: 900.0 - i),
    ];
    final neighbours = {
      'c1': {'c2', 'c3'},
      'c2': {'c1'},
      'c3': {'c1', 'c4'},
      'c4': {'c3'},
    };
    final curriculum = _curriculum(streets, neighbours: neighbours);
    Map<String, CardState> finished(List<String> chunks) => {
      for (final c in chunks)
        for (var i = 0; i < 4; i++) '$c-$i': _card('$c-$i'),
    };
    String firstChunk({
      Map<String, CardState> cards = const {},
      List<String> anchors = const [],
    }) => _next(
      curriculum,
      cards: cards,
      count: 1,
      anchors: anchors,
    ).single.split('-').first;

    test('the centre’s chunk first, the anchors before it', () {
      expect(firstChunk(), 'c1');
      expect(firstChunk(anchors: ['c4']), 'c4');
    });

    test('a started chunk goes on before a new one', () {
      final c3Started = {
        ...finished(['c1']),
        'c3-0': _card('c3-0'),
      };
      expect(firstChunk(cards: c3Started), 'c3');
    });

    test('then the chunk bordering the most finished ones, ties nearer the '
        'centre', () {
      expect(firstChunk(cards: finished(['c1'])), 'c2');
      expect(firstChunk(cards: finished(['c1', 'c4'])), 'c3');
    });

    test('a group stays in its chunk while it has streets', () {
      expect(_next(curriculum, count: 6), [
        'c1-0',
        'c1-1',
        'c1-2',
        'c1-3',
        'c2-0',
        'c2-1',
      ]);
    });
  });

  group('families', () {
    final parent = _street('p', length: 200);
    final others = [_street('o1', length: 500), _street('o2', length: 250)];
    final children = [
      for (var n = 1; n <= 6; n++) _street('p$n', length: 300.0 - n),
    ];
    final curriculum = _curriculum(
      [parent, ...others, ...children],
      families: [for (var n = 1; n <= 6; n++) _child('p', 'p$n', n)],
    );

    test('parents first, then the other streets, then children by number', () {
      expect(_next(curriculum), ['p', 'o1', 'o2']);
      expect(_next(curriculum, cards: {'p': _card('p')}), [
        'o1',
        'o2',
        'p1',
        'p2',
        'p3',
        'p4',
      ]);
    });

    test('a child waits for its parent’s stability to reach 3 days', () {
      final young = {'p': _card('p', stability: 2.31)};
      expect(_next(curriculum, cards: young), ['o1', 'o2']);
      final ready = {'p': _card('p', stability: 3)};
      expect(_next(curriculum, cards: ready), contains('p1'));
    });

    test('at most 4 new siblings a day, counting today’s intros', () {
      final cards = {
        'p': _card('p'),
        'p1': _card('p1', daysAgo: 0),
        'p2': _card('p2', daysAgo: 1),
      };
      expect(
        _next(curriculum, cards: cards).where((id) => id.startsWith('p')),
        ['p3', 'p4', 'p5'],
      );
    });

    test('a family: parent, siblings and children; the chip counts them by '
        'kind', () {
      final nested = _curriculum(
        [parent, ...children, _street('p1a')],
        families: [
          for (var n = 1; n <= 6; n++) _child('p', 'p$n', n),
          (
            parentId: 'p1',
            childId: 'p1a',
            kind: FamilyKind.deadEnd,
            n: 1,
            orphan: false,
          ),
        ],
      );
      expect(nested.familyOf('p2'), {'p', 'p1', 'p3', 'p4', 'p5', 'p6'});
      expect(nested.familyOf('p1'), {'p', 'p2', 'p3', 'p4', 'p5', 'p6', 'p1a'});
      expect(nested.familyOf('o1'), isEmpty);
      expect(nested.familyChip('p3')?.parentId, 'p');
      expect(nested.familyChip('p3')?.children, {FamilyKind.lane: 6});
      expect(nested.familyChip('p1a')?.parentId, 'p1');
      expect(nested.familyChip('p1a')?.children, {FamilyKind.deadEnd: 1});
      expect(nested.familyChip('p')?.parentId, 'p');
      expect(nested.familyChip('o1'), isNull);
    });

    test('an orphan is a single street', () {
      final orphaned = _curriculum(
        [parent, children.first],
        families: [_child('p', 'p1', 1, orphan: true)],
      );
      expect(_next(orphaned), ['p1', 'p']);
    });
  });

  test('short streets wait for 80 % of their chunk’s core streets to be '
      'Solid', () {
    final core = [for (var i = 0; i < 5; i++) _street('s$i')];
    final curriculum = _curriculum([...core, _street('short', length: 90)]);
    Map<String, CardState> solid(int count) => {
      for (var i = 0; i < 5; i++)
        's$i': _card('s$i', stability: i < count ? 21 : 10),
    };
    expect(_next(curriculum, cards: solid(3)), isEmpty);
    expect(_next(curriculum, cards: solid(4)), ['short']);
  });

  test('placement: every core tier A street, then 5 seeded tier B streets '
      'per raion; the sweep takes the rest', () {
    final streets = [
      _street('a1', tier: StreetTier.a, length: 900),
      _street('a-short', tier: StreetTier.a, length: 100),
      for (var i = 0; i < 8; i++)
        _street('r1b$i', tier: StreetTier.b, chunk: 'c1'),
      for (var i = 0; i < 3; i++)
        _street('r2b$i', tier: StreetTier.b, chunk: 'c3'),
    ];
    final curriculum = _curriculum(streets);
    final picks = curriculum.placement(7);
    expect(picks, curriculum.placement(7));
    expect(picks.first, 'a1');
    expect(picks, isNot(contains('a-short')));
    final r1 = picks.where((id) => id.startsWith('r1')).toList();
    expect(r1, hasLength(5));
    expect(picks.where((id) => id.startsWith('r2')), hasLength(3));
    final sweep = curriculum.placementSweep('r1', r1);
    expect({...sweep, ...r1}, {for (var i = 0; i < 8; i++) 'r1b$i'});
    expect(sweep, hasLength(3));
  });

  group('a placement run', () {
    final streets = [
      _street('a1', tier: StreetTier.a, length: 900),
      _street('a2', tier: StreetTier.a, length: 800),
      for (var i = 0; i < 8; i++)
        _street('r1b$i', tier: StreetTier.b, chunk: 'c1'),
      for (var i = 0; i < 6; i++)
        _street('r2b$i', tier: StreetTier.b, chunk: 'c3'),
    ];
    final curriculum = _curriculum(streets);

    test('skips carded streets; a raion sample that passes sweeps the '
        'rest of its grid right after it', () {
      final run = Placement(curriculum, seed: 3, carded: {'a2'});
      expect(run.streets.take(1), ['a1']);
      expect(run.streets, isNot(contains('a2')));
      expect(run.streets, hasLength(11));
      expect(run.answer('a1', Rating.good), isEmpty);
      final r1 = run.streets.where((id) => id.startsWith('r1')).toList();
      expect(run.answer(r1[0], Rating.good), isEmpty);
      expect(run.answer(r1[1], null), isEmpty);
      expect(run.answer(r1[2], Rating.good), isEmpty);
      expect(run.answer(r1[3], Rating.good), isEmpty);
      final sweep = run.answer(r1[4], Rating.good);
      expect(sweep, hasLength(3));
      expect({...sweep, ...r1}, {for (var i = 0; i < 8; i++) 'r1b$i'});
      expect(run.streets.indexOf(sweep.first), run.streets.indexOf(r1[4]) + 1);
      expect(run.answer(sweep.first, Rating.good), isEmpty);
      expect(run.mainRoads, (passed: 1, of: 1));
      expect(run.raions, 2);
      expect(run.passed, 6);
    });

    test('a sample with two misses sweeps nothing; Hard is not a pass', () {
      final run = Placement(curriculum, seed: 3);
      final r2 = run.streets.where((id) => id.startsWith('r2')).toList();
      final ratings = [Rating.good, Rating.hard, Rating.again, Rating.good];
      for (var i = 0; i < 4; i++) {
        expect(run.answer(r2[i], ratings[i]), isEmpty);
      }
      expect(run.answer(r2[4], Rating.good), isEmpty);
      expect(run.passed, 3);
    });
  });

  test('areaCounts: neighbourhoods and raions all Mastered, raions with a '
      'Known street; leeches cleared once one was', () {
    CardState card(String id, double stability) => CardState(
      itemId: CardType.p.item(id),
      phase: CardPhase.review,
      memory: Memory(
        stability: stability,
        difficulty: 5,
        lastReview: _now.subtract(const Duration(days: 1)),
      ),
      lastRating: Rating.good,
      introAt: _now.subtract(const Duration(days: 30)),
    );
    final streets = [
      _street('m1', chunk: 'c1'),
      _street('m2', chunk: 'c1'),
      _street('k1', chunk: 'c3'),
      _street('u1', chunk: 'c3'),
    ];
    expect(
      areaCounts(
        streets: streets,
        districts: _chunks,
        cards: {
          'm1': card('m1', 95),
          'm2': card('m2', 120),
          'k1': card('k1', 10),
        },
        now: _now,
      ),
      (masteredRaions: 1, masteredNeighbourhoods: 1, knownRaions: 2),
    );
    final lapsed = CardState(
      itemId: 'P:x',
      phase: CardPhase.review,
      lapses: LearningConfig.leechLapses,
    );
    expect(leechesCleared([card('m1', 95)]), isFalse);
    expect(leechesCleared([lapsed]), isTrue);
    expect(
      leechesCleared([
        lapsed,
        const CardState(itemId: 'P:y', phase: CardPhase.suspended),
      ]),
      isFalse,
    );
  });

  test('a pack without curriculum columns teaches longest first', () {
    final curriculum = _curriculum([
      _street('x', tier: null, chunk: null, length: 200),
      _street('y', tier: null, chunk: null, length: 700),
    ]);
    expect(_next(curriculum), ['y', 'x']);
  });

  group('name and ends cards (SPEC §3)', () {
    final curriculum = _curriculum(
      [
        _street('a', tier: StreetTier.a, length: 2000),
        _street('b', tier: StreetTier.b),
        _street('p'),
        _street('p1'),
        _street('long', length: 1500),
      ],
      families: [_child('p', 'p1', 1)],
    );

    test('a name card for tiers A and B and family parents, an ends card '
        'past 1.2 km', () {
      expect(curriculum.sideTypesOf('a'), [CardType.n, CardType.e]);
      expect(curriculum.sideTypesOf('b'), [CardType.n]);
      expect(curriculum.sideTypesOf('p'), [CardType.n]);
      expect(curriculum.sideTypesOf('p1'), isEmpty);
      expect(curriculum.sideTypesOf('long'), [CardType.e]);
    });

    test('a name opens after the pin card'
        's two retrievals or when known '
        'before, ends at 7 days; most stable first', () {
      Map<String, CardState> byItem(List<CardState> cards) => {
        for (final c in cards) c.itemId: c,
      };
      expect(
        curriculum.openSides(
          byItem([
            _card('a', stability: 6.9, reps: 1),
            _card('b', stability: 2, reps: 2),
            _card('p', stability: 3, reps: 1, priorKnown: true),
            _card('long', stability: 7, reps: 4),
          ]),
        ),
        ['E:long', 'N:p', 'N:b'],
      );
      final named = CardState(itemId: 'N:b', phase: CardPhase.review);
      expect(
        curriculum.openSides(byItem([_card('b', stability: 9), named])),
        isEmpty,
        reason: 'b already has its name card',
      );
      expect(curriculum.sidesOf('a', byItem([named, _card('a')])), [
        null,
        null,
      ]);
    });
  });

  group('drills (SPEC §7)', () {
    final lanes = [for (var n = 1; n <= 7; n++) _street('p$n')];
    final curriculum = _curriculum(
      [_street('p'), ...lanes],
      families: [for (var n = 1; n <= 7; n++) _child('p', 'p$n', n)],
    );
    CardState dueIn(String id, int days) => CardState(
      itemId: CardType.p.item(id),
      phase: CardPhase.review,
      memory: Memory(stability: 5, difficulty: 5, lastReview: _now),
      dueAt: _now.add(Duration(days: days)),
      lastRating: Rating.good,
    );

    test('a family sweep needs 3 children due within 2 days', () {
      FamilySweep? sweep(Map<String, CardState> cards) =>
          familySweep(curriculum: curriculum, cards: cards, now: _now);
      expect(
        sweep({
          'p1': dueIn('p1', 0),
          'p2': dueIn('p2', 1),
          'p3': dueIn('p3', 3),
        }),
        isNull,
      );
      final cards = {
        for (var n = 1; n <= 7; n++) 'p$n': dueIn('p$n', n == 7 ? 5 : 0),
      };
      final s = sweep(cards)!;
      expect(s.parentId, 'p');
      expect(s.children, hasLength(LearningConfig.familySweepMax));
      expect(s.children, isNot(contains('P:p7')));
    });

    test('bearings need a raion whose grid is half Solid', () {
      CardState solid(String id) => _card(id, stability: 30);
      final grid = [
        for (var i = 0; i < 4; i++)
          NamedStreet([
            Street(
              id: 'g$i',
              nameKa: 'g$i',
              nameEn: null,
              roadClass: 'secondary',
              difficulty: Difficulty.expert,
              lengthM: 400,
              midpoint: LatLng(_centre.lat + 0.02 * (i + 1), _centre.lon),
              bbox: const Bbox(41.7, 44.8, 41.8, 44.8),
              geometry: const [],
              tier: StreetTier.b,
              chunkId: 'c2',
            ),
          ]),
      ];
      final c = _curriculum(grid);
      List<String> targets(Map<String, CardState> cards) => bearingTargets(
        curriculum: c,
        streets: grid.toSet(),
        cards: cards,
        centre: _centre,
        random: Random(1),
      );
      expect(targets({'g0': solid('g0')}), isEmpty);
      final t = targets({'g0': solid('g0'), 'g1': solid('g1')});
      expect(t, isNotEmpty);
      expect(t.toSet().difference({'g0', 'g1'}), isEmpty);
    });
  });
}
