import 'dart:convert';

import '../geo/geo.dart';
import '../geo/polyline6.dart';
import '../scoring/scoring.dart';

/// A pack row as returned by any SQLite binding (column name -> value).
typedef PackRow = Map<String, Object?>;

/// multiline6: JSON array of polyline6 strings.
MultiPolyline decodeMultiline6(String json) => [
  for (final part in jsonDecode(json) as List<Object?>)
    decodePolyline6(part! as String),
];

/// multipolygon6: JSON array of polygons, each an array of polyline6 rings.
List<List<Polyline>> decodeMultipolygon6(String json) => [
  for (final polygon in jsonDecode(json) as List<Object?>)
    [
      for (final ring in polygon! as List<Object?>)
        decodePolyline6(ring! as String),
    ],
];

LatLng _latLng(PackRow r, String prefix) =>
    LatLng(_d(r['${prefix}_lat']), _d(r['${prefix}_lon']));

Bbox _bbox(PackRow r) =>
    Bbox.tryParse(r) ?? (throw FormatException('row without a bbox', r));

double _d(Object? v) => (v! as num).toDouble();

class City {
  const City({
    required this.id,
    required this.nameKa,
    required this.nameEn,
    required this.osmRelationId,
    required this.center,
    required this.bbox,
    required this.areaM2,
    required this.boundary,
  });

  factory City.fromRow(PackRow r) => City(
    id: r['id']! as String,
    nameKa: r['name_ka']! as String,
    nameEn: r['name_en']! as String,
    osmRelationId: r['osm_relation_id']! as int,
    center: _latLng(r, 'center'),
    bbox: _bbox(r),
    areaM2: _d(r['area_m2']),
    boundary: decodeMultipolygon6(r['boundary']! as String),
  );

  final String id;
  final String nameKa;
  final String nameEn;
  final int osmRelationId;
  final LatLng center;
  final Bbox bbox;
  final double areaM2;
  final List<List<Polyline>> boundary;
}

/// A district (raion), or one of the smaller areas inside: an OSM quarter
/// (they tile most of a city) or neighbourhood (smaller, may overlap).
enum DistrictKind { district, quarter, neighbourhood }

class District {
  const District({
    required this.id,
    required this.kind,
    required this.osmRelationId,
    required this.nameKa,
    required this.nameEn,
    required this.center,
    required this.bbox,
    required this.areaM2,
    required this.boundary,
  });

  factory District.fromRow(PackRow r) => District(
    id: r['id']! as String,
    kind: DistrictKind.values.byName(r['kind']! as String),
    osmRelationId: r['osm_relation_id'] as int?,
    nameKa: r['name_ka']! as String,
    nameEn: r['name_en'] as String?,
    center: _latLng(r, 'center'),
    bbox: _bbox(r),
    areaM2: _d(r['area_m2']),
    boundary: decodeMultipolygon6(r['boundary']! as String),
  );

  final String id;
  final DistrictKind kind;
  final int? osmRelationId;
  final String nameKa;
  final String? nameEn;
  final LatLng center;
  final Bbox bbox;
  final double areaM2;
  final List<List<Polyline>> boundary;
}

class Street {
  const Street({
    required this.id,
    required this.nameKa,
    required this.nameEn,
    required this.roadClass,
    required this.difficulty,
    required this.lengthM,
    required this.midpoint,
    required this.bbox,
    required this.geometry,
  });

  factory Street.fromRow(PackRow r) => Street(
    id: r['id']! as String,
    nameKa: r['name_ka']! as String,
    nameEn: r['name_en'] as String?,
    roadClass: r['road_class']! as String,
    difficulty: Difficulty.values.byName(r['difficulty']! as String),
    lengthM: _d(r['length_m']),
    midpoint: _latLng(r, 'mid'),
    bbox: _bbox(r),
    geometry: decodeMultiline6(r['geometry']! as String),
  );

  final String id;
  final String nameKa;
  final String? nameEn;
  final String roadClass;
  final Difficulty difficulty;
  final double lengthM;
  final LatLng midpoint;
  final Bbox bbox;
  final MultiPolyline geometry;
}
