import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../drive_glyph.dart';
import 'drive_parts.dart';

/// The car's speed beside the speed sign (SpeedNow): the [kmh] on the plate's ink disc, as big
/// as the sign.
class SpeedNow extends StatelessWidget {
  const SpeedNow({super.key, required this.kmh, required this.semanticsLabel});

  final int kmh;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final style = (kmh >= 100 ? PindoroType.headlineMd : PindoroType.headlineLg)
        .copyWith(color: c.drivePlateText, height: 1);
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: unscaled(
          context,
          Container(
            width: SpeedLimitSign.size,
            height: SpeedLimitSign.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.drivePlate,
            ),
            child: Text('$kmh', style: style),
          ),
        ),
      ),
    );
  }
}

/// A round speed-limit sign (SpeedLimitSign): the [limit] in a red ring.
/// [over] (over the limit plus the tolerance) pulses it two and a half times
/// and leaves it grown with its halos; a new [beat] while over pulses again.
class SpeedLimitSign extends StatefulWidget {
  const SpeedLimitSign({
    super.key,
    required this.limit,
    required this.semanticsLabel,
    this.over = false,
    this.beat = 0,
  });

  final int limit;
  final String semanticsLabel;
  final bool over;
  final int beat;

  static const double size = 64;

  @override
  State<SpeedLimitSign> createState() => _SpeedLimitSignState();
}

class _SpeedLimitSignState extends State<SpeedLimitSign>
    with SingleTickerProviderStateMixin {
  /// Two and a half beats of `duration.base` + `duration.slow`, ending at a peak.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: (PindoroMotion.durationBase + PindoroMotion.durationSlow) * 2.5,
  );

  @override
  void initState() {
    super.initState();
    if (widget.over) _pulse.value = 1;
  }

  @override
  void didUpdateWidget(SpeedLimitSign old) {
    super.didUpdateWidget(old);
    if (!widget.over) {
      _pulse.value = 0;
    } else if (!old.over || widget.beat != old.beat) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _pulse.value = 1;
      } else {
        _pulse.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final three = widget.limit >= 100;
    final figures =
        (three ? PindoroType.headlineMd : PindoroType.headlineLg).fontSize!;
    return Semantics(
      image: true,
      label: widget.semanticsLabel,
      child: ExcludeSemantics(
        child: unscaled(
          context,
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final beats = _pulse.value * 2.5;
              final i = (1 - math.cos(2 * math.pi * beats)) / 2;
              return Transform.scale(
                scale: 1 + 0.06 * i,
                child: Container(
                  width: SpeedLimitSign.size,
                  height: SpeedLimitSign.size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.driveSignBg,
                    border: Border.all(color: c.driveSignRing, width: 7),
                    boxShadow: [
                      if (i > 0) ...[
                        BoxShadow(
                          color: c.driveSignRing.withValues(alpha: 0.45),
                          spreadRadius: 6 * i,
                        ),
                        BoxShadow(
                          color: c.driveSignRing.withValues(alpha: 0.18),
                          spreadRadius: 12 * i,
                        ),
                      ],
                    ],
                  ),
                  child: Text(
                    '${widget.limit}',
                    style: PindoroType.driveRead.copyWith(
                      fontSize: figures,
                      height: 1,
                      letterSpacing: -0.02 * figures,
                      color: c.driveSignText,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The orange camera badge beside the speed sign while a camera is ahead
/// (CameraBadge). Its words join the bar's or the screen's announcement.
class CameraBadge extends StatelessWidget {
  const CameraBadge({super.key});

  static const double size = SpeedLimitSign.size;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.driveCamera,
        borderRadius: BorderRadius.circular(PindoroRadius.lg),
      ),
      child: DriveGlyph(
        DriveGlyphName.camera,
        size: 44,
        color: c.driveCameraInk,
        cut: c.driveCamera,
      ),
    );
  }
}
