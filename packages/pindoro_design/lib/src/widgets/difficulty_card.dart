import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'surfaces.dart';
import 'tappable.dart';

/// A selectable difficulty: road art (more and thinner roads per level), the
/// name, a four-bar gauge and the description. One of four in a radio group.
class DifficultyCard extends StatelessWidget {
  const DifficultyCard({
    super.key,
    required this.difficulty,
    required this.name,
    required this.description,
    required this.selected,
    required this.onPressed,
  });

  final Difficulty difficulty;
  final String name;
  final String description;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final level = difficulty.index + 1;
    final levels = Difficulty.values.length;
    return Tappable(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: '$name, $description, $level / $levels',
      onTap: onPressed,
      child: LipBox(
        face: selected ? c.primarySoft : c.surfaceRaised,
        lip: selected ? c.primaryBase : c.lineBase,
        border: selected ? c.primaryBase : c.lineBase,
        lipHeight: PindoroElevation.e2,
        child: Padding(
          padding: const EdgeInsets.all(PindoroSpace.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: PindoroSpace.s2,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(PindoroRadius.md),
                child: SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _RoadArt(colors: c, level: level),
                  ),
                ),
              ),
              Text(
                name,
                style: PindoroType.titleLg.copyWith(color: c.textPrimary),
              ),
              Row(
                spacing: 3,
                children: [
                  for (var i = 1; i <= levels; i++)
                    Container(
                      width: 14,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i <= level ? c.primaryText : c.xpTrack,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              Text(
                description,
                style: PindoroType.bodySm.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A grid of streets on the basemap; [level] of them (1, 3, 6, 10) in answer
/// paint, thinner each level.
class _RoadArt extends CustomPainter {
  _RoadArt({required this.colors, required this.level});

  final PindoroColors colors;
  final int level;

  static const _highlighted = [1, 3, 6, 10];
  static const _width = [18.0, 11.0, 6.0, 3.0];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.mapBasemapLand);
    final road = Paint()
      ..color = colors.mapBasemapRoad
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final casing = Paint()
      ..color = colors.mapBasemapCasing
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final lines = <(Offset, Offset)>[
      for (var i = 1; i <= 4; i++)
        (
          Offset(0, size.height * i / 5),
          Offset(size.width, size.height * i / 5),
        ),
      for (var i = 1; i <= 6; i++)
        (
          Offset(size.width * i / 7, 0),
          Offset(size.width * i / 7, size.height),
        ),
    ];
    for (final (a, b) in lines) {
      canvas
        ..drawLine(a, b, casing)
        ..drawLine(a, b, road);
    }
    final paint = Paint()
      ..color = colors.mapAnswerLine
      ..strokeWidth = _width[level - 1]
      ..strokeCap = StrokeCap.round;
    // A fixed order so each level adds roads to the previous one.
    const order = [1, 7, 3, 5, 0, 9, 2, 6, 4, 8];
    for (final i in order.take(_highlighted[level - 1])) {
      final (a, b) = lines[i];
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(_RoadArt old) =>
      old.level != level || old.colors != colors;
}
