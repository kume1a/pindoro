import 'package:flutter/material.dart';

import '../../generated/pindoro_tokens.dart';
import '../../theme.dart';
import '../graphics.dart';
import '../painters.dart';
import '../pindoro_button.dart';
import '../surfaces.dart';
import '../tappable.dart';
import 'drive_parts.dart';

/// One route in [RouteCards]: its [tag] ("Fastest", "Now", "+3 min"), [time] ("16 min") and
/// [length] ("15.8 km"), and a [note] under them ("On your left").
typedef RouteCard = ({String tag, String time, String length, String? note});

/// The routes side by side (RouteCards, SPEC §16.23 item 134): a card each, the [selected] one
/// on `color.primary.base`, the rest raised; a tap picks one ([onPick], by index). It scrolls
/// sideways when they don't fit.
class RouteCards extends StatelessWidget {
  const RouteCards({
    super.key,
    required this.cards,
    required this.selected,
    required this.onPick,
  });

  final List<RouteCard> cards;
  final int selected;
  final void Function(int index) onPick;

  static const double _minWidth = 104;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    Widget card(int i, RouteCard r) {
      final lit = i == selected;
      final ink = lit ? c.primaryOn : c.textPrimary;
      final soft = lit ? c.primaryOn : c.textSecondary;
      return Tappable(
        label: [r.tag, r.time, r.length, ?r.note].join(', '),
        selected: lit,
        onTap: () => onPick(i),
        child: LipBox(
          face: lit ? c.primaryBase : null,
          lip: lit ? c.primaryLip : null,
          radius: PindoroRadius.lg,
          padding: const EdgeInsets.symmetric(
            horizontal: PindoroSpace.s3,
            vertical: PindoroSpace.s2,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: _minWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.tag, style: PindoroType.labelMd.copyWith(color: soft)),
                Text(
                  r.time,
                  style: PindoroType.headlineSm.copyWith(color: ink),
                ),
                Text(
                  r.length,
                  style: PindoroType.labelLg.copyWith(color: soft),
                ),
                if (r.note case final note?)
                  Text(note, style: PindoroType.labelSm.copyWith(color: soft)),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: PindoroSpace.s2,
        children: [for (final (i, r) in cards.indexed) card(i, r)],
      ),
    );
  }
}

/// A route's bubble on the map (RouteCallout, item 134): its [lines] ("16 min", "15.8 km") on
/// `color.primary.base` for the route picked ([picked]), another's difference ("+3 min") on
/// `color.drive.surface`; the tail at its bottom centre points at the route. Decorative: the
/// cards carry the words.
class RouteCallout extends StatelessWidget {
  const RouteCallout(this.lines, {super.key, this.picked = false});

  final List<String> lines;
  final bool picked;

  static const Size _tail = Size(14, 8);

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    final face = picked ? c.primaryBase : c.driveSurface;
    final ink = picked ? c.primaryOn : c.driveText;
    return ExcludeSemantics(
      child: unscaled(
        context,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: PindoroSpace.s3,
                vertical: PindoroSpace.s1,
              ),
              decoration: BoxDecoration(
                color: face,
                borderRadius: BorderRadius.circular(PindoroRadius.md),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, l) in lines.indexed)
                    Text(
                      l,
                      style:
                          (i == 0 ? PindoroType.titleSm : PindoroType.labelMd)
                              .copyWith(color: ink),
                    ),
                ],
              ),
            ),
            CustomPaint(size: _tail, painter: TailPainter(face, down: true)),
          ],
        ),
      ),
    );
  }
}

/// A stop on the way in [RouteEnds]: its [label] ("Stop 1"), [name] and [removeLabel]
/// ("Remove Nikora").
typedef RouteStop = ({String label, String name, String removeLabel});

/// Where a route runs (RouteEnds, item 134): [fromLabel] and [from] (where the car is), the
/// [stops] on the way each with a remove button ([onRemove], by index), [toLabel] and [to] (a
/// tap, [onTo], changes it), then [addLabel] (Add stop, [onAdd]; none at the most stops).
class RouteEnds extends StatelessWidget {
  const RouteEnds({
    super.key,
    required this.fromLabel,
    required this.from,
    required this.toLabel,
    required this.to,
    this.stops = const [],
    this.onRemove,
    this.onTo,
    this.addLabel,
    this.onAdd,
  });

  final String fromLabel;
  final String from;
  final String toLabel;
  final String to;
  final List<RouteStop> stops;
  final void Function(int index)? onRemove;
  final VoidCallback? onTo;
  final String? addLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    Widget line({
      required Widget mark,
      required String text,
      String? label,
      Widget? trailing,
      VoidCallback? onTap,
      Color? ink,
    }) {
      final content = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: PindoroSize.buttonMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: PindoroSpace.s3),
          child: Row(
            spacing: PindoroSpace.s3,
            children: [
              SizedBox.square(
                dimension: PindoroSize.iconMd,
                child: Center(child: mark),
              ),
              Expanded(
                child: Text.rich(
                  semanticsLabel: [?label, text].join(' '),
                  TextSpan(
                    children: [
                      if (label != null)
                        TextSpan(
                          text: '$label  ',
                          style: PindoroType.labelMd.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      TextSpan(text: text),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PindoroType.titleSm.copyWith(
                    color: ink ?? c.textPrimary,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      );
      return onTap == null
          ? content
          : Tappable(
              label: [?label, text].join(' '),
              onTap: onTap,
              child: content,
            );
    }

    Widget glyph(PindoroGlyph g, {Color? color}) => PindoroIcon(
      g,
      size: PindoroSize.iconSm,
      color: color ?? c.textSecondary,
    );
    final remove = onRemove;
    final lines = [
      line(mark: glyph(PindoroGlyph.locate), label: fromLabel, text: from),
      for (final (i, s) in stops.indexed)
        line(
          mark: _StopDot(i + 1),
          label: s.label,
          text: s.name,
          trailing: remove == null
              ? null
              : Tappable(
                  label: s.removeLabel,
                  onTap: () => remove(i),
                  child: SizedBox.square(
                    dimension: PindoroSize.buttonMd,
                    child: Center(child: glyph(PindoroGlyph.close)),
                  ),
                ),
        ),
      line(
        mark: glyph(PindoroGlyph.flag, color: c.textPrimary),
        label: toLabel,
        text: to,
        onTap: onTo,
        trailing: onTo == null ? null : glyph(PindoroGlyph.chevronDown),
      ),
      if ((addLabel, onAdd) case (final label?, final add?))
        line(
          mark: glyph(PindoroGlyph.plus, color: c.primaryText),
          text: label,
          ink: c.primaryText,
          onTap: add,
        ),
    ];
    return LipBox(
      radius: PindoroRadius.lg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, l) in lines.indexed) ...[
            if (i > 0)
              Divider(
                height: PindoroStroke.hairline,
                thickness: PindoroStroke.hairline,
                indent: PindoroSpace.s3 * 2 + PindoroSize.iconMd,
                color: c.lineBase,
              ),
            l,
          ],
        ],
      ),
    );
  }
}

/// A stop's number in a small cobalt disc, as on its map pin.
class _StopDot extends StatelessWidget {
  const _StopDot(this.n);

  final int n;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return Container(
      width: PindoroSize.iconSm,
      height: PindoroSize.iconSm,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.mapRouteLine),
      child: Text(
        '$n',
        style: PindoroType.labelSm.copyWith(color: c.mapRouteArrow, height: 1),
      ),
    );
  }
}

/// Guided's routes (RouteOptions, SPEC §16.23 items 130, 133 and 134): [ends] on top (the stops
/// and the destination, RouteEnds), then the route driven now and the other ways on as
/// [RouteCards], the [selected] one lit, as on the map; [takeLabel] (Take this route) takes it.
class RouteOptions extends StatelessWidget {
  const RouteOptions({
    super.key,
    required this.semanticsLabel,
    required this.cards,
    required this.onPick,
    this.ends,
    this.selected = 0,
    this.takeLabel,
    this.onTake,
  });

  final String semanticsLabel;
  final List<RouteCard> cards;
  final void Function(int index) onPick;
  final Widget? ends;
  final int selected;
  final String? takeLabel;
  final VoidCallback? onTake;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: semanticsLabel,
    child: DriveCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s2,
        children: [
          ?ends,
          RouteCards(cards: cards, selected: selected, onPick: onPick),
          if ((takeLabel, onTake) case (final label?, final tap?))
            PindoroButton(label: label, onPressed: tap),
        ],
      ),
    ),
  );
}
