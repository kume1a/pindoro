import 'package:pindoro_core/pindoro_core.dart';

/// A small road network for the recital and drive tests: junctions placed in metres east and
/// north of a point in Tbilisi, edges of named streets (one part each) or connectors.
class RoadNet {
  static const LatLng origin = LatLng(41.70, 44.75);

  final Map<int, LatLng> at = {};
  final List<RoadEdge> edges = [];
  final Map<String, ({String ka, String en})> _names = {};
  final Map<String, List<RoadEdge>> _byStreet = {};

  /// The point [east], [north] metres from [origin].
  static LatLng point(double east, double north) =>
      LocalProjection(origin).unproject((east, north));

  void junction(int id, double east, double north) =>
      at[id] = point(east, north);

  void street(String key, String ka, String en) =>
      _names[key] = (ka: ka, en: en);

  RoadEdge edge(
    int id,
    int from,
    int to,
    String? street, {
    double? m,
    Oneway oneway = Oneway.both,
  }) {
    final line = [at[from]!, at[to]!];
    final e = RoadEdge(
      id: id,
      from: from,
      to: to,
      streetId: street == null ? null : 'e$id',
      lengthM: m ?? distanceBetween(line.first, line.last),
      line: line,
      oneway: oneway,
    );
    edges.add(e);
    if (street != null) _byStreet.putIfAbsent(street, () => []).add(e);
    return e;
  }

  RoadGraph graph({List<TurnRestriction> restrictions = const []}) =>
      RoadGraph(at, edges, restrictions: restrictions);

  /// The named streets by key.
  late final Map<String, NamedStreet> named = {
    for (final MapEntry(:key, :value) in _byStreet.entries)
      key: NamedStreet([
        for (final e in value)
          Street(
            id: e.streetId!,
            nameKa: _names[key]!.ka,
            nameEn: _names[key]!.en,
            roadClass: 'residential',
            difficulty: Difficulty.medium,
            lengthM: e.lengthM,
            midpoint: e.line.first,
            bbox: Bbox.of(e.line),
            geometry: [e.line],
          ),
      ]),
  };

  /// The named streets by part id.
  Map<String, NamedStreet> get byPart => {
    for (final s in named.values)
      for (final p in s.parts) p.id: s,
  };
}
