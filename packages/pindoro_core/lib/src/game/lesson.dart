import 'dart:math';

import '../geo/geo.dart';
import '../scoring/scoring.dart';
import 'course.dart';
import 'knowledge.dart';
import 'named_street.dart';
import 'road_trip.dart';

abstract final class LessonRules {
  static const int nameXp = 50;
  static const int finishXp = 20;
  static const int perfectXp = 50;

  /// A road trip drawn as the shortest drive.
  static const int tripXp = 100;

  /// "Which street is this?" steps in a lesson; every street also gets a pin.
  static const int nameTests = 2;

  /// Fixes and practice earn half, rounded down.
  static int half(int xp) => xp ~/ 2;

  /// A lesson killed by the OS resumes at its step for this long after its
  /// last save.
  static const Duration resumeFor = Duration(hours: 24);

  /// A lesson with every pin and its road trip Perfect, every name right and
  /// no mistakes.
  static int get maxXp =>
      CourseRules.streetsPerLesson * ScoringConfig.perfectXp +
      nameTests * nameXp +
      tripXp +
      finishXp +
      perfectXp;
}

sealed class LessonStep {
  const LessonStep(this.street);

  final NamedStreet street;
}

/// "New street · [number] of 4": no answer, no XP.
final class CardStep extends LessonStep {
  const CardStep(super.street, this.number);

  final int number;
}

sealed class TestStep extends LessonStep {
  const TestStep(super.street, {this.fix = false});

  /// A mistake coming back at the end of the lesson.
  final bool fix;
}

final class PinStep extends TestStep {
  const PinStep(super.street, {super.fix, this.lastDistanceM});

  /// How far the pin was the last time (the "Try again" plate).
  final double? lastDistanceM;
}

final class NameStep extends TestStep {
  const NameStep(super.street, this.options, {super.fix});

  /// The answer and the other plates, in the order shown.
  final List<NamedStreet> options;
}

/// A road trip ending on its destination street (the step's street).
final class TripStep extends TestStep {
  TripStep(this.trip, {super.fix}) : super(trip.destination);

  final Trip trip;
}

/// A lesson's steps: 4 new-street cards, then a pin on each street and
/// [LessonRules.nameTests] names, shuffled so no street asks twice in a row,
/// then the road [trip] when there is one. Practice skips the cards; a unit's
/// Pit stop is one pin per street with its [lastDistances]. Name options come
/// from [unitStreets].
List<LessonStep> planLesson({
  required LessonKind kind,
  required List<NamedStreet> streets,
  required List<NamedStreet> unitStreets,
  Map<String, double> lastDistances = const {},
  Trip? trip,
  Random? random,
}) {
  final rng = random ?? Random();
  if (kind == LessonKind.pitStop) {
    return [
      for (final s in streets) PinStep(s, lastDistanceM: lastDistances[s.id]),
    ];
  }
  final named = ([...streets]..shuffle(rng)).take(LessonRules.nameTests);
  final tests = <TestStep>[
    for (final s in streets) PinStep(s),
    for (final s in named) NameStep(s, _options(s, unitStreets, rng)),
  ];
  // ponytail: reshuffles until no street repeats; with 6 steps and 2 repeated
  // streets about half the shuffles qualify, so 50 tries never run out.
  for (var i = 0; i < 50; i++) {
    tests.shuffle(rng);
    if (!_repeats(tests)) break;
  }
  return [
    if (kind == LessonKind.lesson)
      for (final (i, s) in streets.indexed) CardStep(s, i + 1),
    ...tests,
    if (trip != null) TripStep(trip),
  ];
}

bool _repeats(List<TestStep> steps) => [
  for (var i = 1; i < steps.length; i++)
    steps[i].street.id == steps[i - 1].street.id,
].any((same) => same);

/// [answer] and two other streets with names of their own, shuffled.
List<NamedStreet> _options(
  NamedStreet answer,
  List<NamedStreet> pool,
  Random rng,
) {
  final names = {answer.name};
  final others = [
    for (final s in [...pool]..shuffle(rng))
      if (names.add(s.name)) s,
  ].take(2);
  return [answer, ...others]..shuffle(rng);
}

/// One answered test step; a name is Great when right, Miss when wrong; a
/// road trip has no distance.
typedef StepAnswer = ({
  TestStep step,
  Tier tier,
  int xp,
  double? distanceM,
  DateTime at,
});

/// An answer by the index of the step it answered, as a saved lesson keeps it.
typedef SavedAnswer = ({
  int step,
  String streetId,
  Tier tier,
  int xp,
  double? distanceM,
  DateTime at,
});

/// A lesson being played: where it is, what was answered and what it earns.
/// A lesson's first-try mistakes come back once, after its last step.
class LessonRun {
  LessonRun(this.kind, this.steps)
    : index = 0,
      answers = const [],
      _fixesAdded = false;

  const LessonRun._(
    this.kind,
    this.steps,
    this.index,
    this.answers,
    this._fixesAdded,
  );

  final LessonKind kind;
  final List<LessonStep> steps;
  final int index;
  final List<StepAnswer> answers;
  final bool _fixesAdded;

  /// [steps] as planned (before fixes) with [answers] replayed and walked on
  /// to [index]; null when an answer doesn't fit its step (the plan changed).
  static LessonRun? restore(
    LessonKind kind,
    List<LessonStep> steps,
    List<SavedAnswer> answers,
    int index,
  ) {
    var run = LessonRun(kind, steps);
    for (final a in answers) {
      while (run.index < a.step && !run.finished) {
        run = run.next();
      }
      if (run.finished || run.index != a.step) return null;
      final step = run.step;
      if (step is! TestStep || step.street.id != a.streetId) return null;
      run = run._answer((
        step: step,
        tier: a.tier,
        xp: a.xp,
        distanceM: a.distanceM,
        at: a.at,
      ));
    }
    while (run.index < index && !run.finished) {
      run = run.next();
    }
    return run;
  }

  /// The answers, by the index of the step each answered.
  List<SavedAnswer> get saved => [
    for (final a in answers)
      (
        step: steps.indexWhere((s) => identical(s, a.step)),
        streetId: a.step.street.id,
        tier: a.tier,
        xp: a.xp,
        distanceM: a.distanceM,
        at: a.at,
      ),
  ];

  /// Where a restored run continues: past a reveal that was showing.
  LessonRun resumeAt() => answered ? next() : this;

  LessonStep get step => steps[index];

  bool get finished => index >= steps.length;

  /// Whether the current step has its answer (the reveal is showing).
  bool get answered =>
      answers.isNotEmpty && !finished && identical(answers.last.step, step);

  /// Steps, counting the fixes the mistakes so far will add.
  int get total => _fixesAdded ? steps.length : steps.length + mistakes.length;

  /// First-try mistakes ([isMistake]), in order; only a lesson brings them
  /// back.
  List<StepAnswer> get mistakes => kind != LessonKind.lesson
      ? const []
      : [
          for (final a in answers)
            if (!a.step.fix && isMistake(a)) a,
        ];

  /// The first fix is next: the screen lists the mistakes before it.
  bool get startsFixes =>
      !finished &&
      index > 0 &&
      step is TestStep &&
      (step as TestStep).fix &&
      !_isFix(steps[index - 1]);

  static bool _isFix(LessonStep step) => step is TestStep && step.fix;

  bool get _halved => kind == LessonKind.practice;

  LessonRun answerPin(Score score, double distanceM, DateTime at) {
    final pin = step as PinStep;
    final xp = pin.fix || _halved ? LessonRules.half(score.xp) : score.xp;
    return _answer((
      step: pin,
      tier: score.tier,
      xp: xp,
      distanceM: distanceM,
      at: at,
    ));
  }

  LessonRun answerName({required bool right, required DateTime at}) {
    final name = step as NameStep;
    final full = right ? LessonRules.nameXp : 0;
    return _answer((
      step: name,
      tier: right ? Tier.great : Tier.miss,
      xp: name.fix || _halved ? LessonRules.half(full) : full,
      distanceM: null,
      at: at,
    ));
  }

  /// A road trip scored by [scoreRoute] ("Show the route" is a Miss).
  LessonRun answerTrip(Score score, DateTime at) {
    final trip = step as TripStep;
    return _answer((
      step: trip,
      tier: score.tier,
      xp: trip.fix || _halved ? LessonRules.half(score.xp) : score.xp,
      distanceM: null,
      at: at,
    ));
  }

  LessonRun _answer(StepAnswer answer) =>
      LessonRun._(kind, steps, index, [...answers, answer], _fixesAdded);

  /// On to the next step; after a lesson's last step its mistakes come back.
  LessonRun next() {
    final last = index == steps.length - 1;
    if (!last || _fixesAdded || mistakes.isEmpty) {
      return LessonRun._(kind, steps, index + 1, answers, _fixesAdded);
    }
    return LessonRun._(
      kind,
      [
        ...steps,
        for (final m in mistakes)
          switch (m.step) {
            PinStep(:final street) => PinStep(
              street,
              fix: true,
              lastDistanceM: m.distanceM,
            ),
            NameStep(:final street, :final options) => NameStep(
              street,
              options,
              fix: true,
            ),
            TripStep(:final trip) => TripStep(trip, fix: true),
          },
      ],
      index + 1,
      answers,
      true,
    );
  }

  int get stepXp => answers.fold(0, (sum, a) => sum + a.xp);

  int get fixXp => answers.fold(0, (sum, a) => sum + (a.step.fix ? a.xp : 0));

  /// A lesson with no first-try mistakes.
  bool get perfect => kind == LessonKind.lesson && mistakes.isEmpty;

  int get bonusXp => kind != LessonKind.lesson
      ? 0
      : LessonRules.finishXp + (perfect ? LessonRules.perfectXp : 0);

  int get xp => stepXp + bonusXp;

  /// Tests answered (first tries).
  int get tests => answers.where((a) => !a.step.fix).length;

  /// Tests right first time: a Great or Perfect pin, a right name, a road
  /// trip that isn't a Miss.
  int get rightFirst =>
      answers.where((a) => !a.step.fix && !isMistake(a)).length;
}

/// A mistake comes back once at the end: a Close or Miss pin, a wrong name,
/// a Miss road trip (a Close drive still found its way).
bool isMistake(StepAnswer a) =>
    a.step is TripStep ? a.tier == Tier.miss : isRetryTier(a.tier);

/// The answers of a finished [run] the Pit stop tab takes, in order: never a
/// road trip (it is about the route, not one street). Practice and a unit's
/// Pit stop give all the others. A lesson gives every answer for a street
/// already [inPitStop], and otherwise only fixes that were wrong again.
List<({String streetId, Tier tier})> reviewAnswers(
  LessonRun run, {
  required Set<String> inPitStop,
}) => [
  for (final a in run.answers)
    if (a.step is! TripStep &&
        (run.kind != LessonKind.lesson ||
            inPitStop.contains(a.step.street.id) ||
            (a.step.fix && isRetryTier(a.tier))))
      (streetId: a.step.street.id, tier: a.tier),
];

enum RoadType { mainRoad, street, sideStreet }

RoadType roadTypeOf(String roadClass) => switch (roadClass) {
  'motorway' || 'trunk' || 'primary' => RoadType.mainRoad,
  'secondary' || 'tertiary' => RoadType.street,
  _ => RoadType.sideStreet,
};

/// A line within this of another touches it (a shared junction node).
const double _touchM = 3;

/// Streets with another name whose lines cross or touch [street].
int crossingCount(NamedStreet street, Iterable<NamedStreet> others) {
  final lines = street.geometry;
  final points = lines.expand((l) => l).toList();
  if (points.isEmpty) return 0;
  final proj = LocalProjection(points.first);
  final box = _grown(Bbox.of(points), _touchM);
  final names = <String>{};
  for (final other in others) {
    if (other.name == street.name || names.contains(other.name)) continue;
    final otherPoints = other.geometry.expand((l) => l);
    if (!box.intersects(Bbox.of(otherPoints))) continue;
    final meets =
        otherPoints.any(
          (p) => pointToPolylineDistance(p, lines).distanceMeters <= _touchM,
        ) ||
        _linesCross(lines, other.geometry, proj);
    if (meets) names.add(other.name);
  }
  return names.length;
}

Bbox _grown(Bbox b, double m) {
  final dLat = m / 111320;
  final dLon = dLat / cos(b.center.lat * pi / 180);
  return Bbox(
    b.minLat - dLat,
    b.minLon - dLon,
    b.maxLat + dLat,
    b.maxLon + dLon,
  );
}

bool _linesCross(MultiPolyline a, MultiPolyline b, LocalProjection proj) {
  for (final la in a) {
    for (var i = 1; i < la.length; i++) {
      final p1 = proj.project(la[i - 1]), p2 = proj.project(la[i]);
      for (final lb in b) {
        for (var j = 1; j < lb.length; j++) {
          if (_segmentsCross(
            p1,
            p2,
            proj.project(lb[j - 1]),
            proj.project(lb[j]),
          )) {
            return true;
          }
        }
      }
    }
  }
  return false;
}

double _cross(Xy o, Xy a, Xy b) =>
    (a.$1 - o.$1) * (b.$2 - o.$2) - (a.$2 - o.$2) * (b.$1 - o.$1);

bool _segmentsCross(Xy p1, Xy p2, Xy q1, Xy q2) =>
    _cross(p1, p2, q1) * _cross(p1, p2, q2) < 0 &&
    _cross(q1, q2, p1) * _cross(q1, q2, p2) < 0;

/// Within this of the city centre a street is "in the city centre".
const double centreRadiusM = 1000;

/// Which way [street] lies from the city centre; null within [centreRadiusM].
CompassPoint? directionFromCentre(NamedStreet street, LatLng cityCenter) {
  final mid = street.parts.first.midpoint;
  return distanceBetween(cityCenter, mid) < centreRadiusM
      ? null
      : compassPoint(cityCenter, mid);
}
