import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// What the current step asks beyond a pin, and its answer once given
/// (SessionScreen `nameHidden` … `orientation`, docs/design/v3-screens.md).
sealed class SessionTask {
  const SessionTask();

  /// The answer's tier once it is graded; null while asking. A pin's lives in
  /// the reveal.
  Tier? get result;
}

/// A pin for a P card, a guess or a placement: the reveal holds the answer.
final class PinTask extends SessionTask {
  const PinTask();

  @override
  Tier? get result => null;
}

/// Name it (card N): the painted street and [choices] of names to pick from.
final class NameTask extends SessionTask {
  const NameTask({
    required this.choices,
    this.picked,
    this.right,
    this.nextReviewDays,
  });

  final List<NamedStreet> choices;
  final NamedStreet? picked;

  /// Whether the checked pick was the street; null until picked.
  final bool? right;
  final int? nextReviewDays;

  @override
  Tier? get result => switch (right) {
    null => null,
    true => Tier.great,
    false => Tier.miss,
  };

  NameTask copyWith({NamedStreet? picked, bool? right, int? nextReviewDays}) =>
      NameTask(
        choices: choices,
        picked: picked ?? this.picked,
        right: right ?? this.right,
        nextReviewDays: nextReviewDays ?? this.nextReviewDays,
      );
}

/// Both ends (card E): up to two pins, then the grade.
final class ExtentTask extends SessionTask {
  const ExtentTask({this.pins = const [], this.grade, this.nextReviewDays});

  final List<LatLng> pins;
  final ExtentGrade? grade;
  final int? nextReviewDays;

  @override
  Tier? get result => grade?.tier;
}

/// The family sweep: each lane's label dropped on a lane ([placed]: label's
/// street id → the lane's), then checked.
final class SweepTask extends SessionTask {
  const SweepTask({
    required this.lanes,
    this.placed = const {},
    this.checked = false,
  });

  final List<NamedStreet> lanes;
  final Map<String, String> placed;
  final bool checked;

  int get right => placed.entries.where((e) => e.key == e.value).length;

  @override
  Tier? get result => checked ? Grader.gradeShare(right, lanes.length) : null;

  SweepTask copyWith({Map<String, String>? placed, bool? checked}) => SweepTask(
    lanes: lanes,
    placed: placed ?? this.placed,
    checked: checked ?? this.checked,
  );
}

/// The crossings drill: drive from [from] and name each crossing in turn;
/// [named] holds whether each answered one was right.
final class CrossingsTask extends SessionTask {
  const CrossingsTask({
    required this.from,
    required this.start,
    required this.crossings,
    this.named = const [],
  });

  final NamedStreet from;

  /// Where the drive starts: where [from] meets the street.
  final LatLng start;
  final List<Crossing> crossings;
  final List<bool> named;

  bool get done => named.length == crossings.length;

  @override
  Tier? get result => done
      ? Grader.gradeShare(named.where((n) => n).length, crossings.length)
      : null;
}

/// A bearing from the city centre to the step's street: the player's arrow,
/// then the error once checked; a Miss when checked as [notKnown] ("I don't know").
final class BearingTask extends SessionTask {
  const BearingTask({
    required this.trueBearing,
    required this.distanceM,
    this.bearing = 0,
    this.checked = false,
    this.notKnown = false,
  });

  final double trueBearing;
  final double distanceM;
  final double bearing;
  final bool checked;
  final bool notKnown;

  double get error => bearingError(bearing, trueBearing);

  @override
  Tier? get result => !checked
      ? null
      : notKnown
      ? Tier.miss
      : Grader.gradeBearing(error);

  BearingTask copyWith({double? bearing, bool? checked, bool? notKnown}) =>
      BearingTask(
        trueBearing: trueBearing,
        distanceM: distanceM,
        bearing: bearing ?? this.bearing,
        checked: checked ?? this.checked,
        notKnown: notKnown ?? this.notKnown,
      );
}

/// A route card (SPEC §3): a turn, a gateway, a bridge, a connection or a
/// landmark. [choice] is what the player picked before Confirm — a [Turn],
/// a [Bridge], a junction (L2) or a name (L3); a pin goes in
/// `SessionPlaying.pin`.
final class RouteTask extends SessionTask {
  const RouteTask(
    this.question, {
    this.choice,
    this.rating,
    this.nextReviewDays,
  });

  final RouteQuestion question;
  final Object? choice;
  final Rating? rating;
  final int? nextReviewDays;

  @override
  Tier? get result => switch (rating) {
    final r? => RouteGrader.tierOf(r),
    null => null,
  };

  /// [choice] is a function so "I don't know" can clear it.
  RouteTask copyWith({
    Object? Function()? choice,
    Rating? rating,
    int? nextReviewDays,
  }) => RouteTask(
    question,
    choice: choice == null ? this.choice : choice(),
    rating: rating ?? this.rating,
    nextReviewDays: nextReviewDays ?? this.nextReviewDays,
  );
}

/// How a recital is answered (RecitalScreen). Speak waits for speech
/// recognition (SPEC §11, parked).
enum RecitalMode { type, draw }

/// A recital (card R, SPEC §5.3): from [from] (A, on [fromStreet]) to [to]
/// (B, on [toStreet]), pack junctions of [run], by heart. Typed as [steps]
/// (the [turn] picked for the next one; [hinted] once a suggestion was
/// taken) or drawn as [draft]; [graded] once checked, with the J cards that
/// went to [practice] and whether the player [reported] the illegal move.
final class RecitalTask extends SessionTask {
  const RecitalTask(
    this.run, {
    required this.from,
    required this.to,
    required this.fromStreet,
    required this.toStreet,
    required this.draft,
    this.mode = RecitalMode.type,
    this.steps = const [],
    this.turn,
    this.hinted = false,
    this.graded,
    this.practice = const [],
    this.nextReviewDays,
    this.reported = false,
  });

  final Run run;
  final int from;
  final int to;
  final NamedStreet fromStreet;
  final NamedStreet toStreet;
  final RouteDraft draft;
  final RecitalMode mode;
  final List<RecitalStep> steps;
  final Turn? turn;
  final bool hinted;
  final RecitalResult? graded;
  final List<String> practice;
  final int? nextReviewDays;
  final bool reported;

  @override
  Tier? get result => graded?.tier;

  RecitalTask copyWith({
    RouteDraft? draft,
    RecitalMode? mode,
    List<RecitalStep>? steps,
    Turn? Function()? turn,
    bool? hinted,
    RecitalResult? graded,
    List<String>? practice,
    int? nextReviewDays,
    bool? reported,
  }) => RecitalTask(
    run,
    from: from,
    to: to,
    fromStreet: fromStreet,
    toStreet: toStreet,
    draft: draft ?? this.draft,
    mode: mode ?? this.mode,
    steps: steps ?? this.steps,
    turn: turn == null ? this.turn : turn(),
    hinted: hinted ?? this.hinted,
    graded: graded ?? this.graded,
    practice: practice ?? this.practice,
    nextReviewDays: nextReviewDays ?? this.nextReviewDays,
    reported: reported ?? this.reported,
  );
}
