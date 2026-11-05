import 'package:flutter/material.dart';

import '../generated/pindoro_tokens.dart';

typedef _T = PindoroTokens;

enum PindoroButtonVariant { primary, secondary, ghost }

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
  final VoidCallback? onPressed;
  final PindoroButtonVariant variant;
  final IconData? icon;

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
    final (fill, lip, text) = switch (widget.variant) {
      PindoroButtonVariant.primary => (
        _T.colorButtonPrimaryFill,
        _T.colorButtonPrimaryLip,
        _T.colorButtonPrimaryText,
      ),
      PindoroButtonVariant.secondary => (
        _T.colorButtonSecondaryFill,
        _T.colorButtonSecondaryLip,
        _T.colorButtonSecondaryText,
      ),
      PindoroButtonVariant.ghost => (
        Colors.transparent,
        Colors.transparent,
        _T.colorButtonGhostText,
      ),
    };
    final enabled = widget.onPressed != null;
    final radius = BorderRadius.circular(_T.radiusLg);
    final lipHeight = _pressed ? 0.0 : _T.sizeButtonLip;
    final label = Text(
      widget.label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: text),
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
          child: Opacity(
            opacity: enabled ? 1 : PindoroTokens.opacityDisabled,
            child: AnimatedContainer(
              duration: _T.motionPress,
              curve: _T.motionPressCurve,
              margin: EdgeInsets.only(top: _T.sizeButtonLip - lipHeight),
              padding: EdgeInsets.only(bottom: lipHeight),
              decoration: BoxDecoration(color: lip, borderRadius: radius),
              child: Container(
                height: _T.sizeButtonHeight,
                padding: const EdgeInsets.symmetric(horizontal: _T.spaceLg),
                decoration: BoxDecoration(color: fill, borderRadius: radius),
                alignment: Alignment.center,
                child: widget.icon == null
                    ? label
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: _T.spaceSm,
                        children: [
                          Icon(widget.icon, color: text),
                          label,
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
