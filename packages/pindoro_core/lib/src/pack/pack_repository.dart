import '../scoring/scoring.dart';
import 'models.dart';
import 'road_graph.dart';

/// Read-only access to one city pack (see docs/pack-format.md).
abstract interface class PackRepository {
  /// The `meta` table (format_version, version, scope, attribution, ...).
  Map<String, String> meta();

  City city();

  List<District> districts();

  /// Streets, optionally limited to one district and/or some difficulties.
  List<Street> streets({String? districtId, Set<Difficulty>? difficulties});

  /// Street (part) ids in each district, by district id.
  Map<String, Set<String>> partsByDistrict();

  /// Metres of each street part inside each district: district id → part id
  /// → metres.
  Map<String, Map<String, double>> lengthsByDistrict();

  /// The road graph (format 3); null for an older pack without one.
  RoadGraph? roadGraph();

  /// Lane families (format 4); empty for an older pack.
  List<FamilyLink> families();

  /// Each neighbourhood's bordering neighbourhoods (format 4); empty for an
  /// older pack.
  Map<String, Set<String>> chunkNeighbours();

  /// Each junction's OSM node id (format 5), by pack junction id: the stable
  /// part of route item ids. Empty for an older pack.
  Map<int, int> junctionNodes();

  /// The bridges over the river (format 5); empty for an older pack.
  List<Bridge> bridges();

  /// The landmarks the junction items use (format 5); empty for an older pack.
  List<Landmark> landmarks();

  /// Every named place in the city (format 9); empty for an older pack.
  List<Poi> pois();

  /// The turns worth knowing, rank order (format 5); empty for an older pack.
  List<JunctionItem> junctionItems();

  void close();
}
