import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import 'motion_parts.dart';

enum CelebrationSize { small, medium, big }

/// The celebration for a tier: big for a Perfect, medium for a Great, small
/// for a Close, none for a Miss. Repeats calm down: a round's second Perfect
/// gets the medium one, and from the fifth Great-or-better in a row a Great
/// only pops its badge.
CelebrationSize? celebrationFor(
  Tier tier, {
  int perfectsThisRound = 1,
  int inARow = 1,
}) => switch (tier) {
  Tier.perfect when perfectsThisRound > 1 => CelebrationSize.medium,
  Tier.perfect => CelebrationSize.big,
  Tier.great when inARow >= 5 => null,
  Tier.great => CelebrationSize.medium,
  Tier.close => CelebrationSize.small,
  Tier.miss => null,
};

/// Lane-dash and star confetti (big), a 12-dash burst around [burstCenter]
/// (medium and big) and a lane-yellow edge glow (big). Never blocks input;
/// nothing at all with reduce motion on.
class Celebration extends StatefulWidget {
  const Celebration({super.key, required this.size, this.burstCenter});

  final CelebrationSize size;

  /// Where the burst radiates from, as an alignment in the overlay.
  final Alignment? burstCenter;

  @override
  State<Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<Celebration>
    with SingleTickerProviderStateMixin {
  /// Made on the first build that shows something: a calm or small celebration never ticks.
  AnimationController? _c;

  final _pieces = [
    for (var i = 0; i < 28; i++)
      (
        x: math.Random(i).nextDouble(),
        delay: math.Random(i + 99).nextDouble() * 0.3,
        spin: math.Random(i + 7).nextDouble() * 6 - 3,
        star: i % 4 == 0,
        cobalt: i % 7 == 3,
      ),
  ];

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isCalm(context) || widget.size == CelebrationSize.small) {
      return const SizedBox.shrink();
    }
    final c = _c ??= AnimationController(
      vsync: this,
      duration: switch (widget.size) {
        CelebrationSize.small => PindoroMotion.celebrateSmall,
        CelebrationSize.medium => PindoroMotion.celebrateMedium,
        CelebrationSize.big => PindoroMotion.celebrateBig,
      },
    )..forward();
    final colors = PindoroTheme.of(context).colors;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: c,
        builder: (_, _) => CustomPaint(
          size: Size.infinite,
          painter: _CelebrationPainter(
            t: c.value,
            big: widget.size == CelebrationSize.big,
            burstCenter: widget.burstCenter ?? Alignment.center,
            pieces: _pieces,
            colors: colors,
          ),
        ),
      ),
    );
  }
}

class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter({
    required this.t,
    required this.big,
    required this.burstCenter,
    required this.pieces,
    required this.colors,
  });

  final double t;
  final bool big;
  final Alignment burstCenter;
  final List<({double x, double delay, double spin, bool star, bool cobalt})>
  pieces;
  final PindoroColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final dash = Paint()
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    // 12 lane dashes flying out from the badge.
    final burst = (t * 2.5).clamp(0.0, 1.0);
    if (burst < 1) {
      final center = burstCenter.alongSize(size);
      dash.color = colors.accentBase.withValues(alpha: 1 - burst);
      for (var i = 0; i < 12; i++) {
        final a = 2 * math.pi * i / 12;
        final dir = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(
          center + dir * (28 + 40 * burst),
          center + dir * (38 + 52 * burst),
          dash,
        );
      }
    }
    if (!big) return;
    // Confetti showering from the top.
    for (final p in pieces) {
      final life = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (life <= 0 || life >= 1) continue;
      final at = Offset(p.x * size.width, -20 + life * (size.height * 0.9));
      final color = p.cobalt ? colors.primaryBase : colors.accentBase;
      canvas
        ..save()
        ..translate(at.dx, at.dy)
        ..rotate(p.spin * life * math.pi);
      if (p.star) {
        canvas.drawPath(_star(6), Paint()..color = color);
      } else {
        canvas.drawLine(
          const Offset(-6, 0),
          const Offset(6, 0),
          dash..color = color.withValues(alpha: 1 - life * 0.3),
        );
      }
      canvas.restore();
    }
    // A 10 dp lane-yellow glow around the screen edge, pulsing once.
    final glow = math.sin(t * math.pi);
    canvas.drawRect(
      (Offset.zero & size).deflate(5),
      Paint()
        ..color = colors.accentBase.withValues(alpha: 0.6 * glow)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  static Path _star(double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? r : r / 2.4;
      final a = -math.pi / 2 + i * math.pi / 5;
      final point = Offset(radius * math.cos(a), radius * math.sin(a));
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_CelebrationPainter old) => old.t != t;
}
