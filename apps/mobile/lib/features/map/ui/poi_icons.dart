import 'package:flutter/painting.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:pindoro_design/pindoro_design.dart';

/// A landmark's disc colour (`color.map.poi.*`).
enum PoiCategory {
  food,
  shop,
  culture,
  worship,
  nature,
  transit,
  civic,
  health;

  Color color(PindoroColors c) => switch (this) {
    food => c.mapPoiFood,
    shop => c.mapPoiShop,
    culture => c.mapPoiCulture,
    worship => c.mapPoiWorship,
    nature => c.mapPoiNature,
    transit => c.mapPoiTransit,
    civic => c.mapPoiCivic,
    health => c.mapPoiHealth,
  };
}

/// The basemap's landmark kinds (the style's `pois` layer, written by the
/// pipeline's `tiles`) with their Maki icon and category.
const Map<String, (String, PoiCategory)> poiIcons = {
  'station': ('rail-metro', PoiCategory.transit),
  'bus_station': ('bus', PoiCategory.transit),
  'aerodrome': ('airport', PoiCategory.transit),
  'museum': ('museum', PoiCategory.culture),
  'theatre': ('theatre', PoiCategory.culture),
  'cinema': ('cinema', PoiCategory.culture),
  'gallery': ('art-gallery', PoiCategory.culture),
  'attraction': ('attraction', PoiCategory.culture),
  'monument': ('monument', PoiCategory.culture),
  'castle': ('castle', PoiCategory.culture),
  'place_of_worship': ('place-of-worship', PoiCategory.worship),
  'park': ('park', PoiCategory.nature),
  'garden': ('garden', PoiCategory.nature),
  'zoo': ('zoo', PoiCategory.nature),
  'peak': ('mountain', PoiCategory.nature),
  'university': ('college', PoiCategory.civic),
  'college': ('college', PoiCategory.civic),
  'school': ('school', PoiCategory.civic),
  'library': ('library', PoiCategory.civic),
  'stadium': ('stadium', PoiCategory.civic),
  'townhall': ('town-hall', PoiCategory.civic),
  'post_office': ('post', PoiCategory.civic),
  'hotel': ('lodging', PoiCategory.civic),
  'hospital': ('hospital', PoiCategory.health),
  'pharmacy': ('pharmacy', PoiCategory.health),
  'restaurant': ('restaurant', PoiCategory.food),
  'cafe': ('cafe', PoiCategory.food),
  'bar': ('bar', PoiCategory.food),
  'pub': ('beer', PoiCategory.food),
  'fast_food': ('fast-food', PoiCategory.food),
  'supermarket': ('grocery', PoiCategory.shop),
  'mall': ('shop', PoiCategory.shop),
  'marketplace': ('shop', PoiCategory.shop),
};

/// Adds the `poi-<kind>` image the style's `pois` layer draws, for every
/// kind. Overlays never wait on these: call it after them.
// ponytail: re-rastered on every map load (~30 tiny SVGs); cache per theme and pixel ratio if it shows in traces.
Future<void> addPoiImages(
  ml.MapLibreMapController c,
  PindoroColors colors,
  double pixelRatio,
) => Future.wait([
  for (final MapEntry(key: kind, value: (icon, category)) in poiIcons.entries)
    () async {
      final mark = PoiMark(
        icon: icon,
        color: category.color(colors),
        colors: colors,
      );
      await c.addImage('poi-$kind', await mark.toPng(pixelRatio));
    }(),
]);
