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
  'fuel': ('fuel', PoiCategory.transit),
};

/// Any other named place on the navigation maps (the style's `pois-all`, item 132): Maki's
/// marker on a civic disc, as `poi-other`.
const (String, PoiCategory) poiOtherIcon = ('marker', PoiCategory.civic);

/// The image the style's `oneway-arrows` layer draws along one-way roads.
const String onewayImage = 'oneway';

/// Adds the images the basemap's own layers draw: the `poi-<kind>` landmark
/// icons and the one-way arrow. Overlays never wait on these: call it after
/// them.
// ponytail: re-rastered on every map load (~30 tiny SVGs); cache per theme and pixel ratio if it shows in traces.
Future<void> addBasemapImages(
  ml.MapLibreMapController c,
  PindoroColors colors,
  double pixelRatio,
) => Future.wait([
  for (final (kind, (icon, category)) in [
    for (final MapEntry(:key, :value) in poiIcons.entries) (key, value),
    ('other', poiOtherIcon),
  ])
    () async {
      final mark = PoiMark(
        icon: icon,
        color: category.color(colors),
        colors: colors,
      );
      await c.addImage('poi-$kind', await mark.toPng(pixelRatio));
    }(),
  () async {
    await c.addImage(
      onewayImage,
      await onewayArrowPng(colors.mapVectorOneway, pixelRatio),
    );
  }(),
]);
