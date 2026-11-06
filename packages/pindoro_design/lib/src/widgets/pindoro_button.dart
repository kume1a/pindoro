import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';

enum PindoroButtonVariant { primary, secondary, tertiary }

/// Flat face on a solid bottom lip; pressing pushes the face down onto it.
class PindoroButton extends StatefulWidget {
  const PindoroButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = PindoroButtonVariant.primary,
    this.icon,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final PindoroButtonVariant variant;
  final PindoroGlyph? icon;

  @override
  State<PindoroButton> createState() => _PindoroButtonState();
}

class _PindoroButtonState extends State<PindoroButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed != null) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final enabled = widget.onPressed != null;
    final (face, lip, text, border) = !enabled
        ? (c.buttonDisabledBg, c.buttonDisabledLip, c.buttonDisabledText, null)
        : switch (widget.variant) {
            PindoroButtonVariant.primary => (
              c.buttonPrimaryBg,
              c.buttonPrimaryLip,
              c.buttonPrimaryText,
              null,
            ),
            PindoroButtonVariant.secondary => (
              c.buttonSecondaryBg,
              c.buttonSecondaryLip,
              c.buttonSecondaryText,
              c.buttonSecondaryBorder,
            ),
            PindoroButtonVariant.tertiary => (
              Colors.transparent,
              Colors.transparent,
              c.buttonTertiaryText,
              null,
            ),
          };
    final radius = BorderRadius.circular(PindoroRadius.lg);
    final lipHeight = _pressed ? 0.0 : PindoroElevation.e2;
    final label = Text(
      widget.label,
      style: PindoroType.labelButton.copyWith(color: text),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        child: GestureDetector(
          onTap: widget.onPressed,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: AnimatedContainer(
            duration: PindoroMotion.durationInstant,
            curve: PindoroMotion.easePress,
            margin: EdgeInsets.only(top: PindoroElevation.e2 - lipHeight),
            padding: EdgeInsets.only(bottom: lipHeight),
            decoration: BoxDecoration(color: lip, borderRadius: radius),
            child: Container(
              height: PindoroSize.buttonLg,
              padding: const EdgeInsets.symmetric(horizontal: PindoroSpace.s6),
              decoration: BoxDecoration(
                color: face,
                borderRadius: radius,
                border: border == null
                    ? null
                    : Border.all(color: border, width: PindoroStroke.base),
              ),
              alignment: Alignment.center,
              child: widget.icon == null
                  ? label
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: PindoroSpace.s2,
                      children: [
                        PindoroIcon(widget.icon!, color: text, cut: face),
                        label,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
