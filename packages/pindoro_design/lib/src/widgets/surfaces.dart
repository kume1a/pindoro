import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';

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

/// A `title.md` heading above a group of cards or rows.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: PindoroType.titleMd.copyWith(
        color: PindoroTheme.of(context).colors.textPrimary,
      ),
    ),
  );
}

/// Rows in one raised group (`radius.xl`, 2 dp border, `elevation.1` lip),
/// separated by hairlines.
class ListGroup extends StatelessWidget {
  const ListGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.semanticsLabel,
    this.toggled,
    this.check,
  });

  final String title;
  final String? subtitle;

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

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final enabled = onTap != null || toggled == null;
    final check = this.check;
    return Semantics(
      button: onTap != null && toggled == null && check == null,
      toggled: toggled,
      checked: check == null ? null : check.isChecked,
      mixed: check == null ? null : check == CheckState.partial,
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.surfaceSunken,
          mouseCursor: onTap == null ? null : SystemMouseCursors.click,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: PindoroSpace.s4,
                vertical: PindoroSpace.s2,
              ),
              child: Row(
                spacing: PindoroSpace.s3,
                children: [
                  ?leading,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: PindoroType.titleMd.copyWith(
                            color: enabled ? c.textPrimary : c.textDisabled,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: PindoroType.bodySm.copyWith(
                              color: c.textSecondary,
                            ),
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
/// `color.primary.text` glyph.
class RowTile extends StatelessWidget {
  const RowTile({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.primarySoft,
        borderRadius: BorderRadius.circular(PindoroRadius.md),
      ),
      child: IconTheme(
        data: IconThemeData(color: c.primaryText, size: PindoroSize.iconMd),
        child: child,
      ),
    );
  }
}
