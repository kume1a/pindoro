import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:pindoro/core/config.dart';

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
  });

  /// Every street and place.
  static const all = MapNames(streets: null, places: true);

  /// The streets named, by their OSM name; null names every street.
  final Set<String>? streets;

  /// Whether places are named.
  final bool places;

  /// Lower-case stems no named place may contain: it would name the street
  /// being asked (pindoro_learning `nameStems`).
  final Set<String> placesNot;

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
      setEquals(streets, other.streets) &&
      setEquals(placesNot, other.placesNot);

  @override
  int get hashCode => Object.hash(
    places,
    streets == null ? null : Object.hashAllUnordered(streets!),
    Object.hashAllUnordered(placesNot),
  );
}
