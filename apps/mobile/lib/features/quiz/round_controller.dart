import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../../app/database.dart';
import '../pack/sqlite_pack_repository.dart';

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
typedef RoundQuestion = ({String id, NamedStreet street});

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
  final List<RoundQuestion> questions;
  final int index;

  /// Answers given so far, in order.
  final List<Answer> answers;

  /// The round whose Close and Miss streets this one retries.
  final String? retryOf;

  /// For a retry: how far the pin was last time, by question id.
  final Map<String, double> previousDistanceM;

  String get currentId => questions[index].id;
  int get xp => answers.fold(0, (sum, a) => sum + a.xp);

  /// Consecutive Great-or-better answers ending with the latest one.
  int get streak {
    var n = 0;
    for (final a in answers.reversed) {
      if (!isKnownTier(a.tier)) break;
      n++;
    }
    return n;
  }

  RoundContext withAnswer(Answer answer) => RoundContext(
    id: id,
    shape: shape,
    difficulty: difficulty,
    packVersion: packVersion,
    questions: questions,
    index: index,
    answers: [...answers, answer],
    retryOf: retryOf,
    previousDistanceM: previousDistanceM,
  );

  NamedStreet get current => questions[index].street;
  int get number => index + 1;
  int get total => questions.length;
  bool get isLast => index == questions.length - 1;

  RoundContext advance() => RoundContext(
    id: id,
    shape: shape,
    difficulty: difficulty,
    packVersion: packVersion,
    questions: questions,
    index: index + 1,
    answers: answers,
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
}

class RoundController extends Notifier<RoundState> {
  bool _saving = false;

  @override
  RoundState build() => const RoundLoading();

  AppDatabase get _db => ref.read(databaseProvider);

  Future<void> start(Area? area, Difficulty difficulty) async {
    state = const RoundLoading();
    final pack = await ref.read(packRepositoryProvider.future);
    final shape = area?.shapeIn(pack);
    if (area == null || shape == null) {
      if (ref.mounted) state = const RoundAreaMissing();
      return;
    }
    final cityId = pack.city().id;
    final bestById = await _db.bestTierByStreet(cityId);
    final recentIds = await _db.askedInLastRounds(cityId);
    final names = pack.streetNames({...bestById.keys, ...recentIds});
    final selection = ref
        .read(questionSelectorProvider)
        .select(
          area.streetsIn(pack, difficulty.pool),
          bounds: shape.bbox,
          knowledge: {
            for (final MapEntry(key: name, value: tier) in bestTierByName(
              bestById,
              names,
            ).entries)
              name: knowledgeFrom(tier),
          },
          recentNames: {for (final id in recentIds) ?names[id]},
        );
    switch (selection) {
      case NotEnoughStreets(:final count):
        if (ref.mounted) state = RoundNotEnough(count);
      case SelectedQuestions(:final streetIds):
        final questions = resolveQuestions(pack, streetIds);
        final packVersion = pack.meta()['version']!;
        final roundId = await _db.startRound(
          cityId: cityId,
          area: area,
          difficulty: difficulty,
          packVersion: packVersion,
          streetIds: [for (final q in questions) q.id],
        );
        if (!ref.mounted) return;
        state = RoundAsking(
          RoundContext(
            id: roundId,
            shape: shape,
            difficulty: difficulty,
            packVersion: packVersion,
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
    final pack = await ref.read(packRepositoryProvider.future);
    final original = (await _db.roundProgress(roundId)).round;
    final area = parseArea(original.areaJson);
    final shape = area?.shapeIn(pack);
    if (area == null || shape == null) {
      if (ref.mounted) state = const RoundAreaMissing();
      return;
    }
    final questions = resolveQuestions(pack, await _db.retrySet(roundId));
    if (questions.isEmpty) {
      if (ref.mounted) state = RoundFinished(roundId);
      return;
    }
    final packVersion = pack.meta()['version']!;
    final retryId = await _db.startRound(
      cityId: original.cityId,
      area: area,
      difficulty: original.difficulty,
      packVersion: packVersion,
      streetIds: [for (final q in questions) q.id],
      retryOf: roundId,
    );
    if (!ref.mounted) return;
    state = RoundAsking(
      RoundContext(
        id: retryId,
        shape: shape,
        difficulty: original.difficulty,
        packVersion: packVersion,
        questions: questions,
        index: 0,
        retryOf: roundId,
        previousDistanceM: await _distancesOf(roundId),
      ),
    );
  }

  Future<Map<String, double>> _distancesOf(String roundId) async => {
    for (final a in await _db.answersForRound(roundId)) a.streetId: a.distanceM,
  };

  Future<void> resume(String roundId) async {
    state = const RoundLoading();
    final pack = await ref.read(packRepositoryProvider.future);
    final progress = await _db.roundProgress(roundId);
    if (!ref.mounted) return;
    final shape = parseArea(progress.round.areaJson)?.shapeIn(pack);
    if (shape == null) {
      state = const RoundAreaMissing();
      return;
    }
    final questions = resolveQuestions(pack, progress.planned);
    final answered = {for (final a in progress.answers) a.streetId};
    final index = questions.indexWhere((q) => !answered.contains(q.id));
    if (index == -1) {
      await _db.finishRound(roundId);
      if (ref.mounted) state = RoundFinished(roundId);
      return;
    }
    final retryOf = progress.round.retryOf;
    final previous = retryOf == null
        ? const <String, double>{}
        : await _distancesOf(retryOf);
    if (!ref.mounted) return;
    state = RoundAsking(
      RoundContext(
        id: roundId,
        shape: shape,
        difficulty: progress.round.difficulty,
        packVersion: pack.meta()['version']!,
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

  Future<void> confirm() async {
    if (_saving) return;
    if (state case RoundAsking(:final round, pin: final pin?)) {
      _saving = true;
      try {
        final question = round.questions[round.index];
        final nearest = question.street.nearest(pin);
        final score = scoreAnswer(
          nearest.distanceM,
          nearest.part.roadClass,
          round.difficulty,
        );
        final answer = await _db
            .into(_db.answers)
            .insertReturning(
              AnswersCompanion.insert(
                roundId: round.id,
                streetId: question.id,
                pinLat: pin.lat,
                pinLon: pin.lon,
                distanceM: nearest.distanceM,
                tier: score.tier,
                xp: score.xp,
                packVersion: round.packVersion,
              ),
            );
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

  Future<void> next() async {
    if (state case RoundRevealed(:final round)) {
      if (!round.isLast) {
        state = RoundAsking(round.advance());
        return;
      }
      await _db.finishRound(round.id);
      if (ref.mounted) state = RoundFinished(round.id);
    }
  }
}

/// Planned ids → their named streets (every part in the city). Ids are stable
/// across pack versions; ones retired since are skipped.
List<RoundQuestion> resolveQuestions(PackRepository pack, List<String> ids) {
  final nameById = pack.streetNames(ids);
  final byName = {
    for (final s in groupByName(pack.streetsNamed(nameById.values.toSet())))
      s.name: s,
  };
  return [
    for (final id in ids)
      if (byName[nameById[id]] case final street?) (id: id, street: street),
  ];
}
