import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

const _centre = LatLng(41.7, 44.8);
final _now = DateTime(2026, 3, 2, 9);

NamedStreet _street(String id, StreetTier tier, {String chunk = 'c1'}) =>
    NamedStreet([
      Street(
        id: id,
        nameKa: id,
        nameEn: null,
        roadClass: 'residential',
        difficulty: Difficulty.expert,
        lengthM: 400,
        midpoint: _centre,
        bbox: const Bbox(41.7, 44.8, 41.7, 44.8),
        geometry: const [],
        tier: tier,
        chunkId: chunk,
      ),
    ]);

District _chunk(String id) => District(
  id: id,
  kind: DistrictKind.neighbourhood,
  osmRelationId: null,
  nameKa: id,
  nameEn: null,
  center: _centre,
  bbox: const Bbox(41.69, 44.79, 41.71, 44.81),
  areaM2: 1e6,
  boundary: const [],
  parentId: 'r1',
);

CardState _card(String street, {double stability = 10}) => CardState(
  itemId: CardType.p.item(street),
  phase: CardPhase.review,
  memory: Memory(
    stability: stability,
    difficulty: 5,
    lastReview: _now.subtract(const Duration(days: 1)),
  ),
  dueAt: _now.add(const Duration(days: 9)),
  lastRating: Rating.good,
  priorKnown: true,
);

RouteCandidate _candidate(
  String id,
  RouteLayer layer, {
  Set<String> known = const {},
  String? raion,
  String? chunk,
  bool phase2 = false,
  bool personal = false,
  int rank = 1,
}) => (
  itemId: id,
  layer: layer,
  rank: rank,
  known: known,
  raion: raion,
  chunk: chunk,
  phase2: phase2,
  personal: personal,
);

void main() {
  test('a pin anywhere in a park is on it; outside, it is measured to the '
      'edge (SPEC §16.18 item 95)', () {
    const at = LatLng(41.7, 44.8);
    const ring = [
      LatLng(41.699, 44.799),
      LatLng(41.699, 44.801),
      LatLng(41.701, 44.801),
      LatLng(41.701, 44.799),
      LatLng(41.699, 44.799),
    ];
    LandmarkQuestion place({List<List<Polyline>>? outline}) => LandmarkQuestion(
      'L:p:1',
      n: 1,
      landmark: (
        id: 'p',
        name: 'Park',
        nameEn: null,
        kind: 'park',
        at: at,
        personal: false,
        junction: null,
        onLeft: false,
      ),
      outline: outline,
    );
    const corner = LatLng(41.7009, 44.8009);
    expect(
      place(
        outline: const [
          [ring],
        ],
      ).distanceFrom(corner).distanceM,
      0,
    );
    const east = LatLng(41.7, 44.802);
    final out = place(
      outline: const [
        [ring],
      ],
    ).distanceFrom(east);
    expect(
      out.distanceM,
      closeTo(distanceBetween(east, const LatLng(41.7, 44.801)), 0.5),
    );
    expect(place().distanceFrom(corner).distanceM, greaterThan(100));
  });

  test(
    'turns: within 30° straight, past 150° a U-turn, else left or right',
    () {
      expect(turnOf(0, 20), Turn.straight);
      expect(turnOf(350, 80), Turn.right);
      expect(turnOf(90, 0), Turn.left);
      expect(turnOf(0, 175), Turn.uTurn);
    },
  );

  test('route item ids are built from stable OSM ids', () {
    expect(RouteIds.junction(12, 34, 56), 'J:n12:n34:n56');
    expect(RouteIds.gateway('osm:w9', 12, out: true), 'G:osm:w9:n12:out');
    expect(RouteIds.bridge('w7', 'L', 12), 'B:w7:L:n12');
    expect(RouteIds.landmark('osm:n5', 2), 'L:osm:n5:2');
    expect(CardType.ofItem(RouteIds.connection('s1')), CardType.c);
  });

  group('unlocks (SPEC §3)', () {
    final curriculum = Curriculum(
      streets: [
        _street('a1', StreetTier.a),
        _street('a2', StreetTier.a),
        _street('b1', StreetTier.b),
        _street('b2', StreetTier.b),
        _street('c1', StreetTier.c),
        _street('c2', StreetTier.c),
      ],
      districts: [_chunk('c1')],
      centre: _centre,
    );
    List<String> open(
      Map<String, CardState> cards,
      List<RouteCandidate> candidates, {
      Set<String> carded = const {},
      bool phase2Open = false,
    }) => curriculum.openRoutes(
      candidates,
      cards: cards,
      carded: carded,
      now: _now,
      phase2Open: phase2Open,
    );

    test('bridges wait for every tier A street; turns for Known streets', () {
      final candidates = [
        _candidate('B:x', RouteLayer.bridge),
        _candidate('J:s', RouteLayer.skeleton, known: {'a1', 'a2'}),
      ];
      expect(open({'a1': _card('a1')}, candidates), isEmpty);
      expect(open({'a1': _card('a1'), 'a2': _card('a2')}, candidates), [
        'B:x',
        'J:s',
      ]);
      expect(
        open(
          {'a1': _card('a1'), 'a2': _card('a2')},
          candidates,
          carded: {'B:x'},
        ),
        ['J:s'],
      );
    });

    test('district turns need the raion\'s grid 80 % Solid', () {
      final turn = [
        _candidate('J:d', RouteLayer.district, known: {'c1'}, raion: 'r1'),
      ];
      final known = {'c1': _card('c1'), 'b1': _card('b1', stability: 30)};
      expect(open(known, turn), isEmpty);
      expect(open({...known, 'b2': _card('b2', stability: 30)}, turn), ['J:d']);
    });

    test('gateways need 70 % of the chunk\'s main streets Known; the way in '
        'waits for phase 2', () {
      final cards = {
        for (final s in ['a1', 'a2', 'b1', 'b2', 'c1']) s: _card(s),
      };
      final out = _candidate('G:out', RouteLayer.gateway, chunk: 'c1');
      final into = _candidate(
        'G:in',
        RouteLayer.gateway,
        chunk: 'c1',
        phase2: true,
      );
      expect(open({'a1': _card('a1')}, [out]), isEmpty);
      expect(open(cards, [out, into]), ['G:out']);
      expect(open(cards, [out, into], phase2Open: true), ['G:in', 'G:out']);
    });

    test('a turn or place with no named street to know stays shut', () {
      expect(
        open(
          {'a1': _card('a1')},
          [
            _candidate('J:s', RouteLayer.skeleton),
            _candidate('L:n1:1', RouteLayer.landmark),
          ],
        ),
        isEmpty,
      );
    });

    test('a place\'s L2 and L3 wait for its L1 to be Known', () {
      final place = [
        for (final n in [1, 2, 3])
          _candidate('L:n1:$n', RouteLayer.landmark, known: {'a1'}, rank: n),
      ];
      final streets = {'a1': _card('a1')};
      expect(open(streets, place), ['L:n1:1']);
      final l1 = CardState(
        itemId: 'L:n1:1',
        phase: CardPhase.review,
        memory: Memory(
          stability: 10,
          difficulty: 5,
          lastReview: _now.subtract(const Duration(days: 2)),
        ),
        dueAt: _now.add(const Duration(days: 8)),
        lastRating: Rating.good,
        priorKnown: true,
      );
      expect(
        curriculum.openRoutes(
          place,
          cards: streets,
          carded: {'L:n1:1'},
          items: {'L:n1:1': l1},
          now: _now,
        ),
        ['L:n1:2', 'L:n1:3'],
      );
    });

    test('a personal landmark opens at once', () {
      expect(
        open(const {}, [
          _candidate('L:me:1:1', RouteLayer.landmark, personal: true),
        ]),
        ['L:me:1:1'],
      );
    });
  });

  test('grading (SPEC §5.2)', () {
    expect(RouteGrader.turn(exitRight: false), Rating.again);
    expect(RouteGrader.turn(exitRight: true), Rating.good);
    expect(RouteGrader.turn(exitRight: true, streetAsked: true), Rating.hard);
    expect(RouteGrader.turn(exitRight: true, streetRight: false), Rating.hard);
    expect(RouteGrader.turn(exitRight: true, streetRight: true), Rating.good);
    expect(RouteGrader.gateway(distanceM: 40, streetRight: true), Rating.good);
    expect(RouteGrader.gateway(distanceM: 90, streetRight: true), Rating.hard);
    expect(
      RouteGrader.gateway(distanceM: 90, streetRight: false),
      Rating.again,
    );
    expect(RouteGrader.point(15).tier, Tier.perfect);
    expect(RouteGrader.point(150).rating, Rating.again);
    expect(RouteGrader.tierOf(Rating.hard), Tier.close);
  });
}
