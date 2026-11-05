import '../geo/geo.dart';
import '../pack/pack_repository.dart';

/// Name, size and outline of an area as found in a pack.
typedef AreaShape = ({
  String name,
  double areaM2,
  Bbox bbox,
  List<List<Polyline>> boundary,
});

/// What a round covers: the whole city or one district of the pack.
sealed class Area {
  const Area();

  /// Parses the JSON stored in `user_settings.last_area_json` / `round.area_json`.
  factory Area.fromJson(Map<String, Object?> json) => switch (json) {
    {'kind': 'city'} => const WholeCity(),
    {'kind': 'district', 'district_id': final String id} => DistrictArea(id),
    _ => throw FormatException('Not an area: $json'),
  };

  /// Null for the whole city.
  String? get districtId;

  Map<String, Object?> toJson();

  /// Null when the pack doesn't contain this area (e.g. the offline fixture).
  AreaShape? shapeIn(PackRepository pack);
}

final class WholeCity extends Area {
  const WholeCity();

  @override
  String? get districtId => null;

  @override
  Map<String, Object?> toJson() => {'kind': 'city'};

  @override
  AreaShape shapeIn(PackRepository pack) {
    final city = pack.city();
    return (
      name: city.nameKa,
      areaM2: city.areaM2,
      bbox: city.bbox,
      boundary: city.boundary,
    );
  }

  @override
  bool operator ==(Object other) => other is WholeCity;

  @override
  int get hashCode => (WholeCity).hashCode;
}

final class DistrictArea extends Area {
  const DistrictArea(this.districtId);

  @override
  final String districtId;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'district',
    'district_id': districtId,
  };

  @override
  AreaShape? shapeIn(PackRepository pack) {
    for (final d in pack.districts()) {
      if (d.id == districtId) {
        return (
          name: d.nameKa,
          areaM2: d.areaM2,
          bbox: d.bbox,
          boundary: d.boundary,
        );
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is DistrictArea && other.districtId == districtId;

  @override
  int get hashCode => districtId.hashCode;
}
