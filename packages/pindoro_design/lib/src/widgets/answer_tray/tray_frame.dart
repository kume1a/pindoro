import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../pindoro_button.dart';
import '../surfaces.dart';
import '../text_scale.dart';

/// The tray's share of the screen's height (60 % from 160 % text).
double _maxShare(BuildContext context) => isLargeText(context) ? 0.6 : 0.45;

/// The edge a scrolling list fades out over.
const double _fade = 28;

/// The tray's chrome: the overlay surface docked to the bottom with its
/// handle, the ask row, the scrolling [list] and the pinned [confirm]. A drag
/// down on the handle strip peeks (handle and ask row only); a tap or a drag
/// up opens it again, as does the next question.
class TrayFrame extends StatefulWidget {
  const TrayFrame({
    super.key,
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
  State<TrayFrame> createState() => _TrayFrameState();
}

class _TrayFrameState extends State<TrayFrame> {
  bool _peek = false;
  double _drag = 0;

  @override
  void didUpdateWidget(TrayFrame old) {
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

/// A tray's way out under its Confirm: its [label] ("I don't know") and [onSkip].
typedef TraySkip = ({String label, VoidCallback onSkip});

/// The full-width Confirm, with [hint] for screen readers while it waits.
class TrayConfirm extends StatelessWidget {
  const TrayConfirm({
    super.key,
    required this.label,
    required this.onPressed,
    this.hint,
    this.skip,
  });

  final String label;
  final String? hint;
  final VoidCallback? onPressed;
  final TraySkip? skip;

  @override
  Widget build(BuildContext context) {
    final confirm = Semantics(
      hint: onPressed == null ? hint : null,
      child: PindoroButton(label: label, onPressed: onPressed),
    );
    return switch (skip) {
      (:final label, :final onSkip) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s1,
        children: [
          confirm,
          PindoroButton(
            label: label,
            variant: PindoroButtonVariant.tertiary,
            onPressed: onSkip,
          ),
        ],
      ),
      null => confirm,
    };
  }
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
