import 'package:pindoro/features/session/ui/session_tasks.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

export 'package:pindoro/features/session/ui/session_tasks.dart';

sealed class SessionState {
  const SessionState();
}

final class SessionLoading extends SessionState {
  const SessionLoading();
}

/// Nothing to learn now: no pack, or nothing due and no new streets.
final class SessionEmpty extends SessionState {
  const SessionEmpty();
}

/// A family member's intro chip: its parent and how many children of each
/// kind the parent has.
typedef SessionFamily = ({NamedStreet parent, Map<FamilyKind, int> children});

/// Guess first (SPEC §6.4): a child whose parent the player knows is pinned
/// before its intro; the guess is graded but schedules nothing.
typedef SessionGuess = ({NamedStreet parent, int knownSiblings});

/// A graded pin, as the reveal shows it.
/// A pin step answered: its [grade], the [pin] and the street's [nearest] point; all three
/// null for "I don't know".
typedef SessionReveal = ({
  PinGrade? grade,
  LatLng? pin,
  LatLng? nearest,

  /// Null: back in this session (Again).
  int? nextReviewDays,

  /// The street a Mix-up's pin hit.
  NamedStreet? hit,
});

final class SessionPlaying extends SessionState {
  const SessionPlaying({
    required this.steps,
    required this.index,
    required this.forgotten,
    required this.street,
    required this.area,
    required this.knownNames,
    required this.newIndex,
    required this.newTotal,
    this.task = const PinTask(),
    this.family,
    this.guess,
    this.frame,
    this.pin,
    this.reveal,
    this.contrast,
    this.note,
    this.leech = false,
    this.suspended = false,
  });

  /// The whole session, done steps included; relearns join as Again comes.
  final List<SessionStep> steps;
  final int index;

  /// Step indices answered Again, for the session bar.
  final Set<int> forgotten;

  /// The current step's street.
  final NamedStreet street;

  /// The city: the pin can go anywhere in it.
  final AreaShape area;

  /// Names of the streets the player knows: a place question names them
  /// (SPEC §16.18).
  final Set<String> knownNames;

  /// "New street · [newIndex] of [newTotal]".
  final int newIndex;
  final int newTotal;

  /// What the step asks beyond a pin (name, ends, drills).
  final SessionTask task;
  final SessionFamily? family;

  /// Set while an intro waits for its guess.
  final SessionGuess? guess;

  /// Retrieval 1 frames the street's district; null frames the city.
  final List<LatLng>? frame;
  final LatLng? pin;
  final SessionReveal? reveal;

  /// A leech's intro: the street it is most often mixed up with, shown
  /// beside it, and the player's note.
  final NamedStreet? contrast;
  final String? note;

  /// The intro brings back a suspended leech (SPEC §4).
  final bool leech;

  /// The answer just made the card a leech: suspended until a fresh intro.
  final bool suspended;

  SessionStep get step => steps[index];

  /// The step's answer is in: the reveal or the task's result shows.
  bool get answered => reveal != null || task.result != null;

  /// The answer's tier, for its sound and haptic; a Mix-up is a Miss.
  Tier? get resultTier => switch (reveal) {
    final r? => r.hit == null ? r.grade?.tier ?? Tier.miss : Tier.miss,
    null => task.result,
  };

  /// [pin] is a function so "I don't know" can clear it.
  SessionPlaying copyWith({
    LatLng? Function()? pin,
    SessionReveal? reveal,
    List<SessionStep>? steps,
    Set<int>? forgotten,
    SessionTask? task,
    bool? suspended,
  }) => SessionPlaying(
    steps: steps ?? this.steps,
    index: index,
    forgotten: forgotten ?? this.forgotten,
    street: street,
    area: area,
    knownNames: knownNames,
    newIndex: newIndex,
    newTotal: newTotal,
    task: task ?? this.task,
    family: family,
    guess: guess,
    frame: frame,
    pin: pin == null ? this.pin : pin(),
    reveal: reveal ?? this.reveal,
    contrast: contrast,
    note: note,
    leech: leech,
    suspended: suspended ?? this.suspended,
  );
}

/// What the session did (Session done).
typedef SessionSummary = ({
  int reviews,
  int newStreets,
  int recalledPercent,
  double memoryBefore,
  double memoryAfter,
  List<(NamedStreet, NamedStreet)> mixUps,
  List<NamedStreet> closeTwice,
  int minutes,
  bool cleared,

  /// The round just played, 1-based, of [rounds]: Next round while more are left.
  int round,
  int rounds,
});

final class SessionDone extends SessionState {
  const SessionDone(this.summary);

  final SessionSummary summary;
}

/// What placement found (the placement result).
typedef PlacementSummary = ({
  int passed,
  ({int passed, int of}) mainRoads,
  int raions,

  /// The road class new streets start with, else the neighbourhood.
  RoadBand? startBand,
  District? startIn,
});

final class SessionPlaced extends SessionState {
  const SessionPlaced(this.summary);

  final PlacementSummary summary;
}
