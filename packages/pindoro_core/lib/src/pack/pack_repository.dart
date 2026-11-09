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

  void close();
}
