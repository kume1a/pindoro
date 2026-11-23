import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The driving glyphs (design system DriveGlyph): bolder than the 24-grid
/// icons, read at a glance from a phone in a holder. Branches not taken are
/// drawn at 35 %, so the junction's shape shows.
enum DriveGlyphName {
  left(
    '<path d="M32 43V24a6 6 0 0 0-6-6H9" stroke-width="7"/>'
    '<path d="M16 10l-8 8 8 8" stroke-width="7"/>',
  ),
  right(
    '<path d="M16 43V24a6 6 0 0 1 6-6h17" stroke-width="7"/>'
    '<path d="M32 10l8 8-8 8" stroke-width="7"/>',
  ),
  straight(
    '<path d="M12 30h24" stroke-width="6" opacity="0.35"/>'
    '<path d="M24 43V7" stroke-width="7"/>'
    '<path d="M15 15l9-9 9 9" stroke-width="7"/>',
  ),
  // Up the right and back down the left: traffic keeps right, so a U-turn turns left.
  uTurn(
    '<path d="M32 43V18a8 8 0 0 0-16 0v14" stroke-width="7"/>'
    '<path d="M24 26l-8 8-8-8" stroke-width="7"/>',
  ),
  keepLeft(
    '<path d="M30 43V31l8-9V8" stroke-width="6" opacity="0.35"/>'
    '<path d="M30 31L16 17V7" stroke-width="7"/>'
    '<path d="M9 13l7-7 7 7" stroke-width="7"/>',
  ),
  keepRight(
    '<path d="M18 43V31l-8-9V8" stroke-width="6" opacity="0.35"/>'
    '<path d="M18 31l14-14V7" stroke-width="7"/>'
    '<path d="M25 13l7-7 7 7" stroke-width="7"/>',
  ),
  merge(
    '<path d="M36 43V31L26 21" stroke-width="6" opacity="0.35"/>'
    '<path d="M14 43V31l10-10V7" stroke-width="7"/>'
    '<path d="M16 14l8-8 8 8" stroke-width="7"/>',
  ),
  roundabout1(
    '<path d="M24 16V5M16 24H6M32 24a8 8 0 1 0-8 8" stroke-width="6" '
    'opacity="0.35"/>'
    '<path d="M24 44V32a8 8 0 0 0 8-8h10" stroke-width="7"/>'
    '<path d="M37 17l7 7-7 7" stroke-width="7"/>',
  ),
  roundabout2(
    '<path d="M32 24h10M16 24H6" stroke-width="6" opacity="0.35"/>'
    '<path d="M24 44V32a8 8 0 1 0 0-16V5" stroke-width="7"/>'
    '<path d="M17 11l7-7 7 7" stroke-width="7"/>',
  ),
  roundabout3(
    '<path d="M32 24h10M24 16V5" stroke-width="6" opacity="0.35"/>'
    '<path d="M24 44V32a8 8 0 1 0-8-8H5" stroke-width="7"/>'
    '<path d="M11 17l-7 7 7 7" stroke-width="7"/>',
  ),
  flag(
    '<path d="M13 44V6" stroke-width="7"/>'
    '<path d="M15 7h22l-6 8 6 8H15z" fill="currentColor" stroke-width="3"/>',
  ),
  rescue(
    '<circle cx="24" cy="24" r="16" stroke-width="7"/>'
    '<circle cx="24" cy="24" r="7" stroke-width="7"/>'
    '<path d="M13 13l6 6M35 13l-6 6M13 35l6-6M35 35l-6-6" stroke-width="7"/>',
  ),
  recentre(
    '<path d="M24 8L38 40L24 32L10 40Z" fill="currentColor" '
    'stroke-width="3"/>',
  ),
  compass(
    '<circle cx="24" cy="24" r="18" stroke-width="7"/>'
    '<path d="M24 9l6 15h-12z" fill="currentColor"/>'
    '<path d="M24 39l-6-15h12z" fill="currentColor" opacity="0.35"/>',
  ),
  routes(
    '<path d="M24 44V30" stroke-width="7"/>'
    '<path d="M24 30c0-7 11-8 11-16v-3" stroke-width="6" opacity="0.35"/>'
    '<circle cx="35" cy="7" r="4.5" fill="currentColor" opacity="0.35"/>'
    '<path d="M24 30c0-7-11-8-11-16v-3" stroke-width="7"/>'
    '<circle cx="13" cy="7" r="4.5" fill="currentColor"/>',
  ),
  park(
    '<path d="M24 5l11 15h-6l9 12H27v11h-6V32H10l9-12h-6z" '
    'fill="currentColor"/>',
  ),
  fuel(
    '<path d="M10 8h18v35H10z" fill="currentColor"/>'
    '<path d="M14 13h10v9H14z" fill="CUT"/>'
    '<path d="M28 16l7 5v15a3 3 0 0 0 6 0V22l-4-6" stroke-width="4"/>',
  ),
  shop(
    '<path d="M9 17h30l-3 25H12z" fill="currentColor"/>'
    '<path d="M17 17v-3a7 7 0 0 1 14 0v3" stroke-width="4"/>',
  ),
  metro(
    '<path d="M7 40V8h8l9 16 9-16h8v32h-8V23l-9 15-9-15v17z" '
    'fill="currentColor"/>',
  ),
  lights(
    '<path d="M15 3h18a3 3 0 0 1 3 3v29a3 3 0 0 1-3 3H27v7h-6v-7h-6a3 3 0 0 '
    '1-3-3V6a3 3 0 0 1 3-3z" fill="currentColor"/>'
    '<circle cx="24" cy="11" r="4.5" fill="CUT"/>'
    '<circle cx="24" cy="21" r="4.5" fill="CUT"/>'
    '<circle cx="24" cy="31" r="4.5" fill="CUT"/>',
  ),
  camera(
    '<path d="M6 15h8l4-6h12l4 6h8a2 2 0 0 1 2 2v20a2 2 0 0 1-2 2H6a2 2 0 0 '
    '1-2-2V17a2 2 0 0 1 2-2z" fill="currentColor"/>'
    '<circle cx="24" cy="26" r="8.5" fill="CUT"/>'
    '<circle cx="24" cy="26" r="4.5" fill="currentColor"/>',
  );

  const DriveGlyphName(this.markup);

  /// The glyph's elements on the 48 grid: `currentColor` is the ink, `CUT`
  /// the colour behind (cut-outs).
  final String markup;
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// A [DriveGlyphName] at [size] in [color], its cut-outs in [cut] (the colour
/// behind it). Decorative: what holds it carries the words. Strokes scale
/// with the glyph.
class DriveGlyph extends StatelessWidget {
  const DriveGlyph(
    this.name, {
    super.key,
    required this.size,
    required this.color,
    required this.cut,
  });

  final DriveGlyphName name;
  final double size;
  final Color color;
  final Color cut;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.string(
      driveGlyphSvg(name, color: color, cut: cut),
      width: size,
      height: size,
    ),
  );
}

/// [name]'s SVG on its 48 grid, in [color] with its cut-outs in [cut].
String driveGlyphSvg(
  DriveGlyphName name, {
  required Color color,
  required Color cut,
}) {
  final ink = _hex(color);
  // Elements without a stroke width are fills only; the root's zero width
  // keeps them unstroked.
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" '
      'fill="none" stroke="$ink" stroke-width="0" stroke-linecap="round" '
      'stroke-linejoin="round">'
      '${name.markup.replaceAll('currentColor', ink).replaceAll('CUT', _hex(cut))}'
      '</svg>';
}
