import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart' show DriveMarker, Settings;
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_levels.dart';
import 'package:pindoro/features/drive/ui/drive_route_screen.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro/features/learning/ui/landmark_glyph.dart';
import 'package:pindoro/features/map/ui/drive_map.dart';
import 'package:pindoro/features/map/ui/widgets/map_attribution.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart' hide Navigator;

/// "Now Coached" stays this long after the guard steps in (board V32-31).
const Duration _guardNotice = Duration(seconds: 4);

/// Guided's map goes back to the car this long after the last touch (item 116).
const Duration _recentreAfter = Duration(seconds: 10);

/// A drive in progress at its level (boards V32-20 to V32-41, SPEC §16.23 items 115–118, 127,
/// 130): Guided's map under the turn card, the speeds and the floating bar, Coached and Quiet's dial (Recovery
/// over it after a wrong turn), Off's black screen. Day or night by sun time at the car. Moving,
/// only Guided's map takes touch; stopped, the stopped-controls bar rises. Back does nothing:
/// End drive ends it.
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

  /// Guided's map follows the car until the player moves it, then again after
  /// [_recentreAfter] or Recentre.
  bool _following = true;
  Timer? _recentre;

  @override
  void initState() {
    super.initState();
    // The clock's lines (arrival, "GPS lost 1:02", "Now Coached") move without a fix.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    _recentre?.cancel();
    super.dispose();
  }

  void _moved() {
    _recentre?.cancel();
    _recentre = Timer(_recentreAfter, _follow);
    if (_following) setState(() => _following = false);
  }

  void _follow() {
    _recentre?.cancel();
    if (mounted) setState(() => _following = true);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recording;
    final view = r.view;
    final now = ref.read(clockProvider)();
    // An open picker closes unchanged the moment the car moves (item 116).
    if (!r.stopped) _levelOpen = false;
    // Until the car is on a road the navigator has no plan: the route picked at setup shows.
    final plan = view?.plan ?? r.suggestion?.plan;
    final toPlan = view?.toPlan ?? const <LatLng>[];
    final leftM = view?.leftM;
    // How far along the navigator's plan the car is; null while short of it or before it.
    final doneM = view?.plan != null && leftM != null && toPlan.length < 2
        ? plan!.route.lengthM - leftM
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
          : plan!.slice(doneM, plan.route.lengthM);
      _route = doneM != null
          ? [if (ahead.length > 1) ahead]
          : [if (toPlan.length > 1) toPlan, ...?plan?.route.lines];
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
      child: Theme(
        data: buildPindoroTheme(night ? Brightness.dark : Brightness.light),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
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
                  DriveLevel.off => _off(context, r, now),
                  _ => _quiet(context, r, now, settings),
                },
              );
            },
          ),
        ),
      ),
    );
  }

  DriveController get _controller => ref.read(driveControllerProvider.notifier);

  /// "12:41", in the device's 12- or 24-hour style; null without a plan.
  String? _arrival(BuildContext context, NavView? view, DateTime now) {
    final leftS = view?.leftS;
    if (leftS == null) return null;
    final at = now.add(Duration(seconds: leftS.round())).toLocal();
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(at),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  Widget _guided(
    BuildContext context,
    DriveRecording r,
    DateTime now,
    Settings? settings,
  ) {
    final l10n = context.l10n;
    final view = r.view;
    final lostS = view?.gpsLostS;
    final leftM = view?.leftM;
    final arriving = leftM != null && leftM <= LearningConfig.navArriveM;
    final district = view?.district;
    final mapOf = ref.watch(driveMapBuilderProvider);
    final arrow =
        (settings?.driveMarker ?? DriveMarker.arrow) == DriveMarker.arrow;
    // The road the car is on straight up; the GPS's own until it is on the plan.
    final bearing = view?.onRoad?.headingDeg ?? view?.headingDeg;
    final plate = _plate(context, r, settings, arriving: arriving);
    final arrival = _arrival(context, view, now);
    final left = leftM == null ? null : formatDistance(leftM, l10n);
    final leftS = view?.leftS;
    final minutes = leftS == null
        ? null
        : l10n.unitMinutes(math.max(1, (leftS / 60).ceil()));
    final limit = view?.limitKmh;
    final over = view?.over ?? false;
    final camera = view?.camera ?? false;
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
      minutes: minutes,
      progress: view == null || leftM == null
          ? null
          : view.drivenM / math.max(1, view.drivenM + leftM),
      line: lostLine,
      rescued: r.rescued,
      leading: DriveCompass(
        headingDeg: bearing ?? 0,
        recentreLabel: l10n.a11yRecentre,
        onRecentre: _following ? null : _follow,
      ),
      // Stopped only (item 116), like the controls above the bar.
      trailing: r.stopped
          ? DriveBarButton(
              glyph: PindoroGlyph.close,
              label: l10n.driveEnd,
              onTap: () => unawaited(_controller.end()),
            )
          : null,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: mapOf(
            DriveMap(
              key: ValueKey(arrow),
              arrow: arrow,
              at: view?.onRoad?.at ?? view?.at ?? r.start,
              heading: bearing,
              route: _route,
              turn: _turn,
              destination: r.destination,
              lost: lostS != null,
              follow: _following,
              onMoved: _moved,
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _plateSwitch(context, plate),
        ),
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
                if (district != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.35,
                    ),
                    child: DistrictChip(
                      district,
                      semanticsLabel: l10n.a11yDistrict(district),
                    ),
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
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  PindoroSpace.s3,
                  0,
                  PindoroSpace.s3,
                  PindoroSpace.s2,
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: MapAttribution(),
                ),
              ),
              _rise(context, r, r.stopped ? _guidedControls(context, r) : null),
              bar,
            ],
          ),
        ),
      ],
    );
  }

  /// Guided's Mute, level and Route above its bar while stopped (item 130); End drive is the
  /// bar's button.
  Widget _guidedControls(BuildContext context, DriveRecording r) {
    final l10n = context.l10n;
    final level = levelLabel(l10n, r.level);
    return Padding(
      key: const ValueKey('stopped'),
      padding: const EdgeInsets.only(bottom: PindoroSpace.s2),
      child: StoppedControls(
        semanticsLabel: l10n.a11yStoppedControls,
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
        routeLabel: l10n.a11yDriveRoute,
        onRoute: () => _openRoute(context),
        pickerTitle: l10n.driveLevelRest,
        pickerReason: suggestionReason(l10n, r.to, r.suggestion),
        picker: _levelPicker(context, r),
      ),
    );
  }

  /// The level picker of the stopped controls: a level picked applies at once.
  Widget _levelPicker(BuildContext context, DriveRecording r) {
    final l10n = context.l10n;
    return LevelPicker<DriveLevel>(
      steps: levelSteps(l10n, r.choices),
      selected: r.level,
      suggested: r.to == DriveTo.run ? null : r.suggestion?.level,
      suggestedLabel: l10n.driveSuggestedTag,
      semanticsLabel: l10n.driveLevelTitle,
      onChanged: (level) {
        _controller.pickDriveLevel(level);
        setState(() => _levelOpen = false);
      },
    );
  }

  void _openRoute(BuildContext context) => unawaited(
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DriveRouteScreen())),
  );

  /// The turn card (TurnPlate, SPEC §16.23 item 130): finding you, arrival, the next decision
  /// (the street just turned onto first, unless the next is already close), or the street
  /// alone; none on an unnamed road.
  TurnPlate? _plate(
    BuildContext context,
    DriveRecording r,
    Settings? settings, {
    required bool arriving,
  }) {
    final l10n = context.l10n;
    final view = r.view;
    String short(NamedStreet s) => shortKind(streetName(s, settings));
    String full(NamedStreet s) => streetName(s, settings);
    if (view?.gpsLostS case final lostS?) {
      final lines = lostS >= LearningConfig.gpsLostSayS
          ? [l10n.driveStillFinding]
          : [l10n.driveKeepGoing, l10n.driveFindingYou];
      return TurnPlate(
        key: ValueKey('lost${lines.length}'),
        semanticsLabel: lines.join(' '),
        lead: lines,
      );
    }
    if (arriving) {
      final street = r.target.street;
      return TurnPlate(
        key: const ValueKey('here'),
        semanticsLabel: '${l10n.driveHere}: ${full(street)}',
        glyph: DriveGlyphName.flag,
        headline: l10n.driveHere,
        street: short(street),
      );
    }
    if (view == null) return null;
    final next = view.next;
    final turned = view.turned;
    if (next != null && (view.prepareM != null || turned == null)) {
      final glyph = decisionGlyph(next);
      final action = decisionAction(l10n, glyph, onto: next.street != null);
      final landmark = next.landmark;
      final then = view.then;
      final at = landmarkLine(l10n, next, settings);
      final distance = formatDistance(
        math.max(50, ((view.nextInM ?? 0) / 50).round() * 50.0),
        l10n,
      );
      return TurnPlate(
        key: ValueKey('turn${next.junction}${view.newRoute}'),
        semanticsLabel: [
          if (view.newRoute) l10n.driveNewRoute,
          l10n.navIn(distance),
          ?at,
          [action, if (next.street case final s?) full(s)].join(' '),
          if (then != null) l10n.driveThen,
        ].join(', '),
        lead: [if (view.newRoute) l10n.driveNewRoute],
        glyph: glyph,
        headline: distance,
        street: switch (next.street) {
          final s? => short(s),
          null => action,
        },
        note: at,
        noteKind: landmark != null
            ? landmarkDriveGlyph(landmark.kind)
            : next.signals
            ? DriveGlyphName.lights
            : null,
        lanes: view.prepareM == null ? const [] : navLanes(next) ?? const [],
        then: then == null ? null : decisionGlyph(then),
        thenLabel: l10n.driveThen,
      );
    }
    final street = turned?.street ?? view.street;
    if (street == null) return null;
    final heading = switch (turned?.headingDeg) {
      final h? => l10n.driveHeading(l10n.compassWord(compassPointOf(h).name)),
      null => null,
    };
    return TurnPlate(
      key: ValueKey('street${street.id}'),
      semanticsLabel: [full(street), ?heading].join(', '),
      street: short(street),
      note: heading,
    );
  }

  /// The card slides down and fades in, a new one replacing the last (TurnPlate motion).
  Widget _plateSwitch(BuildContext context, Widget? plate) {
    final calm = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: calm
          ? PindoroMotion.driveStoppedCalm
          : PindoroMotion.durationBase,
      reverseDuration: calm
          ? PindoroMotion.driveStoppedCalm
          : PindoroMotion.durationFast,
      switchInCurve: PindoroMotion.easeDecelerate,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: calm
            ? child
            : AnimatedBuilder(
                animation: animation,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, -PindoroSpace.s6 * (1 - animation.value)),
                  child: child,
                ),
                child: child,
              ),
      ),
      child: plate,
    );
  }

  /// The bottom slot: the stopped-controls bar rises 40 dp as it fades in and drops as it
  /// leaves; only fades under reduce motion (`motion.drive.stopped.*`). Moving, it takes no
  /// touch, also while the bar is still leaving (item 116).
  Widget _rise(BuildContext context, DriveRecording r, Widget? child) {
    final calm = MediaQuery.disableAnimationsOf(context);
    return AbsorbPointer(
      absorbing: !r.stopped,
      child: AnimatedSwitcher(
        duration: calm
            ? PindoroMotion.driveStoppedCalm
            : PindoroMotion.driveStoppedEnter,
        reverseDuration: calm
            ? PindoroMotion.driveStoppedCalm
            : PindoroMotion.driveStoppedExit,
        switchInCurve: PindoroMotion.driveStoppedEnterEase,
        switchOutCurve: PindoroMotion.driveStoppedExitEase,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.bottomCenter,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: calm
              ? child
              : AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(
                      0,
                      PindoroMotion.driveStoppedRise * (1 - animation.value),
                    ),
                    child: child,
                  ),
                  child: child,
                ),
        ),
        child: child,
      ),
    );
  }

  /// Coached, Quiet and Off's stopped-controls bar (StoppedBar, board V32-41); Off adds Rescue
  /// above it.
  Widget _stoppedBar(BuildContext context, DriveRecording r, DateTime now) {
    final l10n = context.l10n;
    final view = r.view;
    final level = levelLabel(l10n, r.level);
    final arrival = _arrival(context, view, now);
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

  Widget _quiet(
    BuildContext context,
    DriveRecording r,
    DateTime now,
    Settings? settings,
  ) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final view = r.view;
    final lost = view?.gpsLostS != null;
    final recovering = view?.recovering ?? false;
    final status = lost
        ? DriveStatus.lost
        : recovering
        ? DriveStatus.recovering
        : DriveStatus.good;
    final top = MediaQuery.paddingOf(context).top;
    final point = switch (view?.headingDeg) {
      final h? => compassPointOf(h),
      null => null,
    };
    final direction = point == null ? null : l10n.compassWord(point.name);
    final district = view?.district;
    final goodS = view?.goodS;
    final limit = view?.limitKmh;
    final over = view?.over ?? false;
    final guardedAt = r.guardedAt;
    final guarded =
        guardedAt != null && now.difference(guardedAt) < _guardNotice;
    return Stack(
      children: [
        Positioned.fill(
          child: SafeArea(
            child: Center(
              child: recovering
                  ? _recovery(context, view!, settings)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 28,
                      children: [
                        HeadingDial(
                          heading: lost ? null : view?.headingDeg,
                          letter: point == null
                              ? ''
                              : l10n.driveCardinal(point.name),
                          status: status,
                          semanticsLabel: lost || direction == null
                              ? l10n.a11yHeadingLost
                              : district == null
                              ? l10n.a11yHeading(direction)
                              : l10n.a11yHeadingIn(direction, district),
                        ),
                        if (district != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: PindoroSpace.s3,
                            ),
                            child: ExcludeSemantics(
                              child: DistrictLine(district),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        if (recovering)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Opacity(
              opacity: goodS == null ? 1 : 0.45,
              child: const RecoveryBand(),
            ),
          ),
        if (!lost && !r.stopped && limit != null)
          Positioned(
            top: top + PindoroSpace.s2,
            left: PindoroSpace.s3,
            child: Row(
              spacing: PindoroSpace.s3,
              children: [
                SpeedLimitSign(
                  limit: limit,
                  over: over,
                  beat: r.beat,
                  semanticsLabel: over
                      ? l10n.a11ySpeedOver(limit)
                      : l10n.a11ySpeedLimit(limit),
                ),
                if (view?.camera ?? false)
                  Semantics(
                    label: l10n.a11yCameraAhead,
                    child: const CameraBadge(),
                  ),
              ],
            ),
          ),
        Positioned(
          // The dot's centre sits 24 dp under the inset and 28 dp in.
          top: top,
          right: PindoroSpace.s1,
          child: Row(
            spacing: PindoroSpace.s3,
            children: [
              if (r.level == DriveLevel.coached && r.speaking)
                const SpeakingBars(),
              StatusDot(
                status: status,
                ring: recovering && goodS != null
                    ? goodS / LearningConfig.recoveryHoldS
                    : null,
                semanticsLabel: switch (status) {
                  DriveStatus.good => l10n.a11yOnGoodPath,
                  DriveStatus.recovering => l10n.a11yRecoveringDot,
                  DriveStatus.lost => l10n.a11yFindingPosition,
                },
              ),
            ],
          ),
        ),
        if (guarded)
          Positioned(
            left: PindoroSpace.s3,
            right: PindoroSpace.s3,
            bottom: MediaQuery.paddingOf(context).bottom + PindoroSpace.s16,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: PindoroSpace.s3,
                ),
                decoration: BoxDecoration(
                  color: c.drivePlate,
                  borderRadius: BorderRadius.circular(PindoroRadius.lg),
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.driveNowLevel(levelLabel(l10n, r.level)),
                    style: PindoroType.driveRead.copyWith(
                      color: c.drivePlateText,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _rise(
            context,
            r,
            r.stopped ? _stoppedBar(context, r, now) : null,
          ),
        ),
      ],
    );
  }

  /// The heading-up next-turn view while recovering (board V32-31): the way back and the street
  /// to turn into, dimmed once back on a good path.
  Widget _recovery(BuildContext context, NavView view, Settings? settings) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final next = view.next;
    final glyph = next == null ? DriveGlyphName.straight : decisionGlyph(next);
    final street = next?.street;
    return Semantics(
      liveRegion: true,
      label: l10n.a11yRecovering(
        [
          decisionAction(l10n, glyph, onto: street != null),
          if (street != null) streetName(street, settings),
        ].join(' '),
      ),
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          opacity: view.goodS == null ? 1 : 0.45,
          duration: PindoroMotion.durationSlow,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s4,
            children: [
              DriveGlyph(
                glyph,
                size: 220,
                color: c.drivePlateGlyph,
                cut: c.driveQuietBg,
              ),
              if (street != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PindoroSpace.s3,
                  ),
                  child: MediaQuery.withNoTextScaling(
                    child: Text(
                      shortKind(streetName(street, settings)),
                      textAlign: TextAlign.center,
                      style: PindoroType.driveRead.copyWith(
                        color: c.driveQuietText,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _off(BuildContext context, DriveRecording r, DateTime now) => Stack(
    children: [
      Positioned(
        top: MediaQuery.paddingOf(context).top + PindoroSpace.s4,
        right: PindoroSpace.s5,
        child: RecordingDot(semanticsLabel: context.l10n.driveRecording),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: _rise(
          context,
          r,
          r.stopped ? _stoppedBar(context, r, now) : null,
        ),
      ),
    ],
  );
}
