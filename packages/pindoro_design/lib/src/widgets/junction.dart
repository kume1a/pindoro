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
