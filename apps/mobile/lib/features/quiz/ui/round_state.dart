import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

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

/// The [answer] shown: its [pin] and the street's [nearest] point (the measure line), both
/// null for "I don't know".
final class RoundRevealed extends RoundInPlay {
  const RoundRevealed(
    super.round,
    super.pin, {
    required this.answer,
    required this.nearest,
  });

  final Answer answer;
  final LatLng? nearest;
}
