import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../graphics.dart';
import '../tappable.dart';
import '../text_scale.dart';
import 'drive_parts.dart';

/// One step of a [LevelPicker]: disabled with its [disabledReason].
typedef LevelStep<T> = ({
  T value,
  String label,
  PindoroGlyph icon,
  String? disabledReason,
});

/// Four steps of help for a drive (LevelPicker): the [suggested] step wears
/// a yellow [suggestedLabel] tag; a disabled step says why on long-press. A
/// tap applies at once. Parked only: it follows the app theme.
class LevelPicker<T> extends StatelessWidget {
  const LevelPicker({
    super.key,
    required this.steps,
    required this.selected,
    required this.suggestedLabel,
    required this.onChanged,
    required this.semanticsLabel,
    this.suggested,
  });

  final List<LevelStep<T>> steps;
  final T selected;
  final T? suggested;
  final String suggestedLabel;
  final ValueChanged<T> onChanged;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final large = isLargeText(context);
    Widget step(int i) {
      final s = steps[i];
      return Expanded(
        child: _LevelStepView(
          step: s,
          selected: s.value == selected,
          suggested: s.value == suggested,
          suggestedLabel: suggestedLabel,
          semanticsLabel: [
            s.label,
            if (s.value == suggested) suggestedLabel,
            ?s.disabledReason,
            '${i + 1} / ${steps.length}',
          ].join(', '),
          // The selected step stays enabled (read as checked, not unavailable).
          onTap: s.disabledReason != null
              ? null
              : () {
                  if (s.value != selected) onChanged(s.value);
                },
        ),
      );
    }

    Widget row(Iterable<int> indexes) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: PindoroSpace.s1,
      children: [for (final i in indexes) step(i)],
    );
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Container(
        // Room above for the suggested tag.
        margin: const EdgeInsets.only(top: PindoroSpace.s3),
        padding: const EdgeInsets.all(PindoroSpace.s1),
        decoration: BoxDecoration(
          color: c.surfaceSunken,
          borderRadius: BorderRadius.circular(PindoroRadius.lg),
        ),
        child: IntrinsicHeight(
          child: large
              ? Column(
                  spacing: PindoroSpace.s4,
                  children: [
                    for (var i = 0; i < steps.length; i += 2)
                      IntrinsicHeight(
                        child: row([i, if (i + 1 < steps.length) i + 1]),
                      ),
                  ],
                )
              : row(List.generate(steps.length, (i) => i)),
        ),
      ),
    );
  }
}

class _LevelStepView<T> extends StatelessWidget {
  const _LevelStepView({
    required this.step,
    required this.selected,
    required this.suggested,
    required this.suggestedLabel,
    required this.semanticsLabel,
    required this.onTap,
  });

  final LevelStep<T> step;
  final bool selected;
  final bool suggested;
  final String suggestedLabel;
  final String semanticsLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final disabled = step.disabledReason != null;
    final ink = disabled
        ? c.textDisabled
        : selected
        ? c.primaryText
        : c.textSecondary;
    final large = isLargeText(context);
    final face = AnimatedContainer(
      duration: PindoroMotion.durationQuick,
      curve: PindoroMotion.easeStandard,
      constraints: BoxConstraints(minHeight: large ? 96 : 64),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      decoration: BoxDecoration(
        color: selected ? c.surfaceRaised : Colors.transparent,
        borderRadius: BorderRadius.circular(PindoroRadius.md),
        border: selected
            ? Border(
                bottom: BorderSide(
                  color: c.lineBase,
                  width: PindoroElevation.e1,
                ),
              )
            : null,
      ),
      foregroundDecoration: selected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(PindoroRadius.md),
              border: Border.all(
                color: c.primaryBase,
                width: PindoroStroke.thick,
              ),
            )
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 2,
        children: [
          PindoroIcon(
            step.icon,
            size: large ? 32 : 22,
            color: ink,
            cut: selected ? c.surfaceRaised : c.surfaceSunken,
          ),
          Text(
            step.label,
            textAlign: TextAlign.center,
            style: PindoroType.labelLg.copyWith(
              color: ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
    final tapped = Tappable(
      label: semanticsLabel,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      onTap: onTap,
      child: disabled
          ? Tooltip(
              message: step.disabledReason,
              triggerMode: TooltipTriggerMode.longPress,
              child: face,
            )
          : face,
    );
    if (!suggested) return tapped;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        tapped,
        Positioned(
          top: -PindoroSpace.s4,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              // Grows with large text instead of clipping it.
              constraints: const BoxConstraints(minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: c.accentBase,
                borderRadius: BorderRadius.circular(PindoroRadius.full),
              ),
              alignment: Alignment.center,
              child: Text(
                suggestedLabel,
                maxLines: 1,
                style: PindoroType.labelSm.copyWith(
                  color: c.accentOn,
                  fontWeight: FontWeight.w800,
                  height: 18 / 11,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The line above the level picker (LevelSuggestion): "[lead] [level]" and
/// its [reason], with a pip per turn on the route, filled for the [yours]
/// ones; [pipsLabel] reads the pips as one image.
class LevelSuggestion extends StatelessWidget {
  const LevelSuggestion({
    super.key,
    required this.lead,
    required this.level,
    required this.reason,
    this.yours,
    this.pipsLabel,
  });

  final String lead;
  final String level;
  final String reason;
  final List<bool>? yours;
  final String? pipsLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final style = PindoroType.labelLg.copyWith(color: c.textPrimary);
    final large = isLargeText(context);
    final what = Text.rich(
      TextSpan(
        text: '$lead ',
        children: [
          TextSpan(
            text: level,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
      style: style,
    );
    final why = Text(reason, style: style.copyWith(color: c.textSecondary));
    final icon = PindoroIcon(
      PindoroGlyph.hint,
      size: large ? 32 : 22,
      color: c.primaryText,
      cut: c.surfaceBase,
    );
    final pips = yours;
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s2,
        children: [
          MergeSemantics(
            child: Row(
              crossAxisAlignment: large
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              spacing: PindoroSpace.s2,
              children: [
                icon,
                if (large)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [what, why],
                    ),
                  )
                else ...[
                  Expanded(child: what),
                  Flexible(child: why),
                ],
              ],
            ),
          ),
          if (pips != null && pips.isNotEmpty)
            Semantics(
              image: true,
              label: pipsLabel,
              child: ExcludeSemantics(
                child: Row(
                  spacing: 3,
                  children: [
                    for (final mine in pips)
                      Expanded(
                        child: Container(
                          height: large ? 20 : 14,
                          decoration: BoxDecoration(
                            color: mine ? c.primaryBase : null,
                            borderRadius: BorderRadius.circular(4),
                            border: mine
                                ? null
                                : Border.all(
                                    color: c.accentLip,
                                    width: PindoroStroke.thick,
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The level picker in a card over Guided's map (LevelPickerCard, opened by its level button):
/// [picker] under its [title] and the [reason] for the level suggested.
class LevelPickerCard extends StatelessWidget {
  const LevelPickerCard({
    super.key,
    required this.picker,
    this.title,
    this.reason,
  });

  final Widget picker;
  final String? title;
  final String? reason;

  @override
  Widget build(BuildContext context) => DriveCard(
    child: PickerPanel(title: title, reason: reason, picker: picker),
  );
}
