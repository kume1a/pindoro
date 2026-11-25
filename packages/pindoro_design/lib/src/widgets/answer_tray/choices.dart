import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../graphics.dart';
import '../tappable.dart';
import '../whole_words.dart';

/// One answer in an [AnswerTray] (or a label in a [SweepTray]): the name as
/// the city writes it, and its transliteration when the scripts differ.
typedef AnswerChoiceData = ({String label, String? sublabel});

/// The choices in rows of two, each row as tall as its tallest, or in one
/// column when a name doesn't fit half the width (a word too wide even at
/// its soft hyphens, or more than three lines), or the text is at 200 %.
/// Decided once for the whole list. [builder] makes choice `i`, numbered or
/// not.
class ChoiceGrid extends StatelessWidget {
  const ChoiceGrid({
    super.key,
    required this.labels,
    required this.builder,
    this.numbered,
  });

  final List<String> labels;
  final bool? numbered;
  final Widget Function(int i, bool numbered) builder;

  /// A choice's padding, border and key around its text box.
  static const double _chrome =
      2 * PindoroSpace.s2 + 2 * PindoroStroke.thick + PindoroSize.iconSm + 6;

  static bool _fits(String label, double width, TextScaler scaler) {
    for (final word in label.split(RegExp(r'\s+'))) {
      // A word may break at its soft hyphens, each piece with its hyphen.
      final pieces = word.split('­');
      for (final (i, piece) in pieces.indexed) {
        final shown = i < pieces.length - 1 ? '$piece-' : piece;
        if (textWidth(shown, PindoroType.labelLg, scaler: scaler) > width) {
          return false;
        }
      }
    }
    final whole = TextPainter(
      text: TextSpan(text: label, style: PindoroType.labelLg),
      textScaler: scaler,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final lines = whole.computeLineMetrics().length;
    whole.dispose();
    return lines <= 3;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final text = (constraints.maxWidth - PindoroSpace.s2) / 2 - _chrome;
      final one =
          scaler.scale(1) >= 2 || !labels.every((l) => _fits(l, text, scaler));
      final numbered = this.numbered ?? one;
      final n = labels.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s2,
        children: one
            ? [for (var i = 0; i < n; i++) builder(i, numbered)]
            : [
                for (var i = 0; i < n; i += 2)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: PindoroSpace.s2,
                      children: [
                        Expanded(child: builder(i, numbered)),
                        Expanded(
                          child: i + 1 < n
                              ? builder(i + 1, numbered)
                              : const SizedBox(),
                        ),
                      ],
                    ),
                  ),
              ],
      );
    },
  );
}

enum ChoiceState { idle, selected, right, wrong, off }

/// A checked choice's mark: a check when right, `reroute` when wrong.
PindoroGlyph verdictGlyph(bool right) =>
    right ? PindoroGlyph.check : PindoroGlyph.reroute;

enum ChoiceLead { radio, number, grip }

/// One choice: a secondary button's face and lip with its key and name. A
/// selected choice stays half pressed; after Confirm the right one is Great
/// with a check, a wrong pick Miss with `reroute`, the others disabled.
class AnswerChoice extends StatefulWidget {
  const AnswerChoice({
    super.key,
    required this.choice,
    required this.state,
    required this.lead,
    required this.number,
    required this.onTap,
    this.compact = false,
  });

  final AnswerChoiceData choice;
  final ChoiceState state;
  final ChoiceLead lead;
  final int number;
  final VoidCallback? onTap;

  /// As wide as its name (a dragged label), not as its column.
  final bool compact;

  @override
  State<AnswerChoice> createState() => _AnswerChoiceState();
}

class _AnswerChoiceState extends State<AnswerChoice>
    with LipPressState<AnswerChoice> {
  @override
  bool get pressEnabled => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    (Color, Color, double, Color, Color) verdict(Tier tier) {
      final t = theme.tier(tier);
      return (t.fill, t.fill, PindoroStroke.base, t.lip, t.on);
    }

    final state = widget.state;
    final (face, edge, edgeWidth, lip, ink) = switch (state) {
      ChoiceState.idle => (
        c.surfaceRaised,
        c.lineBase,
        PindoroStroke.base,
        c.lineBase,
        c.textPrimary,
      ),
      ChoiceState.selected => (
        c.primarySoft,
        c.primaryBase,
        PindoroStroke.thick,
        c.primaryLip,
        c.primaryText,
      ),
      ChoiceState.right => verdict(Tier.great),
      ChoiceState.wrong => verdict(Tier.miss),
      ChoiceState.off => (
        c.buttonDisabledBg,
        c.buttonDisabledBg,
        PindoroStroke.base,
        c.buttonDisabledLip,
        c.buttonDisabledText,
      ),
    };
    const full = PindoroElevation.e2;
    final lipNow = pressed
        ? 0.0
        : state == ChoiceState.selected
        ? full / 2
        : full;
    final sub = switch (state) {
      ChoiceState.idle => c.textSecondary,
      _ => ink,
    };
    final choice = widget.choice;
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          choice.label,
          softWrap: true,
          style: PindoroType.labelLg.copyWith(color: ink),
        ),
        if (choice.sublabel case final s?)
          Text(
            s,
            style: PindoroType.bodySm.copyWith(height: 18 / 13, color: sub),
          ),
      ],
    );
    final radius = BorderRadius.circular(PindoroRadius.lg);
    final body = LipFace(
      full: full,
      lip: lipNow,
      lipColor: lip,
      radius: radius,
      child: Container(
        constraints: const BoxConstraints(minHeight: PindoroSize.buttonMd),
        padding: const EdgeInsets.all(PindoroSpace.s2),
        decoration: BoxDecoration(
          color: face,
          borderRadius: radius,
          border: Border.all(color: edge, width: edgeWidth),
        ),
        child: Row(
          mainAxisSize: widget.compact ? MainAxisSize.min : MainAxisSize.max,
          spacing: 6,
          children: [
            _key(c, face, ink),
            if (widget.compact)
              Flexible(child: name)
            else
              Expanded(child: name),
          ],
        ),
      ),
    );
    final sublabel = choice.sublabel;
    return Tappable(
      onTap: widget.onTap,
      label: sublabel == null ? choice.label : '$sublabel, ${choice.label}',
      inMutuallyExclusiveGroup: widget.lead != ChoiceLead.grip,
      checked: widget.lead == ChoiceLead.grip
          ? null
          : state == ChoiceState.selected,
      selected: widget.lead == ChoiceLead.grip
          ? state == ChoiceState.selected
          : null,
      onPress: press,
      child: body,
    );
  }

  Widget _key(PindoroColors c, Color face, Color ink) {
    final state = widget.state;
    if (state == ChoiceState.right || state == ChoiceState.wrong) {
      return PindoroIcon(
        verdictGlyph(state == ChoiceState.right),
        size: PindoroSize.iconSm,
        color: ink,
        cut: face,
      );
    }
    final on = state == ChoiceState.selected;
    final off = state == ChoiceState.off;
    switch (widget.lead) {
      case ChoiceLead.grip:
        return CustomPaint(
          size: const Size(10, 18),
          painter: _Grip(off ? c.buttonDisabledText : c.textSecondary),
        );
      case ChoiceLead.number:
        return Container(
          width: PindoroSize.iconMd,
          height: PindoroSize.iconMd,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? c.primaryBase : c.surfaceSunken,
            borderRadius: BorderRadius.circular(PindoroRadius.sm),
          ),
          child: Text(
            '${widget.number}',
            textScaler: TextScaler.noScaling,
            style: PindoroType.labelMd.copyWith(
              fontWeight: FontWeight.w800,
              color: on
                  ? c.primaryOn
                  : off
                  ? c.buttonDisabledText
                  : c.textSecondary,
            ),
          ),
        );
      case ChoiceLead.radio:
        return Container(
          width: PindoroSize.iconSm,
          height: PindoroSize.iconSm,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? c.primaryBase : null,
            border: Border.all(
              color: on
                  ? c.primaryBase
                  : off
                  ? c.buttonDisabledText
                  : c.lineStrong,
              width: PindoroStroke.base,
            ),
          ),
          child: on
              ? Container(
                  width: PindoroSpace.s2,
                  height: PindoroSpace.s2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.primaryOn,
                  ),
                )
              : null,
        );
    }
  }
}

/// A label's grip: six dots in two columns.
class _Grip extends CustomPainter {
  const _Grip(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final x in [2.5, 7.5]) {
      for (final y in [3.0, 9.0, 15.0]) {
        canvas.drawCircle(Offset(x, y), 1.75, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Grip old) => old.color != color;
}
