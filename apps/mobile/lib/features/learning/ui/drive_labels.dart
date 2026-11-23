import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/features/learning/data/drive_history.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// A destination's name: the place picked, else its street.
String targetName(DriveTarget t, Settings? settings) => switch (t.place) {
  final p? => placeLabel(p, settings),
  null => streetName(t.street, settings),
};

/// A route by its ends' names, "Home → Vake Park" (route keys, SPEC §16.23 item 120); an end
/// gone from the pack keeps its key.
String routeName(
  AppLocalizations l10n,
  String route, {
  required Map<String, Landmark> places,
  required Map<String, NamedStreet> streets,
  required Settings? settings,
}) => [
  for (final end in route.split(routeArrow))
    switch (end) {
      'home' => l10n.driveHome,
      'work' => l10n.driveWork,
      _ when end.startsWith('p:') => switch (places[end.substring(2)]) {
        final p? => placeLabel(p, settings),
        null => end,
      },
      _ when end.startsWith('s:') => switch (streets[end.substring(2)]) {
        final s? => streetName(s, settings),
        null => end,
      },
      _ => end,
    },
].join(' $routeArrow ');

/// A drive level's name (SPEC §16.23 item 112).
String levelLabel(AppLocalizations l10n, DriveLevel level) => switch (level) {
  DriveLevel.guided => l10n.driveLevelGuided,
  DriveLevel.coached => l10n.driveLevelCoached,
  DriveLevel.quiet => l10n.driveLevelQuiet,
  DriveLevel.off => l10n.driveLevelOff,
};

/// A level's icon in the picker and on the stopped bar's chip (LevelPicker).
PindoroGlyph levelIcon(DriveLevel level) => switch (level) {
  DriveLevel.guided => PindoroGlyph.map,
  DriveLevel.coached => PindoroGlyph.soundOn,
  DriveLevel.quiet => PindoroGlyph.compass,
  DriveLevel.off => PindoroGlyph.locateOff,
};
