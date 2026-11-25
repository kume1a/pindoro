import '../geo/geo.dart';
import '../geo/polyline6.dart';
import 'models.dart';

/// Which way an edge may be driven (pack format 5 `road_edge.oneway`):
/// [forward] only from its `from` junction to its `to`, [backward] only the
/// other way.
enum Oneway { both, forward, backward }

/// A turn restriction (OSM `type=restriction`, pack `turn_restriction`):
/// arriving on [fromEdge] at junction [via], [toEdge] is forbidden (`no_*`),
/// or with [only] (`only_*`) the only way on.
typedef TurnRestriction = ({int fromEdge, int via, int toEdge, bool only});

/// A speed camera on [edgeId] (pack format 7 `speed_camera`): its limit and the heading of the
/// traffic it checks, when tagged.
typedef SpeedCamera = ({
  int id,
  int edgeId,
  LatLng at,
  int? maxspeedKmh,
  double? directionDeg,
});

/// A stretch of road between two junctions (pack `road_edge`): of a street,
/// or with no [streetId] a connector (an unnamed way or a `*_link`).
class RoadEdge {
  RoadEdge({
    required this.id,
    required this.from,
    required this.to,
    required this.streetId,
    required this.lengthM,
    required Polyline line,
    this.oneway = Oneway.both,
    this.maxspeedKmh,
    this.lanes,
    this.lanesBack,
  }) : _line = line,
       _geometry = null;

  /// Keeps the polyline6 and decodes it on first use: a city has thousands
  /// of edges and a trip draws a few dozen. Packs before format 5 have no
  /// `oneway` column: every edge is two-way there; packs before format 8
  /// have no lanes.
  RoadEdge.fromRow(PackRow r)
    : id = r['id']! as int,
      from = r['from_junction']! as int,
      to = r['to_junction']! as int,
      streetId = r['street_id'] as String?,
      lengthM = (r['length_m']! as num).toDouble(),
      oneway = switch (r['oneway']) {
        1 => Oneway.forward,
        -1 => Oneway.backward,
        _ => Oneway.both,
      },
      maxspeedKmh = r['maxspeed'] as int?,
      lanes = r['lanes'] as String?,
      lanesBack = r['lanes_back'] as String?,
      _geometry = r['geometry']! as String;

  /// This edge open both ways (`RoadGraph.allowing` a reported move).
  RoadEdge get twoWay => RoadEdge._twoWay(this);

  RoadEdge._twoWay(RoadEdge e)
    : id = e.id,
      from = e.from,
      to = e.to,
      streetId = e.streetId,
      lengthM = e.lengthM,
      oneway = Oneway.both,
      _geometry = e._geometry,
      maxspeedKmh = e.maxspeedKmh,
      lanes = e.lanes,
      lanesBack = e.lanesBack,
      _line = e._line;

  final int id;
  final int from;
  final int to;

  /// The street part (pack `street.id`) it belongs to; null for a connector.
  final String? streetId;
  final double lengthM;
  final Oneway oneway;

  /// The signed speed limit in km/h (pack format 7); null where none is mapped or in an older
  /// pack.
  final int? maxspeedKmh;

  /// The lane arrows driving from [from] to [to], left to right (pack format 8, OSM `turn:lanes`
  /// values such as `left|through;right|right`); null when unmapped or in an older pack.
  final String? lanes;

  /// The lane arrows driving from [to] to [from], as [lanes].
  final String? lanesBack;
  final String? _geometry;
  Polyline? _line;

  /// From [from] to [to].
  Polyline get line => _line ??= decodePolyline6(_geometry!);

  /// The far end, driving away from [junction].
  int other(int junction) => junction == from ? to : from;

  /// The lanes driving toward [junction], left to right (OSM turn:lanes values); null when
  /// unmapped.
  String? lanesInto(int junction) => junction == to
      ? lanes
      : junction == from
      ? lanesBack
      : null;

  /// The line as driven away from [junction].
  Polyline lineFrom(int junction) =>
      junction == from ? line : line.reversed.toList();
}

/// The heading arriving at [junction] on [edge], past a repeated last vertex.
double arrivingBearing(RoadEdge edge, int junction) {
  final line = edge.lineFrom(edge.other(junction));
  return bearingDegrees(_awayFrom(line.last, line.reversed.skip(1)), line.last);
}

/// The heading leaving [junction] on [edge], past a repeated first vertex.
double leavingBearing(RoadEdge edge, int junction) {
  final line = edge.lineFrom(junction);
  return bearingDegrees(line.first, _awayFrom(line.first, line.skip(1)));
}

/// The first of [points] that isn't [at] (the last one when all are).
LatLng _awayFrom(LatLng at, Iterable<LatLng> points) =>
    points.firstWhere((p) => p != at, orElse: () => points.last);
