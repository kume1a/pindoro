import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'surfaces.dart';
import 'tappable.dart';

/// A 56 dp search field on a 2 dp lip; the border and lip turn cobalt while
/// focused, and a clear button shows once there is text.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.clearLabel,
    this.onChanged,
    this.onSubmitted,
    this.glyph = PindoroGlyph.search,
    this.textInputAction = TextInputAction.search,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String placeholder;
  final String clearLabel;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// The leading icon; a name field uses [PindoroGlyph.user].
  final PindoroGlyph glyph;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    widget.controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final edge = _focus.hasFocus ? c.inputBorderFocus : c.inputBorder;
    return LipBox(
      face: c.inputBg,
      lip: edge,
      border: edge,
      radius: PindoroRadius.lg,
      // 56 dp counting the border and the lip.
      child: SizedBox(
        height:
            PindoroSize.buttonLg - PindoroElevation.e1 - 2 * PindoroStroke.base,
        child: Row(
          children: [
            const SizedBox(width: PindoroSpace.s4),
            PindoroIcon(widget.glyph, color: c.inputIcon),
            const SizedBox(width: PindoroSpace.s2),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                textInputAction: widget.textInputAction,
                textCapitalization: widget.textCapitalization,
                cursorColor: c.primaryBase,
                style: PindoroType.bodyLg.copyWith(color: c.inputText),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintText: widget.placeholder,
                  hintStyle: PindoroType.bodyLg.copyWith(
                    color: c.inputPlaceholder,
                  ),
                ),
              ),
            ),
            if (widget.controller.text.isNotEmpty)
              Tappable(
                label: widget.clearLabel,
                onTap: () {
                  widget.controller.clear();
                  widget.onChanged?.call('');
                },
                child: SizedBox.square(
                  dimension: PindoroSize.tapMin,
                  child: Center(
                    child: PindoroIcon(
                      PindoroGlyph.close,
                      size: PindoroSize.iconSm,
                      color: c.inputIcon,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Home's top-left control: pin, city name, chevron.
class CitySwitcher extends StatelessWidget {
  const CitySwitcher({
    super.key,
    required this.city,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String city;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(PindoroRadius.md),
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.surfaceSunken,
          mouseCursor: SystemMouseCursors.click,
          child: SizedBox(
            height: PindoroSize.tapMin,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: PindoroSpace.s1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: PindoroSpace.s1,
                children: [
                  PindoroIcon(PindoroGlyph.pin, size: 22, color: c.primaryText),
                  Flexible(
                    child: Text(
                      city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PindoroType.titleMd.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  PindoroIcon(
                    PindoroGlyph.chevronDown,
                    size: 18,
                    color: c.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill-shaped toggle (districts): 40 dp face inside a 48 dp target; a
/// selected chip is cobalt-soft with a check. [PindoroChip.action] is a
/// plain button in the same shape (e.g. "All 104").
class PindoroChip extends StatelessWidget {
  const PindoroChip({
    super.key,
    required this.label,
    required bool this.selected,
    required this.onPressed,
  });

  const PindoroChip.action({
    super.key,
    required this.label,
    required this.onPressed,
  }) : selected = null;

  final String label;

  /// Null for an action chip, which has no checked state.
  final bool? selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final selected = this.selected ?? false;
    final ink = selected ? c.chipSelectedText : c.chipText;
    return Tappable(
      button: this.selected == null,
      checked: this.selected,
      label: label,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: PindoroSpace.s1),
        child: LipBox(
          face: selected ? c.chipSelectedBg : c.chipBg,
          lip: selected ? c.chipSelectedBorder : c.chipBorder,
          border: selected ? c.chipSelectedBorder : c.chipBorder,
          radius: PindoroRadius.full,
          padding: const EdgeInsets.symmetric(
            horizontal: PindoroSpace.s3,
            vertical: PindoroSpace.s2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s1,
            children: [
              if (selected)
                PindoroIcon(
                  PindoroGlyph.check,
                  size: PindoroSize.iconSm,
                  color: ink,
                ),
              Text(label, style: PindoroType.labelLg.copyWith(color: ink)),
            ],
          ),
        ),
      ),
    );
  }
}
