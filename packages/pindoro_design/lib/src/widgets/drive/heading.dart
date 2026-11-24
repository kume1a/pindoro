import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../painters.dart';
import 'drive_parts.dart';

/// The district under the Coached and Quiet dial:
/// `type.drive.district`, stepping down 2 dp at a time to fit, never under
/// 54 dp; still too wide, it wraps.
class DistrictLine extends StatelessWidget {
  const DistrictLine(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final base = PindoroType.driveDistrict.copyWith(color: c.driveQuietText);
    return LayoutBuilder(
      builder: (context, constraints) {
        var size = base.fontSize!;
        while (size > PindoroType.driveRead.fontSize!) {
          final text = TextPainter(
            text: TextSpan(
              text: name,
              style: base.copyWith(fontSize: size),
            ),
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout();
          final fits = text.width <= constraints.maxWidth;
          text.dispose();
          if (fits) break;
          size -= 2;
        }
        return unscaled(
          context,
          Text(
            name,
            textAlign: TextAlign.center,
            style: base.copyWith(fontSize: size),
          ),
        );
      },
    );
  }
}

/// Where the drive stands: on a good path, recovering from a wrong turn, or
/// finding the car (GPS lost).
enum DriveStatus { good, recovering, lost }

Color _statusColor(PindoroColors c, DriveStatus status) => switch (status) {
  DriveStatus.good => c.driveDotGood,
  DriveStatus.recovering => c.driveDotRecover,
  DriveStatus.lost => c.driveDotLost,
};

/// The Coached and Quiet dial (HeadingDial): a north-up ring in the
/// [status] colour, the car's [heading] on it and its cardinal [letter] in
/// the middle. Finding the car, the pointer and letter go and the dial dims.
class HeadingDial extends StatefulWidget {
  const HeadingDial({
    super.key,
    required this.heading,
    required this.letter,
    required this.status,
    required this.semanticsLabel,
    this.size = 280,
  });

  final double? heading;
  final String letter;
  final DriveStatus status;
  final String semanticsLabel;
  final double size;

  @override
  State<HeadingDial> createState() => _HeadingDialState();
}

class _HeadingDialState extends State<HeadingDial> {
  /// The pointer's turns, unwrapped so it always turns the shorter way.
  double _turns = 0;

  @override
  void initState() {
    super.initState();
    _turns = (widget.heading ?? 0) / 360;
  }

  @override
  void didUpdateWidget(HeadingDial old) {
    super.didUpdateWidget(old);
    final heading = widget.heading;
    if (heading == null) return;
    final from = (_turns * 360) % 360;
    _turns += (((heading - from) % 360 + 540) % 360 - 180) / 360;
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final lost = widget.status == DriveStatus.lost;
    final s = widget.size / 280;
    final calm = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      image: true,
      label: widget.semanticsLabel,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: lost ? 0.5 : 1,
          child: SizedBox.square(
            dimension: widget.size,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DialPainter(
                      ring: _statusColor(c, widget.status),
                      dashed: lost,
                      north: c.driveQuietText,
                      ticks: c.driveQuietRing,
                    ),
                  ),
                ),
                // No pointer before the first heading: north would be a guess.
                if (!lost && widget.heading != null) ...[
                  Positioned.fill(
                    child: AnimatedRotation(
                      turns: _turns,
                      duration: calm
                          ? Duration.zero
                          : PindoroMotion.durationFast,
                      child: CustomPaint(
                        painter: _PointerPainter(
                          heading: c.driveHeading,
                          rim: c.driveQuietBg,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 100 * s,
                    child: unscaled(
                      context,
                      Text(
                        widget.letter,
                        textAlign: TextAlign.center,
                        style: PindoroType.drivePrimary.copyWith(
                          color: c.driveQuietText,
                          fontSize: PindoroType.drivePrimary.fontSize! * s,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.ring,
    required this.dashed,
    required this.north,
    required this.ticks,
  });

  final Color ring;
  final bool dashed;
  final Color north;
  final Color ticks;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 280;
    canvas.scale(s);
    const centre = Offset(140, 140);
    final stroke = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    final circle = Path()
      ..addOval(Rect.fromCircle(center: centre, radius: 124));
    if (dashed) {
      canvas.drawPath(dashedPath(circle, dash: 10, period: 24), stroke);
    } else {
      canvas.drawPath(circle, stroke);
    }
    canvas.drawPath(
      Path()
        ..moveTo(140, 2)
        ..lineTo(151, 18)
        ..lineTo(129, 18)
        ..close(),
      Paint()..color = north,
    );
    final tick = Paint()
      ..color = ticks
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var t = 45; t < 360; t += 45) {
      final b = t * math.pi / 180;
      Offset at(double r) => centre + Offset(r * math.sin(b), -r * math.cos(b));
      canvas.drawLine(at(112), at(126), tick);
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.ring != ring ||
      old.dashed != dashed ||
      old.north != north ||
      old.ticks != ticks;
}

/// The heading pointer and its fan, drawn pointing north; rotated around the
/// centre to the heading.
class _PointerPainter extends CustomPainter {
  const _PointerPainter({required this.heading, required this.rim});

  final Color heading;
  final Color rim;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.shortestSide / 280);
    const centre = Offset(140, 140);
    const half = 18 * math.pi / 180;
    canvas.drawPath(
      Path()
        ..moveTo(centre.dx, centre.dy)
        ..arcTo(
          Rect.fromCircle(center: centre, radius: 116),
          -math.pi / 2 - half,
          2 * half,
          false,
        )
        ..close(),
      Paint()..color = heading.withValues(alpha: 0.16),
    );
    final pointer = Path()
      ..moveTo(140, 6)
      ..lineTo(164, 46)
      ..lineTo(140, 36)
      ..lineTo(116, 46)
      ..close();
    canvas
      ..drawPath(
        pointer,
        Paint()
          ..color = rim
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawPath(pointer, Paint()..color = heading);
  }

  @override
  bool shouldRepaint(_PointerPainter old) =>
      old.heading != heading || old.rim != rim;
}

/// The status dot in the top corner of Coached and Quiet: filled on a good
/// path, with a halo while recovering, an outline while finding the car;
/// [ring] (0 to 1) fills the 10 s ring around it after a recovery.
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.status,
    required this.semanticsLabel,
    this.ring,
  });

  final DriveStatus status;
  final String semanticsLabel;
  final double? ring;

  static const double size = 24;
  static const double ringSize = 48;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final color = _statusColor(c, status);
    return Semantics(
      liveRegion: true,
      image: true,
      label: semanticsLabel,
      child: SizedBox.square(
        dimension: ringSize,
        child: CustomPaint(
          painter: ring == null
              ? null
              : _RingPainter(progress: ring!, color: c.driveDotGood),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: status == DriveStatus.lost ? null : color,
                border: status == DriveStatus.lost
                    ? Border.all(color: color, width: 4)
                    : null,
                boxShadow: status == DriveStatus.recovering
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.3),
                          spreadRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const width = PindoroStroke.thick;
    canvas.drawArc(
      (Offset.zero & size).deflate(width / 2),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0, 1),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Five bars beside the status dot that move while Coached's voice speaks;
/// still at mid height under reduce motion. Decorative.
class SpeakingBars extends StatefulWidget {
  const SpeakingBars({super.key});

  @override
  State<SpeakingBars> createState() => _SpeakingBarsState();
}

class _SpeakingBarsState extends State<SpeakingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: PindoroMotion.durationSlow * 2,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _wave.stop();
    } else if (!_wave.isAnimating) {
      _wave.repeat();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = PindoroTheme.of(
      context,
    ).colors.driveQuietText.withValues(alpha: 0.7);
    final calm = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: 24,
        child: AnimatedBuilder(
          animation: _wave,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s1,
            children: [
              for (var i = 0; i < 5; i++)
                Container(
                  width: 4,
                  height: calm
                      ? 12
                      : 6 +
                            18 *
                                (0.5 +
                                    0.5 *
                                        math.sin(
                                          2 * math.pi * (_wave.value + i / 5),
                                        )),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 10 dp orange band along the top edge while recovering (RecoveryBand).
class RecoveryBand extends StatelessWidget {
  const RecoveryBand({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 10,
    width: double.infinity,
    child: ColoredBox(color: PindoroTheme.of(context).colors.driveDotRecover),
  );
}

/// Off's only mark: a small steady red dot (RecordingDot).
class RecordingDot extends StatelessWidget {
  const RecordingDot({super.key, required this.semanticsLabel});

  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: semanticsLabel,
    child: Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: PindoroTheme.of(context).colors.driveRec,
      ),
    ),
  );
}
