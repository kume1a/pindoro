import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Route;
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/core/toast.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/map/ui/route_layers.dart';
import 'package:pindoro/features/map/ui/route_projection.dart';
import 'package:pindoro/features/map/ui/widgets/question_plate.dart';
import 'package:pindoro/features/map/ui/widgets/route_draw_layer.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// A checked road trip: its [score], the sheet's [chips] and [action]
/// label, and the celebration.
typedef RouteReveal = ({
  Object key,
  Score score,
  List<Widget> chips,
  String action,
  CelebrationSize? celebration,
});

/// The best-route replay (canvas R4-32): the car drives it in this long.
const Duration _replayLength = Duration(milliseconds: 1200);

/// The first-trip ghost covers about this much of the best route, and its
/// finger dot loops twice.
const double _ghostM = 300;
const Duration _ghostLoop = Duration(milliseconds: 1600);
const int _ghostLoops = 2;

/// A toast follows this long off the road.
const Duration _offRoadToast = Duration(seconds: 1);

/// One road trip, shared by lessons and the Final drive (canvas R4-30 to
/// R4-34): the [topBar], the plate asking for the shortest drive to the
/// trip's destination, A and B on the map, drawing by drag (a list of turns
/// with a screen reader on), Undo, Show the route, Check route; once checked
/// ([reveal]) the car replays the best route and the tier sheet rises.
class RouteView extends ConsumerStatefulWidget {
  const RouteView({
    super.key,
    required this.area,
    required this.questionKey,
    required this.ask,
    required this.trip,
    required this.draft,
    required this.reveal,
    required this.topBar,
    required this.showBody,
    required this.onDraft,
    required this.onCheck,
    required this.onShow,
    required this.onNext,
    this.ghost = false,
  });

  final AreaShape area;

  /// Changes per trip, so the plate rises in anew.
  final Object questionKey;

  /// "Road trip: draw the shortest drive to".
  final String ask;
  final Trip trip;
  final RouteDraft draft;
  final RouteReveal? reveal;
  final Widget topBar;

  /// The Show the route dialog's body.
  final String showBody;
  final ValueChanged<RouteDraft> onDraft;
  final VoidCallback onCheck;
  final VoidCallback onShow;
  final Future<void> Function() onNext;

  /// The first road trip ever: the ghost route and the coach bubble.
  final bool ghost;

  @override
  ConsumerState<RouteView> createState() => _RouteViewState();
}

class _RouteViewState extends ConsumerState<RouteView>
    with TickerProviderStateMixin {
  MapProjection? _projection;
  bool _touched = false;
  Timer? _offRoad;

  late final AnimationController _replay = AnimationController(
    vsync: this,
    duration: _replayLength,
  )..addListener(() => setState(() {}));

  late final AnimationController _ghostDot = AnimationController(
    vsync: this,
    duration: _ghostLoop,
  )..addListener(() => setState(() {}));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.reveal != null) _startReplay();
      if (widget.ghost && !MediaQuery.disableAnimationsOf(context)) {
        unawaited(_ghostDot.repeat(count: _ghostLoops));
      }
    });
  }

  @override
  void didUpdateWidget(RouteView old) {
    super.didUpdateWidget(old);
    if (widget.reveal?.key != old.reveal?.key) {
      if (widget.reveal == null) {
        _replay.value = 0;
      } else {
        _startReplay();
      }
    }
  }

  @override
  void dispose() {
    _offRoad?.cancel();
    _replay.dispose();
    _ghostDot.dispose();
    super.dispose();
  }

  void _startReplay() {
    _offRoad?.cancel();
    if (MediaQuery.disableAnimationsOf(context)) {
      _replay.value = 1;
    } else {
      unawaited(_replay.forward(from: 0));
    }
  }

  void _skip() => _replay.value = 1;

  bool get _replaying => widget.reveal != null && _replay.value < 1;

  /// Haptics and, for screen readers, an announcement per junction and at B.
  void _draft(RouteDraft next, {String? turn}) {
    final feedback = ref.read(feedbackProvider);
    if (next.edges.length > widget.draft.edges.length) feedback.junction();
    if (next.reached && !widget.draft.reached) feedback.reached();
    if (turn != null) {
      final l10n = context.l10n;
      _announce(
        next.reached
            ? l10n.a11yRouteReachedB
            : l10n.a11yRouteTurned(turn, formatDistance(next.lengthM, l10n)),
      );
    }
    widget.onDraft(next);
  }

  void _announce(String message) => unawaited(
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    ),
  );

  void _onOffRoad(bool off) {
    _offRoad?.cancel();
    if (!off) return;
    _offRoad = Timer(_offRoadToast, () {
      if (mounted) {
        showToast(
          context,
          context.l10n.routeOffRoad,
          above: _controlsInset(context),
        );
      }
    });
  }

  Future<void> _show() async {
    final l10n = context.l10n;
    final show = await showDialog<bool>(
      context: context,
      builder: (context) => PindoroDialog(
        title: l10n.routeShowTitle,
        body: widget.showBody,
        primary: l10n.routeKeepDriving,
        secondary: l10n.routeShowConfirm,
      ),
    );
    if ((show ?? false) && mounted) widget.onShow();
  }

  /// Undo, Show the route and Check route at the bottom of the map.
  static double _controlsInset(BuildContext context) =>
      2 * PindoroSize.buttonLg +
      PindoroSpace.s2 +
      PindoroElevation.e2 +
      bottomActionGap(context);

  /// The tier sheet's rough height (it keeps both routes visible).
  static double _sheetInset(BuildContext context) =>
      260 + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final streets = ref.watch(cityStreetsProvider).value ?? const {};
    final reveal = widget.reveal;
    final trip = widget.trip;
    final draft = widget.draft;
    final graph = draft.graph;
    final a = graph.at(trip.from), b = graph.at(trip.to);
    final listMode =
        MediaQuery.accessibleNavigationOf(context) ||
        (settings?.turnList ?? false);
    final ghost = widget.ghost && !_touched && reveal == null && !listMode;
    final drawn = draft.lines;
    final best = reveal == null ? null : _along(trip.best.lines, _replay.value);
    // The full plate is taller than a pin drop's (the ask, two name lines,
    // the sub-line); A and B must clear it.
    final topInset =
        MediaQuery.paddingOf(context).top + (reveal == null ? 260 : 180);
    final bottomInset = reveal != null
        ? _sheetInset(context)
        : listMode
        ? MediaQuery.sizeOf(context).height * 0.45
        : _controlsInset(context);
    final ghostLines = ghost ? _ghostLines(trip.best) : const <Polyline>[];
    return Scaffold(
      body: Stack(
        children: [
          Semantics(
            label: l10n.a11yRouteMap,
            child: ref.watch(pindoroMapBuilderProvider)(
              PindoroMap(
                area: widget.area,
                route: (
                  a: a,
                  b: b,
                  drawn: drawn,
                  best: best?.lines ?? const [],
                  ghost: ghostLines,
                  car: _replaying ? best?.tip : null,
                  chip: reveal != null || drawn.isEmpty || draft.reached
                      ? null
                      : (
                          at: graph.at(draft.end),
                          label: l10n.routeSoFar(
                            formatDistance(draft.lengthM, l10n),
                          ),
                          anchor: chipAnchor(
                            _projection?.toScreen(graph.at(draft.end)).dx ?? 0,
                            MediaQuery.sizeOf(context).width,
                          ),
                        ),
                  reached: draft.reached,
                ),
                frame: reveal == null
                    ? [a, b]
                    : [
                        a,
                        b,
                        for (final l in trip.best.lines) ...l,
                        for (final l in drawn) ...l,
                      ],
                onCamera: (p) => setState(() => _projection = p),
                topInset: topInset,
                bottomInset: bottomInset,
                showControls: reveal == null,
              ),
            ),
          ),
          if (reveal == null && !listMode)
            Positioned.fill(
              child: RouteDrawLayer(
                projection: _projection,
                draft: draft,
                onDraft: _draft,
                onTouch: () {
                  if (!_touched) setState(() => _touched = true);
                },
                onOffRoad: _onOffRoad,
              ),
            ),
          if (ghost && _projection != null && _ghostDot.isAnimating)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _GhostFingerPainter(
                    colors: PindoroTheme.of(context).colors,
                    at: _projection!.toScreen(
                      _along(ghostLines, _ghostDot.value).tip,
                    ),
                  ),
                ),
              ),
            ),
          if (ghost)
            Align(
              alignment: const Alignment(0, 0.1),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PindoroSpace.s4,
                ),
                child: IgnorePointer(
                  child: CoachBubble(
                    title: l10n.routeCoachTitle,
                    body: l10n.routeCoachBody,
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(PindoroSpace.s4),
              child: Column(
                spacing: PindoroSpace.s4,
                children: [
                  widget.topBar,
                  RiseSwitcher(
                    child: _Plate(
                      key: ValueKey(widget.questionKey),
                      ask: widget.ask,
                      street: trip.destination,
                      settings: settings,
                      compact: reveal != null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (reveal == null && listMode)
            Align(
              alignment: Alignment.bottomCenter,
              child: _TurnList(
                draft: draft,
                streets: streets,
                settings: settings,
                onTurn: (edge, label) => _draft(draft.take(edge), turn: label),
                onUndo: () => widget.onDraft(draft.undo()),
                onCheck: widget.onCheck,
                onShow: _show,
              ),
            )
          else if (reveal == null)
            _Controls(
              draft: draft,
              onUndo: () => widget.onDraft(draft.undo()),
              onStartOver: () => widget.onDraft(draft.startOver()),
              onCheck: widget.onCheck,
              onShow: _show,
            )
          else if (_replaying)
            _ReplayBanner(onSkip: _skip)
          else ...[
            Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: RiseIn(
                  key: ValueKey(reveal.key),
                  child: _TierSheet(
                    reveal: reveal,
                    drawnM: draft.lengthM,
                    best: trip.best,
                    streets: streets,
                    settings: settings,
                    onNext: widget.onNext,
                  ),
                ),
              ),
            ),
            if (reveal.celebration != null)
              Positioned.fill(
                child: Celebration(
                  key: ValueKey(reveal.key),
                  size: reveal.celebration!,
                  burstCenter: const Alignment(-0.78, 0.5),
                ),
              ),
          ],
          // A tap anywhere skips the replay.
          if (_replaying)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _skip,
              ),
            ),
        ],
      ),
    );
  }
}

/// [lines] up to [fraction] of their length, and the point reached.
({MultiPolyline lines, LatLng tip}) _along(
  MultiPolyline lines,
  double fraction,
) {
  final total = lines.fold(0.0, (sum, l) => sum + _length(l));
  var left = total * fraction.clamp(0, 1);
  final out = <Polyline>[];
  for (final line in lines) {
    final part = <LatLng>[line.first];
    for (var i = 1; i < line.length; i++) {
      final step = distanceBetween(line[i - 1], line[i]);
      if (step >= left) {
        final t = step == 0 ? 0.0 : left / step;
        final tip = LatLng(
          line[i - 1].lat + (line[i].lat - line[i - 1].lat) * t,
          line[i - 1].lon + (line[i].lon - line[i - 1].lon) * t,
        );
        return (
          lines: [
            ...out,
            [...part, tip],
          ],
          tip: tip,
        );
      }
      left -= step;
      part.add(line[i]);
    }
    out.add(part);
  }
  return (lines: out, tip: out.lastOrNull?.lastOrNull ?? const LatLng(0, 0));
}

double _length(Polyline line) {
  var m = 0.0;
  for (var i = 1; i < line.length; i++) {
    m += distanceBetween(line[i - 1], line[i]);
  }
  return m;
}

/// The first streets of the best route, about [_ghostM] long.
MultiPolyline _ghostLines(Route best) {
  final lines = best.lines;
  final out = <Polyline>[];
  var m = 0.0;
  for (final (i, e) in best.edges.indexed) {
    out.add(lines[i]);
    m += e.lengthM;
    if (m >= _ghostM) break;
  }
  return out;
}

class _Plate extends StatelessWidget {
  const _Plate({
    super.key,
    required this.ask,
    required this.street,
    required this.settings,
    required this.compact,
  });

  final String ask;
  final NamedStreet street;
  final Settings? settings;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = streetName(street, settings);
    final other = otherScript(street, settings);
    return StreetPlate(
      name,
      compact: compact,
      prompt: ask,
      promptGlyph: PindoroGlyph.car,
      subline: [?other, l10n.routeStartAtA].join(' · '),
      semanticLabel: '$ask $name. ${l10n.routeStartAtA}.',
    );
  }
}

/// Undo (hold: start over) and Show the route above Check route.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.draft,
    required this.onUndo,
    required this.onStartOver,
    required this.onCheck,
    required this.onShow,
  });

  final RouteDraft draft;
  final VoidCallback onUndo;
  final VoidCallback onStartOver;
  final VoidCallback onCheck;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Positioned(
      left: PindoroSpace.s4,
      right: PindoroSpace.s4,
      bottom: bottomActionGap(context),
      child: Column(
        spacing: PindoroSpace.s2,
        children: [
          Row(
            spacing: PindoroSpace.s3,
            children: [
              GestureDetector(
                onLongPress: onStartOver,
                child: MapControl(
                  glyph: PindoroGlyph.back,
                  semanticLabel: l10n.a11yRouteUndo,
                  onPressed: onUndo,
                ),
              ),
              Expanded(
                child: Semantics(
                  label: draft.reached ? null : l10n.a11yRouteCheckDisabled,
                  child: PindoroButton(
                    label: l10n.routeCheck,
                    onPressed: draft.reached ? onCheck : null,
                  ),
                ),
              ),
            ],
          ),
          PindoroButton(
            label: l10n.routeShow,
            icon: PindoroGlyph.route,
            variant: PindoroButtonVariant.tertiary,
            onPressed: onShow,
          ),
        ],
      ),
    );
  }
}

/// Turn by turn (canvas R4-34): the streets at the route's end as turns.
class _TurnList extends StatelessWidget {
  const _TurnList({
    required this.draft,
    required this.streets,
    required this.settings,
    required this.onTurn,
    required this.onUndo,
    required this.onCheck,
    required this.onShow,
  });

  final RouteDraft draft;
  final Map<String, NamedStreet> streets;
  final Settings? settings;
  final void Function(RoadEdge edge, String label) onTurn;
  final VoidCallback onUndo;
  final VoidCallback onCheck;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    String name(String partId) =>
        streets[partId] == null ? '' : streetName(streets[partId]!, settings);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.45,
      ),
      child: Material(
        color: c.surfaceRaised,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(PindoroRadius.xl),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(PindoroSpace.s4),
            children: [
              Text(
                l10n.routeTurnList(formatDistance(draft.lengthM, l10n)),
                style: PindoroType.labelMd.copyWith(color: c.textSecondary),
              ),
              if (!draft.reached) ...[
                Semantics(
                  header: true,
                  child: Text(
                    l10n.routeTurnAsk,
                    style: PindoroType.titleMd.copyWith(color: c.textPrimary),
                  ),
                ),
                const SizedBox(height: PindoroSpace.s2),
                ListGroup(
                  children: [
                    for (final t in turnsAt(draft))
                      () {
                        final label = l10n.routeTurn(
                          t.turn.name,
                          name(t.edge.streetId),
                        );
                        return ListRow(
                          title: label,
                          subtitle: l10n.routeTurnHeading(
                            t.heading.name,
                            t.towardGoal ? 'yes' : 'no',
                          ),
                          onTap: () => onTurn(t.edge, label),
                        );
                      }(),
                  ],
                ),
              ],
              const SizedBox(height: PindoroSpace.s3),
              Row(
                spacing: PindoroSpace.s2,
                children: [
                  Expanded(
                    child: PindoroButton(
                      label: l10n.routeUndoTurn,
                      variant: PindoroButtonVariant.secondary,
                      onPressed: draft.edges.isEmpty ? null : onUndo,
                    ),
                  ),
                  Expanded(
                    child: PindoroButton(
                      label: l10n.routeCheck,
                      onPressed: draft.reached ? onCheck : null,
                    ),
                  ),
                ],
              ),
              PindoroButton(
                label: l10n.routeShow,
                variant: PindoroButtonVariant.tertiary,
                onPressed: onShow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Driving the best route…" with Skip, while the car drives.
class _ReplayBanner extends StatelessWidget {
  const _ReplayBanner({required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Positioned(
      left: PindoroSpace.s4,
      right: PindoroSpace.s4,
      bottom: bottomActionGap(context),
      child: Row(
        children: [
          Expanded(
            child: Pill(
              label: l10n.routeReplay,
              icon: PindoroGlyph.car,
              floating: true,
            ),
          ),
          PindoroButton(
            label: l10n.routeSkip,
            variant: PindoroButtonVariant.secondary,
            onPressed: onSkip,
          ),
        ],
      ),
    );
  }
}

/// The road trip's tier sheet (canvas R4-33).
class _TierSheet extends StatelessWidget {
  const _TierSheet({
    required this.reveal,
    required this.drawnM,
    required this.best,
    required this.streets,
    required this.settings,
    required this.onNext,
  });

  final RouteReveal reveal;
  final double drawnM;
  final Route best;
  final Map<String, NamedStreet> streets;
  final Settings? settings;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tier = reveal.score.tier;
    final bestM = formatDistance(best.lengthM, l10n);
    final percent = formatNumber(
      math.max(0, ((drawnM / best.lengthM - 1) * 100).round()),
    );
    final sentence = switch (tier) {
      Tier.perfect => l10n.routePerfectSentence(bestM),
      Tier.great || Tier.close => l10n.routeLongerSentence(percent),
      Tier.miss => l10n.routeLegsSentence(_legs(l10n), bestM),
    };
    return CountUp(
      value: reveal.score.xp,
      builder: (context, xp) => RevealSheet(
        tier: tier,
        label: switch (tier) {
          Tier.perfect => l10n.routeTierPerfect,
          Tier.great => l10n.routeTierGreat,
          Tier.close => l10n.routeTierClose,
          Tier.miss => l10n.routeTierMiss,
        },
        sentence: sentence,
        xpLabel: tier == Tier.miss ? null : l10n.commonXp(formatNumber(xp)),
        chips: [
          if (tier == Tier.great || tier == Tier.close)
            Pill(
              label: l10n.routeLengths(formatDistance(drawnM, l10n), bestM),
              icon: PindoroGlyph.route,
            ),
          ...reveal.chips,
        ],
        mascot: Pindo(switch (tier) {
          Tier.perfect || Tier.great => PindoExpression.cheering,
          Tier.close => PindoExpression.happy,
          Tier.miss => PindoExpression.encouraging,
        }, height: 80),
        action: PindoroButton(
          tier: tier,
          label: reveal.action,
          onPressed: () => unawaited(onNext()),
        ),
      ),
    );
  }

  /// "East on Chavchavadze Avenue, then south on Paliashvili Street".
  String _legs(AppLocalizations l10n) {
    final legs = routeLegs(best, streetOf: (part) => streets[part]?.id ?? part);
    String name(String id) =>
        streets[id] == null ? '' : streetName(streets[id]!, settings);
    const shown = 3;
    return [
      for (final (i, leg) in legs.take(shown).indexed)
        i == 0
            ? l10n.routeLegFirst(leg.heading.name, name(leg.streetId))
            : l10n.routeLegNext(leg.heading.name, name(leg.streetId)),
      if (legs.length > shown) l10n.routeLegsMore(legs.length - shown),
    ].join(', ');
  }
}

/// The first-trip ghost's finger dot, looping along the ghost route.
class _GhostFingerPainter extends CustomPainter {
  _GhostFingerPainter({required this.colors, required this.at});

  final PindoroColors colors;
  final Offset at;

  static const double _radius = 10;

  @override
  void paint(Canvas canvas, Size size) => canvas
    ..drawCircle(
      at,
      _radius + PindoroStroke.base,
      Paint()..color = colors.mapPlayerHalo,
    )
    ..drawCircle(at, _radius, Paint()..color = colors.coachBg);

  @override
  bool shouldRepaint(_GhostFingerPainter old) => old.at != at;
}
