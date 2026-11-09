import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'motion.dart';
import 'surfaces.dart';

/// The XP bar: a rounded track with a lane-yellow fill on a lower lip. It
/// fills from [from] to [value] after [delay] (`duration.slow`) and calls
/// [onEnd] when it gets there; [tip] ("+695 XP") rides the fill's end while
/// [tipShown]; [ring] lights the accent ring (a level reached).
class XpBar extends StatelessWidget {
  const XpBar({
    super.key,
    required this.value,
    required this.semanticLabel,
    this.from,
    this.delay = Duration.zero,
    this.onEnd,
    this.tip,
    this.tipShown = true,
    this.ring = false,
  });

  /// 0–1.
  final double value;
  final String semanticLabel;

  /// Where the fill starts on first build; defaults to [value].
  final double? from;
  final Duration delay;
  final VoidCallback? onEnd;
  final String? tip;
  final bool tipShown;
  final bool ring;

  static const double _height = 18;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final (duration, curve) = delayedMotion(
      context,
      delay,
      PindoroMotion.durationSlow,
      PindoroMotion.easeStandard,
    );
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: AccentRing(
        on: ring,
        radius: PindoroRadius.full,
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            color: c.xpTrack,
            borderRadius: BorderRadius.circular(PindoroRadius.full),
          ),
          child: TweenAnimationBuilder<double>(
            tween: Tween(
              begin: (from ?? value).clamp(0, 1),
              end: value.clamp(0, 1),
            ),
            duration: duration,
            curve: curve,
            onEnd: onEnd,
            builder: (_, v, _) => LayoutBuilder(
              builder: (context, box) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: box.maxWidth * v,
                    decoration: BoxDecoration(
                      color: c.xpFill,
                      borderRadius: BorderRadius.circular(PindoroRadius.full),
                      border: Border(
                        bottom: BorderSide(
                          color: c.xpLip,
                          width: PindoroElevation.e2,
                        ),
                      ),
                    ),
                  ),
                  if (tip != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: _height + PindoroSpace.s2,
                      // Follows the fill's end but never sticks out past the
                      // bar's ends.
                      child: Align(
                        alignment: Alignment(2 * v - 1, 1),
                        child: AnimatedOpacity(
                          opacity: tipShown ? 1 : 0,
                          duration: PindoroMotion.durationFast,
                          child: _Tip(tip!),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A raised label with a tail pointing down at what it names.
class _Tip extends StatelessWidget {
  const _Tip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LipBox(
          radius: PindoroRadius.md,
          padding: const EdgeInsets.symmetric(
            horizontal: PindoroSpace.s3,
            vertical: PindoroSpace.s2,
          ),
          child: Text(
            label,
            style: PindoroType.labelLg.copyWith(color: c.primaryText),
          ),
        ),
        CustomPaint(
          size: const Size(14, 7),
          painter: _TailPainter(c.surfaceRaised, down: true),
        ),
      ],
    );
  }
}

/// A hint bubble over the map on the inverse surface; passes taps through.
class CoachBubble extends StatelessWidget {
  const CoachBubble({
    super.key,
    required this.title,
    this.body,
    this.pointsUp = false,
  });

  final String title;
  final String? body;

  /// A tail on top pointing at what the bubble explains, which sits above.
  final bool pointsUp;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: pointsUp
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomPaint(
                      size: const Size(18, 9),
                      painter: _TailPainter(c.coachBg, down: false),
                    ),
                    _bubble(c),
                  ],
                )
              : _bubble(c),
        ),
      ),
    );
  }

  Widget _bubble(PindoroColors c) => LipBox(
    face: c.coachBg,
    lip: c.coachLip,
    lipHeight: PindoroElevation.e2,
    radius: PindoroRadius.lg,
    shadow: true,
    padding: const EdgeInsets.symmetric(
      horizontal: PindoroSpace.s4,
      vertical: PindoroSpace.s3,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: PindoroType.titleSm.copyWith(color: c.coachText)),
        if (body != null)
          Text(body!, style: PindoroType.bodySm.copyWith(color: c.coachText)),
      ],
    ),
  );
}

/// A triangle tail for bubbles, pointing down or up.
class _TailPainter extends CustomPainter {
  _TailPainter(this.color, {required this.down});

  final Color color;
  final bool down;

  @override
  void paint(Canvas canvas, Size size) {
    final path = down
        ? (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width, 0)
            ..lineTo(size.width / 2, size.height))
        : (Path()
            ..moveTo(0, size.height)
            ..lineTo(size.width, size.height)
            ..lineTo(size.width / 2, 0));
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter old) =>
      old.color != color || old.down != down;
}

/// The accent ring around [child] (`stroke.thick`, lane yellow) while [on];
/// it fades in and out over `duration.fast`.
class AccentRing extends StatelessWidget {
  const AccentRing({
    super.key,
    required this.on,
    required this.radius,
    required this.child,
  });

  final bool on;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: PindoroMotion.durationFast,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: on
              ? PindoroTheme.of(context).colors.accentBase
              : Colors.transparent,
          spreadRadius: PindoroStroke.thick,
        ),
      ],
    ),
    child: child,
  );
}

/// The level shield: level number on `color.level.bg` inside a yellow rim;
/// [LevelBadge.glyph] shows an icon instead (Unit complete's trophy).
class LevelBadge extends StatelessWidget {
  const LevelBadge(int this.level, {super.key, this.size = 48}) : glyph = null;

  const LevelBadge.glyph(PindoroGlyph this.glyph, {super.key, this.size = 48})
    : level = null;

  final int? level;
  final PindoroGlyph? glyph;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: c.levelBg,
        shape: StarBorder.polygon(
          sides: 6,
          pointRounding: 0.4,
          side: BorderSide(color: c.levelRim, width: size / 16),
        ),
      ),
      child: glyph != null
          ? PindoroIcon(
              glyph!,
              size: size / 2,
              color: c.levelText,
              cut: c.levelBg,
            )
          // Large text sizes grow the number up to the shield, never past it.
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$level',
                style: PindoroType.numericMd.copyWith(
                  color: c.levelText,
                  fontSize: size * 0.42,
                ),
              ),
            ),
    );
  }
}
