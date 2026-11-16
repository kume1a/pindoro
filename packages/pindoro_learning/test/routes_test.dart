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

CardState _card(String street, {double stability = 10, String? item}) =>
    CardState(
      itemId: item ?? CardType.p.item(street),
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
  Set<String> knownCards = const {},
  Set<String> solidCards = const {},
}) => (
  itemId: id,
  layer: layer,
  rank: rank,
  known: known,
  raion: raion,
  chunk: chunk,
  phase2: phase2,
  personal: personal,
  knownCards: knownCards,
  solidCards: solidCards,
);

void main() {
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
    expect(RouteIds.scene('m123', 2), 'S2:m123');
    expect(CardType.ofItem(RouteIds.scene('p9', 3)), CardType.s3);
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
      Map<String, CardState> items = const {},
      bool phase2Open = false,
    }) => curriculum.openRoutes(
      candidates,
      cards: cards,
      carded: carded,
      now: _now,
      items: items,
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

    test('street photos wait for their cards: S1 its street\'s pin and name '
        'Solid in phase 2, S2 its turn Known, S3 its raion\'s grid Solid', () {
      final photos = [
        _candidate(
          'S1:m1',
          RouteLayer.scene,
          known: {'b1'},
          phase2: true,
          solidCards: {'P:b1', 'N:b1'},
        ),
        _candidate(
          'S2:m1',
          RouteLayer.scene,
          known: {'b1'},
          knownCards: {'J:x'},
        ),
        _candidate('S3:m1', RouteLayer.scene, known: {'b1'}, raion: 'r1'),
      ];
      final b1 = _card('b1', stability: 30);
      final cards = {'b1': b1};
      final grid = {...cards, 'b2': _card('b2', stability: 30)};
      final items = {
        'P:b1': b1,
        'N:b1': _card('b1', stability: 30, item: 'N:b1'),
        'J:x': _card('b1', item: 'J:x'),
      };
      expect(open(cards, photos), isEmpty);
      expect(open(grid, photos), ['S3:m1']);
      expect(open(grid, photos, items: items), ['S2:m1', 'S3:m1']);
      expect(open(grid, photos, items: items, phase2Open: true), [
        'S1:m1',
        'S2:m1',
        'S3:m1',
      ]);
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
    expect(
      RouteGrader.scenePlace(distanceM: 60, headingOffDeg: 30),
      Rating.good,
    );
    expect(
      RouteGrader.scenePlace(distanceM: 160, headingOffDeg: 30),
      Rating.hard,
    );
    expect(
      RouteGrader.scenePlace(distanceM: 60, headingOffDeg: 90),
      Rating.hard,
    );
    expect(
      RouteGrader.scenePlace(distanceM: 160, headingOffDeg: 90),
      Rating.again,
    );
  });

  test('street photos aim for 85 % recall, so they wait longer (SPEC §4)', () {
    expect(retentionOf(CardType.s2), LearningConfig.retentionScene);
    expect(retentionOf(CardType.p), LearningConfig.retentionDefault);
    final now = DateTime(2026, 3, 2);
    DateTime due(String item) => applyReview(
      null,
      itemId: item,
      rating: Rating.good,
      now: now,
      format: ReviewFormat.review,
      source: ReviewSource.session,
    ).card.dueAt!;
    expect(due('S1:m1').isAfter(due('C:m1')), isTrue);
  });
}
