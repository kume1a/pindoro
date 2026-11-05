import '../scoring/scoring.dart';
import 'models.dart';

/// Read-only access to one city pack (see docs/pack-format.md).
abstract interface class PackRepository {
  /// The `meta` table (format_version, version, scope, attribution, ...).
  Map<String, String> meta();

  City city();

  List<District> districts();

  /// Streets, optionally limited to one district and/or some difficulties.
  List<Street> streets({String? districtId, Set<Difficulty>? difficulties});

  List<StreetDistrict> streetDistricts(String streetId);

  /// `name_ka` by street id; ids missing from the pack are left out.
  Map<String, String> streetNames(Iterable<String> ids);

  void close();
}
