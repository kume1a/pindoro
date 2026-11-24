import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'graphics.dart';
import 'painters.dart';
import 'pindoro_button.dart';
import 'surfaces.dart';
import 'tappable.dart';
import 'text_scale.dart';

/// One answer in an [AnswerTray] (or a label in a [SweepTray]): the name as
/// the city writes it, and its transliteration when the scripts differ.
typedef AnswerChoiceData = ({String label, String? sublabel});

/// A graded question: the index picked and the right one.
typedef AnswerResult = ({int picked, int right});

/// The tray's share of the screen's height (60 % from 160 % text).
double _maxShare(BuildContext context) => isLargeText(context) ? 0.6 : 0.45;

/// The edge a scrolling list fades out over.
const double _fade = 28;

/// The question tray docked over the map (Answer choices): the [question]
/// and its [meta] ("6 names"), four to six [choices] in a grid of equal rows
/// (one column, numbered, when a name doesn't fit half the width), then
/// [confirmLabel]. A tap selects, Confirm grades ([onConfirm] with the
/// index). With [result] set the choices show the right one and a wrong
/// pick, and take no input; the app swaps in the reveal sheet after 600 ms.
/// The handle drags it down to a peek. Give each question its own key: the
/// selection lives here.
class AnswerTray extends StatefulWidget {
  const AnswerTray({
    super.key,
    required this.question,
    required this.meta,
    required this.choices,
    required this.confirmLabel,
    required this.onConfirm,
    this.confirmHint,
    this.result,
  });

  final String question;
  final String meta;
  final List<AnswerChoiceData> choices;
  final String confirmLabel;
  final ValueChanged<int> onConfirm;

  /// What a screen reader hears on the disabled Confirm ("Pick a name
  /// first.").
  final String? confirmHint;
  final AnswerResult? result;

  @override
  State<AnswerTray> createState() => _AnswerTrayState();
}

class _AnswerTrayState extends State<AnswerTray> {
  int? _selected;

  @override
  void didUpdateWidget(AnswerTray old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.choices, widget.choices)) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final selected = _selected;
    return _TrayFrame(
      question: widget.question,
      meta: widget.meta,
      list: _ChoiceGrid(
        labels: [for (final c in widget.choices) c.label],
        builder: (i, numbered) {
          final state = switch (result) {
            (picked: _, right: final r) when r == i => _ChoiceState.right,
            (picked: final p, right: _) when p == i => _ChoiceState.wrong,
            _? => _ChoiceState.off,
            null when selected == i => _ChoiceState.selected,
            null => _ChoiceState.idle,
          };
          return _AnswerChoice(
            choice: widget.choices[i],
            state: state,
            lead: numbered ? _Lead.number : _Lead.radio,
            number: i + 1,
            onTap: result == null
                ? () {
                    unawaited(HapticFeedback.selectionClick());
                    setState(() => _selected = i);
                  }
                : null,
          );
        },
      ),
      confirm: _Confirm(
        label: widget.confirmLabel,
        hint: widget.confirmHint,
        onPressed: selected == null || result != null
            ? null
            : () {
                unawaited(HapticFeedback.mediumImpact());
                widget.onConfirm(selected);
              },
      ),
    );
  }
}

/// The family sweep's tray (Answer choices, sweep): the lanes' [labels],
/// each with a grip, to be tapped (then a [SweepSocket] tapped) or long
/// pressed and dragged onto their lanes. A [placed] label leaves a dashed
/// outline. [held] is the label picked up; [onHold] hears a pick up (and
/// null when it is put back). Confirm waits for [onConfirm].
class SweepTray extends StatelessWidget {
  const SweepTray({
    super.key,
    required this.question,
    required this.meta,
    required this.labels,
    required this.placed,
    required this.held,
    required this.onHold,
    required this.confirmLabel,
    this.onConfirm,
    this.confirmHint,
  });

  final String question;
  final String meta;
  final List<AnswerChoiceData> labels;
  final Set<int> placed;
  final int? held;
  final ValueChanged<int?> onHold;
  final String confirmLabel;
  final VoidCallback? onConfirm;
  final String? confirmHint;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final half = MediaQuery.sizeOf(context).width / 2;
    return _TrayFrame(
      question: question,
      meta: meta,
      list: _ChoiceGrid(
        labels: [for (final l in labels) l.label],
        numbered: false,
        builder: (i, _) {
          Widget face({bool lifted = false}) => _AnswerChoice(
            choice: labels[i],
            state: held == i ? _ChoiceState.selected : _ChoiceState.idle,
            lead: _Lead.grip,
            number: i + 1,
            compact: lifted,
            onTap: lifted ? null : () => onHold(held == i ? null : i),
          );
          final slot = CustomPaint(
            foregroundPainter: _DashedEdge(
              color: theme.colors.lineStrong,
              radius: PindoroRadius.lg,
            ),
            child: ExcludeSemantics(
              child: Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: face(),
              ),
            ),
          );
          if (placed.contains(i)) return slot;
          return LongPressDraggable<int>(
            data: i,
            onDragStarted: () => onHold(i),
            onDraggableCanceled: (_, _) => onHold(null),
            childWhenDragging: slot,
            feedback: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: half),
                child: Transform.scale(
                  scale: 1.04,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(PindoroRadius.lg),
                      boxShadow: [theme.floatShadow],
                    ),
                    child: face(lifted: true),
                  ),
                ),
              ),
            ),
            child: face(),
          );
        },
      ),
      confirm: _Confirm(
        label: confirmLabel,
        hint: confirmHint,
        onPressed: onConfirm,
      ),
    );
  }
}

/// A lane's socket on the map (Answer choices, sweep): an empty dashed
/// pill, awake (cobalt, with a plus) while a label is held ([waking]) or
/// dragged over it; the placed [label] as a cobalt name chip; once checked
/// ([right] set) in the Great or Miss colours, with the [truth] under a
/// wrong one in yellow paint. [onAccept] takes a dropped label's index.
class SweepSocket extends StatelessWidget {
  const SweepSocket({
    super.key,
    required this.semanticsLabel,
    this.label,
    this.waking = false,
    this.right,
    this.truth,
    this.onAccept,
    this.onTap,
  });

  final String semanticsLabel;
  final String? label;
  final bool waking;
  final bool? right;
  final String? truth;
  final ValueChanged<int>? onAccept;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    final label = this.label;
    final right = this.right;
    final truth = this.truth;
    Widget pill(bool hovering) {
      final awake = (waking || hovering) && right == null;
      final tier = switch (right) {
        true => theme.tier(Tier.great),
        false => theme.tier(Tier.miss),
        null => null,
      };
      final (face, lip, ink) = switch ((tier, label)) {
        (final t?, _) => (t.fill, t.lip, t.on),
        (null, _) when awake => (c.primarySoft, null, c.primaryText),
        (null, _?) => (c.mapAreaLabelBg, c.mapAreaLabelLip, c.mapAreaLabelText),
        (null, null) => (c.mapRegionLabelBg, null, c.textSecondary),
      };
      final radius = BorderRadius.circular(PindoroRadius.full);
      final body = Container(
        constraints: const BoxConstraints(minWidth: 84, minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: PindoroSpace.s3),
        decoration: BoxDecoration(
          color: face,
          borderRadius: radius,
          border: awake
              ? Border.all(color: c.primaryBase, width: PindoroStroke.thick)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: PindoroSpace.s1,
          children: [
            if (tier != null)
              PindoroIcon(
                right! ? PindoroGlyph.check : PindoroGlyph.reroute,
                size: PindoroSize.iconSm,
                color: ink,
                cut: face,
              )
            else if (awake && label == null)
              PindoroIcon(
                PindoroGlyph.plus,
                size: PindoroSize.iconSm,
                color: ink,
                cut: face,
              ),
            if (label != null)
              Flexible(
                child: Text(
                  label,
                  style: PindoroType.labelMd.copyWith(color: ink),
                ),
              ),
          ],
        ),
      );
      final edged = label == null && !awake && tier == null
          ? CustomPaint(
              foregroundPainter: _DashedEdge(
                color: c.mapAreaStroke,
                radius: PindoroRadius.full,
              ),
              child: body,
            )
          : body;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: lip ?? Colors.transparent,
          borderRadius: radius,
          boxShadow: [theme.floatShadow],
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: lip == null ? 0 : PindoroStroke.base,
          ),
          child: edged,
        ),
      );
    }

    return Tappable(
      label: semanticsLabel,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PindoroSpace.s1,
          vertical: PindoroSpace.s2,
        ),
        child: DragTarget<int>(
          onWillAcceptWithDetails: (_) => onAccept != null,
          onAcceptWithDetails: (d) => onAccept?.call(d.data),
          builder: (context, hovering, _) => Column(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s1,
            children: [
              pill(hovering.isNotEmpty),
              if (right == false && truth != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PindoroSpace.s2,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.mapAnswerLine,
                    borderRadius: BorderRadius.circular(PindoroRadius.full),
                    border: Border.all(
                      color: c.mapAnswerCasing,
                      width: PindoroStroke.base,
                    ),
                  ),
                  child: Text(
                    truth,
                    style: PindoroType.labelMd.copyWith(
                      color: c.mapAnswerCasing,
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

/// The tray's chrome: the overlay surface docked to the bottom with its
/// handle, the ask row, the scrolling [list] and the pinned [confirm]. A drag
/// down on the handle strip peeks (handle and ask row only); a tap or a drag
/// up opens it again, as does the next question.
class _TrayFrame extends StatefulWidget {
  const _TrayFrame({
    required this.question,
    required this.meta,
    required this.list,
    required this.confirm,
  });

  final String question;
  final String meta;
  final Widget list;
  final Widget confirm;

  @override
  State<_TrayFrame> createState() => _TrayFrameState();
}

class _TrayFrameState extends State<_TrayFrame> {
  bool _peek = false;
  double _drag = 0;

  @override
  void didUpdateWidget(_TrayFrame old) {
    super.didUpdateWidget(old);
    if (old.question != widget.question) _peek = false;
  }

  void _dragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final down = v != 0 ? v > 0 : _drag > 0;
    if (_drag != 0 || v != 0) setState(() => _peek = down);
    _drag = 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final mq = MediaQuery.of(context);
    const top = BorderRadius.vertical(top: Radius.circular(PindoroRadius.r2xl));
    final head = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _peek ? () => setState(() => _peek = false) : null,
      onVerticalDragUpdate: (d) => _drag += d.delta.dy,
      onVerticalDragEnd: _dragEnd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: SheetHandle()),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: PindoroSpace.s3,
            runSpacing: 2,
            children: [
              Text(
                widget.question,
                style: PindoroType.titleMd.copyWith(color: c.textPrimary),
              ),
              Text(
                widget.meta,
                style: PindoroType.labelMd.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.question,
      // The 2 dp top edge: the overlay sits 2 dp down on a line-coloured
      // shape of the same radius.
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.lineBase, borderRadius: top),
        child: Padding(
          padding: const EdgeInsets.only(top: PindoroStroke.base),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surfaceOverlay,
              borderRadius: top,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: mq.size.height * _maxShare(context),
              ),
              // AnimatedSize with a zero duration re-dirties itself in layout,
              // so reduce motion goes without it.
              child: _sized(
                context,
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    PindoroSpace.s3,
                    0,
                    PindoroSpace.s3,
                    PindoroSpace.s4 + mq.padding.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      head,
                      if (!_peek) ...[
                        const SizedBox(height: PindoroSpace.s2),
                        Flexible(child: _FadeScroll(child: widget.list)),
                        const SizedBox(height: PindoroSpace.s2),
                        widget.confirm,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [child] growing and shrinking as the tray peeks, unless motion is reduced.
Widget _sized(BuildContext context, Widget child) =>
    MediaQuery.disableAnimationsOf(context)
    ? child
    : AnimatedSize(
        duration: PindoroMotion.durationFast,
        curve: PindoroMotion.easeStandard,
        alignment: Alignment.topCenter,
        child: child,
      );

/// The full-width Confirm, with [hint] for screen readers while it waits.
class _Confirm extends StatelessWidget {
  const _Confirm({required this.label, required this.onPressed, this.hint});

  final String label;
  final String? hint;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    hint: onPressed == null ? hint : null,
    child: PindoroButton(label: label, onPressed: onPressed),
  );
}

/// [child] scrolling, its cut edges fading out over [_fade] dp.
class _FadeScroll extends StatefulWidget {
  const _FadeScroll({required this.child});

  final Widget child;

  @override
  State<_FadeScroll> createState() => _FadeScrollState();
}

class _FadeScrollState extends State<_FadeScroll> {
  bool _above = false;
  bool _below = false;

  bool _update(ScrollMetrics m) {
    final above = m.extentBefore > 0.5;
    final below = m.extentAfter > 0.5;
    if (above != _above || below != _below) {
      setState(() {
        _above = above;
        _below = below;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) => _update(n.metrics),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => _update(n.metrics),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) {
              final f = (_fade / math.max(rect.height, 1)).clamp(0.0, 0.5);
              const solid = Color(0xFFFFFFFF);
              const clear = Color(0x00FFFFFF);
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _above ? clear : solid,
                  solid,
                  solid,
                  _below ? clear : solid,
                ],
                stops: [0, f, 1 - f, 1],
              ).createShader(rect);
            },
            // The lips and the press need room above the first row.
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 2),
              child: widget.child,
            ),
          ),
        ),
      );
}

/// The choices in rows of two, each row as tall as its tallest, or in one
/// column when a name doesn't fit half the width (a word too wide even at
/// its soft hyphens, or more than three lines), or the text is at 200 %.
/// Decided once for the whole list. [builder] makes choice `i`, numbered or
/// not.
class _ChoiceGrid extends StatelessWidget {
  const _ChoiceGrid({
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
    TextPainter painter(String text) => TextPainter(
      text: TextSpan(text: text, style: PindoroType.labelLg),
      textScaler: scaler,
      textDirection: TextDirection.ltr,
    );
    double widthOf(String text) {
      final p = painter(text)..layout();
      final width = p.width;
      p.dispose();
      return width;
    }

    for (final word in label.split(RegExp(r'\s+'))) {
      // A word may break at its soft hyphens, each piece with its hyphen.
      final pieces = word.split('­');
      for (final (i, piece) in pieces.indexed) {
        final shown = i < pieces.length - 1 ? '$piece-' : piece;
        if (widthOf(shown) > width) return false;
      }
    }
    final whole = painter(label)..layout(maxWidth: width);
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

enum _ChoiceState { idle, selected, right, wrong, off }

enum _Lead { radio, number, grip }

/// One choice: a secondary button's face and lip with its key and name. A
/// selected choice stays half pressed; after Confirm the right one is Great
/// with a check, a wrong pick Miss with `reroute`, the others disabled.
class _AnswerChoice extends StatefulWidget {
  const _AnswerChoice({
    required this.choice,
    required this.state,
    required this.lead,
    required this.number,
    required this.onTap,
    this.compact = false,
  });

  final AnswerChoiceData choice;
  final _ChoiceState state;
  final _Lead lead;
  final int number;
  final VoidCallback? onTap;

  /// As wide as its name (a dragged label), not as its column.
  final bool compact;

  @override
  State<_AnswerChoice> createState() => _AnswerChoiceState();
}

class _AnswerChoiceState extends State<_AnswerChoice> {
  bool _pressed = false;

  void _press(bool down) {
    if (widget.onTap != null) setState(() => _pressed = down);
  }

  @override
  void didUpdateWidget(_AnswerChoice old) {
    super.didUpdateWidget(old);
    // Disabled mid-press (graded): its release never comes.
    if (widget.onTap == null) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final state = widget.state;
    final (face, edge, edgeWidth, lip, ink) = switch (state) {
      _ChoiceState.idle => (
        c.surfaceRaised,
        c.lineBase,
        PindoroStroke.base,
        c.lineBase,
        c.textPrimary,
      ),
      _ChoiceState.selected => (
        c.primarySoft,
        c.primaryBase,
        PindoroStroke.thick,
        c.primaryLip,
        c.primaryText,
      ),
      _ChoiceState.right => (
        c.feedbackGreatFill,
        c.feedbackGreatFill,
        PindoroStroke.base,
        c.feedbackGreatLip,
        c.feedbackGreatOn,
      ),
      _ChoiceState.wrong => (
        c.feedbackMissFill,
        c.feedbackMissFill,
        PindoroStroke.base,
        c.feedbackMissLip,
        c.feedbackMissOn,
      ),
      _ChoiceState.off => (
        c.buttonDisabledBg,
        c.buttonDisabledBg,
        PindoroStroke.base,
        c.buttonDisabledLip,
        c.buttonDisabledText,
      ),
    };
    const full = PindoroElevation.e2;
    final lipNow = _pressed
        ? 0.0
        : state == _ChoiceState.selected
        ? full / 2
        : full;
    final sub = switch (state) {
      _ChoiceState.idle => c.textSecondary,
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
    final body = AnimatedContainer(
      duration: PindoroMotion.durationInstant,
      curve: PindoroMotion.easePress,
      margin: EdgeInsets.only(top: full - lipNow),
      padding: EdgeInsets.only(bottom: lipNow),
      decoration: BoxDecoration(color: lip, borderRadius: radius),
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
      inMutuallyExclusiveGroup: widget.lead != _Lead.grip,
      checked: widget.lead == _Lead.grip
          ? null
          : state == _ChoiceState.selected,
      selected: widget.lead == _Lead.grip
          ? state == _ChoiceState.selected
          : null,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      child: body,
    );
  }

  Widget _key(PindoroColors c, Color face, Color ink) {
    final state = widget.state;
    if (state == _ChoiceState.right || state == _ChoiceState.wrong) {
      return PindoroIcon(
        state == _ChoiceState.right ? PindoroGlyph.check : PindoroGlyph.reroute,
        size: PindoroSize.iconSm,
        color: ink,
        cut: face,
      );
    }
    final on = state == _ChoiceState.selected;
    final off = state == _ChoiceState.off;
    switch (widget.lead) {
      case _Lead.grip:
        return CustomPaint(
          size: const Size(10, 18),
          painter: _Grip(off ? c.buttonDisabledText : c.textSecondary),
        );
      case _Lead.number:
        return Container(
          width: 24,
          height: 24,
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
      case _Lead.radio:
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

/// A 2 dp dashed rounded edge (an empty socket, a placed label's slot).
class _DashedEdge extends CustomPainter {
  const _DashedEdge({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const w = PindoroStroke.base;
    final r = math.min(radius, size.shortestSide / 2);
    final edge = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(w / 2),
          Radius.circular(r),
        ),
      );
    final dashes = dashedPath(edge, dash: 6, period: 10);
    canvas.drawPath(
      dashes,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w,
    );
  }

  @override
  bool shouldRepaint(_DashedEdge old) =>
      old.color != color || old.radius != radius;
}
