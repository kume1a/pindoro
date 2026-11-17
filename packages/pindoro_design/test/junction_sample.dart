import 'package:pindoro_design/pindoro_design.dart';

String exitLabel(ExitDirection d) => switch (d) {
  ExitDirection.left => 'Turn left',
  ExitDirection.straight => 'Go straight on',
  ExitDirection.right => 'Turn right',
  ExitDirection.uTurn => 'Turn back',
};

const LandmarkBadge sampleLandmark = LandmarkBadge(
  name: 'Connect',
  glyph: PindoroGlyph.fuelStation,
  semanticsLabel: 'Your landmark: Connect fuel station, south-east corner',
);
