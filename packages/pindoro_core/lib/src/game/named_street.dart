import '../geo/geo.dart';
import '../pack/models.dart';
import '../scoring/scoring.dart';

/// Every pack row sharing a `name_ka`: one street to the player. The pipeline
/// splits same-name parts more than 30 m apart into separate rows.
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

/// Groups streets by exact `name_ka`; each group's parts longest first.
List<NamedStreet> groupByName(Iterable<Street> streets) {
  final byName = <String, List<Street>>{};
  for (final s in streets) {
    byName.putIfAbsent(s.nameKa, () => []).add(s);
  }
  return [
    for (final parts in byName.values)
      NamedStreet(parts..sort((a, b) => b.lengthM.compareTo(a.lengthM))),
  ];
}
