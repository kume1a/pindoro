import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// Under this many streets the picker warns that streets may repeat.
const int _fewStreets = 30;

/// Whether the areas [picked] hold so few streets that rounds may repeat
/// them; false while [byArea] loads.
bool fewStreets(Set<String> picked, Map<String, Set<String>>? byArea) =>
    byArea != null &&
    picked.isNotEmpty &&
    streetCount(byArea, picked) < _fewStreets;

typedef DistrictGroup = ({District district, List<District> parts});

/// Each district with the smaller areas whose centre lies in it (else the
/// nearest district), districts by name.
List<DistrictGroup> groupByDistrict(List<District> areas) {
  final districts = [
    for (final d in areas)
      if (d.isRaion) d,
  ];
  final parts = {for (final d in districts) d.id: <District>[]};
  for (final n in areas) {
    if (n.isRaion || districts.isEmpty) continue;
    final home =
        districts
            .where((d) => boundaryContains(d.boundary, n.center))
            .firstOrNull ??
        (districts.toList()..sort(
              (a, b) => distanceBetween(
                n.center,
                a.center,
              ).compareTo(distanceBetween(n.center, b.center)),
            ))
            .first;
    parts[home.id]!.add(n);
  }
  return [for (final d in districts) (district: d, parts: parts[d.id]!)];
}

/// Picks follow the area tree: a picked district takes in its smaller
/// areas, and a tap on one of them narrows the pick to that area.
class AreaTree {
  AreaTree(List<District> areas) : groups = groupByDistrict(areas) {
    for (final g in groups) {
      for (final p in g.parts) {
        _parent[p.id] = g.district.id;
      }
    }
  }

  final List<DistrictGroup> groups;
  final Map<String, String> _parent = {};

  String? parentOf(String id) => _parent[id];

  /// [picked] without the areas a picked district already covers.
  Set<String> normalise(Set<String> picked) => {
    for (final id in picked)
      if (!picked.contains(_parent[id])) id,
  };

  /// [picked] after a tap on [id]; [narrowed] when the tap swapped [id]'s
  /// picked district for [id].
  ({Set<String> picked, bool narrowed}) toggle(Set<String> picked, String id) {
    final parent = _parent[id];
    if (parent != null && picked.contains(parent)) {
      return (
        picked: {...picked}
          ..remove(parent)
          ..add(id),
        narrowed: true,
      );
    }
    return (
      picked: picked.contains(id)
          ? ({...picked}..remove(id))
          : normalise({...picked, id}),
      narrowed: false,
    );
  }
}

/// Each area's streets (named-street ids), for the picker's counts.
final areaStreetsProvider = FutureProvider<Map<String, Set<String>>>((
  ref,
) async {
  final pack = await ref.watch(packRepositoryProvider.future);
  final streets = await ref.watch(cityStreetsProvider.future);
  return {
    for (final MapEntry(key: area, value: parts)
        in pack.partsByDistrict().entries)
      area: {for (final part in parts) ?streets[part]?.id},
  };
});

/// How many different streets the areas [ids] hold together.
int streetCount(Map<String, Set<String>> byArea, Iterable<String> ids) =>
    {for (final id in ids) ...?byArea[id]}.length;
