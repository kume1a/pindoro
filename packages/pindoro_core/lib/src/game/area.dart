import 'dart:convert';
import 'dart:math' as math;

import '../geo/geo.dart';
import '../pack/models.dart';
import '../pack/pack_repository.dart';
import '../scoring/scoring.dart';

/// Outline of an area for framing the map and dimming outside it. [name] is
/// the districts' names joined; null for circles and rectangles.
typedef AreaShape = ({String? name, Bbox bbox, List<List<Polyline>> boundary});

/// A part is in an area when at least this much of it lies inside...
const double inAreaMinLengthM = 150;

/// ...or at least this share of it (the pipeline's `street_district` rule).
const double inAreaMinShare = 0.3;

/// What a round covers: some districts of the pack, a circle or a rectangle.
sealed class Area {
  const Area();

  /// Parses `user_settings.last_area_json` / `round.area_json`; the M1
  /// one-district form still reads. Throws [FormatException] otherwise.
  factory Area.fromJson(Map<String, Object?> json) => switch (json) {
    {'kind': 'districts', 'ids': final List<Object?> ids} => DistrictsArea(
      ids.cast<String>().toSet(),
    ),
    {'kind': 'district', 'district_id': final String id} => DistrictsArea({id}),
    {
      'kind': 'circle',
      'lat': final num lat,
      'lon': final num lon,
      'radius_m': final num radius,
    } =>
      CircleArea(LatLng(lat.toDouble(), lon.toDouble()), radius.toDouble()),
    {
      'kind': 'rect',
      'min_lat': final num minLat,
      'min_lon': final num minLon,
      'max_lat': final num maxLat,
      'max_lon': final num maxLon,
    } =>
      RectArea(
        Bbox(
          minLat.toDouble(),
          minLon.toDouble(),
          maxLat.toDouble(),
          maxLon.toDouble(),
        ),
      ),
    _ => throw FormatException('Not an area: $json'),
  };

  Map<String, Object?> toJson();

  /// Null when the pack lacks a picked district (e.g. the offline fixture).
  AreaShape? shapeIn(PackRepository pack);

  /// Pack streets at [difficulties] with ≥ [inAreaMinLengthM] or
  /// ≥ [inAreaMinShare] of their length inside the area.
  List<Street> streetsIn(PackRepository pack, Set<Difficulty> difficulties);

  @override
  bool operator ==(Object other) =>
      other is Area && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

final class DistrictsArea extends Area {
  const DistrictsArea(this.ids);

  final Set<String> ids;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'districts',
    'ids': ids.toList()..sort(),
  };

  @override
  AreaShape? shapeIn(PackRepository pack) {
    final picked = [
      for (final d in pack.districts())
        if (ids.contains(d.id)) d,
    ];
    if (picked.isEmpty || picked.length < ids.length) return null;
    return (
      name: picked.map((d) => d.nameKa).join(', '),
      bbox: Bbox.of([
        for (final d in picked) ...[
          LatLng(d.bbox.minLat, d.bbox.minLon),
          LatLng(d.bbox.maxLat, d.bbox.maxLon),
        ],
      ]),
      boundary: [for (final d in picked) ...d.boundary],
    );
  }

  /// The pipeline already applied the in-area rule to `street_district`.
  @override
  List<Street> streetsIn(PackRepository pack, Set<Difficulty> difficulties) {
    final byId = <String, Street>{};
    for (final id in ids) {
      for (final s in pack.streets(
        districtId: id,
        difficulties: difficulties,
      )) {
        byId[s.id] = s;
      }
    }
    return byId.values.toList();
  }
}

/// A shape drawn on the map rather than taken from the pack.
sealed class DrawnArea extends Area {
  const DrawnArea();

  Bbox get bbox;

  List<Polyline> get ring;

  bool contains(LatLng p);

  @override
  AreaShape shapeIn(PackRepository pack) =>
      (name: null, bbox: bbox, boundary: [ring]);

  @override
  List<Street> streetsIn(PackRepository pack, Set<Difficulty> difficulties) => [
    for (final s in pack.streets(difficulties: difficulties))
      if (s.bbox.intersects(bbox) && _counts(s)) s,
  ];

  bool _counts(Street s) {
    final inside = lengthInside(s.geometry, contains);
    return inside >= inAreaMinLengthM || inside >= inAreaMinShare * s.lengthM;
  }
}

final class CircleArea extends DrawnArea {
  const CircleArea(this.center, this.radiusM);

  static const double minRadiusM = 500;
  static const double maxRadiusM = 5000;
  static const int _ringPoints = 64;

  final LatLng center;
  final double radiusM;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'circle',
    'lat': center.lat,
    'lon': center.lon,
    'radius_m': radiusM,
  };

  @override
  List<Polyline> get ring {
    final proj = LocalProjection(center);
    final points = [
      for (var i = 0; i < _ringPoints; i++)
        proj.unproject((
          radiusM * math.cos(2 * math.pi * i / _ringPoints),
          radiusM * math.sin(2 * math.pi * i / _ringPoints),
        )),
    ];
    return [
      [...points, points.first],
    ];
  }

  @override
  Bbox get bbox => Bbox.of(ring.first);

  @override
  bool contains(LatLng p) => distanceBetween(center, p) <= radiusM;
}

final class RectArea extends DrawnArea {
  const RectArea(this.bounds);

  static const double minSideM = 500;
  static const double maxSideM = 10000;

  final Bbox bounds;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'rect',
    'min_lat': bounds.minLat,
    'min_lon': bounds.minLon,
    'max_lat': bounds.maxLat,
    'max_lon': bounds.maxLon,
  };

  @override
  List<Polyline> get ring => [
    [
      LatLng(bounds.minLat, bounds.minLon),
      LatLng(bounds.minLat, bounds.maxLon),
      LatLng(bounds.maxLat, bounds.maxLon),
      LatLng(bounds.maxLat, bounds.minLon),
      LatLng(bounds.minLat, bounds.minLon),
    ],
  ];

  @override
  Bbox get bbox => bounds;

  @override
  bool contains(LatLng p) => bounds.contains(p);
}

/// Metres of [geometry] inside a shape: each segment is walked in steps of at
/// most [stepM] and a step counts when its midpoint is inside.
double lengthInside(
  MultiPolyline geometry,
  bool Function(LatLng) contains, {
  double stepM = 25,
}) {
  var inside = 0.0;
  for (final line in geometry) {
    for (var i = 0; i + 1 < line.length; i++) {
      final a = line[i], b = line[i + 1];
      final length = distanceBetween(a, b);
      final steps = math.max(1, (length / stepM).ceil());
      for (var k = 0; k < steps; k++) {
        final t = (k + 0.5) / steps;
        final mid = LatLng(
          a.lat + (b.lat - a.lat) * t,
          a.lon + (b.lon - a.lon) * t,
        );
        if (contains(mid)) inside += length / steps;
      }
    }
  }
  return inside;
}
