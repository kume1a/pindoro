import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'controls.dart';
import 'graphics.dart';
import 'motion.dart';
import 'pindoro_button.dart';
import 'surfaces.dart';

/// A raised chip with an icon and a short stat (`.pd-statchip`): the
/// next-review chip, the family chip, the pair chip. The label wraps, never
/// truncates.
class StatChip extends StatelessWidget {
  const StatChip({super.key, required this.label, this.glyph});

  final String label;
  final PindoroGlyph? glyph;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final glyph = this.glyph;
    return LipBox(
      face: c.surfaceRaised,
      lip: c.lineBase,
      radius: PindoroRadius.md,
      padding: const EdgeInsets.symmetric(
        horizontal: PindoroSpace.s3,
        vertical: PindoroSpace.s2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          if (glyph != null)
            ExcludeSemantics(child: PindoroIcon(glyph, color: c.textPrimary)),
          Flexible(
            child: Text(
              label,
              style: PindoroType.bodyLg.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w900,
                height: 22 / 17,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// When a street comes back (Next-review chip): "Next review in 12 days"
/// with the calendar, or "Back in this session" with retry. It pops in after
/// the tier title unless [animate] is off.
class NextReviewChip extends StatelessWidget {
  const NextReviewChip({
    super.key,
    required this.label,
    required this.backThisSession,
    this.animate = true,
  });

  final String label;
  final bool backThisSession;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final chip = StatChip(
      label: label,
      glyph: backThisSession ? PindoroGlyph.retry : PindoroGlyph.calendar,
    );
    return animate
        ? PopIn(delay: PindoroMotion.durationBase, child: chip)
        : chip;
  }
}

/// The new street's or place's sheet (Intro sheet): where it is, the facts,
/// the optional etymology and family chip, then Hear the name (only with
/// [onHear]), Street View (only with [onStreetView]) and Got it. Not
/// dismissible; it scrolls when text is large and keeps the actions pinned.
class IntroSheet extends StatelessWidget {
  const IntroSheet({
    super.key,
    required this.title,
    required this.where,
    required this.facts,
    required this.gotItLabel,
    required this.onGotIt,
    required this.regionLabel,
    this.etymology,
    this.family,
    this.hearLabel,
    this.onHear,
    this.streetViewLabel,
    this.onStreetView,
    this.extra = const [],
  });

  /// "Where it is".
  final String title;
  final String where;

  /// "2.1 km · avenue · crosses 9 streets · 3.4 km from the centre".
  final String facts;
  final String? etymology;

  /// "26 May Street · 9 lanes, 6 dead ends".
  final String? family;
  final String gotItLabel;
  final VoidCallback onGotIt;

  /// The sheet's screen-reader region: "About this street".
  final String regionLabel;

  /// "Hear the name"; the button shows only with [onHear].
  final String? hearLabel;
  final VoidCallback? onHear;

  /// "Street View"; the button shows only with [onStreetView].
  final String? streetViewLabel;
  final VoidCallback? onStreetView;

  /// More under the facts, 12 dp apart (a leech's contrast and note).
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final secondary = c.textSecondary;
    final onHear = this.onHear;
    final onStreetView = this.onStreetView;
    return Semantics(
      container: true,
      label: regionLabel,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: c.surfaceOverlay,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(PindoroRadius.r2xl),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          PindoroSpace.s4,
          PindoroSpace.s3,
          PindoroSpace.s4,
          PindoroSpace.s3 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: PindoroType.titleMd.copyWith(color: c.textPrimary),
                    ),
                    const SizedBox(height: PindoroSpace.s1),
                    Text(
                      where,
                      style: PindoroType.bodyMd.copyWith(color: secondary),
                    ),
                    const SizedBox(height: PindoroSpace.s2),
                    Text(
                      facts,
                      style: PindoroType.labelMd.copyWith(color: secondary),
                    ),
                    if (etymology case final etymology?) ...[
                      const SizedBox(height: PindoroSpace.s2),
                      Text(
                        etymology,
                        style: PindoroType.bodySm.copyWith(color: secondary),
                      ),
                    ],
                    if (family case final family?) ...[
                      const SizedBox(height: PindoroSpace.s3),
                      StatChip(label: family, glyph: PindoroGlyph.road),
                    ],
                    for (final widget in extra) ...[
                      const SizedBox(height: PindoroSpace.s3),
                      widget,
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: PindoroSpace.s3),
            Row(
              spacing: PindoroSpace.s3,
              children: [
                if (onHear != null)
                  PindoroIconButton(
                    glyph: PindoroGlyph.soundOn,
                    semanticLabel: hearLabel ?? '',
                    onPressed: onHear,
                  ),
                if (onStreetView != null)
                  PindoroIconButton(
                    glyph: PindoroGlyph.eye,
                    semanticLabel: streetViewLabel ?? '',
                    onPressed: onStreetView,
                  ),
                Expanded(
                  child: PindoroButton(label: gotItLabel, onPressed: onGotIt),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
