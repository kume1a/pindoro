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
    this.parentId,
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
    parentId: r['parent_id'] as String?,
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

  /// A smaller area's raion (pack format 4); null for a raion and older packs.
  final String? parentId;

  /// A district proper, not one of the smaller areas inside.
  bool get isRaion => kind == DistrictKind.district;
}

/// A street's curriculum tier (pack format 4): [a] the skeleton (motorway,
/// trunk, primary), [b] the grid (secondary, tertiary), [c] the rest.
enum StreetTier { a, b, c }

/// The side of the city's river a street lies on, facing downstream.
enum RiverBank { left, right }

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
    this.tier,
    this.ring,
    this.bank,
    this.chunkId,
    this.etymology,
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
    tier: switch (r['tier']) {
      final String t => StreetTier.values.byName(t.toLowerCase()),
      _ => null,
    },
    ring: r['ring'] as int?,
    bank: switch (r['bank']) {
      'L' => RiverBank.left,
      'R' => RiverBank.right,
      _ => null,
    },
    chunkId: r['chunk_id'] as String?,
    etymology: r['etymology'] as String?,
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

  // The curriculum's columns (pack format 4); null in older packs.
  final StreetTier? tier;

  /// 2 km bands round the city centre, 0 innermost.
  final int? ring;
  final RiverBank? bank;

  /// The neighbourhood that teaches this street.
  final String? chunkId;

  /// OSM `name:etymology`.
  final String? etymology;
}

/// A lane-family kind, by the Georgian word that ends the child's name.
enum FamilyKind { lane, deadEnd, passage }

/// A numbered lane, dead end or passage and the street it belongs to (pack
/// format 4). [orphan]: the child lies far from its parent.
typedef FamilyLink = ({
  String parentId,
  String childId,
  FamilyKind kind,
  int n,
  bool orphan,
});

FamilyLink familyLinkFromRow(PackRow r) => (
  parentId: r['parent_street_id']! as String,
  childId: r['child_street_id']! as String,
  kind: switch (r['kind']) {
    'dead_end' => FamilyKind.deadEnd,
    final String k => FamilyKind.values.byName(k),
    _ => throw FormatException('family without a kind', r),
  },
  n: r['n']! as int,
  orphan: r['orphan'] == 1,
);

/// A bridge over the city's river (pack format 5): `id` is `w<lowest way id>`.
class Bridge {
  const Bridge({
    required this.id,
    required this.nameKa,
    required this.nameEn,
    required this.midpoint,
    required this.geometry,
  });

  factory Bridge.fromRow(PackRow r) => Bridge(
    id: r['id']! as String,
    nameKa: r['name_ka']! as String,
    nameEn: r['name_en'] as String?,
    midpoint: _latLng(r, 'mid'),
    geometry: decodeMultiline6(r['geometry']! as String),
  );

  final String id;
  final String nameKa;
  final String? nameEn;
  final LatLng midpoint;
  final MultiPolyline geometry;
}

/// An OSM landmark near a junction item (pack format 5, SPEC §9); `salience`
/// leaves out the turn-dependent structural part.
class Landmark {
  const Landmark({
    required this.id,
    required this.kind,
    required this.nameKa,
    required this.nameEn,
    required this.brand,
    required this.salience,
    required this.at,
    this.outline,
  });

  factory Landmark.fromRow(PackRow r) => Landmark(
    id: r['id']! as String,
    kind: r['kind']! as String,
    nameKa: r['name_ka']! as String,
    nameEn: r['name_en'] as String?,
    brand: r['brand'] as String?,
    salience: _d(r['salience']),
    at: LatLng(_d(r['lat']), _d(r['lon'])),
    outline: switch (r['outline']) {
      final String json => decodeMultipolygon6(json),
      _ => null,
    },
  );

  final String id;
  final String kind;
  final String nameKa;
  final String? nameEn;
  final String? brand;
  final double salience;
  final LatLng at;

  /// An area's outline (a park, a mall), null for a point (format 6).
  final List<List<Polyline>>? outline;
}

/// Any named place in the city (pack format 9 `poi`), a destination to drive to: [kind] is its
/// OSM tag value under [osmKey] (`restaurant` under `amenity`), with what OSM says of its address,
/// opening hours, phone and website.
class Poi extends Landmark {
  const Poi({
    required super.id,
    required super.kind,
    required super.nameKa,
    required super.nameEn,
    required super.brand,
    required super.at,
    required this.osmKey,
    super.outline,
    this.street,
    this.housenumber,
    this.hours,
    this.phone,
    this.website,
  }) : super(salience: 0);

  factory Poi.fromRow(PackRow r) => Poi(
    id: r['id']! as String,
    osmKey: r['key']! as String,
    kind: r['kind']! as String,
    nameKa: r['name_ka']! as String,
    nameEn: r['name_en'] as String?,
    brand: r['brand'] as String?,
    at: LatLng(_d(r['lat']), _d(r['lon'])),
    outline: switch (r['outline']) {
      final String json => decodeMultipolygon6(json),
      _ => null,
    },
    street: r['street'] as String?,
    housenumber: r['housenumber'] as String?,
    hours: r['hours'] as String?,
    phone: r['phone'] as String?,
    website: r['website'] as String?,
  );

  final String osmKey;

  /// OSM `addr:street` and `addr:housenumber`.
  final String? street;
  final String? housenumber;

  /// OSM `opening_hours`, as tagged.
  final String? hours;
  final String? phone;
  final String? website;
}

/// Where a junction item sits in the route layers (SPEC §6.5).
enum JunctionLayer { skeleton, district, gatewayOut, gatewayIn, bridge }

/// A turn worth knowing (pack format 5, SPEC §6.6): arriving at
/// [junctionId] on [approachEdge], take [exitEdge]. Ids are pack-local.
class JunctionItem {
  const JunctionItem({
    required this.junctionId,
    required this.approachEdge,
    required this.exitEdge,
    required this.layer,
    required this.rank,
    this.chunkId,
    this.destChunkId,
    this.landmarkId,
    this.landmarkOnLeft,
    this.bridgeId,
  });

  factory JunctionItem.fromRow(PackRow r) => JunctionItem(
    junctionId: r['junction_id']! as int,
    approachEdge: r['approach_edge']! as int,
    exitEdge: r['exit_edge']! as int,
    layer: switch (r['layer']! as String) {
      'gateway_out' => JunctionLayer.gatewayOut,
      'gateway_in' => JunctionLayer.gatewayIn,
      final l => JunctionLayer.values.byName(l),
    },
    rank: r['rank']! as int,
    chunkId: r['chunk_id'] as String?,
    destChunkId: r['dest_chunk_id'] as String?,
    landmarkId: r['landmark_id'] as String?,
    landmarkOnLeft: switch (r['landmark_side']) {
      'left' => true,
      'right' => false,
      _ => null,
    },
    bridgeId: r['bridge_id'] as String?,
  );

  final int junctionId;
  final int approachEdge;
  final int exitEdge;
  final JunctionLayer layer;

  /// Coverage order, 1 first.
  final int rank;

  /// A gateway's neighbourhood.
  final String? chunkId;

  /// Where the routes through it mostly head.
  final String? destChunkId;
  final String? landmarkId;

  /// Which side the landmark is on, driving in on the approach.
  final bool? landmarkOnLeft;

  /// The bridge the exit leads onto (layer bridge).
  final String? bridgeId;
}
