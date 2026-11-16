import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_design/pindoro_design.dart';

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
  'hospital' || 'pharmacy' => PindoroGlyph.plus,
  'university' => PindoroGlyph.book,
  'monument' => PindoroGlyph.flag,
  'attraction' => PindoroGlyph.star,
  'tower' => PindoroGlyph.signpost,
  'stadium' => PindoroGlyph.trophy,
  'park' => PindoroGlyph.neighbourhood,
  'bank' => PindoroGlyph.briefcase,
  'fast_food' => PindoroGlyph.flame,
  _ => PindoroGlyph.pin,
};

/// A personal landmark kind's name: Fuel, Metro, Church, Shop, Other.
String landmarkKindName(AppLocalizations l10n, String kind) => switch (kind) {
  'fuel' => l10n.landmarkKindFuel,
  'metro' => l10n.landmarkKindMetro,
  'worship' => l10n.landmarkKindWorship,
  'shop' => l10n.landmarkKindShop,
  _ => l10n.landmarkKindOther,
};
