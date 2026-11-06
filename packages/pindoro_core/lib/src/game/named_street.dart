import '../geo/geo.dart';
import '../pack/models.dart';
import '../scoring/scoring.dart';

/// Nearby pack rows sharing a `name_ka`: one street to the player. The
/// pipeline splits same-name parts more than 30 m apart into separate rows.
class NamedStreet {
  /// [parts] longest first, all with the same `name_ka`.
  NamedStreet(this.parts) : assert(parts.isNotEmpty);

  final List<Street> parts;

  /// The longest part's stable id; any part's id resolves to this street.
  String get id => parts.first.id;

  String get name => parts.first.nameKa;

  String? get nameEn => parts.map((p) => p.nameEn).nonNulls.firstOrNull;

  double get lengthM => parts.fold(0, (sum, p) => sum + p.lengthM);

  MultiPolyline get geometry => [for (final p in parts) ...p.geometry];

  /// The part nearest to [pin], the distance to it and the closest point on it.
  ({Street part, double distanceM, LatLng nearestPoint}) nearest(LatLng pin) {
    ({Street part, double distanceM, LatLng nearestPoint})? best;
    for (final part in parts) {
      final d = pointToPolylineDistance(pin, part.geometry);
      if (best == null || d.distanceMeters < best.distanceM) {
        best = (
          part: part,
          distanceM: d.distanceMeters,
          nearestPoint: d.nearestPoint,
        );
      }
    }
    return best!;
  }

  /// Scores a pin against the nearest part, using that part's road class.
  Score score(LatLng pin, Difficulty difficulty) {
    final n = nearest(pin);
    return scoreAnswer(n.distanceM, n.part.roadClass, difficulty);
  }
}

/// Same-name parts with an end within this of each other are one street;
/// farther apart they're different streets sharing a name (e.g. one per
/// suburb). ponytail: end-to-line distance, misses parts that only run side by
/// side; compare whole lines if that shows up.
const double sameStreetMaxGapM = 500;

/// Groups streets by exact `name_ka` and nearness; each group's parts longest
/// first.
List<NamedStreet> groupByName(Iterable<Street> streets) {
  final byName = <String, List<Street>>{};
  for (final s in streets) {
    byName.putIfAbsent(s.nameKa, () => []).add(s);
  }
  return [
    for (final parts in byName.values)
      for (final group in _nearbyGroups(parts))
        NamedStreet(group..sort((a, b) => b.lengthM.compareTo(a.lengthM))),
  ];
}

List<List<Street>> _nearbyGroups(List<Street> parts) {
  final groups = <List<Street>>[];
  for (final s in parts) {
    final touching = [
      for (final g in groups)
        if (g.any((p) => _endNear(p, s) || _endNear(s, p))) g,
    ];
    groups
      ..removeWhere(touching.contains)
      ..add([s, for (final g in touching) ...g]);
  }
  return groups;
}

bool _endNear(Street a, Street b) => a.geometry.any(
  (line) => [line.first, line.last].any(
    (end) =>
        pointToPolylineDistance(end, b.geometry).distanceMeters <=
        sameStreetMaxGapM,
  ),
);
