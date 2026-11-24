import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../generated/pindoro_tokens.dart';
import '../theme.dart';
import 'drive_glyph.dart';
import 'graphics.dart';
import 'pindoro_button.dart';
import 'surfaces.dart';
import 'text_scale.dart';
import 'whole_words.dart';

/// The parked parts of v3.2 · Navigate and learn (drive setup, the route
/// preview, the debrief, Past drives, Progress and Today). They use the
/// system tokens and the app theme, never `color.drive.*`.

/// [child] read as an image named [label], or left out when there is none.
Widget _image(String? label, Widget child) => label == null
    ? ExcludeSemantics(child: child)
    : Semantics(
        image: true,
        label: label,
        excludeSemantics: true,
        child: child,
      );

/// What happened at one turn of a drive (Review mark).
enum MarkKind { good, hard, again, helped, watched }

/// A turn's outcome (Review mark): Good filled aqua with a check, Hard an
/// aqua ring with a check, Again the Miss red with `reroute`, Helped sunken
/// with `sound-on`, Watched only an outline with `eye`. 32 dp in lists (48 at
/// 200 % text), 28 dp [onMap] with a lip and the float shadow.
class ReviewMark extends StatelessWidget {
  const ReviewMark(
    this.kind, {
    super.key,
    this.onMap = false,
    this.semanticsLabel,
  });

  final MarkKind kind;
  final bool onMap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    final (face, edge, edgeWidth, glyph, ink) = switch (kind) {
      MarkKind.good => (
        c.feedbackGreatFill,
        null,
        0.0,
        PindoroGlyph.check,
        c.feedbackGreatOn,
      ),
      MarkKind.hard => (
        c.feedbackGreatBg,
        c.feedbackGreatFill,
        PindoroStroke.thick,
        PindoroGlyph.check,
        c.feedbackGreatInk,
      ),
      MarkKind.again => (
        c.feedbackMissFill,
        null,
        0.0,
        PindoroGlyph.reroute,
        c.feedbackMissOn,
      ),
      MarkKind.helped => (
        c.surfaceSunken,
        c.lineStrong,
        PindoroStroke.base,
        PindoroGlyph.soundOn,
        c.textSecondary,
      ),
      MarkKind.watched => (
        onMap ? c.surfaceRaised : null,
        c.lineStrong,
        PindoroStroke.base,
        PindoroGlyph.eye,
        c.textSecondary,
      ),
    };
    final side = onMap
        ? 28.0
        : (32 + (textScaleOf(context) - 1) * 16).clamp(32.0, 48.0);
    final radius = BorderRadius.circular(PindoroRadius.md);
    final mark = Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: face,
        borderRadius: radius,
        border: edge == null ? null : Border.all(color: edge, width: edgeWidth),
      ),
      child: PindoroIcon(
        glyph,
        size: side * (onMap ? 18 / 28 : 20 / 32),
        color: ink,
        cut: face ?? c.surfaceRaised,
      ),
    );
    return _image(
      semanticsLabel,
      onMap
          ? Container(
              padding: const EdgeInsets.only(bottom: PindoroElevation.e1),
              decoration: BoxDecoration(
                color: c.lineStrong,
                borderRadius: radius,
                boxShadow: [theme.floatShadow],
              ),
              child: mark,
            )
          : mark,
    );
  }
}

/// A key turn's number (Turn number): white tabular figures on an ink disc
/// (`color.map.measure.label`), 32 dp in lists (52 at 200 % text), 26 dp
/// [onMap] with a land halo; the [current] turn grows to 32 dp with the float
/// shadow. Two digits widen it to a pill.
class TurnNumber extends StatelessWidget {
  const TurnNumber(
    this.n, {
    super.key,
    this.onMap = false,
    this.current = false,
    this.semanticsLabel,
  });

  final int n;
  final bool onMap;
  final bool current;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    final side = onMap
        ? (current ? 32.0 : 26.0)
        : (32 + (textScaleOf(context) - 1) * 20).clamp(32.0, 52.0);
    final figures = Text(
      '$n',
      // On the map the figures keep their size; the list carries the text.
      textScaler: onMap ? TextScaler.noScaling : null,
      style: PindoroType.labelMd.copyWith(
        fontSize: onMap && !current ? 13 : 15,
        height: 1,
        fontWeight: FontWeight.w900,
        color: c.mapMeasureLabelText,
      ),
    );
    return _image(
      semanticsLabel,
      AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : PindoroMotion.durationFast,
        curve: PindoroMotion.easeOvershoot,
        constraints: BoxConstraints(minWidth: side, minHeight: side),
        padding: EdgeInsets.symmetric(horizontal: onMap ? 5 : 7),
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: c.mapMeasureLabel,
          shadows: [
            if (onMap) BoxShadow(color: c.mapVectorLand, spreadRadius: 3),
            if (onMap && current) theme.floatShadow,
          ],
        ),
        // Centred in the disc without growing to the space it is given.
        child: Center(widthFactor: 1, heightFactor: 1, child: figures),
      ),
    );
  }
}

/// Where a route starts (Turn number): an 18 dp ink ring
/// (`color.map.measure.line`) around a raised centre; [onMap] with a land
/// halo.
class StartRing extends StatelessWidget {
  const StartRing({super.key, this.onMap = false, this.semanticsLabel});

  final bool onMap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return _image(
      semanticsLabel,
      Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.surfaceRaised,
          border: Border.all(color: c.mapMeasureLine, width: 4),
          boxShadow: onMap
              ? [BoxShadow(color: c.mapVectorLand, spreadRadius: 2)]
              : null,
        ),
      ),
    );
  }
}

/// Where a route ends (Turn number): the `flag` drive glyph in ink, 32 dp
/// [onMap] (with a land halo), 28 dp in lists. On the map, place it with
/// [foot] so the pole's foot sits on the point.
class DestinationFlag extends StatelessWidget {
  const DestinationFlag({super.key, this.onMap = false, this.semanticsLabel});

  final bool onMap;
  final String? semanticsLabel;

  /// Where the pole's foot is in the flag's box.
  static const Alignment foot = Alignment(-0.46, 0.84);

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final size = onMap ? 32.0 : 28.0;
    Widget flag(Color color) => DriveGlyph(
      DriveGlyphName.flag,
      size: size,
      color: color,
      cut: c.mapVectorLand,
    );
    const halo = 1.5;
    return _image(
      semanticsLabel,
      onMap
          ? Stack(
              children: [
                // ponytail: a halo from eight offset copies; a stroked path
                // if the flag ever needs a thicker one.
                for (final (dx, dy) in const [
                  (-halo, -halo),
                  (0.0, -halo),
                  (halo, -halo),
                  (-halo, 0.0),
                  (halo, 0.0),
                  (-halo, halo),
                  (0.0, halo),
                  (halo, halo),
                ])
                  Transform.translate(
                    offset: Offset(dx, dy),
                    child: flag(c.mapVectorLand),
                  ),
                flag(c.mapMeasureLabel),
              ],
            )
          : flag(c.mapMeasureLabel),
    );
  }
}

/// The progress of a short sequence (Step dots): one 8 dp segment per step
/// (12 dp from 160 % text), done yellow with its lip, now cobalt, to come
/// outlined, with an optional [line] above. [current] is zero-based; more
/// than 12 steps show the line only. Reads as one progress indicator,
/// [semanticsLabel] with [semanticsValue] ("2 of 5").
class StepDots extends StatelessWidget {
  const StepDots({
    super.key,
    required this.count,
    required this.current,
    required this.semanticsLabel,
    required this.semanticsValue,
    this.line,
  });

  final int count;
  final int current;
  final String semanticsLabel;
  final String semanticsValue;
  final String? line;

  /// More steps than this don't fit as segments a thumb can read.
  static const int maxSegments = 12;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final height = isLargeText(context) ? 12.0 : 8.0;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : PindoroMotion.durationFast;
    final radius = BorderRadius.circular(height / 2);
    // The done lip's share of the segment, from the bottom.
    final lip = 1 - PindoroStroke.base / height;
    BoxDecoration segment(int i) => i < current
        ? BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                c.progressDone,
                c.progressDone,
                c.progressDoneLip,
                c.progressDoneLip,
              ],
              stops: [0, lip, lip, 1],
            ),
          )
        : i == current
        ? BoxDecoration(color: c.progressCurrent, borderRadius: radius)
        : BoxDecoration(
            color: c.progressTodo,
            borderRadius: radius,
            border: Border.all(
              color: c.progressTodoBorder,
              width: PindoroStroke.base,
            ),
          );
    final line = this.line;
    return Semantics(
      label: semanticsLabel,
      value: semanticsValue,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s2,
        children: [
          if (line != null)
            Text(
              line,
              style: PindoroType.labelMd.copyWith(color: c.textSecondary),
            ),
          if (count <= maxSegments)
            Row(
              spacing: PindoroSpace.s1,
              children: [
                for (var i = 0; i < count; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: duration,
                      curve: PindoroMotion.easeStandard,
                      height: height,
                      decoration: segment(i),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A drive's tier at the end of a Past drives row (Tier chip): the tier's
/// background, a 2 dp edge in its fill and its word in its ink; a null
/// [tier] is No tier (Guided drives): an outline in secondary text.
class TierChip extends StatelessWidget {
  const TierChip({super.key, required this.tier, required this.label});

  final Tier? tier;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = PindoroTheme.of(context);
    final c = theme.colors;
    final style = switch (tier) {
      final t? => theme.tier(t),
      null => null,
    };
    return ConstrainedBox(
      // Narrow enough to leave a row's title its room: a long label wraps.
      constraints: const BoxConstraints(minHeight: 28, maxWidth: 96),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: style?.bg,
          shape: StadiumBorder(
            side: BorderSide(
              color: style?.fill ?? c.lineStrong,
              width: PindoroStroke.base,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: WholeWords(
              Text(
                label,
                textAlign: TextAlign.center,
                style: PindoroType.labelMd.copyWith(
                  color: style?.ink ?? c.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the week's drive goals (Goal line): a 12 dp dot per unit of the
/// goal (18 dp from 160 % text; none past five units), filled for each met,
/// then the [count] ("1 of 2") in bold and the rest of the goal in [text].
/// One text node; the dots are left out.
class GoalLine extends StatelessWidget {
  const GoalLine({
    super.key,
    required this.done,
    required this.goal,
    required this.count,
    required this.text,
    this.semanticsLabel,
  });

  final int done;
  final int goal;
  final String count;
  final String text;
  final String? semanticsLabel;

  /// Goals with more units show the count only.
  static const int maxDots = 5;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final style = PindoroType.labelMd;
    final dot = isLargeText(context) ? 18.0 : 12.0;
    // The dots centre on the first line when the text wraps.
    final line = MediaQuery.textScalerOf(
      context,
    ).scale(style.fontSize! * style.height!);
    return Semantics(
      label: semanticsLabel ?? '$count $text',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: PindoroSpace.s2,
        children: [
          if (goal <= maxDots)
            Padding(
              padding: EdgeInsets.only(top: ((line - dot) / 2).clamp(0, 99)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: PindoroSpace.s1,
                children: [
                  for (var i = 0; i < goal; i++)
                    Container(
                      width: dot,
                      height: dot,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < done ? c.streakDayDone : c.streakDayEmpty,
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: count,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(text: ' $text'),
                ],
              ),
              style: style.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of a [PlanChecklist]: the route and its level, and why it's
/// offered.
typedef PlanItem = ({String title, String subtitle});

/// A short list to pick [limit] of (Plan checklist): checkbox rows in one
/// list group. At the limit the rows still off look disabled and a tap on
/// one calls [onLimit] (the app says why).
class PlanChecklist extends StatelessWidget {
  const PlanChecklist({
    super.key,
    required this.items,
    required this.picked,
    required this.limit,
    required this.onChanged,
    this.onLimit,
  });

  final List<PlanItem> items;
  final Set<int> picked;
  final int limit;
  final ValueChanged<Set<int>> onChanged;
  final VoidCallback? onLimit;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final big = isLargeText(context);
    final full = picked.length >= limit;
    Widget row(int i, PlanItem item) {
      final on = picked.contains(i);
      final off = !on && full;
      final box = Container(
        width: big ? 44 : 28,
        height: big ? 44 : 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on
              ? c.primaryBase
              : off
              ? c.buttonDisabledBg
              : c.surfaceRaised,
          borderRadius: BorderRadius.circular(PindoroRadius.sm),
          border: Border.all(
            color: on
                ? c.primaryBase
                : off
                ? c.buttonDisabledBg
                : c.lineStrong,
            width: PindoroStroke.thick,
          ),
        ),
        child: on
            ? PindoroIcon(
                PindoroGlyph.check,
                size: big ? 30 : PindoroSize.iconSm,
                color: c.primaryOn,
                cut: c.primaryBase,
              )
            : null,
      );
      return MergeSemantics(
        child: Semantics(
          checked: on,
          enabled: !off,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () {
                if (off) {
                  onLimit?.call();
                  return;
                }
                unawaited(HapticFeedback.selectionClick());
                onChanged(on ? ({...picked}..remove(i)) : {...picked, i});
              },
              splashFactory: NoSplash.splashFactory,
              highlightColor: c.surfaceSunken,
              mouseCursor: SystemMouseCursors.click,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PindoroSpace.s4,
                    vertical: PindoroSpace.s2,
                  ),
                  child: Row(
                    crossAxisAlignment: big
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    spacing: PindoroSpace.s3,
                    children: [
                      box,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.title,
                              style: PindoroType.titleMd.copyWith(
                                fontSize: 17,
                                height: 22 / 17,
                                color: off ? c.textDisabled : c.textPrimary,
                              ),
                            ),
                            Text(
                              item.subtitle,
                              style: PindoroType.bodySm.copyWith(
                                color: off ? c.textDisabled : c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ListGroup(
      children: [for (final (i, item) in items.indexed) row(i, item)],
    );
  }
}

/// One month of a route's help (Route level stair): its short name and the
/// level most of its drives used, 0 Guided … 3 Off; null for no drive.
typedef MonthBar = ({String month, int? level});

/// How much help a route has needed, month by month (Route level stair): a
/// 48 dp cobalt bar per month, full for Guided down to a quarter for Off, an
/// empty track for a month with no drive, the month names under it (every
/// other one from 160 % text). The bars grow from the base on first show.
/// One image named [semanticsLabel] (the history in words).
class RouteLevelStair extends StatelessWidget {
  const RouteLevelStair({
    super.key,
    required this.months,
    required this.semanticsLabel,
  });

  final List<MonthBar> months;
  final String semanticsLabel;

  static const double _height = 48;
  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final sparse = isLargeText(context);
    const top = BorderRadius.vertical(top: Radius.circular(PindoroRadius.xs));
    Widget bars(double grown) => SizedBox(
      height: _height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: _gap,
        children: [
          for (final m in months)
            Expanded(
              child: switch (m.level) {
                null => DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.progressTrack,
                    borderRadius: top,
                  ),
                ),
                final level => Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: (1 - level.clamp(0, 3) * 0.25) * grown,
                    widthFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.primaryBase,
                        borderRadius: top,
                      ),
                    ),
                  ),
                ),
              },
            ),
        ],
      ),
    );
    return Semantics(
      image: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s1,
        children: [
          if (MediaQuery.disableAnimationsOf(context))
            bars(1)
          else
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: PindoroMotion.durationSlow,
              curve: PindoroMotion.easeStandard,
              builder: (_, t, _) => bars(t),
            ),
          Row(
            spacing: _gap,
            children: [
              for (final (i, m) in months.indexed)
                Expanded(
                  // A name may spill into its unnamed neighbours.
                  child: OverflowBox(
                    maxWidth: double.infinity,
                    fit: OverflowBoxFit.deferToChild,
                    child: Text(
                      sparse && i.isOdd ? '' : m.month,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: PindoroType.labelSm.copyWith(
                        height: 14 / 11,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One suggestion for the next drive (Suggestion card): the ready Today
/// card's cobalt ring and lip around an icon tile, the [title] and the
/// reason [line], with an optional full-width secondary [action]. The icon
/// goes above the text from 160 % text.
class SuggestionCard extends StatelessWidget {
  const SuggestionCard({
    super.key,
    required this.glyph,
    required this.title,
    required this.line,
    this.action,
    this.onAction,
  });

  final PindoroGlyph glyph;
  final String title;
  final String line;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final radius = BorderRadius.circular(PindoroRadius.xl);
    final text = MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: PindoroType.titleMd.copyWith(color: c.textPrimary),
          ),
          Text(
            line,
            style: PindoroType.bodySm.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
    final tile = RowTile(glyph);
    final head = isLargeText(context)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: PindoroSpace.s3,
            children: [tile, text],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: PindoroSpace.s3,
            children: [
              tile,
              Expanded(child: text),
            ],
          );
    final action = this.action;
    return Container(
      padding: const EdgeInsets.only(bottom: PindoroElevation.e2),
      decoration: BoxDecoration(color: c.primaryLip, borderRadius: radius),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          PindoroSpace.s4,
          PindoroSpace.s3,
          PindoroSpace.s4,
          PindoroSpace.s4,
        ),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: radius,
          border: Border.all(color: c.primaryBase, width: PindoroStroke.thick),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroSpace.s3,
          children: [
            head,
            if (action != null)
              PindoroButton(
                label: action,
                variant: PindoroButtonVariant.secondary,
                onPressed: onAction,
              ),
          ],
        ),
      ),
    );
  }
}
