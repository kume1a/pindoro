import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'tappable.dart';
import 'whole_words.dart';

/// A flat face sitting on a solid bottom lip: the system's only depth.
/// Cards, list groups, chips, pills and buttons are all built from it.
class LipBox extends StatelessWidget {
  const LipBox({
    super.key,
    required this.child,
    this.face,
    this.lip,
    this.border,
    this.lipHeight = PindoroElevation.e1,
    this.radius = PindoroRadius.xl,
    this.padding = EdgeInsets.zero,
    this.shadow = false,
  });

  final Widget child;

  /// Defaults to `color.surface.raised` with a `color.line.base` lip.
  final Color? face;
  final Color? lip;

  /// A [PindoroStroke.base] outline in this colour.
  final Color? border;
  final double lipHeight;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// `shadow.float`, for things floating over the map.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    final shape = BorderRadius.circular(radius);
    return Container(
      padding: EdgeInsets.only(bottom: lipHeight),
      decoration: BoxDecoration(
        color: lip ?? c.lineBase,
        borderRadius: shape,
        boxShadow: shadow ? [theme.floatShadow] : null,
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: face ?? c.surfaceRaised,
          borderRadius: shape,
          border: border == null
              ? null
              : Border.all(color: border!, width: PindoroStroke.base),
        ),
        child: child,
      ),
    );
  }
}

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

  static const double stackAt = 1.6;

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

/// Rows in one raised group (`radius.xl`, 2 dp border, `elevation.1` lip),
/// separated by hairlines; nothing at all without rows, not an empty frame.
class ListGroup extends StatelessWidget {
  const ListGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final c = PindoroTheme.of(context).colors;
    return LipBox(
      border: c.lineBase,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PindoroRadius.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0)
                Divider(
                  height: PindoroStroke.hairline,
                  thickness: PindoroStroke.hairline,
                  color: c.lineBase,
                ),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// The workhorse row: optional leading tile, `title.md` title, `body.sm`
/// subtitle, trailing slot. At least 64 dp tall; the whole row is the target.
/// [dense] keeps it to one 48 dp line: the title, then the subtitle at the
/// right end, cut short if it must (a route option's time, then its tags).
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleSpan,
    this.leading,
    this.trailing,
    this.onTap,
    this.semanticsLabel,
    this.toggled,
    this.check,
    this.below,
    this.dense = false,
  });

  final String title;
  final String? subtitle;

  /// A styled subtitle (e.g. a coloured word), instead of [subtitle].
  final InlineSpan? subtitleSpan;

  /// Usually a [RowTile] with an icon.
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  /// Set for a row whose trailing slot is a toggle: announced as a switch.
  final bool? toggled;

  /// Set for a checkbox row: the box sits before [trailing] and the row is
  /// announced as a checkbox (partial as mixed).
  final CheckState? check;

  /// Under the subtitle, 6 dp below it (Me's city minibar).
  final Widget? below;

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final enabled = onTap != null || toggled == null;
    final titleText = Text(
      title,
      maxLines: dense ? 1 : null,
      overflow: dense ? TextOverflow.ellipsis : null,
      style: PindoroType.titleMd.copyWith(
        color: enabled ? c.textPrimary : c.textDisabled,
      ),
    );
    final sub = switch (subtitleSpan ?? _span(subtitle)) {
      final span? => Text.rich(
        span,
        maxLines: dense ? 1 : null,
        overflow: dense ? TextOverflow.ellipsis : null,
        textAlign: dense ? TextAlign.end : null,
        style: PindoroType.bodySm.copyWith(color: c.textSecondary),
      ),
      null => null,
    };
    final check = this.check;
    return Semantics(
      container: semanticsLabel != null,
      button: onTap != null && toggled == null && check == null,
      toggled: toggled,
      checked: check?.isChecked,
      mixed: check == null ? null : check == CheckState.partial,
      label: semanticsLabel,
      // A labelled row drops the InkWell's semantics, its tap with them, so
      // the row's own node carries the tap.
      onTap: semanticsLabel == null ? null : onTap,
      excludeSemantics: semanticsLabel != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.surfaceSunken,
          mouseCursor: onTap == null ? null : SystemMouseCursors.click,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: dense ? PindoroSize.buttonMd : 64,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: PindoroSpace.s4,
                vertical: PindoroSpace.s2,
              ),
              child: Row(
                spacing: PindoroSpace.s3,
                children: [
                  ?leading,
                  // Dense: the title and the subtitle each cut short past half the row.
                  if (dense) ...[
                    Flexible(child: titleText),
                    Expanded(child: sub ?? const SizedBox.shrink()),
                  ] else
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WholeWords(titleText),
                          ?sub,
                          if (below case final below?)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: below,
                            ),
                        ],
                      ),
                    ),
                  if (check != null) _CheckBox(check),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A checkbox [ListRow]'s state. [included] is checked by a parent pick (a
/// district covers its quarters): ticked, but in the soft tint.
enum CheckState {
  off,
  on,
  partial,
  included;

  bool get isChecked => this == on || this == included;
}

class _CheckBox extends StatelessWidget {
  const _CheckBox(this.state);

  final CheckState state;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final (fill, ink, glyph) = switch (state) {
      CheckState.off => (null, null, null),
      CheckState.on => (c.primaryBase, c.primaryOn, PindoroGlyph.check),
      CheckState.partial => (c.primaryBase, c.primaryOn, PindoroGlyph.minus),
      CheckState.included => (c.primarySoft, c.primaryText, PindoroGlyph.check),
    };
    return Container(
      width: PindoroSize.iconMd,
      height: PindoroSize.iconMd,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(PindoroRadius.xs),
        border: fill == null
            ? Border.all(color: c.lineStrong, width: PindoroStroke.base)
            : null,
      ),
      child: glyph == null
          ? null
          : Center(
              child: PindoroIcon(
                glyph,
                size: PindoroSize.iconSm,
                color: ink,
                cut: fill,
              ),
            ),
    );
  }
}

/// The 40 dp leading tile of a [ListRow]: `color.primary.soft` behind a
/// `color.primary.text` glyph, or [face] and [ink] with a [lip] (the Pit
/// stop's review tile).
class RowTile extends StatelessWidget {
  const RowTile(this.glyph, {super.key, this.face, this.ink, this.lip});

  final PindoroGlyph glyph;
  final Color? face;
  final Color? ink;
  final Color? lip;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final face = this.face ?? c.primarySoft;
    final icon = PindoroIcon(glyph, color: ink ?? c.primaryText, cut: face);
    final lip = this.lip;
    if (lip != null) {
      return LipBox(
        face: face,
        lip: lip,
        radius: PindoroRadius.md,
        child: SizedBox.square(
          dimension: 40 - PindoroElevation.e1,
          child: Center(child: icon),
        ),
      );
    }
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: face,
        borderRadius: BorderRadius.circular(PindoroRadius.md),
      ),
      child: icon,
    );
  }
}

InlineSpan? _span(String? text) => text == null ? null : TextSpan(text: text);
