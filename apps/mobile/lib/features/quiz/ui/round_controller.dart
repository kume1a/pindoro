import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// Overridden in tests with a seeded Random.
final questionSelectorProvider = Provider<QuestionSelector>(
  (ref) => QuestionSelector(),
);

final roundControllerProvider =
    NotifierProvider.autoDispose<RoundController, RoundState>(
      RoundController.new,
    );

/// A planned question: the id stored in `round_question` (and on its answer)
/// and the named street it resolves to in the active pack.
typedef PlannedQuestion = ({String id, NamedStreet street});

/// What a round needs while it is played.
class RoundContext {
  const RoundContext({
    required this.id,
    required this.shape,
    required this.difficulty,
    required this.packVersion,
    required this.questions,
    required this.index,
    this.answers = const [],
    this.retryOf,
    this.previousDistanceM = const {},
  });

  final String id;
  final AreaShape shape;
  final Difficulty difficulty;
  final String packVersion;

  /// Planned questions whose streets are in the active pack, in round order.
  final List<PlannedQuestion> questions;
  final int index;

  /// Answers given so far, in order.
  final List<Answer> answers;

  /// The round whose Close and Miss streets this one retries.
  final String? retryOf;

  /// For a retry: how far the pin was last time, by question id.
  final Map<String, double> previousDistanceM;

  PlannedQuestion get question => questions[index];
  String get currentId => question.id;
  NamedStreet get current => question.street;
  int get number => index + 1;
  int get total => questions.length;
  bool get isLast => index == questions.length - 1;
  int get xp => answers.xp;

  /// Consecutive Great-or-better answers ending with the latest one.
  int get streak {
    var n = 0;
    for (final a in answers.reversed) {
      if (!isKnownTier(a.tier)) break;
      n++;
    }
    return n;
  }

  int get perfects => answers.where((a) => a.tier == Tier.perfect).length;

  RoundContext withAnswer(Answer answer) =>
      _copyWith(answers: [...answers, answer]);

  RoundContext advance() => _copyWith(index: index + 1);

  RoundContext _copyWith({int? index, List<Answer>? answers}) => RoundContext(
    id: id,
    shape: shape,
    difficulty: difficulty,
    packVersion: packVersion,
    questions: questions,
    index: index ?? this.index,
    answers: answers ?? this.answers,
    retryOf: retryOf,
    previousDistanceM: previousDistanceM,
  );
}

sealed class RoundState {
  const RoundState();
}

final class RoundLoading extends RoundState {
  const RoundLoading();
}

final class RoundNotEnough extends RoundState {
  const RoundNotEnough(this.count);

  final int count;
}

final class RoundAreaMissing extends RoundState {
  const RoundAreaMissing();
}

/// A Pit stop with nothing due (it emptied since the screen was opened).
final class RoundNothingDue extends RoundState {
  const RoundNothingDue();
}

final class RoundFinished extends RoundState {
  const RoundFinished(this.roundId);

  final String roundId;
}

sealed class RoundInPlay extends RoundState {
  const RoundInPlay(this.round, this.pin);

  final RoundContext round;
  final LatLng? pin;
}

final class RoundAsking extends RoundInPlay {
  const RoundAsking(super.round, [super.pin]);
}

final class RoundRevealed extends RoundInPlay {
  const RoundRevealed(
    super.round,
    LatLng super.pin, {
    required this.answer,
    required this.nearest,
  });

  final Answer answer;

  /// Closest point of the street to the pin (end of the measure line).
  final LatLng nearest;

  @override
  LatLng get pin => super.pin!;
}

class RoundController extends Notifier<RoundState> {
  bool _saving = false;

  @override
  RoundState build() => const RoundLoading();

  // Leaving the round disposes this controller and its ref: methods take the
  // DAO before their first await and check ref.mounted before using ref or
  // state again, so a round left while loading starts nothing.
  ProgressDao get _progress => ref.read(progressDaoProvider);

  Future<void> start(Area? area, Difficulty difficulty) async {
    state = const RoundLoading();
    final dao = _progress;
    final pack = await ref.read(packRepositoryProvider.future);
    if (!ref.mounted) return;
    final shape = area?.shapeIn(pack);
    if (area == null || shape == null) {
      state = const RoundAreaMissing();
      return;
    }
    final cityId = pack.city().id;
    final streets = await ref.read(cityStreetsProvider.future);
    final best = bestTierPerStreet(await dao.bestTierByPart(cityId), streets);
    final recent = await dao.askedInLastRounds(cityId);
    if (!ref.mounted) return;
    final selection = ref
        .read(questionSelectorProvider)
        .select(
          area.streetsIn(pack, difficulty.pool),
          bounds: shape.bbox,
          cityStreets: streets,
          knowledge: {
            for (final MapEntry(key: id, value: tier) in best.entries)
              id: knowledgeFrom(tier),
          },
          recentStreets: {for (final id in recent) ?streets[id]?.id},
        );
    switch (selection) {
      case NotEnoughStreets(:final count):
        state = RoundNotEnough(count);
      case SelectedQuestions(:final streetIds):
        final questions = resolveQuestions(streets, streetIds);
        final version = packVersion(pack);
        final roundId = await dao.startRound(
          cityId: cityId,
          area: area,
          difficulty: difficulty,
          packVersion: version,
          streetIds: [for (final q in questions) q.id],
        );
        if (!ref.mounted) return;
        state = RoundAsking(
          RoundContext(
            id: roundId,
            shape: shape,
            difficulty: difficulty,
            packVersion: version,
            questions: questions,
            index: 0,
          ),
        );
    }
  }

  /// Plays [roundId]'s Close and Miss streets in a new round with the same
  /// city, area and difficulty. An empty retry set starts nothing.
  Future<void> startRetry(String roundId) async {
    state = const RoundLoading();
    final dao = _progress;
    final pack = await ref.read(packRepositoryProvider.future);
    final original = await dao.roundProgress(roundId);
    if (!ref.mounted) return;
    final area = parseArea(original.round.areaJson);
    final shape = area?.shapeIn(pack);
    if (area == null || shape == null) {
      state = const RoundAreaMissing();
      return;
    }
    final questions = resolveQuestions(
      await ref.read(cityStreetsProvider.future),
      original.retryIds,
    );
    if (!ref.mounted) return;
    if (questions.isEmpty) {
      state = RoundFinished(roundId);
      return;
    }
    final version = packVersion(pack);
    final retryId = await dao.startRound(
      cityId: original.round.cityId,
      area: area,
      difficulty: original.round.difficulty,
      packVersion: version,
      streetIds: [for (final q in questions) q.id],
      retryOf: roundId,
    );
    final previous = await dao.previousDistances(retryId);
    if (!ref.mounted) return;
    state = RoundAsking(
      RoundContext(
        id: retryId,
        shape: shape,
        difficulty: original.round.difficulty,
        packVersion: version,
        questions: questions,
        index: 0,
        retryOf: roundId,
        previousDistanceM: previous,
      ),
    );
  }

  /// Plays the open city's Pit stop: up to [ReviewRules.pitStopSize] due
  /// streets, most overdue first, framed by the districts that hold them.
  Future<void> startPitStop(Difficulty difficulty) async {
    state = const RoundLoading();
    final dao = _progress;
    final pack = await ref.read(packRepositoryProvider.future);
    if (!ref.mounted) return;
    final cityId = pack.city().id;
    final streets = await ref.read(cityStreetsProvider.future);
    final today = calendarDay(DateTime.now());
    final due = (await dao.pitStop(cityId)).dueIn(streets, today);
    final questions = resolveQuestions(streets, [
      for (final item in due.take(ReviewRules.pitStopSize)) item.streetId,
    ]);
    if (!ref.mounted) return;
    final area = DistrictsArea(districtsHolding(pack, questions));
    final shape = area.shapeIn(pack);
    if (questions.isEmpty || shape == null) {
      state = const RoundNothingDue();
      return;
    }
    final version = packVersion(pack);
    final roundId = await dao.startRound(
      cityId: cityId,
      area: area,
      difficulty: difficulty,
      packVersion: version,
      streetIds: [for (final q in questions) q.id],
      pitStop: true,
    );
    final previous = await dao.previousDistances(roundId);
    if (!ref.mounted) return;
    state = RoundAsking(
      RoundContext(
        id: roundId,
        shape: shape,
        difficulty: difficulty,
        packVersion: version,
        questions: questions,
        index: 0,
        previousDistanceM: previous,
      ),
    );
  }

  Future<void> resume(String roundId) async {
    state = const RoundLoading();
    final dao = _progress;
    final pack = await ref.read(packRepositoryProvider.future);
    if (!ref.mounted) return;
    final streets = await ref.read(cityStreetsProvider.future);
    final progress = await dao.roundProgress(roundId);
    if (!ref.mounted) return;
    final shape = parseArea(progress.round.areaJson)?.shapeIn(pack);
    if (shape == null) {
      state = const RoundAreaMissing();
      return;
    }
    final questions = resolveQuestions(streets, progress.planned);
    final answered = {for (final a in progress.answers) a.streetId};
    final index = questions.indexWhere((q) => !answered.contains(q.id));
    if (index == -1) {
      await dao.finishRound(roundId);
      if (ref.mounted) state = RoundFinished(roundId);
      return;
    }
    final retryOf = progress.round.retryOf;
    // Retry and Pit stop rounds show the reroute plate with the last distance.
    final previous = retryOf != null || progress.round.pitStop
        ? await dao.previousDistances(roundId)
        : const <String, double>{};
    if (!ref.mounted) return;
    state = RoundAsking(
      RoundContext(
        id: roundId,
        shape: shape,
        difficulty: progress.round.difficulty,
        packVersion: packVersion(pack),
        questions: questions,
        index: index,
        answers: progress.answers,
        retryOf: retryOf,
        previousDistanceM: previous,
      ),
    );
  }

  void placePin(LatLng pin) {
    if (state case RoundAsking(:final round)) state = RoundAsking(round, pin);
  }

  /// Scores and saves the pin. The last answer also finishes the round, so a
  /// fully answered round is never left to resume.
  Future<void> confirm() async {
    if (_saving) return;
    if (state case RoundAsking(:final round, pin: final pin?)) {
      _saving = true;
      try {
        final dao = _progress;
        final question = round.question;
        final nearest = question.street.nearest(pin);
        final score = scoreAnswer(
          nearest.distanceM,
          nearest.part.roadClass,
          round.difficulty,
        );
        final answer = await dao.recordAnswer(
          roundId: round.id,
          streetId: question.id,
          pin: pin,
          distanceM: nearest.distanceM,
          tier: score.tier,
          xp: score.xp,
          packVersion: round.packVersion,
        );
        if (round.isLast) await dao.finishRound(round.id);
        if (ref.mounted) {
          state = RoundRevealed(
            round.withAnswer(answer),
            pin,
            answer: answer,
            nearest: nearest.nearestPoint,
          );
        }
      } finally {
        _saving = false;
      }
    }
  }

  /// The next question, or the results after the last one.
  Future<void> next() async {
    if (state case RoundRevealed(:final round)) {
      state = round.isLast
          ? RoundFinished(round.id)
          : RoundAsking(round.advance());
    }
  }
}

/// Planned ids → their streets in [cityStreets]. Ids are stable across pack
/// versions; ones retired since are skipped.
List<PlannedQuestion> resolveQuestions(
  Map<String, NamedStreet> cityStreets,
  List<String> ids,
) => [
  for (final id in ids)
    if (cityStreets[id] case final street?) (id: id, street: street),
];

/// The city districts (not quarters or neighbourhoods) holding any part of
/// [questions]' streets: a Pit stop round's area.
Set<String> districtsHolding(
  PackRepository pack,
  List<PlannedQuestion> questions,
) {
  final parts = {
    for (final q in questions)
      for (final p in q.street.parts) p.id,
  };
  final districts = {
    for (final d in pack.districts())
      if (d.kind == DistrictKind.district) d.id,
  };
  return {
    for (final MapEntry(key: id, value: inside)
        in pack.partsByDistrict().entries)
      if (districts.contains(id) && inside.any(parts.contains)) id,
  };
}
