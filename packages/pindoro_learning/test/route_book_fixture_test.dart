import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _fixture =
    '../../apps/mobile/assets/packs_fixture/tbilisi_vake_fixture.sqlite';

void main() {
  late RouteBook book;
  late RoadGraph graph;
  late Map<int, int> nodes;

  setUpAll(() {
    final db = sqlite3.open(_fixture, mode: OpenMode.readOnly);
    try {
      final streets = streetsByPartId([
        for (final r in db.select('SELECT * FROM street')) Street.fromRow(r),
      ]);
      graph = RoadGraph(
        {
          for (final r in db.select('SELECT id, lat, lon FROM junction'))
            r['id'] as int: LatLng(
              (r['lat'] as num).toDouble(),
              (r['lon'] as num).toDouble(),
            ),
        },
        [
          for (final r in db.select('SELECT * FROM road_edge'))
            RoadEdge.fromRow(r),
        ],
        restrictions: [
          for (final r in db.select('SELECT * FROM turn_restriction'))
            (
              fromEdge: r['from_edge'] as int,
              via: r['via_junction'] as int,
              toEdge: r['to_edge'] as int,
              only: r['only'] == 1,
            ),
        ],
      );
      nodes = {
        for (final r in db.select('SELECT id, node_id FROM junction'))
          r['id'] as int: r['node_id'] as int,
      };
      final districts = [
        for (final r in db.select('SELECT * FROM district'))
          District.fromRow(r),
      ];
      book = buildRouteBook(
        graph: graph,
        junctionNodes: nodes,
        items: [
          for (final r in db.select(
            'SELECT * FROM junction_item ORDER BY rank',
          ))
            JunctionItem.fromRow(r),
        ],
        landmarks: [
          for (final r in db.select('SELECT * FROM landmark'))
            Landmark.fromRow(r),
        ],
        bridges: const [],
        streets: streets,
        curriculum: Curriculum(
          streets: streets.values,
          districts: districts,
          centre: City.fromRow(db.select('SELECT * FROM city').first).center,
          families: [
            for (final r in db.select('SELECT * FROM family'))
              familyLinkFromRow(r),
          ],
        ),
      );
    } finally {
      db.close();
    }
  });

  test('every J card offers only the junction\'s legal exits, the right one '
      'among them (PLAN M5 accept)', () {
    final turns = book.questions.values.whereType<TurnQuestion>().toList();
    expect(turns, isNotEmpty);
    for (final q in turns) {
      final legal = {
        for (final e in graph.legalExits(q.junction, approach: q.approach))
          e.id,
      };
      expect(q.exits.values.every((e) => legal.contains(e.id)), isTrue);
      expect(q.exits[q.correct], isNotNull);
      expect(q.exits.length, greaterThanOrEqualTo(2));
      expect(q.itemId, startsWith('J:n${nodes[q.junction]}:n'));
    }
  });

  test('the book holds gateways, connections and landmark cards, each with '
      'what opens it', () {
    final types = {for (final id in book.questions.keys) CardType.ofItem(id)};
    expect(
      types,
      containsAll([CardType.j, CardType.g, CardType.c, CardType.l]),
    );
    expect(
      book.candidates.map((c) => c.itemId).toSet(),
      book.questions.keys.toSet(),
    );
    final l2 = book.questions.values.whereType<LandmarkQuestion>().firstWhere(
      (q) => q.n == 2,
    );
    expect(l2.junctions, contains(l2.junction));
  });
}
