import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/hold.dart';
import 'package:pindoro/features/learning/data/explore.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

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

  /// For a retry: how far the pin was last time, by question id.
  final Map<String, double> previousDistanceM;

  PlannedQuestion get question => questions[index];
  String get currentId => question.id;
  NamedStreet get current => question.street;
  int get number => index + 1;
  int get total => questions.length;
  bool get isLast => index == questions.length - 1;

  /// The question bar's filled segments: one per answered question.
  List<Tier> get answeredTiers => [
    for (final a in answers.to({for (final q in questions) q.id})) a.tier,
  ];

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

  @override
  LatLng get pin => super.pin!;
}

class RoundController extends Notifier<RoundState> {
  bool _saving = false;

  /// When the current question showed: an Explore pin's response time.
  DateTime _askedAt = DateTime(0);

  DateTime _now() => ref.read(clockProvider)();

  /// Shows [round]'s current question.
  void _asking(RoundContext round) {
    _askedAt = _now();
    state = RoundAsking(round);
  }

  @override
  RoundState build() => const RoundLoading();

  // Leaving the round disposes this controller and its ref: methods take the
  // DAO before their first await and check ref.mounted before using ref or
  // state again, so a round left while loading starts nothing.
  ProgressDao get _progress => ref.read(progressDaoProvider);

  /// A round in [area] at [difficulty]; with [learned] (knowledge by street
  /// id), a round of only those streets, at every difficulty.
  Future<void> start(
    Area? area,
    Difficulty difficulty, {
    Map<String, StreetKnowledge>? learned,
  }) async {
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
    final knowledge =
        learned ??
        {
          for (final MapEntry(key: id, value: tier) in bestTierPerStreet(
            await dao.bestTierByPart(cityId),
            streets,
          ).entries)
            id: knowledgeFrom(tier),
        };
    final recent = await dao.askedInLastRounds(cityId);
    if (!ref.mounted) return;
    final inArea = area.streetsIn(
      pack,
      learned == null ? difficulty.pool : Difficulty.expert.pool,
    );
    final selection = ref
        .read(questionSelectorProvider)
        .select(
          learned == null
              ? inArea
              : [
                  for (final s in inArea)
                    if (learned.containsKey(streets[s.id]?.id)) s,
                ],
          bounds: shape.bbox,
          cityStreets: streets,
          knowledge: knowledge,
          recentStreets: {for (final id in recent) ?streets[id]?.id},
        );
    switch (selection) {
      case NotEnoughStreets(:final count):
        state = RoundNotEnough(count);
      case SelectedQuestions(:final streetIds):
        // The selector names a street by its longest part inside the area;
        // answers and the Pit stop key it by its city-wide id, as lessons do.
        await _ask(
          dao,
          pack,
          cityId: cityId,
          area: area,
          shape: shape,
          difficulty: difficulty,
          questions: resolveQuestions(streets, [
            for (final id in streetIds) streets[id]?.id ?? id,
          ]),
        );
    }
  }

  /// "Your streets": a round of the streets the player has learned (P cards)
  /// in the districts holding them, the ones not Known now first, scored at
  /// [difficulty]. Its area isn't the saved one, so Explore won't offer to
  /// continue it once left.
  Future<void> startLearned(Difficulty difficulty) async {
    state = const RoundLoading();
    final cards = await ref.hold(streetCardsProvider.future);
    final curriculum = await ref.read(curriculumProvider.future);
    if (!ref.mounted) return;
    final now = _now();
    await start(
      DistrictsArea({for (final id in cards.keys) ?curriculum.raionOf(id)}),
      difficulty,
      learned: {
        for (final MapEntry(key: id, value: card) in cards.entries)
          id: isKnown(card, now)
              ? StreetKnowledge.known
              : StreetKnowledge.missed,
      },
    );
  }

  /// Saves a new round of [questions] and asks the first.
  Future<void> _ask(
    ProgressDao dao,
    PackRepository pack, {
    required String cityId,
    required Area area,
    required AreaShape shape,
    required Difficulty difficulty,
    required List<PlannedQuestion> questions,
    String? retryOf,
  }) async {
    final version = packVersion(pack);
    final roundId = await dao.startRound(
      cityId: cityId,
      area: area,
      difficulty: difficulty,
      packVersion: version,
      streetIds: [for (final q in questions) q.id],
      retryOf: retryOf,
    );
    final previous = retryOf != null
        ? await dao.previousDistances(roundId)
        : const <String, double>{};
    if (!ref.mounted) return;
    _asking(
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
    await _ask(
      dao,
      pack,
      cityId: original.round.cityId,
      area: area,
      shape: shape,
      difficulty: original.round.difficulty,
      questions: questions,
      retryOf: roundId,
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
      if (ref.mounted) _finish(roundId);
      return;
    }
    final previous = progress.round.retryOf != null
        ? await dao.previousDistances(roundId)
        : const <String, double>{};
    if (!ref.mounted) return;
    _asking(
      RoundContext(
        id: roundId,
        shape: shape,
        difficulty: progress.round.difficulty,
        packVersion: packVersion(pack),
        questions: questions,
        index: index,
        answers: progress.answers,
        previousDistanceM: previous,
      ),
    );
  }

  void placePin(LatLng pin) {
    if (state case RoundAsking(:final round)) state = RoundAsking(round, pin);
  }

  /// Scores and saves the pin, and feeds it to the learning cards. The last
  /// answer also finishes the round, so a fully answered round is never left
  /// to resume.
  Future<void> confirm() async {
    if (_saving) return;
    if (state case RoundAsking(:final round, pin: final pin?)) {
      _saving = true;
      try {
        final dao = _progress;
        final question = round.question;
        final nearest = question.street.nearest(pin);
        final rtMs = _now().difference(_askedAt).inMilliseconds;
        final answer = await dao.recordAnswer(
          roundId: round.id,
          streetId: question.id,
          pin: pin,
          distanceM: nearest.distanceM,
          tier: scoreAnswer(
            nearest.distanceM,
            nearest.part.roadClass,
            round.difficulty,
          ),
          packVersion: round.packVersion,
        );
        if (round.isLast) await dao.finishRound(round.id);
        if (!ref.mounted) return;
        await learnFromExplore(
          ref,
          street: question.street,
          pin: pin,
          rtMs: rtMs,
          roundId: round.id,
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

  /// The next question, or the results after the last one.
  Future<void> next() async {
    if (state case RoundRevealed(:final round)) {
      if (round.isLast) {
        _finish(round.id);
      } else {
        _asking(round.advance());
      }
    }
  }

  void _finish(String roundId) => state = RoundFinished(roundId);
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
