import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart' show DriveMarker, Settings;
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/navigation.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_dial_view.dart';
import 'package:pindoro/features/drive/ui/drive_levels.dart';
import 'package:pindoro/features/drive/ui/drive_route_screen.dart';
import 'package:pindoro/features/drive/ui/drive_view_parts.dart';
import 'package:pindoro/features/drive/ui/route_ends.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro/features/map/data/route_places.dart';
import 'package:pindoro/features/map/ui/drive_map.dart';
import 'package:pindoro/features/map/ui/widgets/map_attribution.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart' hide Navigator;

/// Guided's buttons go and its map goes back to the car this long after the last touch
/// (items 116, 130).
const Duration _recentreAfter = Duration(seconds: 10);

/// A drive in progress at its level (boards V32-20 to V32-41, SPEC §16.23 items 115–118, 127,
/// 130): Guided's map under the turn card, the speeds, the street and the floating bar, its
/// buttons popping in at a touch; Coached and Quiet's dial (Recovery over it after a wrong
/// turn), Off's black screen, their stopped-controls bar rising when stopped. Day or night by
/// sun time at the car. Back does nothing: End drive ends it.
class DriveRecordingView extends ConsumerStatefulWidget {
  const DriveRecordingView({super.key, required this.recording});

  final DriveRecording recording;

  @override
  ConsumerState<DriveRecordingView> createState() => _DriveRecordingViewState();
}

class _DriveRecordingViewState extends ConsumerState<DriveRecordingView> {
  late final Timer _tick;
  bool _levelOpen = false;

  /// The route drawn, ahead of the car only: from it to the plan while short of it, then the
  /// plan's metres left; made again only when the plan, the car or the metre changes.
  (NavPlan?, LatLng?, int?) _routeFor = (null, null, null);
  MultiPolyline _route = const [];

  /// The next decision's arrow on the map, made once per decision.
  (NavPlan?, int?) _turnFor = (null, null);
  Polyline _turn = const [];

  /// Guided's map follows the car until the player moves it ([_following]); a touch shows its
  /// buttons ([_revealed]); both go back [_recentreAfter] after the last touch.
  bool _following = true;
  bool _revealed = false;
  Timer? _idle;

  /// The compass's choice: north up instead of the road ahead.
  bool _northUp = false;

  /// The routes overview's other ways on while it is open, the way picked in it (0 the route
  /// driven now) and their lines on the map: the picked one's yellow, the rest grey.
  List<NavPlan>? _options;
  int _picked = 0;
  MultiPolyline _pickedLines = const [];
  MultiPolyline _optionLines = const [];

  @override
  void initState() {
    super.initState();
    // The clock's lines (arrival, "GPS lost 1:02", "Now Coached") move without a fix.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    _idle?.cancel();
    super.dispose();
  }

  /// A touch anywhere on Guided: its buttons show, until [_recentreAfter] after the last one.
  void _touched() {
    _idle?.cancel();
    _idle = Timer(_recentreAfter, _settle);
    if (!_revealed) setState(() => _revealed = true);
  }

  /// The map dragged or pinched: it stays where the player put it.
  void _moved() {
    _touched();
    if (_following) setState(() => _following = false);
  }

  /// Back to driving: the buttons, the picker and the routes go, the map follows the car.
  void _settle() {
    _idle?.cancel();
    if (!mounted) return;
    setState(() {
      _revealed = false;
      _following = true;
      _levelOpen = false;
      _closeRoutes();
    });
  }

  /// The routes overview shut, the map back on the car.
  void _closeRoutes() {
    if (_options == null) return;
    _options = null;
    _pickRoute(0);
    _following = true;
  }

  void _toggleRoutes() => setState(() {
    if (_options != null) return _closeRoutes();
    _options = _controller.routeOptions();
    _pickRoute(0);
    _levelOpen = false;
  });

  /// The [i]th of the routes (0 is the route driven now) picked: lit on the map, not driven
  /// until Take this route.
  void _pickRoute(int i) {
    final options = _options ?? const [];
    _picked = i;
    _pickedLines = i == 0 ? const [] : options[i - 1].lines;
    _optionLines = [
      if (i > 0) ..._route,
      for (final (j, o) in options.indexed)
        if (j != i - 1) ...o.lines,
    ];
  }

  /// The picked way, driven from here.
  void _takeRoute() {
    final options = _options;
    if (options != null && _picked > 0) {
      _controller.takeRoute(options[_picked - 1]);
    }
    _settle();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recording;
    final view = r.view;
    final now = ref.read(clockProvider)();
    // The stopped bar's picker closes unchanged the moment the car moves (item 116); Guided's
    // goes with its buttons.
    if (!r.stopped && r.level != DriveLevel.guided) _levelOpen = false;
    // Until the car is on a road the navigator has no plan: the route picked at setup shows.
    final plan = view?.plan ?? r.suggestion?.plan;
    final toPlan = view?.toPlan ?? const <LatLng>[];
    final leftM = view?.leftM;
    // How far along the navigator's plan the car is; null while short of it or before it.
    final doneM = view?.plan != null && leftM != null && toPlan.length < 2
        ? plan!.endM - leftM
        : null;
    final routeFor = (
      plan,
      toPlan.length > 1 ? toPlan.first : null,
      doneM?.round(),
    );
    if (routeFor != _routeFor) {
      _routeFor = routeFor;
      final ahead = doneM == null
          ? const <LatLng>[]
          : plan!.slice(doneM, plan.endM);
      _route = doneM != null
          ? [if (ahead.length > 1) ahead]
          : [if (toPlan.length > 1) toPlan, ...?plan?.lines];
    }
    final next = view?.next;
    final turnFor = (view?.plan, next?.index);
    if (turnFor != _turnFor) {
      _turnFor = turnFor;
      final p = view?.plan;
      _turn = p == null || next == null ? const [] : turnArrow(p, next);
    }
    final night = isNight(view?.at ?? r.destination, now);
    return PopScope(
      canPop: false,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _controller.noteTouch(),
        child: Theme(
          data: buildPindoroTheme(night ? Brightness.dark : Brightness.light),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            // Dark icons only over Guided's day map; the other screens are dark.
            value: r.level == DriveLevel.guided && !night
                ? SystemUiOverlayStyle.dark
                : SystemUiOverlayStyle.light,
            child: Builder(
              builder: (context) {
                final c = PindoroTheme.of(context).colors;
                final settings = ref.watch(settingsProvider).value;
                return Scaffold(
                  backgroundColor: switch (r.level) {
                    DriveLevel.off => c.driveOffBg,
                    DriveLevel.guided => c.surfaceBase,
                    _ => c.driveQuietBg,
                  },
                  body: switch (r.level) {
                    DriveLevel.guided => _guided(context, r, now, settings),
                    DriveLevel.off => OffDrive(
                      stoppedBar: r.stopped
                          ? _stoppedBar(context, r, now)
                          : null,
                    ),
                    _ => DialDrive(
                      recording: r,
                      now: now,
                      settings: settings,
                      revealed: _revealed,
                      stoppedBar: r.stopped
                          ? _stoppedBar(context, r, now)
                          : null,
                      onTouch: _touched,
                      onRoute: () => _openRoute(context),
                    ),
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  DriveController get _controller => ref.read(driveControllerProvider.notifier);

  Widget _guided(
    BuildContext context,
    DriveRecording r,
    DateTime now,
    Settings? settings,
  ) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final view = r.view;
    final lostS = view?.gpsLostS;
    final leftM = view?.leftM;
    final arriving = leftM != null && leftM <= LearningConfig.navArriveM;
    final mapOf = ref.watch(driveMapBuilderProvider);
    final arrow =
        (settings?.driveMarker ?? DriveMarker.arrow) == DriveMarker.arrow;
    // The road the car is on straight up; the GPS's own until it is on the plan.
    final bearing = view?.onRoad?.headingDeg ?? view?.headingDeg;
    final plate = turnPlateFor(l10n, r, settings, arriving: arriving);
    final arrival = arrivalTime(context, view, now);
    final left = leftM == null ? null : formatDistance(leftM, l10n);
    final leftS = view?.leftS;
    final limit = view?.limitKmh;
    final over = view?.over ?? false;
    final camera = view?.camera ?? false;
    final options = _options;
    final street = switch (view?.street) {
      final s? => streetName(s, settings),
      null => null,
    };
    final lostLine = lostS != null && lostS >= LearningConfig.gpsLostSayS
        ? l10n.driveGpsLostFor(formatClock(Duration(seconds: lostS)))
        : null;
    final bar = DriveBottomBar(
      semanticsLabel:
          lostLine ??
          [
            if (left != null && arrival != null)
              l10n.a11yDriveBar(left, arrival),
            if (r.rescued) l10n.a11yRescuedDrive,
          ].join('. '),
      left: left,
      arrival: arrival,
      minutes: leftS == null ? null : _minutes(l10n, leftS),
      progress: view == null || leftM == null
          ? null
          : view.drivenM / math.max(1, view.drivenM + leftM),
      line: lostLine,
      rescued: r.rescued,
      // Stopped only (item 116).
      trailing: r.stopped
          ? DriveBarButton(
              glyph: PindoroGlyph.close,
              label: l10n.driveEnd,
              onTap: () => unawaited(_controller.end()),
            )
          : null,
    );
    final level = levelLabel(l10n, r.level);
    // The right-hand column, bottom up: the compass (Recentre once the map is off the car), the
    // level, Mute and the routes.
    final centre = _following && options == null
        ? DriveCompass(
            bearingDeg: _northUp ? 0 : bearing ?? 0,
            label: _northUp ? l10n.a11yHeadingUp : l10n.a11yNorthUp,
            onTap: () => setState(() => _northUp = !_northUp),
          )
        : DriveRecentre(
            label: l10n.a11yRecentre,
            onTap: () => setState(() {
              _following = true;
              _closeRoutes();
            }),
          );
    final column = [
      DriveMapButton(
        label: l10n.a11yRoutes,
        toggled: options != null,
        onTap: _toggleRoutes,
        child: DriveGlyph(
          DriveGlyphName.routes,
          size: 28,
          color: c.driveText,
          cut: c.driveSurface,
        ),
      ),
      DriveMapButton(
        label: r.muted ? l10n.driveUnmute : l10n.driveMute,
        onTap: _controller.toggleMute,
        child: DriveMapButton.glyph(
          context,
          r.muted ? PindoroGlyph.soundOff : PindoroGlyph.soundOn,
        ),
      ),
      DriveMapButton(
        label: l10n.a11yDriveLevel(level),
        toggled: _levelOpen,
        onTap: () => setState(() {
          _levelOpen = !_levelOpen;
          _closeRoutes();
        }),
        child: DriveMapButton.glyph(context, levelIcon(r.level)),
      ),
    ];
    return Listener(
      // Every touch counts, the map's and the buttons': none is taken from them.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touched(),
      child: Stack(
        children: [
          Positioned.fill(
            child: mapOf(
              DriveMap(
                key: ValueKey(arrow),
                arrow: arrow,
                at: view?.onRoad?.at ?? view?.at ?? r.start,
                heading: bearing,
                route: options != null && _picked > 0 ? _pickedLines : _route,
                turn: _turn,
                destination: r.destination,
                via: _viaPoints(r),
                places: _placesNear(view?.plan),
                speedKmh: view?.speedKmh ?? 0,
                lost: lostS != null,
                follow: _following && options == null,
                northUp: _northUp,
                alternatives: _optionLines,
                overview: options != null,
                onMoved: _moved,
              ),
            ),
          ),
          // The routes overview gives the map the card's room.
          if (options == null)
            Positioned(top: 0, left: 0, right: 0, child: PlateSwitch(plate)),
          if (lostS == null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + PindoroSpace.s2,
              right: PindoroSpace.s3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                spacing: PindoroSpace.s2,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: PindoroSpace.s2,
                    children: [
                      if (view != null)
                        SpeedNow(
                          kmh: view.speedKmh.round(),
                          semanticsLabel: l10n.a11ySpeedNow(
                            view.speedKmh.round(),
                          ),
                        ),
                      if (limit != null)
                        SpeedLimitSign(
                          limit: limit,
                          over: over,
                          beat: r.beat,
                          semanticsLabel: over
                              ? l10n.a11ySpeedOver(limit)
                              : l10n.a11ySpeedLimit(limit),
                        ),
                    ],
                  ),
                  if (camera)
                    Semantics(
                      label: l10n.a11yCameraAhead,
                      child: const CameraBadge(),
                    ),
                ],
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (options != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: PindoroSpace.s2),
                    child: _routes(context, r, options, settings),
                  ),
                if (_levelOpen)
                  Padding(
                    padding: const EdgeInsets.only(bottom: PindoroSpace.s2),
                    child: LevelPickerCard(
                      title: l10n.driveLevelRest,
                      reason: suggestionReason(l10n, r.to, r.suggestion),
                      picker: _levelPicker(context, r),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PindoroSpace.s3,
                    0,
                    PindoroSpace.s3,
                    PindoroSpace.s2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: PindoroSpace.s2,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Expanded(
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: MapAttribution(),
                            ),
                          ),
                          // In the routes overview only Recentre stays, its way out.
                          if (options == null)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              spacing: PindoroSpace.s2,
                              children: [
                                for (final b in column)
                                  DrivePop(revealed: _revealed, child: b),
                              ],
                            ),
                        ],
                      ),
                      // The street centred; the compass over the bar's right end.
                      Row(
                        spacing: PindoroSpace.s2,
                        children: [
                          const SizedBox(width: DriveMapButton.size),
                          Expanded(
                            child: Center(
                              child: street == null
                                  ? null
                                  : StreetChip(
                                      street,
                                      semanticsLabel: l10n.a11yStreetNow(
                                        street,
                                      ),
                                    ),
                            ),
                          ),
                          DrivePop(revealed: _revealed, child: centre),
                        ],
                      ),
                    ],
                  ),
                ),
                bar,
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "16 min" for [seconds], at least a minute.
  static String _minutes(AppLocalizations l10n, double seconds) =>
      l10n.unitMinutes(_wholeMinutes(seconds));

  static int _wholeMinutes(double seconds) =>
      math.max(1, (seconds / 60).ceil());

  /// The routes overview (items 130, 133, 134): the stops and the destination, then the route
  /// driven now and the other ways on, slower or quicker, as cards; a card picks a way, Take this
  /// route drives it. Add stop and Change destination at any speed.
  Widget _routes(
    BuildContext context,
    DriveRecording r,
    List<NavPlan> options,
    Settings? settings,
  ) {
    final l10n = context.l10n;
    final nowS = r.view?.leftS ?? 0;
    // Between the minutes shown, so "16 min" and "17 min" read "+1 min".
    String delta(NavPlan p) =>
        routeDelta(l10n, _wholeMinutes(p.seconds) - _wholeMinutes(nowS));

    return RouteOptions(
      semanticsLabel: l10n.a11yRoutes,
      ends: DriveRouteEnds(to: targetName(r.target, settings)),
      cards: [
        (
          tag: l10n.driveRouteNow,
          time: _minutes(l10n, nowS),
          length: formatDistance(r.view?.leftM ?? 0, l10n),
          note: null,
        ),
        for (final p in options)
          (
            tag: delta(p),
            time: _minutes(l10n, p.seconds),
            length: formatDistance(p.endM, l10n),
            note: null,
          ),
      ],
      onPick: (i) => setState(() => _pickRoute(i)),
      selected: _picked,
      takeLabel: _picked > 0 ? l10n.driveTakeRoute : null,
      onTake: _takeRoute,
    );
  }

  /// The level picker (Guided's card, the stopped bar's): a level picked applies at once.
  Widget _levelPicker(BuildContext context, DriveRecording r) {
    final l10n = context.l10n;
    return LevelPicker<DriveLevel>(
      steps: levelSteps(l10n, r.choices),
      selected: r.level,
      // A new destination's suggestion may lie past the setup's choices: no tag on a lock.
      suggested: switch (r.suggestion?.level) {
        final level? when r.to != DriveTo.run && r.choices.contains(level) =>
          level,
        _ => null,
      },
      suggestedLabel: l10n.driveSuggestedTag,
      semanticsLabel: l10n.driveLevelTitle,
      onChanged: (level) {
        _controller.pickDriveLevel(level);
        setState(() => _levelOpen = false);
      },
    );
  }

  void _openRoute(BuildContext context) => unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => inThemeOf(context, const DriveRouteScreen()),
      ),
    ),
  );

  /// The stops on the way not reached yet, as Guided's map marks them; the same list while
  /// they stay the same, so the map isn't sent them on every fix.
  List<LatLng> _viaPoints(DriveRecording r) {
    final graph = ref.watch(drivingGraphProvider).value;
    if (graph == null || r.via.isEmpty) return const [];
    if (identical(r.via, _viaFor)) return _via;
    _viaFor = r.via;
    return _via = [for (final t in r.via) targetPoint(graph, t)];
  }

  List<DriveTarget>? _viaFor;
  List<LatLng> _via = const [];

  /// The places near [plan]'s route, which Guided's map keeps while it follows the car
  /// (item 135); the same set while the plan stays, so the map is sent it once per plan.
  Set<int>? _placesNear(NavPlan? plan) {
    final places = ref.watch(packPlacesProvider).value;
    if (plan == null || places == null) return null;
    if (identical(plan, _placesFor)) return _places;
    _placesFor = plan;
    return _places = placesNear(plan.lines, places.values);
  }

  NavPlan? _placesFor;
  Set<int>? _places;

  /// Coached, Quiet and Off's stopped-controls bar (StoppedBar, board V32-41); Off adds Rescue
  /// above it.
  Widget _stoppedBar(BuildContext context, DriveRecording r, DateTime now) {
    final l10n = context.l10n;
    final view = r.view;
    final level = levelLabel(l10n, r.level);
    final arrival = arrivalTime(context, view, now);
    final bar = StoppedBar(
      semanticsLabel: l10n.a11yStoppedControls,
      left: switch (view?.leftM) {
        final m? => l10n.driveLeft(formatDistance(m, l10n)),
        null => null,
      },
      arrival: arrival == null ? null : l10n.driveArrive(arrival),
      muted: r.muted,
      muteLabel: r.muted ? l10n.driveUnmute : l10n.driveMute,
      onMute: _controller.toggleMute,
      level: (
        icon: levelIcon(r.level),
        label: level,
        semanticsLabel: l10n.a11yDriveLevel(level),
      ),
      levelOpen: _levelOpen,
      onLevel: () => setState(() => _levelOpen = !_levelOpen),
      endLabel: l10n.driveEnd,
      onEnd: () => unawaited(_controller.end()),
      // Off is the GPS-free drive: the way there would be help, so only Rescue gives it.
      routeLabel: r.level == DriveLevel.off ? null : l10n.a11yDriveRoute,
      onRoute: () => _openRoute(context),
      pickerTitle: l10n.driveLevelRest,
      pickerReason: suggestionReason(l10n, r.to, r.suggestion),
      picker: _levelPicker(context, r),
    );
    if (r.level != DriveLevel.off) {
      return KeyedSubtree(key: const ValueKey('stopped'), child: bar);
    }
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    return Column(
      key: const ValueKey('stopped'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PindoroSpace.s3,
            0,
            PindoroSpace.s3,
            PindoroSpace.s3,
          ),
          child: Container(
            padding: const EdgeInsets.all(PindoroSpace.s4),
            decoration: BoxDecoration(
              color: c.driveSurface,
              borderRadius: BorderRadius.circular(PindoroRadius.xl),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: PindoroSpace.s3,
              children: [
                Text(
                  l10n.driveRescueOffer(streetName(r.target.street, settings)),
                  style: PindoroType.bodyLg.copyWith(color: c.driveText),
                ),
                PindoroButton(
                  label: l10n.driveRescue,
                  large: true,
                  onPressed: _controller.rescue,
                ),
              ],
            ),
          ),
        ),
        bar,
      ],
    );
  }
}
