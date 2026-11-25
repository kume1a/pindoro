import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../graphics.dart';
import '../tappable.dart';
import '../text_scale.dart';
import '../whole_words.dart';
import 'lip_box.dart';

/// One number and its label (`.pd-stattile`), for lesson complete and Me:
/// a [LipBox] with `radius.lg`, an optional 20 dp [glyph] (default colour
/// `color.primary.text`) 6 dp before the `label.md` label, the value in
/// `numeric.md` and an optional secondary [caption] under it. Reads as one
/// label, "[label], [value], [caption]" unless [semanticLabel] says otherwise.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.glyph,
    this.glyphColor,
    this.semanticLabel,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;
  final PindoroGlyph? glyph;
  final Color? glyphColor;
  final String? semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final glyph = this.glyph;
    final tile = LipBox(
      border: c.lineBase,
      radius: PindoroRadius.lg,
      padding: const EdgeInsets.all(PindoroSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          // A label too long for the glyph's line drops under it before it shrinks.
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (glyph != null)
                PindoroIcon(
                  glyph,
                  size: PindoroSize.iconSm,
                  color: glyphColor ?? c.primaryText,
                ),
              WholeWords(
                Text(
                  label,
                  style: PindoroType.labelMd.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
          Text(
            value,
            style: PindoroType.numericMd.copyWith(color: c.textPrimary),
          ),
          if (caption case final caption?)
            WholeWords(
              Text(
                caption,
                style: PindoroType.bodySm.copyWith(color: c.textSecondary),
              ),
            ),
        ],
      ),
    );
    final a11y = semanticLabel ?? [label, value, ?caption].join(', ');
    return onTap == null
        ? Semantics(
            container: true,
            label: a11y,
            excludeSemantics: true,
            child: tile,
          )
        : Tappable(onTap: onTap, label: a11y, child: tile);
  }
}

/// A `title.md` heading above a group of cards or rows, with an optional
/// `label.md` [meta] at the end in secondary text (Tab section header).
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.meta});

  final String text;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final title = Semantics(
      header: true,
      child: Text(
        text,
        style: PindoroType.titleMd.copyWith(color: c.textPrimary),
      ),
    );
    final meta = this.meta;
    if (meta == null) return title;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: PindoroSpace.s3,
      children: [
        Expanded(child: title),
        Flexible(
          child: Text(
            meta,
            textAlign: TextAlign.end,
            style: PindoroType.labelMd.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// A card with a `title.sm` [title] and an optional `label.md` [meta] on one
/// line over [child] (the forecast, week and last-round cards). Reads as one
/// node, [semanticsLabel], unless it is null: then its parts read in turn.
class TitledCard extends StatelessWidget {
  const TitledCard({
    super.key,
    required this.title,
    required this.child,
    this.meta,
    this.semanticsLabel,
  });

  final String title;
  final String? meta;
  final Widget child;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final meta = this.meta;
    final card = LipBox(
      border: c.lineBase,
      padding: const EdgeInsets.symmetric(
        horizontal: PindoroSpace.s4,
        vertical: PindoroSpace.s3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s2,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: PindoroSpace.s3,
            children: [
              Text(
                title,
                style: PindoroType.titleSm.copyWith(color: c.textPrimary),
              ),
              if (meta != null)
                Text(
                  meta,
                  style: PindoroType.labelMd.copyWith(color: c.textSecondary),
                ),
            ],
          ),
          child,
        ],
      ),
    );
    final label = semanticsLabel;
    return label == null
        ? card
        : Semantics(
            container: true,
            label: label,
            excludeSemantics: true,
            child: card,
          );
  }
}

/// [tiles] in rows of [columns], [PindoroSpace.s2] apart, each row as tall as
/// its tallest tile; a short last row keeps the columns' width.
class TileGrid extends StatelessWidget {
  const TileGrid(this.tiles, {super.key, this.columns = 2});

  final List<Widget> tiles;
  final int columns;

  /// Today's plan tiles: one to three in a row, four as 2 × 2, one column
  /// once the text is scaled to [stackAt] or more.
  static int columnsFor(int count, double textScale) =>
      textScale >= stackAt ? 1 : (count == 4 ? 2 : count.clamp(1, 3));

  static const double stackAt = largeTextScale;

  @override
  Widget build(BuildContext context) => Column(
    spacing: PindoroSpace.s2,
    children: [
      for (var i = 0; i < tiles.length; i += columns)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s2,
            children: [
              for (final tile in tiles.skip(i).take(columns))
                Expanded(child: tile),
              for (var j = tiles.length - i; j < columns; j++)
                const Expanded(child: SizedBox()),
            ],
          ),
        ),
    ],
  );
}
