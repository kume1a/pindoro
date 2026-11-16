import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'painters.dart';
import 'surfaces.dart';
import 'tappable.dart';

/// A way out of a junction, as the driver sees it.
enum ExitDirection {
  left(PindoroGlyph.turnLeft),
  straight(PindoroGlyph.straight),
  right(PindoroGlyph.turnRight),
  uTurn(PindoroGlyph.uTurn);

  const ExitDirection(this.glyph);

  final PindoroGlyph glyph;
}

/// One exit of the junction map (Exit button): a 56 dp round secondary
/// button with its direction's arrow; [selected] takes the primary colours.
/// A toggle for screen readers, labelled with the action ("Turn right").
/// Placed centred on its arm; [JunctionMap] places its own.
class ExitButton extends StatefulWidget {
  const ExitButton({
    super.key,
    required this.direction,
    required this.selected,
    required this.onTap,
    required this.semanticsLabel,
  });

  final ExitDirection direction;
  final bool selected;
  final VoidCallback onTap;
  final String semanticsLabel;

  /// The face; the lip adds [PindoroElevation.e2] below it.
  static const double size = PindoroSize.buttonLg;

  @override
  State<ExitButton> createState() => _ExitButtonState();
}

class _ExitButtonState extends State<ExitButton> {
  bool _pressed = false;

  void _press(bool down) => setState(() => _pressed = down);

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final selected = widget.selected;
    final (face, lip, ink, border) = selected
        ? (c.primaryBase, c.primaryLip, c.primaryOn, null)
        : (
            c.buttonSecondaryBg,
            c.buttonSecondaryLip,
            c.textSecondary,
            c.buttonSecondaryBorder,
          );
    const lipHeight = PindoroElevation.e2;
    return Tappable(
      label: widget.semanticsLabel,
      toggled: selected,
      onTap: widget.onTap,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      child: SizedBox(
        width: ExitButton.size,
        height: ExitButton.size + lipHeight,
        child: Stack(
          children: [
            Positioned(top: lipHeight, child: _disc(ExitButton.size, lip)),
            AnimatedPositioned(
              duration: PindoroMotion.durationInstant,
              curve: PindoroMotion.easePress,
              top: _pressed ? lipHeight : 0,
              child: Container(
                width: ExitButton.size,
                height: ExitButton.size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: face,
                  shape: BoxShape.circle,
                  border: border == null
                      ? null
                      : Border.all(color: border, width: PindoroStroke.base),
                ),
                child: PindoroIcon(
                  widget.direction.glyph,
                  size: PindoroSize.iconMd,
                  color: ink,
                  cut: face,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _disc(double size, Color color) => Container(
  width: size,
  height: size,
  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
);

/// A landmark on the junction map (Landmark badge): a 40 dp raised tile with
/// the kind's [glyph], and its [name] on the white map label 40 dp below the
/// tile's centre. One image for screen readers ([semanticsLabel]: "Your
/// landmark: Connect fuel station, south-east corner"). Its anchor is the
/// tile's centre: [anchorY] below the top, centred across.
class LandmarkBadge extends StatelessWidget {
  const LandmarkBadge({
    super.key,
    required this.name,
    required this.glyph,
    required this.semanticsLabel,
  });

  final String name;
  final PindoroGlyph glyph;
  final String semanticsLabel;

  static const double _tile = 40;

  /// From the top to the tile's centre.
  static const double anchorY = _tile / 2;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      image: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LipBox(
            lip: c.lineStrong,
            radius: PindoroRadius.md,
            child: SizedBox.square(
              dimension: _tile,
              child: Center(
                child: PindoroIcon(
                  glyph,
                  size: PindoroSize.iconMd,
                  color: c.textPrimary,
                  cut: c.surfaceRaised,
                ),
              ),
            ),
          ),
          // The label's centre sits a tile below the tile's centre.
          const SizedBox(
            height:
                _tile -
                _tile / 2 -
                MapLabelChip.height / 2 -
                PindoroElevation.e1,
          ),
          MapLabelChip(name),
        ],
      ),
    );
  }
}

/// The white street or place label on a map (`.pd-region-label`): 24 dp,
/// round, on a lip with the floating shadow.
class MapLabelChip extends StatelessWidget {
  const MapLabelChip(this.label, {super.key});

  final String label;

  static const double height = 24;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return LipBox(
      face: c.mapRegionLabelBg,
      radius: PindoroRadius.full,
      shadow: true,
      child: Container(
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: PindoroSpace.s2),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: PindoroType.labelMd.copyWith(color: c.mapRegionLabelText),
        ),
      ),
    );
  }
}

/// The driver on a drawn map (`.pd-map-car`): a 32 dp route-arrow disc with
/// the car in route paint, ringed in the halo colour. Centred on its point.
class CarMarker extends StatelessWidget {
  const CarMarker({super.key, this.semanticsLabel});

  /// "You, driving north on Aghmashenebeli Avenue"; decorative without.
  final String? semanticsLabel;

  static const double size = PindoroSize.iconLg + 2 * PindoroStroke.base;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      image: semanticsLabel != null,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.mapPlayerHalo,
          shape: BoxShape.circle,
        ),
        child: Container(
          width: PindoroSize.iconLg,
          height: PindoroSize.iconLg,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.mapRouteArrow,
            shape: BoxShape.circle,
          ),
          child: PindoroIcon(
            PindoroGlyph.car,
            size: PindoroSize.iconSm,
            color: c.mapRouteLine,
            cut: c.mapRouteArrow,
          ),
        ),
      ),
    );
  }
}

/// A tip bubble on the map (`.pd-tip`): a raised tooltip with its pointer
/// below, for numbered bridges and the current crossing; [selected] takes
/// the primary colours. Its anchor is the pointer's tip: bottom centre.
class MapTip extends StatelessWidget {
  const MapTip(this.label, {super.key, this.selected = false});

  final String label;
  final bool selected;

  static const Size _tail = Size(14, 7);

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final (face, ink, lip) = selected
        ? (c.primaryBase, c.primaryOn, c.primaryLip)
        : (c.surfaceRaised, c.primaryText, c.lineBase);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LipBox(
          face: face,
          lip: lip,
          radius: PindoroRadius.md,
          padding: const EdgeInsets.symmetric(
            horizontal: PindoroSpace.s3,
            vertical: PindoroSpace.s2,
          ),
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: PindoroType.labelLg.copyWith(
              color: ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        CustomPaint(size: _tail, painter: TailPainter(lip, down: true)),
      ],
    );
  }
}

/// A road's drawn width on the junction map, by class.
enum JunctionRoadClass {
  main(30),
  secondary(22),
  minor(14),
  local(12);

  const JunctionRoadClass(this.width);

  /// In dp; its casing is 4 dp wider.
  final double width;
}

/// A road near the junction, in metres around it (x east, y north, the
/// junction at the origin).
typedef JunctionRoad = ({List<Offset> line, JunctionRoadClass roadClass});

/// What the junction map draws, in metres around the junction (x east,
/// y north, the junction at the origin): every [roads] line (the arms
/// included), the [approach] (from where the driver comes, ending at the
/// origin), each exit's line from the origin outwards, and optionally
/// building and park blocks and the landmark's plot and point. Lines that
/// stop inside the frame are drawn on to its edge.
class JunctionGeometry {
  const JunctionGeometry({
    required this.roads,
    required this.approach,
    required this.exits,
    this.buildings = const [],
    this.parks = const [],
    this.landmarkPlot,
    this.landmarkBuilding,
    this.landmarkAt,
  });

  final List<JunctionRoad> roads;
  final List<Offset> approach;
  final Map<ExitDirection, List<Offset>> exits;
  final List<Rect> buildings;
  final List<Rect> parks;
  final Rect? landmarkPlot;
  final Rect? landmarkBuilding;

  /// Where the landmark badge sits.
  final Offset? landmarkAt;
}

/// Where the junction map is: asking, or after Confirm right or wrong.
enum JunctionState { choosing, right, wrong }

/// The drawn map of a junction card (Junction map): heading-up, the approach
/// a cobalt arrow from the bottom with the car on it, the landmark on its
/// corner and, while [JunctionState.choosing], one [ExitButton] per exit.
/// After Confirm the buttons go; the [correct] exit paints yellow from the
/// approach through the turn and, when wrong, the [chosen] arm shows cobalt
/// dashes first. Static: no pan or zoom. Fills its parent.
class JunctionMap extends StatefulWidget {
  const JunctionMap({
    super.key,
    required this.geometry,
    required this.state,
    required this.onChoose,
    required this.exitLabel,
    required this.semanticsLabel,
    this.chosen,
    this.correct,
    this.landmark,
    this.carLabel,
    this.animate = false,
  });

  final JunctionGeometry geometry;
  final JunctionState state;
  final ValueChanged<ExitDirection> onChoose;

  /// "Turn left", "Go straight on", "Turn right".
  final String Function(ExitDirection) exitLabel;

  /// "Unlabelled map of the junction ahead."
  final String semanticsLabel;
  final ExitDirection? chosen;

  /// Set once confirmed.
  final ExitDirection? correct;
  final LandmarkBadge? landmark;
  final String? carLabel;

  /// Paints the result in (reduce motion off).
  final bool animate;

  @override
  State<JunctionMap> createState() => _JunctionMapState();
}

class _JunctionMapState extends State<JunctionMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    value: 1,
  );

  @override
  void didUpdateWidget(JunctionMap old) {
    super.didUpdateWidget(old);
    if (old.state == JunctionState.choosing &&
        widget.state != JunctionState.choosing &&
        widget.animate) {
      _reveal
        ..duration =
            PindoroMotion.durationBase *
            (widget.state == JunctionState.wrong ? 2 : 1)
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = PindoroTheme.of(context).colors;
    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final view = _JunctionView(widget.geometry, size);
          final landmark = widget.landmark;
          final landmarkAt = widget.geometry.landmarkAt;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _reveal,
                  builder: (context, _) => CustomPaint(
                    painter: _JunctionPainter(
                      view: view,
                      colors: colors,
                      state: widget.state,
                      chosen: widget.chosen,
                      correct: widget.correct,
                      progress: _reveal.value,
                    ),
                  ),
                ),
              ),
              if (landmark != null && landmarkAt != null)
                _at(
                  view.toScreen(landmarkAt),
                  landmark,
                  anchor: const Offset(-0.5, 0),
                  dy: -LandmarkBadge.anchorY,
                ),
              _at(
                view.along(view.approachBack, _carBackDp),
                CarMarker(semanticsLabel: widget.carLabel),
              ),
              if (widget.state == JunctionState.choosing)
                for (final direction in widget.geometry.exits.keys)
                  _at(
                    view.along(view.exit(direction), _buttonOutDp),
                    ExitButton(
                      direction: direction,
                      selected: widget.chosen == direction,
                      onTap: () => widget.onChoose(direction),
                      semanticsLabel: widget.exitLabel(direction),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  static Widget _at(
    Offset point,
    Widget child, {
    Offset anchor = const Offset(-0.5, -0.5),
    double dy = 0,
  }) => Positioned(
    left: point.dx,
    top: point.dy + dy,
    child: FractionalTranslation(translation: anchor, child: child),
  );
}

/// Metres across the frame's width.
const double _spanM = 260;

/// The junction's height in the frame, from the top.
const double _centreY = 0.51;

/// Along the approach, back from the junction centre, in dp: the arrowhead
/// is 28 dp wide and 22 dp tall.
const double _arrowTipDp = 64;
const double _arrowBaseDp = _arrowTipDp + 22;
const double _arrowWidth = 28;
const double _approachLineDp = 82;
const double _approachHaloDp = 70;
const double _correctFromDp = 90;
const double _carBackDp = 260;

/// An exit button's centre out along its arm.
const double _buttonOutDp = 112;

/// The junction's geometry projected heading-up into a frame of [size].
class _JunctionView {
  _JunctionView(this.geometry, this.size)
    : scale = size.width / _spanM,
      centre = Offset(size.width / 2, size.height * _centreY) {
    final approach = geometry.approach;
    final from = approach.length >= 2
        ? approach[approach.length - 2]
        : const Offset(0, -1);
    // The approach runs into the junction; turn it to point up the screen.
    final into = Offset.zero - from;
    rotation = -math.pi / 2 - math.atan2(-into.dy, into.dx);
  }

  final JunctionGeometry geometry;
  final Size size;

  /// dp per metre.
  final double scale;
  final Offset centre;
  late final double rotation;

  Offset toScreen(Offset m) {
    final x = m.dx * scale, y = -m.dy * scale;
    final cos = math.cos(rotation), sin = math.sin(rotation);
    return centre + Offset(x * cos - y * sin, x * sin + y * cos);
  }

  /// Applies the projection to [canvas], so metres draw in place.
  void transform(Canvas canvas) {
    canvas
      ..translate(centre.dx, centre.dy)
      ..rotate(rotation)
      ..scale(scale, -scale);
  }

  /// Screen points from the junction centre back along the approach, run
  /// on past the frame's edge.
  late final List<Offset> approachBack = _runOn([
    centre,
    for (final m in geometry.approach.reversed.skip(1)) toScreen(m),
  ]);

  /// [direction]'s exit from the junction centre, run on past the edge.
  List<Offset> exit(ExitDirection direction) => _runOn([
    centre,
    for (final m in geometry.exits[direction]!.skip(1)) toScreen(m),
  ]);

  List<Offset> _runOn(List<Offset> points) {
    if (points.length < 2) return points;
    final last = points.last, before = points[points.length - 2];
    final step = last - before;
    if (step.distance == 0) return points;
    return [...points, last + step / step.distance * size.longestSide * 2];
  }

  /// The point [dp] along [line] from its start.
  Offset along(List<Offset> line, double dp) {
    var left = dp;
    for (var i = 1; i < line.length; i++) {
      final step = line[i] - line[i - 1];
      if (step.distance >= left) {
        return line[i - 1] + step / step.distance * left;
      }
      left -= step.distance;
    }
    return line.last;
  }
}

Path _path(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  return path;
}

/// [path] from [from] dp to [to] dp along it.
Path _part(Path path, double from, double to) {
  final out = Path();
  var start = 0.0;
  for (final metric in path.computeMetrics()) {
    final a = (from - start).clamp(0, metric.length).toDouble();
    final b = (to - start).clamp(0, metric.length).toDouble();
    if (b > a) out.addPath(metric.extractPath(a, b), Offset.zero);
    start += metric.length;
  }
  return out;
}

double _length(Path path) =>
    path.computeMetrics().fold(0, (sum, m) => sum + m.length);

class _JunctionPainter extends CustomPainter {
  _JunctionPainter({
    required this.view,
    required this.colors,
    required this.state,
    required this.chosen,
    required this.correct,
    required this.progress,
  });

  final _JunctionView view;
  final PindoroColors colors;
  final JunctionState state;
  final ExitDirection? chosen;
  final ExitDirection? correct;

  /// 0 … 1 through the reveal: on a wrong answer your dashes take the first
  /// half, the yellow exit the second.
  final double progress;

  Paint _stroke(Color color, double width) => Paint()
    ..style = PaintingStyle.stroke
    ..color = color
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    final g = view.geometry;
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.mapBasemapLand);

    // Blocks and roads in metres: widths and corners divided by the scale.
    canvas.save();
    view.transform(canvas);
    final m = 1 / view.scale;
    RRect block(Rect r, double radiusDp) =>
        RRect.fromRectAndRadius(r, Radius.circular(radiusDp * m));
    for (final b in g.buildings) {
      canvas.drawRRect(block(b, 6), Paint()..color = colors.mapBasemapBuilding);
    }
    for (final p in g.parks) {
      canvas.drawRRect(block(p, 6), Paint()..color = colors.mapBasemapPark);
    }
    for (final r in g.roads) {
      canvas.drawPath(
        _path(r.line),
        _stroke(colors.mapBasemapCasing, (r.roadClass.width + 4) * m)
          ..strokeCap = StrokeCap.butt,
      );
    }
    for (final r in g.roads) {
      canvas.drawPath(
        _path(r.line),
        _stroke(colors.mapBasemapRoad, r.roadClass.width * m)
          ..strokeCap = StrokeCap.butt,
      );
    }
    if (g.landmarkPlot case final plot?) {
      canvas
        ..drawRRect(block(plot, 8), Paint()..color = colors.mapBasemapLand)
        ..drawRRect(
          block(plot, 8),
          _stroke(colors.mapBasemapCasing, PindoroStroke.base * m),
        );
    }
    if (g.landmarkBuilding case final building?) {
      canvas.drawRRect(
        block(building, 6),
        Paint()..color = colors.mapBasemapBuilding,
      );
    }
    canvas.restore();

    final wrong = state == JunctionState.wrong;
    final correctT = wrong ? ((progress - 0.5) * 2).clamp(0.0, 1.0) : progress;
    final wrongT = (progress * 2).clamp(0.0, 1.0);

    // The correct exit: from the approach through the turn to the edge.
    final correct = this.correct;
    if (state != JunctionState.choosing && correct != null && correctT > 0) {
      final back = view.approachBack;
      final into = <Offset>[view.along(back, _correctFromDp)];
      var walked = 0.0;
      for (var i = 1; i < back.length; i++) {
        walked += (back[i] - back[i - 1]).distance;
        if (walked >= _correctFromDp) break;
        into.insert(0, back[i]);
      }
      final route = _path([...into.reversed, ...view.exit(correct)]);
      final shown = _part(route, 0, _length(route) * correctT);
      canvas
        ..drawPath(shown, _stroke(colors.mapRouteCasing, 16))
        ..drawPath(shown, _stroke(colors.mapRouteLine, 10));
    }

    // Your wrong choice: cobalt dashes from the centre along its arm.
    final chosen = this.chosen;
    if (wrong && chosen != null && view.geometry.exits.containsKey(chosen)) {
      final arm = _path(view.exit(chosen));
      final shown = _part(arm, 0, _length(arm) * wrongT);
      canvas.drawPath(shown, _stroke(colors.mapPlayerHalo, 14));
      final dashes = Path();
      final end = _length(shown);
      for (var d = 0.0; d < end; d += 18) {
        dashes.addPath(_part(shown, d, math.min(d + 10, end)), Offset.zero);
      }
      canvas.drawPath(dashes, _stroke(colors.mapPlayerRoute, 6));
    }

    // The approach: from the bottom edge to just short of the junction.
    final back = _path(view.approachBack);
    final far = _length(back);
    canvas
      ..drawPath(
        _part(back, _approachHaloDp, far),
        _stroke(colors.mapPlayerHalo, 16),
      )
      ..drawPath(
        _part(back, _approachLineDp, far),
        _stroke(colors.mapPlayerRoute, 8),
      );
    final tip = view.along(view.approachBack, _arrowTipDp);
    final base = view.along(view.approachBack, _arrowBaseDp);
    final ahead = tip - base;
    if (ahead.distance > 0) {
      final unit = ahead / ahead.distance;
      final side = Offset(-unit.dy, unit.dx) * (_arrowWidth / 2);
      final head = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo((base + side).dx, (base + side).dy)
        ..lineTo((base - side).dx, (base - side).dy)
        ..close();
      canvas
        ..drawPath(head, Paint()..color = colors.mapPlayerRoute)
        ..drawPath(head, _stroke(colors.mapPlayerRoute, 4));
    }
  }

  @override
  bool shouldRepaint(_JunctionPainter old) =>
      old.view.geometry != view.geometry ||
      old.view.size != view.size ||
      old.colors != colors ||
      old.state != state ||
      old.chosen != chosen ||
      old.correct != correct ||
      old.progress != progress;
}
