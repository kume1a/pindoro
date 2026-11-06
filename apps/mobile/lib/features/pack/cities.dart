import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../../app/database.dart';
import 'pack_store.dart';
import 'sqlite_pack_repository.dart';

/// Cities to play: the catalog's, plus the installed pack's city so the list
/// works offline.
final cityListProvider = FutureProvider.autoDispose<List<CatalogCity>>((
  ref,
) async {
  final pack = await ref.watch(packRepositoryProvider.future);
  final here = pack.city();
  final installed = (
    id: here.id,
    nameKa: here.nameKa,
    nameEn: here.nameEn,
    bbox: here.bbox,
  );
  try {
    final catalog = await ref.watch(packStoreProvider).cities();
    return [
      ...catalog,
      if (!catalog.any((c) => c.id == installed.id)) installed,
    ];
  } on Object {
    return [installed];
  }
});

/// City ids the player has played, most recent first.
final recentCityIdsProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(databaseProvider).recentCityIds(),
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
