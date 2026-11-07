import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// Cities to play: the catalog's; offline, the active pack's city.
final cityListProvider = FutureProvider.autoDispose<List<CatalogCity>>((
  ref,
) async {
  try {
    return await ref.watch(packStoreProvider).cities();
  } on Object {
    final here = (await ref.watch(packRepositoryProvider.future)).city();
    return [
      (id: here.id, nameKa: here.nameKa, nameEn: here.nameEn, bbox: here.bbox),
    ];
  }
});

/// City ids the player has played, most recent first.
final recentCityIdsProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(progressDaoProvider).recentCityIds(),
);

/// The city whose bounds hold [position]; the smallest when several do.
CatalogCity? cityAt(List<CatalogCity> cities, LatLng position) {
  double span(Bbox b) => (b.maxLat - b.minLat) * (b.maxLon - b.minLon);
  final hits = [
    for (final c in cities)
      if (c.bbox case final b? when b.contains(position))
        (city: c, span: span(b)),
  ]..sort((a, b) => a.span.compareTo(b.span));
  return hits.firstOrNull?.city;
}
