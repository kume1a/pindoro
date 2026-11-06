import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';

/// Street card spec: the name shrinks in 2 dp steps until it fits two lines.
const double _fontStep = 2;

/// Cobalt road-sign plate with a white inner rule. The name starts at
/// headline.md and shrinks until it fits two lines, down to
/// [PindoroSize.plateNameMin]; at the floor it wraps and never truncates.
class StreetPlate extends StatelessWidget {
  const StreetPlate(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    final style = PindoroType.headlineMd.copyWith(color: c.streetCardText);
    return Container(
      padding: const EdgeInsets.only(bottom: PindoroElevation.e2),
      decoration: BoxDecoration(
        color: c.streetCardLip,
        borderRadius: BorderRadius.circular(PindoroRadius.lg),
        boxShadow: [theme.floatShadow],
      ),
      child: Container(
        padding: const EdgeInsets.all(PindoroSpace.s1),
        decoration: BoxDecoration(
          color: c.streetCardBg,
          borderRadius: BorderRadius.circular(PindoroRadius.lg),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: PindoroSpace.s4,
            vertical: PindoroSpace.s2,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: c.streetCardRule,
              width: PindoroStroke.thick,
            ),
            borderRadius: BorderRadius.circular(PindoroRadius.md),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fontSize = plateFontSize(
                name,
                style,
                maxWidth: constraints.maxWidth,
                textScaler: MediaQuery.textScalerOf(context),
              );
              return Text(
                name,
                textAlign: TextAlign.center,
                style: style.copyWith(fontSize: fontSize),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Largest size from [style]'s own down to the floor, in 2 dp steps, at which
/// [text] fits in two lines of [maxWidth]; the floor when nothing fits.
double plateFontSize(
  String text,
  TextStyle style, {
  required double maxWidth,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final start = style.fontSize!;
  if (!maxWidth.isFinite) return start;
  for (var size = start; size > PindoroSize.plateNameMin; size -= _fontStep) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontSize: size),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      textScaler: textScaler,
      maxLines: 2,
    )..layout(maxWidth: maxWidth);
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    if (fits) return size;
  }
  return PindoroSize.plateNameMin;
}
