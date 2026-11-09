import 'package:flutter/material.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// What's new's picture of the path (canvas `WhatsNewScreen` intro): a short
/// road through a done stop, a Perfect one and the current one with its
/// ring. Decorative.
class WhatsNewRoad extends StatelessWidget {
  const WhatsNewRoad({super.key});

  /// The canvas draws it 358 × 170; stops and the road start scale with the
  /// width.
  static const double _canvasWidth = 358;
  static const double height = 170;
  static const Offset _start = Offset(30, 124);
  static const List<(Offset, PathStopLook, PindoroGlyph)> _stops = [
    (Offset(116, 74), PathStopLook.done, PindoroGlyph.check),
    (Offset(210, 124), PathStopLook.perfect, PindoroGlyph.star),
    (Offset(300, 72), PathStopLook.current, PindoroGlyph.play),
  ];

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final k = constraints.maxWidth / _canvasWidth;
            Offset at(Offset p) => Offset(p.dx * k, p.dy);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: LessonRoad(
                    points: [at(_start), for (final s in _stops) at(s.$1)],
                    driven: 2,
                  ),
                ),
                for (final (i, (centre, look, glyph)) in _stops.indexed)
                  () {
                    final current = i == _stops.length - 1;
                    final size = PathStop.sizeOf(big: current);
                    return Positioned(
                      left: at(centre).dx - size / 2,
                      top: centre.dy - size / 2,
                      child: PathStop(
                        look: look,
                        glyph: glyph,
                        big: current,
                        ring: current ? 0 : null,
                        semanticLabel: '',
                      ),
                    );
                  }(),
              ],
            );
          },
        ),
      ),
    ),
  );
}
