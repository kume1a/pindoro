import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';

/// The grabber at the top of a draggable sheet (`.pd-handle`): a 40 × 4 dp
/// `color.line.strong` bar with [PindoroSpace.s2] around it. Decorative.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: PindoroSpace.s2),
    child: Container(
      width: 40,
      height: PindoroSpace.s1,
      decoration: BoxDecoration(
        color: PindoroTheme.of(context).colors.lineStrong,
        borderRadius: BorderRadius.circular(PindoroRadius.full),
      ),
    ),
  );
}

/// A bottom sheet's frame: [color] with round top corners (and [topBorder] along the top),
/// padded clear of the system bar.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.color,
    required this.child,
    this.topBorder,
  });

  final Color color;
  final BorderSide? topBorder;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(PindoroRadius.r2xl),
      ),
      border: switch (topBorder) {
        final side? => Border(top: side),
        null => null,
      },
    ),
    padding: EdgeInsets.fromLTRB(
      PindoroSpace.s4,
      PindoroSpace.s3,
      PindoroSpace.s4,
      PindoroSpace.s3 + MediaQuery.paddingOf(context).bottom,
    ),
    child: child,
  );
}
