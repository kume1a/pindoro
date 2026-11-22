import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// Home or Work for drives (SPEC §16.23 items 120–121): the destination junction's OSM node (pack
/// junction ids change between packs), a part id of its street and the pack place picked, if any.
typedef DrivePlace = ({int node, String street, String? place});

String encodeDrivePlace(DrivePlace p) => jsonEncode({
  'node': p.node,
  'street': p.street,
  if (p.place != null) 'place': p.place,
});

DrivePlace? decodeDrivePlace(String? json) {
  if (json == null) return null;
  return switch (jsonDecode(json)) {
    {'node': final int node, 'street': final String street} &&
        final Map<String, Object?> m =>
      (node: node, street: street, place: m['place'] as String?),
    _ => null,
  };
}

/// A destination in the open pack: a junction on [street], at the pack [place] when one was
/// picked.
typedef DriveTarget = ({int junction, NamedStreet street, Landmark? place});

/// Home and Work as destinations in the open pack; null when unset or gone from the pack.
final drivePlacesProvider =
    FutureProvider.autoDispose<({DriveTarget? home, DriveTarget? work})>((
      ref,
    ) async {
      final settings = await ref.watch(settingsProvider.future);
      final byNode = await ref.watch(junctionsByNodeProvider.future);
      final streets = await ref.watch(cityStreetsProvider.future);
      final pack = await ref.watch(packRepositoryProvider.future);
      final places = {for (final l in pack.landmarks()) l.id: l};
      DriveTarget? resolve(String? json) => switch (decodeDrivePlace(json)) {
        final p? => switch ((byNode[p.node], streets[p.street])) {
          (final junction?, final street?) => (
            junction: junction,
            street: street,
            place: places[p.place],
          ),
          _ => null,
        },
        null => null,
      };
      return (
        home: resolve(settings.driveHome),
        work: resolve(settings.driveWork),
      );
    });

/// [target] to keep as Home or Work, by the open pack's [junctionNodes]; null without a node.
DrivePlace? drivePlaceOf(DriveTarget target, Map<int, int> junctionNodes) =>
    switch (junctionNodes[target.junction]) {
      final node? => (
        node: node,
        street: target.street.id,
        place: target.place?.id,
      ),
      null => null,
    };

/// The destinations driven to lately, newest first, each once, Home and Work aside (board
/// V32-10's Recent).
final recentDestinationsProvider =
    FutureProvider.autoDispose<List<DriveTarget>>((ref) async {
      final drives = await ref.watch(driveLogDaoProvider).all();
      final byNode = await ref.watch(junctionsByNodeProvider.future);
      final streets = await ref.watch(cityStreetsProvider.future);
      final pack = await ref.watch(packRepositoryProvider.future);
      final anchors = await ref.watch(drivePlacesProvider.future);
      final places = {for (final l in pack.landmarks()) l.id: l};
      final skip = {?anchors.home?.junction, ?anchors.work?.junction};
      final out = <DriveTarget>[];
      final seen = <int>{};
      for (final d in drives) {
        final junction = byNode[d.targetNode];
        final street = streets[d.targetStreet];
        if (junction == null ||
            street == null ||
            skip.contains(junction) ||
            !seen.add(junction)) {
          continue;
        }
        out.add((
          junction: junction,
          street: street,
          place: places[d.targetPlace],
        ));
        if (out.length == _recents) break;
      }
      return out;
    });

/// How many recent destinations the setup lists.
const int _recents = 3;

/// A destination picked by name: a [street] or a pack [place]; at [junction] on [street] when
/// known already (a recent destination).
typedef DriveDest = ({NamedStreet? street, Landmark? place, int? junction});

/// The street at junction [j], by part id in [streets].
NamedStreet? streetAt(
  RoadGraph graph,
  Map<String, NamedStreet> streets,
  int j,
) => graph.edgesAt(j).map((e) => streets[e.streetId]).nonNulls.firstOrNull;

/// [dest] on [graph]: at its junction when known; a place at the junction on a named street
/// nearest it; a street at its junction nearest [here] (its first part's middle without it).
DriveTarget? resolveDest(
  RoadGraph graph,
  Map<String, NamedStreet> streets,
  DriveDest dest, {
  LatLng? here,
}) {
  int? nearest(Iterable<int> junctions, LatLng to) => junctions.fold<int?>(
    null,
    (best, j) =>
        best == null ||
            distanceBetween(to, graph.at(j)) <
                distanceBetween(to, graph.at(best))
        ? j
        : best,
  );
  if ((dest.junction, dest.street) case (final j?, final street?)) {
    return (junction: j, street: street, place: dest.place);
  }
  if (dest.place case final place?) {
    final j = nearest(
      graph.junctions.keys.where((j) => streetAt(graph, streets, j) != null),
      place.at,
    );
    final street = j == null ? null : streetAt(graph, streets, j);
    return j == null || street == null
        ? null
        : (junction: j, street: street, place: place);
  }
  final street = dest.street;
  if (street == null) return null;
  final j = nearest({
    for (final p in street.parts) ...graph.junctionsOfPart(p.id),
  }, here ?? street.parts.first.midpoint);
  return j == null ? null : (junction: j, street: street, place: null);
}
