import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';

const String _package = 'pindoro_design';

/// The design system's 62 icons (assets/icons, 24 dp grid). Game icons keep
/// fixed meanings: star Perfect, checkCircle Great, target Close, reroute Miss.
enum PindoroGlyph {
  back('back'),
  bell('bell'),
  bolt('bolt'),
  book('book'),
  calendar('calendar'),
  car('car'),
  check('check'),
  checkCircle('check-circle'),
  chevronDown('chevron-down'),
  chevronRight('chevron-right'),
  city('city'),
  close('close'),
  compass('compass'),
  district('district'),
  download('download'),
  edit('edit'),
  flag('flag'),
  flame('flame'),
  freeze('freeze'),
  fuel('fuel'),
  gauge('gauge'),
  gift('gift'),
  globe('globe'),
  haptics('haptics'),
  help('help'),
  hint('hint'),
  info('info'),
  labelsOff('labels-off'),
  layers('layers'),
  level('level'),
  locate('locate'),
  lock('lock'),
  map('map'),
  medal('medal'),
  minus('minus'),
  moon('moon'),
  more('more'),
  pause('pause'),
  pin('pin'),
  pinDrop('pin-drop'),
  play('play'),
  plus('plus'),
  reroute('reroute'),
  retry('retry'),
  road('road'),
  route('route'),
  search('search'),
  settings('settings'),
  share('share'),
  signpost('signpost'),
  soundOff('sound-off'),
  soundOn('sound-on'),
  star('star'),
  target('target'),
  timer('timer'),
  trophy('trophy'),
  user('user'),
  users('users'),
  wrench('wrench'),
  xp('xp'),
  zoomIn('zoom-in'),
  zoomOut('zoom-out');

  const PindoroGlyph(this.file);

  final String file;
}

/// An icon in [color] (default: the ambient [IconTheme]). The SVGs are drawn
/// in asphalt ink with white details; ink becomes [color] and white becomes
/// [cut], the surface behind (default `color.surface.raised`).
class PindoroIcon extends StatelessWidget {
  const PindoroIcon(
    this.glyph, {
    super.key,
    this.size,
    this.color,
    this.cut,
    this.semanticLabel,
  });

  final PindoroGlyph glyph;
  final double? size;
  final Color? color;
  final Color? cut;

  /// Null for decorative icons (most icons sit next to a text label).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final size = this.size ?? iconTheme.size ?? PindoroSize.iconMd;
    final ink =
        color ?? iconTheme.color ?? PindoroTheme.of(context).colors.textPrimary;
    return SvgPicture(
      SvgAssetLoader(
        'assets/icons/${glyph.file}.svg',
        packageName: _package,
        colorMapper: _InkMapper(
          ink: ink,
          cut: cut ?? PindoroTheme.of(context).colors.surfaceRaised,
        ),
      ),
      width: size,
      height: size,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}

class _InkMapper extends ColorMapper {
  const _InkMapper({required this.ink, required this.cut});

  final Color ink;
  final Color cut;

  static const int _assetInk = 0xFF1B2133;
  static const int _white = 0xFFFFFFFF;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) => switch (color.toARGB32() | 0xFF000000) {
    _assetInk => ink.withValues(alpha: color.a * ink.a),
    _white => cut.withValues(alpha: color.a * cut.a),
    _ => color,
  };

  @override
  bool operator ==(Object other) =>
      other is _InkMapper && other.ink == ink && other.cut == cut;

  @override
  int get hashCode => Object.hash(ink, cut);
}

enum PindoExpression { happy, cheering, thinking, encouraging, sleepy, proud }

/// Pindo, the pin alive. Decorative unless [semanticLabel] describes the
/// moment; keeps its colours in both themes; never smaller than 40 dp.
class Pindo extends StatelessWidget {
  const Pindo(
    this.expression, {
    super.key,
    this.height = 96,
    this.semanticLabel,
  }) : assert(height >= 40);

  final PindoExpression expression;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/mascot/pindo-${expression.name}.svg',
    package: _package,
    height: height,
    semanticsLabel: semanticLabel,
    excludeFromSemantics: semanticLabel == null,
  );
}

/// What the wordmark sits on; picks its letter and pin colours.
enum WordmarkGround {
  light(''),
  dark('-dark'),
  brand('-reversed');

  const WordmarkGround(this._suffix);

  final String _suffix;
}

/// "pindoro" / "პინდორო" in the UI language, coloured for [ground]
/// (default: the theme's surface).
class Wordmark extends StatelessWidget {
  const Wordmark({
    super.key,
    required this.georgian,
    this.height = 52,
    this.ground,
  });

  final bool georgian;
  final double height;
  final WordmarkGround? ground;

  @override
  Widget build(BuildContext context) {
    final ground =
        this.ground ??
        (Theme.of(context).brightness == Brightness.dark
            ? WordmarkGround.dark
            : WordmarkGround.light);
    final script = georgian ? 'georgian' : 'latin';
    return SvgPicture.asset(
      'assets/logos/pindoro-wordmark-$script${ground._suffix}.svg',
      package: _package,
      height: height,
      semanticsLabel: georgian ? 'პინდორო' : 'Pindoro',
    );
  }
}
