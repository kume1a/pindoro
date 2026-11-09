import 'package:pindoro_core/pindoro_core.dart';

/// About 200 m between neighbouring junctions at Tbilisi's latitude.
const double gridLat = 0.0018;
const double gridLon = 0.0024;

/// An [n] × [n] street grid: junction `r * n + c` at row r (north is higher)
/// and column c; row r is street `row<r>`, column c street `col<c>`.
/// [skip] drops edges by id.
({RoadGraph graph, Map<String, NamedStreet> streets}) roadGrid(
  int n, {
  Set<int> skip = const {},
}) {
  LatLng at(int r, int c) => LatLng(41.7 + r * gridLat, 44.8 + c * gridLon);
  final junctions = {
    for (var r = 0; r < n; r++)
      for (var c = 0; c < n; c++) r * n + c: at(r, c),
  };
  final edges = <RoadEdge>[];
  var next = 0;
  void add(int from, int to, String street) {
    final id = next++;
    final a = junctions[from]!, b = junctions[to]!;
    if (skip.contains(id)) return;
    edges.add(
      RoadEdge(
        id: id,
        from: from,
        to: to,
        streetId: street,
        lengthM: distanceBetween(a, b),
        line: [a, b],
      ),
    );
  }

  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      if (c + 1 < n) add(r * n + c, r * n + c + 1, 'row$r');
      if (r + 1 < n) add(r * n + c, (r + 1) * n + c, 'col$c');
    }
  }
  NamedStreet street(String id, LatLng from, LatLng to) => NamedStreet([
    Street(
      id: id,
      nameKa: id,
      nameEn: null,
      roadClass: 'residential',
      difficulty: Difficulty.expert,
      lengthM: distanceBetween(from, to),
      midpoint: LatLng((from.lat + to.lat) / 2, (from.lon + to.lon) / 2),
      bbox: Bbox.of([from, to]),
      geometry: [
        [from, to],
      ],
    ),
  ]);
  return (
    graph: RoadGraph(junctions, edges),
    streets: {
      for (var i = 0; i < n; i++) ...{
        'row$i': street('row$i', at(i, 0), at(i, n - 1)),
        'col$i': street('col$i', at(0, i), at(n - 1, i)),
      },
    },
  );
}
