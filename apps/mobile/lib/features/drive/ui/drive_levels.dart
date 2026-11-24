import 'package:flutter/widgets.dart';
import 'package:pindoro/core/database/database.dart' show Settings;
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// What a level shows and says, in one sentence (board V32-10).
String levelNote(AppLocalizations l10n, DriveLevel level) => switch (level) {
  DriveLevel.guided => l10n.driveLevelGuidedNote,
  DriveLevel.coached => l10n.driveLevelCoachedNote,
  DriveLevel.quiet => l10n.driveLevelQuietNote,
  DriveLevel.off => l10n.driveLevelOffNote,
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
      approach != null &&
      turnAngle(approach, d.exit, d.junction).abs() < LearningConfig.navForkDeg;
  return switch (d.turn) {
    Turn.left => fork ? DriveGlyphName.keepLeft : DriveGlyphName.left,
    Turn.right => fork ? DriveGlyphName.keepRight : DriveGlyphName.right,
    Turn.uTurn => DriveGlyphName.uTurn,
    Turn.straight || null => DriveGlyphName.straight,
  };
}

/// The plate's action for [glyph]: "Left onto", "Keep left"; without [onto] (a street with
/// no name follows) "Turn left".
String decisionAction(
  AppLocalizations l10n,
  DriveGlyphName glyph, {
  bool onto = true,
}) {
  final turn = switch (glyph) {
    DriveGlyphName.left => 'left',
    DriveGlyphName.right => 'right',
    DriveGlyphName.keepLeft => 'keepLeft',
    DriveGlyphName.keepRight => 'keepRight',
    DriveGlyphName.uTurn => 'uTurn',
    _ => 'other',
  };
  return onto ? l10n.driveTurn(turn) : l10n.driveTurnBare(turn);
}

/// The ways on at a recalled turn (the preview's Recite, the debrief), one ExitButton each, in
/// [Turn] order; [onTap] hears the way tapped.
class ExitChoices extends StatelessWidget {
  const ExitChoices({required this.turns, required this.onTap, super.key});

  final Iterable<Turn> turns;
  final ValueChanged<Turn> onTap;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: PindoroSpace.s4,
    runSpacing: PindoroSpace.s3,
    children: [
      for (final turn in Turn.values)
        if (turns.contains(turn))
          ExitButton(
            direction: ExitDirection.values.byName(turn.name),
            selected: false,
            semanticsLabel: exitLabel(context.l10n, turn),
            onTap: () => onTap(turn),
          ),
    ],
  );
}

/// "At Vake Park" or "At the lights" before [d]; null when neither names it.
String? landmarkLine(
  AppLocalizations l10n,
  NavDecision d,
  Settings? settings,
) => switch (d.landmark) {
  final l? => l10n.navAt(landmarkName(l, settings)),
  null when d.signals => l10n.navAtLights,
  null => null,
};
