import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'tappable.dart';
import 'whole_words.dart';

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
    this.large = false,
    this.iconOnly = false,
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

  /// 56 dp (`size.button.lg`): the drive's stopped-controls bar, reached from the driver's seat.
  final bool large;

  /// A square button showing only [icon]; [label] is what a screen reader hears.
  final bool iconOnly;

  /// The face's least height, the lip not counted.
  static const double height = PindoroSize.buttonMd;

  /// Called when any hero button is tapped: the app plays its tap sound.
  // ponytail: a static hook for the one app; an InheritedWidget if a second
  // app ever uses the design system.
  static VoidCallback? onHeroPress;

  /// The least width that keeps every word of [label] whole at the text scale: its widest
  /// word, the icon and the padding.
  double wholeWordsWidth(BuildContext context) {
    if (iconOnly && icon != null) return large ? PindoroSize.buttonLg : height;
    final scaler = MediaQuery.textScalerOf(context);
    final style = textStyleAsShown(context, PindoroType.labelButton);
    var widest = 0.0;
    for (final word in label.split(RegExp(r'\s+'))) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    final iconWidth = icon == null ? 0 : PindoroSize.iconMd + PindoroSpace.s2;
    return widest + iconWidth + 2 * PindoroSpace.s6;
  }

  @override
  State<PindoroButton> createState() => _PindoroButtonState();
}

/// Buttons side by side, sharing the width by [flex], else in equal shares when a label
/// would have to break inside a word (a long Georgian word in a narrow share), else stacked
/// full width in the same order.
class ButtonRow extends StatelessWidget {
  const ButtonRow(
    this.buttons, {
    super.key,
    this.flex,
    this.spacing = PindoroSpace.s3,
  });

  final List<PindoroButton> buttons;
  final List<int>? flex;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final room = box.maxWidth - spacing * (buttons.length - 1);
      final widths = [for (final b in buttons) b.wholeWordsWidth(context)];
      bool fits(List<int> flex) {
        final total = flex.fold(0, (a, b) => a + b);
        return widths.indexed.every((w) => w.$2 <= room * flex[w.$1] / total);
      }

      final equal = [for (final _ in buttons) 1];
      final flex = [?this.flex, equal].firstWhere(fits, orElse: () => const []);
      if (flex.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroSpace.s2,
          children: buttons,
        );
      }
      return Row(
        spacing: spacing,
        children: [
          for (final (i, b) in buttons.indexed)
            Expanded(flex: flex[i], child: b),
        ],
      );
    },
  );
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
    final label = WholeWords(
      Text(
        widget.label,
        textAlign: TextAlign.center,
        style: PindoroType.labelButton.copyWith(color: text),
      ),
    );

    final height = widget.large ? PindoroSize.buttonLg : PindoroButton.height;
    final square = widget.iconOnly && widget.icon != null;
    return Tappable(
      label: square ? widget.label : null,
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
        // A label wrapping at large text sizes grows it.
        child: Container(
          constraints: BoxConstraints(
            minHeight: height,
            minWidth: square ? height : 0,
          ),
          padding: square
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(
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
          // Fills the width it is given, but never a row's height.
          child: Center(
            heightFactor: 1,
            child: widget.icon == null
                ? label
                : square
                ? PindoroIcon(widget.icon!, color: text, cut: face)
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
      ),
    );
  }
}
