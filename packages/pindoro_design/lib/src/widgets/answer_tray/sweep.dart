import 'package:flutter/material.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../graphics.dart';
import '../painters.dart';
import '../tappable.dart';
import 'choices.dart';
import 'tray_frame.dart';

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
    this.skip,
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

  /// A way out under Confirm ("I don't know"), until the sweep is checked.
  final TraySkip? skip;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final half = MediaQuery.sizeOf(context).width / 2;
    return TrayFrame(
      question: question,
      meta: meta,
      list: ChoiceGrid(
        labels: [for (final l in labels) l.label],
        numbered: false,
        builder: (i, _) {
          Widget face({bool lifted = false}) => AnswerChoice(
            choice: labels[i],
            state: held == i ? ChoiceState.selected : ChoiceState.idle,
            lead: ChoiceLead.grip,
            number: i + 1,
            compact: lifted,
            onTap: lifted ? null : () => onHold(held == i ? null : i),
          );
          final slot = CustomPaint(
            foregroundPainter: DashedEdge(
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
      confirm: TrayConfirm(
        label: confirmLabel,
        hint: confirmHint,
        onPressed: onConfirm,
        skip: skip,
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
                verdictGlyph(right!),
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
              foregroundPainter: DashedEdge(
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
