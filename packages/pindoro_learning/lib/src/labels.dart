import 'cards.dart';
import 'constants.dart';
import 'days.dart';
import 'fsrs.dart';

/// Known (now), SPEC §8 and §16.17: a success on a day after the intro (or a
/// placement or carried-over card), the last answer not forgotten, and recall
/// still at [LearningConfig.knownMinR] or more. It decays on its own.
bool isKnown(CardState card, DateTime now, {Fsrs fsrs = const Fsrs()}) {
  final memory = card.memory;
  if (memory == null || !(card.lastRating?.isSuccess ?? false)) return false;
  final introAt = card.introAt;
  final laterDay =
      card.priorKnown ||
      introAt == null ||
      startOfDay(memory.lastReview).isAfter(startOfDay(introAt));
  return laterDay &&
      fsrs.retrievability(memory, now) >= LearningConfig.knownMinR;
}

extension CardLabels on CardState {
  /// Solid, SPEC §8: stability of [LearningConfig.solidDays] or more.
  bool get isSolid => (memory?.stability ?? 0) >= LearningConfig.solidDays;
}

/// The memory bar's states, strongest first (SPEC §8). Every card is at least Seen.
enum MemoryState { mastered, solid, known, seen }

/// Mastered, SPEC §8: stability of [LearningConfig.masteredDays] or more, the last answer a
/// success, and each name and ends card that applies ([sides], null where missing) at
/// [LearningConfig.masteredSideDays] or more.
bool isMastered(CardState card, {Iterable<CardState?> sides = const []}) =>
    (card.memory?.stability ?? 0) >= LearningConfig.masteredDays &&
    (card.lastRating?.isSuccess ?? false) &&
    sides.every(
      (s) => (s?.memory?.stability ?? 0) >= LearningConfig.masteredSideDays,
    );

/// A P card's name and ends cards that apply, null where missing (`Curriculum.sidesOf`).
typedef SidesOf = Iterable<CardState?> Function(CardState p);

MemoryState memoryState(
  CardState card,
  DateTime now, {
  Iterable<CardState?> sides = const [],
  Fsrs fsrs = const Fsrs(),
}) => isMastered(card, sides: sides)
    ? MemoryState.mastered
    : card.isSolid
    ? MemoryState.solid
    : isKnown(card, now, fsrs: fsrs)
    ? MemoryState.known
    : MemoryState.seen;
