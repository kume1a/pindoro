import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';

/// How every custom control takes a tap: one semantics node that carries the
/// tap action, its role and [label] (a labelled node drops its children's
/// semantics, the gesture's own tap action with them), a gesture detector
/// whose whole box is the target, and the click cursor.
class Tappable extends StatelessWidget {
  const Tappable({
    super.key,
    required this.onTap,
    required this.child,
    this.label,
    this.button = true,
    this.checked,
    this.toggled,
    this.selected,
    this.inMutuallyExclusiveGroup = false,
    this.onPress,
  });

  /// Null disables the control.
  final VoidCallback? onTap;
  final Widget child;

  /// Replaces the child's semantics when given.
  final String? label;
  final bool button;
  final bool? checked;

  /// A toggle button's state (an exit button), announced as on or off.
  final bool? toggled;
  final bool? selected;
  final bool inMutuallyExclusiveGroup;

  /// True as a finger goes down on it, false as it lifts or slides off.
  final ValueChanged<bool>? onPress;

  @override
  Widget build(BuildContext context) => Semantics(
    button: button,
    enabled: onTap != null,
    checked: checked,
    toggled: toggled,
    selected: selected,
    inMutuallyExclusiveGroup: inMutuallyExclusiveGroup,
    label: label,
    onTap: onTap,
    excludeSemantics: label != null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onTapDown: onPress == null ? null : (_) => onPress!(true),
      onTapUp: onPress == null ? null : (_) => onPress!(false),
      onTapCancel: onPress == null ? null : () => onPress!(false),
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        child: child,
      ),
    ),
  );
}

/// A lipped control's press ([Tappable.onPress]): [pressed] while a finger is down on it, never
/// while [pressEnabled] is false. Disabled mid-press, its release would be ignored and the face
/// stay down, so it lets go then.
mixin LipPressState<T extends StatefulWidget> on State<T> {
  bool pressed = false;

  bool get pressEnabled => true;

  void press(bool down) {
    if (pressEnabled) setState(() => pressed = down);
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!pressEnabled) pressed = false;
  }
}

/// A face ([child]) on its [lipColor] lip, [full] tall at rest and [lip] tall now: the face
/// sinks into it as it is pressed.
class LipFace extends StatelessWidget {
  const LipFace({
    super.key,
    required this.full,
    required this.lip,
    required this.lipColor,
    required this.radius,
    required this.child,
  });

  final double full;
  final double lip;
  final Color lipColor;
  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: PindoroMotion.durationInstant,
    curve: PindoroMotion.easePress,
    margin: EdgeInsets.only(top: full - lip),
    padding: EdgeInsets.only(bottom: lip),
    decoration: BoxDecoration(color: lipColor, borderRadius: radius),
    child: child,
  );
}
