import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Reports a tap on [child] (a map) the moment the finger lifts: one finger
/// that stayed within [kTouchSlop] and lifted before [kLongPressTimeout].
/// MapLibre's own click waits ~300 ms to rule out a double-tap. Raw pointer
/// events stay out of the gesture arena, so pans and pinches still reach the
/// map.
class MapTaps extends StatefulWidget {
  const MapTaps({super.key, required this.onTap, required this.child});

  /// The tap's position in [child]; null turns taps off.
  final ValueChanged<Offset>? onTap;
  final Widget child;

  @override
  State<MapTaps> createState() => _MapTapsState();
}

class _MapTapsState extends State<MapTaps> {
  int _down = 0;
  bool _tap = false;
  Offset _start = Offset.zero;
  Duration _startedAt = Duration.zero;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (e) {
      _down++;
      _tap = _down == 1;
      _start = e.localPosition;
      _startedAt = e.timeStamp;
    },
    onPointerMove: (e) {
      if ((e.localPosition - _start).distance > kTouchSlop) _tap = false;
    },
    onPointerUp: (e) {
      _down--;
      final tap = _tap && e.timeStamp - _startedAt < kLongPressTimeout;
      _tap = false;
      if (tap) widget.onTap?.call(e.localPosition);
    },
    onPointerCancel: (_) {
      _down--;
      _tap = false;
    },
    child: widget.child,
  );
}
