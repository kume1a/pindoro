import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/personal_landmarks.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// The places the open city's maps can name: the pack's landmarks and the
/// player's own (the most salient), in the street names' script.
final mapPlacesProvider = FutureProvider.autoDispose<List<MapPlace>>((
  ref,
) async {
  final pack = await ref.watch(packRepositoryProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  final mine = await ref.watch(personalLandmarksProvider.future);
  return [
    for (final l in pack.landmarks())
      (
        id: l.id,
        at: l.at,
        label: landmarkName(l, settings),
        salience: l.salience,
      ),
    for (final l in mine)
      (id: l.id, at: LatLng(l.lat, l.lon), label: l.name, salience: 1.0),
  ];
});
