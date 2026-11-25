import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'surfaces.dart';
import 'tappable.dart';

/// A 48 dp search field on a 2 dp lip; the border and lip turn cobalt while
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
    this.obscureText = false,
    this.autocorrect = true,
    this.autofillHints,
    this.autofocus = false,
    this.keepFocus = false,
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

  /// Hides the text, for a password.
  final bool obscureText;

  /// Off for usernames, passwords and codes: no corrections or suggestions.
  final bool autocorrect;

  /// What the platform may autofill (a username, a password).
  final Iterable<String>? autofillHints;

  /// Focused, keyboard up, as the screen opens (a search screen of its own).
  final bool autofocus;

  /// Stays focused, keyboard up, after a submit: a field typed in again and again (names
  /// one after another).
  final bool keepFocus;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

const double _innerHeight =
    PindoroSize.buttonMd - PindoroElevation.e1 - 2 * PindoroStroke.base;

class _SearchFieldState extends State<SearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(SearchField old) {
    super.didUpdateWidget(old);
    if (old.controller == widget.controller) return;
    old.controller.removeListener(_changed);
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
    // The clear button counts as inside: a tap elsewhere hides the keyboard.
    return TextFieldTapRegion(
      child: LipBox(
        face: c.inputBg,
        lip: edge,
        border: edge,
        radius: PindoroRadius.lg,
        // 48 dp counting the border and the lip; taller with large text.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _innerHeight),
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
                  // Without it a submit moves focus on, and the keyboard drops.
                  onEditingComplete: widget.keepFocus ? () {} : null,
                  onTapOutside: (_) => _focus.unfocus(),
                  textInputAction: widget.textInputAction,
                  textCapitalization: widget.textCapitalization,
                  obscureText: widget.obscureText,
                  autofocus: widget.autofocus,
                  autofillHints: widget.autofillHints,
                  autocorrect: widget.autocorrect,
                  enableSuggestions: widget.autocorrect,
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
                  child: SizedBox(
                    width: PindoroSize.tapMin,
                    height: _innerHeight,
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
              // A long label (a street's full name) wraps instead of overflowing.
              Flexible(
                child: Text(
                  label,
                  style: PindoroType.labelLg.copyWith(color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
