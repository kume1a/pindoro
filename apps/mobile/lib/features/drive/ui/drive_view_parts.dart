import 'package:flutter/material.dart';
import 'package:pindoro/core/database/database.dart' show Settings;
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/features/drive/ui/drive_controller.dart';
import 'package:pindoro/features/drive/ui/drive_levels.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro/features/learning/ui/landmark_glyph.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart' hide Navigator;

/// "12:41", in the device's 12- or 24-hour style; null without a plan.
String? arrivalTime(BuildContext context, NavView? view, DateTime now) {
  final leftS = view?.leftS;
  if (leftS == null) return null;
  final at = now.add(Duration(seconds: leftS.round())).toLocal();
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(at),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

/// The turn card (TurnPlate, SPEC §16.23 item 130): finding you, arrival, the next decision
/// (the street just turned onto first, unless the next is already close), or the street
/// alone; none on an unnamed road.
TurnPlate? turnPlateFor(
  AppLocalizations l10n,
  DriveRecording r,
  Settings? settings, {
  required bool arriving,
}) {
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
  // A stop on the way within the prepare reach and before the next decision (item 134).
  final stop = r.via.firstOrNull;
  final stopInM = view.viaInM;
  if (stop != null &&
      stopInM != null &&
      stopInM <= LearningConfig.prepareM &&
      (view.nextInM == null || stopInM < view.nextInM!)) {
    final name = targetName(stop, settings);
    final side = switch (view.side) {
      NavSide.right => l10n.driveRouteRight,
      NavSide.left => l10n.driveRouteLeft,
      null => null,
    };
    final distance = formatDistance(navRoundedM(stopInM), l10n);
    return TurnPlate(
      key: ValueKey('stop${r.via.length}'),
      semanticsLabel: [l10n.navIn(distance), name, ?side].join(', '),
      glyph: DriveGlyphName.flag,
      headline: distance,
      street: name,
      note: side ?? l10n.driveStopN(1),
    );
  }
  if (next != null && (view.prepareM != null || turned == null)) {
    final glyph = decisionGlyph(next);
    final action = decisionAction(l10n, glyph, onto: next.street != null);
    final landmark = next.landmark;
    final then = view.then;
    final at = landmarkLine(l10n, next, settings);
    final distance = formatDistance(navRoundedM(view.nextInM ?? 0), l10n);
    return TurnPlate(
      key: ValueKey('turn${next.junction}${view.newRoute}'),
      semanticsLabel: [
        if (view.newRoute) l10n.driveNewRoute,
        l10n.navIn(distance),
        ?at,
        [action, if (next.street case final s?) full(s)].join(' '),
        if (then != null)
          '${l10n.driveThen} '
              '${decisionAction(l10n, decisionGlyph(then), onto: false)}',
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

/// A Guided button: popping in with a touch ([revealed]), fading out with the rest after it.
class DrivePop extends StatelessWidget {
  const DrivePop({required this.revealed, required this.child, super.key});

  final bool revealed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : PindoroMotion.durationBase;
    return IgnorePointer(
      ignoring: !revealed,
      child: AnimatedOpacity(
        opacity: revealed ? 1 : 0,
        duration: duration,
        child: AnimatedScale(
          scale: revealed ? 1 : 0.6,
          duration: duration,
          curve: revealed
              ? PindoroMotion.easeOvershoot
              : PindoroMotion.easeDecelerate,
          child: child,
        ),
      ),
    );
  }
}

/// The card slides down and fades in, a new one replacing the last (TurnPlate motion).
class PlateSwitch extends StatelessWidget {
  const PlateSwitch(this.plate, {super.key});

  final Widget? plate;

  @override
  Widget build(BuildContext context) {
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
}

/// The bottom slot: the stopped-controls bar rises 40 dp as it fades in and drops as it
/// leaves; only fades under reduce motion (`motion.drive.stopped.*`). Moving, it takes no
/// touch, also while the bar is still leaving (item 116).
class StoppedRise extends StatelessWidget {
  const StoppedRise({required this.stopped, this.child, super.key});

  final bool stopped;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final calm = MediaQuery.disableAnimationsOf(context);
    return AbsorbPointer(
      absorbing: !stopped,
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
}
