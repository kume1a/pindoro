import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:sqlite3/sqlite3.dart';

const _fixture =
    '../../apps/mobile/assets/packs_fixture/tbilisi_vake_fixture.sqlite';

/// The app's bundled Vake pack, read as the app reads it.
class Vake {
  Vake._({
    required this.graph,
    required this.nodes,
    required this.streets,
    required this.curriculum,
    required this.items,
    required this.landmarks,
  });

  factory Vake.load() {
    final db = sqlite3.open(_fixture, mode: OpenMode.readOnly);
    try {
      final neighbours = <String, Set<String>>{};
      for (final r in db.select(
        'SELECT chunk_a, chunk_b FROM chunk_neighbour',
      )) {
        neighbours
            .putIfAbsent(r['chunk_a'] as String, () => {})
            .add(r['chunk_b'] as String);
      }
      final streets = streetsByPartId([
        for (final r in db.select('SELECT * FROM street')) Street.fromRow(r),
      ]);
      return Vake._(
        graph: RoadGraph(
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
        ),
        nodes: {
          for (final r in db.select('SELECT id, node_id FROM junction'))
            r['id'] as int: r['node_id'] as int,
        },
        streets: streets,
        curriculum: Curriculum(
          streets: streets.values,
          districts: [
            for (final r in db.select('SELECT * FROM district'))
              District.fromRow(r),
          ],
          centre: City.fromRow(db.select('SELECT * FROM city').first).center,
          families: [
            for (final r in db.select('SELECT * FROM family'))
              familyLinkFromRow(r),
          ],
          chunkNeighbours: neighbours,
        ),
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
      );
    } finally {
      db.close();
    }
  }

  final RoadGraph graph;

  /// OSM node ids by pack junction id.
  final Map<int, int> nodes;

  /// By part id.
  final Map<String, NamedStreet> streets;
  final Curriculum curriculum;
  final List<JunctionItem> items;
  final List<Landmark> landmarks;

  late final RouteBook book = buildRouteBook(
    graph: graph,
    junctionNodes: nodes,
    items: items,
    landmarks: landmarks,
    bridges: const [],
    streets: streets,
    curriculum: curriculum,
  );
}
