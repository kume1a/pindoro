import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'tappable.dart';

enum PindoroButtonVariant { primary, secondary, tertiary, reward }

/// Flat face on a solid bottom lip; pressing pushes the face down onto it.
class PindoroButton extends StatefulWidget {
  const PindoroButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = PindoroButtonVariant.primary,
    this.icon,
    this.tier,
    this.hero = false,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final PindoroButtonVariant variant;
  final PindoroGlyph? icon;

  /// Tier colours (the reveal sheet's Next); overrides [variant].
  final Tier? tier;

  /// The bigger `elevation.3` lip for hero actions.
  final bool hero;

  /// Called when any hero button is tapped: the app plays its tap sound.
  // ponytail: a static hook for the one app; an InheritedWidget if a second
  // app ever uses the design system.
  static VoidCallback? onHeroPress;

  @override
  State<PindoroButton> createState() => _PindoroButtonState();
}

class _PindoroButtonState extends State<PindoroButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onPressed != null) setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(PindoroButton old) {
    super.didUpdateWidget(old);
    // Disabled mid-press, the release would be ignored and the face stay down.
    if (widget.onPressed == null) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    final enabled = widget.onPressed != null;
    final tier = widget.tier == null ? null : theme.tier(widget.tier!);
    final (face, lip, text, border) = !enabled
        ? (c.buttonDisabledBg, c.buttonDisabledLip, c.buttonDisabledText, null)
        : tier != null
        ? (tier.fill, tier.lip, tier.on, null)
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
            PindoroButtonVariant.reward => (
              c.buttonRewardBg,
              c.buttonRewardLip,
              c.buttonRewardText,
              null,
            ),
          };
    final radius = BorderRadius.circular(PindoroRadius.lg);
    final fullLip = widget.hero ? PindoroElevation.e3 : PindoroElevation.e2;
    final lipHeight = _pressed ? 0.0 : fullLip;
    final label = Text(
      widget.label,
      textAlign: TextAlign.center,
      style: PindoroType.labelButton.copyWith(color: text),
    );

    return Tappable(
      onTap: !enabled
          ? null
          : () {
              if (widget.hero) PindoroButton.onHeroPress?.call();
              widget.onPressed!();
            },
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedContainer(
        duration: PindoroMotion.durationInstant,
        curve: PindoroMotion.easePress,
        margin: EdgeInsets.only(top: fullLip - lipHeight),
        padding: EdgeInsets.only(bottom: lipHeight),
        decoration: BoxDecoration(color: lip, borderRadius: radius),
        // At least 56 dp; a label wrapping at large text sizes grows it.
        child: Container(
          constraints: const BoxConstraints(minHeight: PindoroSize.buttonLg),
          padding: const EdgeInsets.symmetric(
            horizontal: PindoroSpace.s6,
            vertical: PindoroSpace.s2,
          ),
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
                    Flexible(child: label),
                  ],
                ),
        ),
      ),
    );
  }
}
