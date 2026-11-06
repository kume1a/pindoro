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

  /// Every street whose `name_ka` is in [names] (all parts of those names).
  List<Street> streetsNamed(Set<String> names);

  List<StreetDistrict> streetDistricts(String streetId);

  /// `name_ka` by street id; ids missing from the pack are left out.
  Map<String, String> streetNames(Iterable<String> ids);

  /// Every street name in the city, and the names in each district.
  ({Set<String> city, Map<String, Set<String>> byDistrict}) streetNameIndex();

  void close();
}
