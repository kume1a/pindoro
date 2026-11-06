import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';

/// Street card spec: the name shrinks in 2 dp steps until it fits two lines.
const double _fontStep = 2;

/// Cobalt road-sign plate with a white inner rule, floating over the map.
/// The name starts at headline.md and shrinks until it fits two lines, down
/// to [PindoroSize.plateNameMin]; at the floor it wraps and never truncates.
/// [compact] (the reveal) is one line and may ellipsize.
class StreetPlate extends StatelessWidget {
  const StreetPlate(
    this.name, {
    super.key,
    this.prompt,
    this.promptGlyph = PindoroGlyph.pin,
    this.subline,
    this.compact = false,
    this.semanticLabel,
  });

  final String name;

  /// "Drop a pin on" above the name.
  final String? prompt;
  final PindoroGlyph promptGlyph;

  /// Transliteration, the local name in English mode, or the retry distance.
  final String? subline;
  final bool compact;

  /// Heading read by screen readers ("Find: …").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    final style = PindoroType.headlineMd.copyWith(color: c.streetCardText);
    final sub = PindoroType.bodySm.copyWith(color: c.streetCardSubtext);
    return Semantics(
      header: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Container(
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
            padding: EdgeInsets.symmetric(
              horizontal: PindoroSpace.s4,
              vertical: compact ? PindoroSpace.s1 : PindoroSpace.s2,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: c.streetCardRule,
                width: PindoroStroke.thick,
              ),
              borderRadius: BorderRadius.circular(PindoroRadius.md),
            ),
            child: compact
                ? Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PindoroType.titleLg.copyWith(
                      color: c.streetCardText,
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (prompt != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: PindoroSpace.s1,
                          children: [
                            PindoroIcon(
                              promptGlyph,
                              size: PindoroSize.iconSm,
                              color: c.streetCardSubtext,
                              cut: c.streetCardBg,
                            ),
                            Flexible(
                              child: Text(
                                prompt!,
                                style: PindoroType.labelLg.copyWith(
                                  color: c.streetCardSubtext,
                                ),
                              ),
                            ),
                          ],
                        ),
                      LayoutBuilder(
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
                      if (subline != null)
                        Text(subline!, textAlign: TextAlign.center, style: sub),
                    ],
                  ),
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
