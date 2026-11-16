import 'package:flutter/material.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The design system's sample junction: a main road north–south crossed by
/// a secondary street, blocks, a park, and a fuel station's plot on the
/// south-east corner. Metres around the junction (x east, y north).
const JunctionGeometry sampleJunction = JunctionGeometry(
  roads: [
    (
      line: [Offset(0, -400), Offset(0, 400)],
      roadClass: JunctionRoadClass.main,
    ),
    (
      line: [Offset(-300, 0), Offset(300, 0)],
      roadClass: JunctionRoadClass.secondary,
    ),
    (
      line: [Offset(-300, 188), Offset(300, 188)],
      roadClass: JunctionRoadClass.minor,
    ),
    (
      line: [Offset(-97, -400), Offset(-97, 400)],
      roadClass: JunctionRoadClass.local,
    ),
    (
      line: [Offset(97, -400), Offset(97, 400)],
      roadClass: JunctionRoadClass.local,
    ),
    (
      line: [Offset(-300, -188), Offset(300, -188)],
      roadClass: JunctionRoadClass.local,
    ),
  ],
  approach: [Offset(0, -400), Offset.zero],
  exits: {
    ExitDirection.left: [Offset.zero, Offset(-300, 0)],
    ExitDirection.straight: [Offset.zero, Offset(0, 400)],
    ExitDirection.right: [Offset.zero, Offset(300, 0)],
  },
  buildings: [
    Rect.fromLTRB(-89, 12, -14, 178),
    Rect.fromLTRB(14, 12, 89, 178),
    Rect.fromLTRB(-89, -181, -14, -12),
    Rect.fromLTRB(14, -181, 89, -12),
    Rect.fromLTRB(-89, -311, -14, -197),
    Rect.fromLTRB(14, -311, 89, -197),
    Rect.fromLTRB(108, -178, 152, -12),
  ],
  parks: [Rect.fromLTRB(-148, 12, -109, 178)],
  landmarkPlot: Rect.fromLTRB(14, -78, 89, -12),
  landmarkBuilding: Rect.fromLTRB(22, -48, 80, -23),
  landmarkAt: Offset(51, -51),
);

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
