import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// A drive level's name (SPEC §16.23 item 112).
String levelLabel(AppLocalizations l10n, DriveLevel level) => switch (level) {
  DriveLevel.guided => l10n.driveLevelGuided,
  DriveLevel.coached => l10n.driveLevelCoached,
  DriveLevel.quiet => l10n.driveLevelQuiet,
  DriveLevel.off => l10n.driveLevelOff,
};

/// What a level shows and says, in one sentence (board V32-10).
String levelNote(AppLocalizations l10n, DriveLevel level) => switch (level) {
  DriveLevel.guided => l10n.driveLevelGuidedNote,
  DriveLevel.coached => l10n.driveLevelCoachedNote,
  DriveLevel.quiet => l10n.driveLevelQuietNote,
  DriveLevel.off => l10n.driveLevelOffNote,
};

/// A level's icon in the picker and on the stopped bar's chip (LevelPicker).
PindoroGlyph levelIcon(DriveLevel level) => switch (level) {
  DriveLevel.guided => PindoroGlyph.map,
  DriveLevel.coached => PindoroGlyph.soundOn,
  DriveLevel.quiet => PindoroGlyph.compass,
  DriveLevel.off => PindoroGlyph.locateOff,
};

/// The four levels for a [LevelPicker], those not among [choices] disabled
/// with their reason (item 114).
List<LevelStep<DriveLevel>> levelSteps(
  AppLocalizations l10n,
  List<DriveLevel> choices,
) => [
  for (final level in DriveLevel.values)
    (
      value: level,
      label: levelLabel(l10n, level),
      icon: levelIcon(level),
      disabledReason: choices.contains(level) ? null : l10n.driveTooFar,
    ),
];

/// Why the level is suggested: "14 of 17 turns are yours", or today's run's
/// "every level open".
String? suggestionReason(
  AppLocalizations l10n,
  DriveTo to,
  DriveSuggestion? suggestion,
) => to == DriveTo.run
    ? l10n.driveEveryLevel
    : suggestion == null
    ? null
    : l10n.driveYours(suggestion.yours, suggestion.turns);

/// The plate's glyph for [d]: a turn, or keep left or right at a fork.
DriveGlyphName decisionGlyph(NavDecision d) {
  final approach = d.approach;
  final fork =
      approach != null && turnAngle(approach, d.exit, d.junction).abs() < 45;
  return switch (d.turn) {
    Turn.left => fork ? DriveGlyphName.keepLeft : DriveGlyphName.left,
    Turn.right => fork ? DriveGlyphName.keepRight : DriveGlyphName.right,
    Turn.uTurn => DriveGlyphName.uTurn,
    Turn.straight || null => DriveGlyphName.straight,
  };
}

/// The plate's action for [glyph]: "Left onto", "Keep left".
String decisionAction(AppLocalizations l10n, DriveGlyphName glyph) =>
    l10n.driveTurn(switch (glyph) {
      DriveGlyphName.left => 'left',
      DriveGlyphName.right => 'right',
      DriveGlyphName.keepLeft => 'keepLeft',
      DriveGlyphName.keepRight => 'keepRight',
      DriveGlyphName.uTurn => 'uTurn',
      _ => 'other',
    });
