import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Home or Work for drives (SPEC §16.23 items 120–121): the destination junction's OSM node (pack
/// junction ids change between packs), a part id of its street, the pack place picked, if any,
/// and the spot itself when one was picked (item 132).
typedef DrivePlace = ({int node, String street, String? place, LatLng? at});

String encodeDrivePlace(DrivePlace p) => jsonEncode({
  'node': p.node,
  'street': p.street,
  if (p.place != null) 'place': p.place,
  if (p.at case final at?) ...{'lat': at.lat, 'lon': at.lon},
});

DrivePlace? decodeDrivePlace(String? json) {
  if (json == null) return null;
  return switch (jsonDecode(json)) {
    {'node': final int node, 'street': final String street} &&
        final Map<String, Object?> m =>
      (
        node: node,
        street: street,
        place: m['place'] as String?,
        at: switch ((m['lat'], m['lon'])) {
          (final num lat, final num lon) => LatLng(
            lat.toDouble(),
            lon.toDouble(),
          ),
          _ => null,
        },
      ),
    _ => null,
  };
}

/// A destination in the open pack: a junction on [street], at the pack [place] when one was
/// picked, and the spot to stop by when there is one ([at]: the place or a pin, item 132); the
/// junction is the one nearest the stop, which the drive's learning keeps.
typedef DriveTarget = ({
  int junction,
  NamedStreet street,
  Landmark? place,
  LatLng? at,
});

/// Home and Work as destinations in the open pack; null when unset or gone from the pack.
final drivePlacesProvider =
    FutureProvider.autoDispose<({DriveTarget? home, DriveTarget? work})>((
      ref,
    ) async {
      final settings = await ref.watch(settingsProvider.future);
      final byNode = await ref.watch(junctionsByNodeProvider.future);
      final streets = await ref.watch(cityStreetsProvider.future);
      final places = await ref.watch(packPlacesProvider.future);
      DriveTarget? resolve(String? json) => switch (decodeDrivePlace(json)) {
        final p? => switch ((byNode[p.node], streets[p.street])) {
          (final junction?, final street?) => (
            junction: junction,
            street: street,
            place: places[p.place],
            at: p.at,
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
        at: target.at,
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
      final anchors = await ref.watch(drivePlacesProvider.future);
      final places = await ref.watch(packPlacesProvider.future);
      // Home and Work are skipped as the setup shows them as tiles.
      final seen = {?anchors.home?.key, ?anchors.work?.key};
      final out = <DriveTarget>[];
      for (final d in drives) {
        final junction = byNode[d.targetNode];
        final street = streets[d.targetStreet];
        if (junction == null || street == null) continue;
        final target = (
          junction: junction,
          street: street,
          place: places[d.targetPlace],
          at: switch ((d.targetLat, d.targetLon)) {
            (final lat?, final lon?) => LatLng(lat, lon),
            _ => null,
          },
        );
        if (!seen.add(target.key)) continue;
        out.add(target);
        if (out.length == _recents) break;
      }
      return out;
    });

extension DriveTargetKey on DriveTarget {
  /// What makes two destinations the same: the place, else the spot, else the junction.
  Object get key => place?.id ?? at ?? junction;
}

/// How many recent destinations the setup lists.
const int _recents = 3;

/// A destination picked: a [street], a pack [place] or a spot [at] on the map (item 132); at
/// [junction] on [street] when known already (a recent destination).
typedef DriveDest = ({
  NamedStreet? street,
  Landmark? place,
  int? junction,
  LatLng? at,
});

/// The street at junction [j], by part id in [streets].
NamedStreet? streetAt(
  RoadGraph graph,
  Map<String, NamedStreet> streets,
  int j,
) => graph.edgesAt(j).map((e) => streets[e.streetId]).nonNulls.firstOrNull;

/// [dest] on [graph]: at its junction when known; a place or a spot by the road nearest it (its
/// junction the road's end nearer the stop, item 132), a place out of a road's reach at the
/// junction on a named street nearest it; a street at its junction nearest [here] (its first
/// part's middle without it).
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
    return (junction: j, street: street, place: dest.place, at: dest.at);
  }
  if (dest.at ?? dest.place?.at case final spot?) {
    if (stopsNear(graph, spot).firstOrNull
        case NavStop(:final edge?) && final stop) {
      final j = stop.junctionNear;
      final street =
          streets[edge.streetId] ??
          streetAt(graph, streets, j) ??
          streetAt(graph, streets, edge.other(j));
      if (street != null) {
        return (junction: j, street: street, place: dest.place, at: spot);
      }
    }
    final j = nearest(
      graph.junctions.keys.where((j) => streetAt(graph, streets, j) != null),
      spot,
    );
    final street = j == null ? null : streetAt(graph, streets, j);
    return j == null || street == null || dest.place == null
        ? null
        : (junction: j, street: street, place: dest.place, at: null);
  }
  final street = dest.street;
  if (street == null) return null;
  final j = nearest({
    for (final p in street.parts) ...graph.junctionsOfPart(p.id),
  }, here ?? street.parts.first.midpoint);
  return j == null
      ? null
      : (junction: j, street: street, place: null, at: null);
}

/// Where a drive to [target] stops (item 132): beside the road at its spot, each way the road
/// may be driven, the right side first; at its junction without a spot or a road in reach.
List<NavStop> stopsOf(RoadGraph graph, DriveTarget target) {
  final at = target.at;
  final stops = at == null ? const <NavStop>[] : stopsNear(graph, at);
  return stops.isEmpty ? [NavStop.junction(target.junction)] : stops;
}

/// The destination as the maps mark it: its spot, else its junction.
LatLng targetPoint(RoadGraph graph, DriveTarget target) =>
    target.at ?? graph.at(target.junction);
