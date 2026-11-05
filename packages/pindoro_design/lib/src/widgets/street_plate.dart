import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';

typedef _T = PindoroTokens;

/// Cobalt road-sign plate. Fits the name in two lines by shrinking the font in
/// 2 dp steps down to a 20 dp floor; below that it wraps and never truncates.
class StreetPlate extends StatelessWidget {
  const StreetPlate(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.titleLarge!.copyWith(
      color: _T.colorPlateText,
      fontWeight: FontWeight.w700,
    );
    return Container(
      padding: const EdgeInsets.all(_T.spaceXs),
      decoration: BoxDecoration(
        color: _T.colorPlateFill,
        borderRadius: BorderRadius.circular(_T.radiusPlate),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: _T.spaceMd,
          vertical: _T.spaceSm,
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: _T.colorPlateBorder,
            width: _T.sizePlateBorder,
          ),
          borderRadius: BorderRadius.circular(_T.radiusPlate - _T.spaceXs),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fontSize = plateFontSize(
              name,
              base,
              maxWidth: constraints.maxWidth,
              textScaler: MediaQuery.textScalerOf(context),
            );
            return Text(
              name,
              textAlign: TextAlign.center,
              style: base.copyWith(fontSize: fontSize),
            );
          },
        ),
      ),
    );
  }
}

/// Largest font size (from the max token down in step tokens) at which [text]
/// fits in two lines of [maxWidth]; the floor token when nothing fits.
double plateFontSize(
  String text,
  TextStyle style, {
  required double maxWidth,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (!maxWidth.isFinite) return _T.sizePlateFontMax;
  for (
    var size = _T.sizePlateFontMax;
    size > _T.sizePlateFontMin;
    size -= _T.sizePlateFontStep
  ) {
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
  return _T.sizePlateFontMin;
}
