import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:pindoro/core/config.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Bundled style with the tile server injected (Martin source `georgia` and
/// its FiraGO glyphs); its name layers read English names when [english].
Future<String> loadMapStyle(
  Brightness brightness, {
  bool english = false,
}) async {
  final json = await rootBundle.loadString(
    'assets/map_styles/pindoro_${brightness.name}.json',
  );
  return json
      .replaceAll('{TILES_BASE_URL}', AppConfig.tilesBaseUrl)
      .replaceAll('{NAME_KEY}', english ? 'name:en' : 'name');
}

/// The style's name layers (pipeline `tiles.ts` `NAME_LAYERS`), hidden until
/// a map shows them.
abstract final class NameLayers {
  static const String roads = 'road-names';
  static const String pois = 'poi-names';
  static const String areas = 'area-names';
  static const String water = 'water-names';

  /// The layers named with the places: landmarks, neighbourhoods, rivers.
  static const List<String> places = [pois, areas, water];

  /// Every named place's name, for the navigation maps (item 132).
  static const String poisAll = 'poi-names-all';

  /// The lowest name layer in the style: overlay lines go under it.
  static const String lowest = pois;
}

/// The style's place icons: the landmark kinds ([curated], the game's maps) or every named
/// place ([all], the navigation maps, SPEC §16.23 item 132).
abstract final class PoiLayers {
  static const String curated = 'pois';
  static const String all = 'pois-all';
}

/// [style]'s own filter of the layer [id].
Object? styleFilter(String style, String id) {
  final layers = (jsonDecode(style) as Map<String, dynamic>)['layers'] as List;
  return layers.cast<Map<String, dynamic>>().firstWhere(
    (l) => l['id'] == id,
  )['filter'];
}

/// The names a map draws over its basemap (SPEC §16.18): none by default (a
/// question), [MapNames.all] on an intro or a reveal.
@immutable
class MapNames {
  const MapNames({
    this.streets = const {},
    this.places = false,
    this.placesNot = const {},
    this.everyPlace = false,
  });

  /// Every street and place.
  static const all = MapNames(streets: null, places: true);

  /// Every street and every named place there is, not only the landmarks: the navigation maps
  /// (item 132).
  static const everything = MapNames(
    streets: null,
    places: true,
    everyPlace: true,
  );

  /// A question's names: places, but none named after [answer], the street
  /// being asked.
  factory MapNames.asking(NamedStreet? answer) => MapNames(
    places: true,
    placesNot: answer == null ? const {} : nameStems(answer),
  );

  /// The streets named, by their OSM name; null names every street.
  final Set<String>? streets;

  /// Whether places, neighbourhoods and rivers are named.
  final bool places;

  /// Lower-case stems no named place may contain: it would name the street
  /// being asked (pindoro_learning `nameStems`).
  final Set<String> placesNot;

  /// Every named place's icon and name in place of the landmarks' (pipeline `pois-all`).
  final bool everyPlace;

  /// The street layer's filter over the style's own [base]; null hides it.
  Object? roadFilter(Object? base) => switch (streets) {
    null => base,
    final s when s.isEmpty => null,
    final s => [
      'all',
      base,
      [
        'in',
        ['get', 'name'],
        ['literal', s.toList()],
      ],
    ],
  };

  /// The place layer's filter over the style's own [base]; null hides it.
  Object? placeFilter(Object? base) => !places
      ? null
      : [
          'all',
          base,
          for (final stem in placesNot)
            for (final key in ['name', 'name:en'])
              [
                '!',
                [
                  'in',
                  stem,
                  [
                    'downcase',
                    [
                      'coalesce',
                      ['get', key],
                      '',
                    ],
                  ],
                ],
              ],
        ];

  @override
  bool operator ==(Object other) =>
      other is MapNames &&
      places == other.places &&
      everyPlace == other.everyPlace &&
      setEquals(streets, other.streets) &&
      setEquals(placesNot, other.placesNot);

  @override
  int get hashCode => Object.hash(
    places,
    everyPlace,
    streets == null ? null : Object.hashAllUnordered(streets!),
    Object.hashAllUnordered(placesNot),
  );
}
