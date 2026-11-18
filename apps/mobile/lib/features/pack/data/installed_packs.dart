import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/pack/data/pack_store.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// Opens [cityId]'s newest installed pack for [read] and closes it after;
/// null when the phone has none. Never downloads.
Future<T?> readInstalledPack<T>(
  PackStore store,
  String cityId,
  Future<T> Function(PackRepository pack, Map<String, NamedStreet> streets)
  read,
) async {
  final file = store.newest(cityId);
  if (file == null) return null;
  final pack = SqlitePackRepository.open(file.path);
  try {
    return await read(pack, streetsByPartId(pack.streets()));
  } finally {
    pack.close();
  }
}

/// An open pack and its streets as the player sees them.
typedef OpenPack = ({PackRepository pack, Map<String, NamedStreet> streets});

/// The active [pack] once it and its [streets] are loaded, else null.
OpenPack? openPackOf(
  AsyncValue<PackRepository> pack,
  AsyncValue<Map<String, NamedStreet>> streets,
) => switch ((pack.value, streets.value)) {
  (final pack?, final streets?) => (pack: pack, streets: streets),
  _ => null,
};

/// [read] over each of [cityIds]' packs, in order: [open] for its own city,
/// else the city's newest installed pack in [store], opened just for this
/// (the store is only read then). A city with no pack on the phone is left
/// out. Never downloads.
Future<List<T>> readCityPacks<T>(
  PackStore Function() store,
  Iterable<String> cityIds,
  Future<T> Function(PackRepository pack, Map<String, NamedStreet> streets)
  read, {
  OpenPack? open,
}) async => [
  for (final id in cityIds)
    if (open != null && open.pack.city().id == id)
      await read(open.pack, open.streets)
    else
      ?await readInstalledPack(store(), id, read),
];
