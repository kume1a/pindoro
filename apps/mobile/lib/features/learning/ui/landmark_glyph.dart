import 'package:pindoro/core/database/database.dart'
    show Settings, StreetNameMode;
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/l10n/app_localizations.dart';
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
/// branch or a repeated name with its street ("Dunkin', Dolidze Street").
String placeName(
  AppLocalizations l10n,
  LandmarkQuestion q,
  Settings? settings,
) {
  final name = settings?.streetNames == StreetNameMode.english
      ? q.nameEn ?? q.landmark.name
      : q.landmark.name;
  return switch (q.street) {
    final street? when q.ambiguous => l10n.placeOnStreet(
      name,
      streetName(street, settings),
    ),
    _ => name,
  };
}
