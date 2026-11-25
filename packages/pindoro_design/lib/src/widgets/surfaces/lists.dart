import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../graphics.dart';
import '../whole_words.dart';
import 'lip_box.dart';

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
