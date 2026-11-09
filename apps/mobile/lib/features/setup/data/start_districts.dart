import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/location.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// How the picker places a district: nearest to the player, holding the
/// city centre, or by its compass point from the centre.
enum StartHint { near, centre, direction }

/// One choice of "Where do you want to start?": a raion with a unit and its
/// named streets.
typedef StartDistrict = ({
  District district,
  int streets,
  StartHint hint,
  CompassPoint direction,
});

/// The open city's raions that have a unit, nearest first: from the player
/// when location is already allowed and they are in the city, else from the
/// city centre. Writes nothing.
final startDistrictsProvider =
    FutureProvider.autoDispose<({City city, List<StartDistrict> rows})>((
      ref,
    ) async {
      final location = ref.watch(locationServiceProvider);
      final streetsFuture = ref.watch(cityStreetsProvider.future);
      final pack = await ref.watch(packRepositoryProvider.future);
      final streets = await streetsFuture;
      final city = pack.city();
      final raions = [
        for (final d in pack.districts())
          if (d.kind == DistrictKind.district) d,
      ];
      final taught = {
        for (final u in buildCourse(
          districts: raions,
          streets: {...streets.values},
          lengthsByDistrict: pack.lengthsByDistrict(),
          startDistrictId: raions.firstOrNull?.id ?? '',
        ))
          u.id,
      };
      final here = await location.ifAllowed();
      final located = here != null && city.bbox.contains(here);
      final counts = knownCounts(
        streets: streets,
        partsByDistrict: pack.partsByDistrict(),
        known: const {},
      ).byDistrict;
      final ordered = raionsFrom([
        for (final d in raions)
          if (taught.contains(d.id)) d,
      ], located ? here : city.center);
      return (
        city: city,
        rows: [
          for (final (i, d) in ordered.indexed)
            (
              district: d,
              streets: counts[d.id]?.total ?? 0,
              hint: located && i == 0
                  ? StartHint.near
                  : boundaryContains(d.boundary, city.center)
                  ? StartHint.centre
                  : StartHint.direction,
              direction: compassPoint(city.center, d.center),
            ),
        ],
      );
    });
