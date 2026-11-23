import 'package:pindoro/core/database/database.dart' show Settings;
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart' show Landmark, Poi;
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart' show LandmarkQuestion;

/// The icon for a landmark kind: the player's own (fuel, metro, worship, shop,
/// other) and the pack's OSM kinds (SPEC §9).
PindoroGlyph landmarkGlyph(String kind) => switch (kind) {
  'fuel' => PindoroGlyph.fuelStation,
  'metro' || 'station' => PindoroGlyph.route,
  'bridge' => PindoroGlyph.road,
  'square' => PindoroGlyph.district,
  'roundabout' => PindoroGlyph.reroute,
  'worship' => PindoroGlyph.bell,
  'shop' || 'mall' || 'supermarket' => PindoroGlyph.gift,
  'hospital' => PindoroGlyph.plus,
  'university' => PindoroGlyph.book,
  'monument' => PindoroGlyph.star,
  'attraction' => PindoroGlyph.star,
  'tower' => PindoroGlyph.signpost,
  'stadium' => PindoroGlyph.trophy,
  'park' => PindoroGlyph.neighbourhood,
  'fast_food' => PindoroGlyph.flame,
  _ => PindoroGlyph.pin,
};

/// The icon for any place (item 132): a landmark kind's, else a named place's by its OSM tag
/// value or key.
PindoroGlyph placeGlyph(Landmark place) => switch (place) {
  Poi(:final kind, :final osmKey) => switch (kind) {
    'restaurant' ||
    'cafe' ||
    'bar' ||
    'pub' ||
    'food_court' => PindoroGlyph.flame,
    'place_of_worship' => PindoroGlyph.bell,
    'pharmacy' || 'clinic' || 'doctors' || 'dentist' => PindoroGlyph.plus,
    'school' || 'college' || 'kindergarten' || 'library' => PindoroGlyph.book,
    'hotel' || 'hostel' || 'guest_house' => PindoroGlyph.home,
    'bank' || 'bureau_de_change' => PindoroGlyph.briefcase,
    'museum' || 'gallery' || 'theatre' || 'cinema' => PindoroGlyph.star,
    'car_wash' || 'car_repair' || 'car' || 'car_parts' => PindoroGlyph.car,
    'bus_station' || 'aerodrome' => PindoroGlyph.route,
    'garden' ||
    'sports_centre' ||
    'fitness_centre' => PindoroGlyph.neighbourhood,
    _ => switch (landmarkGlyph(kind)) {
      PindoroGlyph.pin => switch (osmKey) {
        'shop' => PindoroGlyph.gift,
        'office' => PindoroGlyph.briefcase,
        'craft' => PindoroGlyph.wrench,
        'healthcare' => PindoroGlyph.plus,
        'tourism' || 'historic' => PindoroGlyph.star,
        'leisure' => PindoroGlyph.neighbourhood,
        _ => PindoroGlyph.pin,
      },
      final glyph => glyph,
    },
  },
  _ => landmarkGlyph(place.kind),
};

/// Any place's kind as named (item 132): a named place's by its OSM tag value, else its key; a
/// landmark's by [landmarkKindName].
String placeKindName(AppLocalizations l10n, Landmark place) => switch (place) {
  Poi(:final kind, :final osmKey) => switch (l10n.poiKind(kind)) {
    '' => l10n.poiKey(osmKey),
    final name => name,
  },
  _ => landmarkKindName(l10n, place.kind),
};

/// A landmark's badge on the drive's turn plate: the kinds DriveGlyph draws;
/// null for the others, which go without a badge.
DriveGlyphName? landmarkDriveGlyph(String kind) => switch (kind) {
  'park' => DriveGlyphName.park,
  'fuel' => DriveGlyphName.fuel,
  'metro' || 'station' => DriveGlyphName.metro,
  'shop' || 'mall' || 'supermarket' => DriveGlyphName.shop,
  _ => null,
};

/// A landmark kind's name: the player's own (Fuel, Metro, Church, Shop,
/// Other) and the pack's OSM kinds.
String landmarkKindName(AppLocalizations l10n, String kind) => switch (kind) {
  'fuel' => l10n.landmarkKindFuel,
  'metro' => l10n.landmarkKindMetro,
  'worship' => l10n.landmarkKindWorship,
  'shop' => l10n.landmarkKindShop,
  'square' => l10n.landmarkKindSquare,
  'mall' => l10n.landmarkKindMall,
  'supermarket' => l10n.landmarkKindSupermarket,
  'station' => l10n.landmarkKindStation,
  'hospital' => l10n.landmarkKindHospital,
  'university' => l10n.landmarkKindUniversity,
  'monument' => l10n.landmarkKindMonument,
  'attraction' => l10n.landmarkKindSight,
  'tower' => l10n.landmarkKindTower,
  'stadium' => l10n.landmarkKindStadium,
  'park' => l10n.landmarkKindPark,
  'fast_food' => l10n.landmarkKindFastFood,
  'bridge' => l10n.landmarkKindBridge,
  'roundabout' => l10n.landmarkKindRoundabout,
  _ => l10n.landmarkKindOther,
};

/// A place as a question names it, in the street names' script: a chain's
/// branch or a repeated name with its street ("Dunkin', Dolidze Street"), and
/// with its corner when another of its name stands on that street too.
String placeName(
  AppLocalizations l10n,
  LandmarkQuestion q,
  Settings? settings,
) {
  final name = landmarkName(q.landmark, settings);
  return switch ((q.street, q.crossStreet)) {
    (final street?, final cross?) => l10n.placeAtCorner(
      name,
      streetName(street, settings),
      streetName(cross, settings),
    ),
    (final street?, _) when q.ambiguous => l10n.placeOnStreet(
      name,
      streetName(street, settings),
    ),
    _ => name,
  };
}
