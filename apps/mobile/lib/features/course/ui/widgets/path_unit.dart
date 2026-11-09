import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The path's geometry (LessonPath README): stops 104 dp apart, swinging
/// centre, left, centre, right by 67 dp; room above the first stop for its
/// tip.
abstract final class PathLayout {
  static const double stopGap = 104;
  static const double swing = 67;
  static const double top = 104;
  static const double bottom = 56;
  static const List<double> _swings = [0, -1, 0, 1];

  static double height(int stops) => top + (stops - 1) * stopGap + bottom;

  /// The centre of stop [i] in a unit [width] wide.
  static Offset stop(int i, double width) =>
      Offset(width / 2 + _swings[i % 4] * swing, top + i * stopGap);
}

/// How one stop draws and reads.
typedef StopView = ({
  PathStopLook look,
  PindoroGlyph glyph,
  bool big,
  double? ring,
  String? tip,
  String label,
});

/// What a locked stop (or the signpost) says when tapped.
typedef LockedNote = ({String title, String? body});

/// One unit's stretch of road and its stops. A tap on an open stop calls
/// [onStop]; a locked one wiggles and shows its [LockedNote] under it for
/// 3 s. [driven] is how far the asphalt reaches (in road points: 0 is the
/// unit's top, 1 its first stop); [scaleOf] lets the unlock grow a stop.
class PathUnit extends StatefulWidget {
  const PathUnit({
    super.key,
    required this.stops,
    required this.driven,
    required this.dim,
    required this.onStop,
    required this.lockedNote,
    this.stopKeys = const {},
    this.scaleOf,
    this.bubbleAtTop,
    this.burst,
  });

  final List<StopView> stops;
  final double driven;
  final bool dim;
  final ValueChanged<int> onStop;

  /// Null for a stop that opens a sheet.
  final LockedNote? Function(int stop) lockedNote;

  /// Keys on stops the Path scrolls to.
  final Map<int, GlobalKey> stopKeys;
  final double Function(int stop)? scaleOf;

  /// A note to show at the top of the unit (its locked signpost was tapped).
  final ValueNotifier<LockedNote?>? bubbleAtTop;

  /// The unlock's 12-dash burst around a stop, [t] from 0 to 1.
  final ({int stop, double t})? burst;

  @override
  State<PathUnit> createState() => _PathUnitState();
}

class _PathUnitState extends State<PathUnit> {
  int? _noteFor;
  LockedNote? _note;
  int _wiggles = 0;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.bubbleAtTop?.addListener(_showTop);
  }

  @override
  void dispose() {
    widget.bubbleAtTop?.removeListener(_showTop);
    _hide?.cancel();
    super.dispose();
  }

  void _showTop() {
    final note = widget.bubbleAtTop?.value;
    if (note != null) _show(-1, note);
  }

  void _show(int stop, LockedNote note) {
    _hide?.cancel();
    setState(() {
      _noteFor = stop;
      _note = note;
      _wiggles++;
    });
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _note = null);
    });
  }

  void _tap(int i) {
    final note = widget.lockedNote(i);
    if (note == null) {
      _hide?.cancel();
      if (_note != null) setState(() => _note = null);
      widget.onStop(i);
    } else {
      _show(i, note);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stops = widget.stops;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = PathLayout.height(stops.length);
        final centres = [
          for (var i = 0; i < stops.length; i++) PathLayout.stop(i, width),
        ];
        final note = _note;
        final noteAt = _noteFor == null || _noteFor! < 0
            ? Offset(width / 2, 0)
            : centres[_noteFor!] +
                  Offset(0, PathStop.sizeOf(big: stops[_noteFor!].big) / 2);
        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: LessonRoad(
                  points: [
                    Offset(width / 2, 0),
                    ...centres,
                    Offset(width / 2, height),
                  ],
                  driven: widget.driven,
                  opacity: widget.dim ? 0.55 : 1,
                ),
              ),
              for (final (i, s) in stops.indexed)
                () {
                  final size = PathStop.sizeOf(big: s.big);
                  final stop = PathStop(
                    key: widget.stopKeys[i],
                    look: s.look,
                    glyph: s.glyph,
                    big: s.big,
                    ring: s.ring,
                    tip: s.tip,
                    scale: widget.scaleOf?.call(i) ?? 1,
                    semanticLabel: s.label,
                    onTap: () => _tap(i),
                  );
                  return Positioned(
                    left: centres[i].dx - size / 2,
                    top: centres[i].dy - size / 2,
                    child: _noteFor == i && note != null
                        ? Wiggle(key: ValueKey(_wiggles), child: stop)
                        : stop,
                  );
                }(),
              if (widget.burst case (:final stop, :final t) when t < 1)
                Positioned(
                  left: centres[stop].dx - _burstRadius,
                  top: centres[stop].dy - _burstRadius,
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: const Size.square(2 * _burstRadius),
                      painter: _BurstPainter(
                        t: t,
                        color: PindoroTheme.of(context).colors.accentBase,
                      ),
                    ),
                  ),
                ),
              if (note != null)
                Positioned(
                  left: PindoroSpace.s4,
                  right: PindoroSpace.s4,
                  top: noteAt.dy + PindoroSpace.s3,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: CoachBubble(
                        title: note.title,
                        body: note.body,
                        pointsUp: true,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// How far the burst's dashes fly from a stop's centre.
const double _burstRadius = 64;

/// 12 lane dashes flying out from a stop and fading (the `.pd-burst`).
class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final paint = Paint()
      ..color = color.withValues(alpha: 1 - t)
      ..strokeWidth = PindoroStroke.thick
      ..strokeCap = StrokeCap.round;
    final from = 40 + 16 * t;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(centre + d * from, centre + d * (from + 8), paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.color != color;
}
