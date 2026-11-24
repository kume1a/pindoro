import 'package:pindoro/core/location.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/drive_suggest.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

export 'package:pindoro/features/learning/data/drive_suggest.dart'
    show DriveSuggestion;

/// Where a drive goes (DriveScreen `setup`, board V32-10): today's run, a surprise, Home, Work or
/// a street or place of the player's own.
enum DriveTo { run, surprise, home, work, own }

sealed class DriveState {
  const DriveState();
}

bool _sameVia(List<DriveTarget> a, List<DriveTarget> b) =>
    a.length == b.length && a.indexed.every((e) => e.$2 == b[e.$1]);

/// Choosing where to go and how much help: no [to] while searching; today's run, a surprise,
/// Home, Work or the player's [own] street or place. [here] once found, [denied] once location
/// was refused; [noTarget] when nothing fits the choice. [target] and the route [options] (the
/// quickest first, item 129) once found from where the player is, [suggestion] the one picked;
/// [level] once picked (else the suggestion). [via]: the stops on the way, in order (item 134).
final class DriveSetup extends DriveState {
  const DriveSetup({
    this.to,
    this.own,
    this.via = const [],
    this.here,
    this.denied,
    this.noTarget = false,
    this.target,
    this.options = const [],
    this.suggestion,
    this.level,
  });

  final DriveTo? to;
  final DriveDest? own;
  final List<DriveTarget> via;
  final LatLng? here;
  final LocationDenied? denied;
  final bool noTarget;
  final DriveTarget? target;
  final List<DriveSuggestion> options;
  final DriveSuggestion? suggestion;
  final DriveLevel? level;

  /// The level picked, else the suggestion; today's run is the GPS-free test (Off) unless
  /// another is picked.
  DriveLevel get chosen =>
      level ??
      (to == DriveTo.run
          ? DriveLevel.off
          : suggestion?.level ?? DriveLevel.guided);

  /// The levels the player may pick (item 114): more help or one step less; any with no
  /// suggestion, and any on today's run.
  List<DriveLevel> get choices => switch (suggestion) {
    final s? when to != DriveTo.run => levelChoices(s.level),
    _ => DriveLevel.values,
  };

  bool sameChoice(DriveSetup other) =>
      to == other.to && own == other.own && _sameVia(via, other.via);

  /// This setup with [suggestion] and [level] picked.
  DriveSetup picking(DriveSuggestion? suggestion, DriveLevel? level) =>
      DriveSetup(
        to: to,
        own: own,
        via: via,
        here: here,
        denied: denied,
        noTarget: noTarget,
        target: target,
        options: options,
        suggestion: suggestion,
        level: level,
      );
}

/// Driving to [target] (at [destination]) since [startedAt] at [level] (the guard, Rescue and a
/// pick while stopped change it, among the setup's [choices]); [view] is the
/// navigator's latest. [speaking] while a prompt is said, [guardedAt] when the guard last
/// stepped in, [beat] counts the speed chimes (each pulses the sign). [start] is where the
/// setup found the phone: the map opens there until the first fix. [districts] by id name the
/// view's district.
final class DriveRecording extends DriveState {
  const DriveRecording({
    required this.target,
    required this.destination,
    required this.to,
    this.via = const [],
    required this.startedAt,
    required this.level,
    required this.choices,
    this.start,
    this.suggestion,
    this.view,
    this.muted = false,
    this.rescued = false,
    this.speaking = false,
    this.guardedAt,
    this.beat = 0,
    this.districts = const {},
  });

  final DriveTarget target;
  final LatLng destination;
  final DriveTo to;

  /// The stops on the way not reached yet, in order (item 134).
  final List<DriveTarget> via;
  final DateTime startedAt;
  final DriveLevel level;
  final List<DriveLevel> choices;
  final LatLng? start;
  final DriveSuggestion? suggestion;
  final NavView? view;
  final bool muted;
  final bool rescued;
  final bool speaking;
  final DateTime? guardedAt;
  final int beat;
  final Map<String, District> districts;

  /// The district the car is in.
  District? get district => districts[view?.district];

  /// Controls take input only while stopped (item 116); before the first fix the car hasn't
  /// moved.
  bool get stopped => view?.stopped ?? true;

  DriveRecording copyWith({
    DriveTarget? target,
    LatLng? destination,
    List<DriveTarget>? via,
    DriveLevel? level,
    DriveSuggestion? suggestion,
    NavView? view,
    bool? muted,
    bool? rescued,
    bool? speaking,
    DateTime? guardedAt,
    int? beat,
  }) => DriveRecording(
    target: target ?? this.target,
    destination: destination ?? this.destination,
    to: to,
    via: via ?? this.via,
    startedAt: startedAt,
    level: level ?? this.level,
    choices: choices,
    start: start,
    suggestion: suggestion ?? this.suggestion,
    view: view ?? this.view,
    muted: muted ?? this.muted,
    rescued: rescued ?? this.rescued,
    speaking: speaking ?? this.speaking,
    guardedAt: guardedAt ?? this.guardedAt,
    beat: beat ?? this.beat,
    districts: districts,
  );
}

/// The drive graded like a recital (SPEC §5.3): the matched [match] over
/// the best route, [stoppedM] from the target when it ended short of it,
/// the J cards it reviewed as a success ([credited]) and as Again ([failed]), and the GPS
/// [gaps]; a [rescued] drive's tier is at most Close (§16.23 item 116). [id] is the drive's in
/// the log.
final class DriveReview extends DriveState {
  const DriveReview({
    required this.target,
    required this.match,
    required this.graded,
    required this.stoppedM,
    required this.credited,
    required this.failed,
    required this.gaps,
    this.rescued = false,
    this.id,
  });

  final DriveTarget target;
  final DriveMatch match;
  final RecitalResult? graded;
  final double? stoppedM;
  final int credited;
  final int failed;
  final GpsGaps gaps;
  final bool rescued;
  final String? id;

  Tier? get tier => driveTier(graded?.tier, rescued: rescued);
}
