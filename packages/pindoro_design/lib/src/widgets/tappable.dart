import 'package:flutter/material.dart';

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
    this.selected,
    this.inMutuallyExclusiveGroup = false,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
  });

  /// Null disables the control.
  final VoidCallback? onTap;
  final Widget child;

  /// Replaces the child's semantics when given.
  final String? label;
  final bool button;
  final bool? checked;
  final bool? selected;
  final bool inMutuallyExclusiveGroup;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapCancelCallback? onTapCancel;

  @override
  Widget build(BuildContext context) => Semantics(
    button: button,
    enabled: onTap != null,
    checked: checked,
    selected: selected,
    inMutuallyExclusiveGroup: inMutuallyExclusiveGroup,
    label: label,
    onTap: onTap,
    excludeSemantics: label != null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onTapDown: onTapDown,
      onTapUp: onTapUp,
      onTapCancel: onTapCancel,
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        child: child,
      ),
    ),
  );
}
