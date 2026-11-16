import 'cards.dart';
import 'constants.dart';
import 'fsrs.dart';
import 'planner.dart';

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

/// City memory, SPEC §8: the recall chance summed over the core streets'
/// cards, so "streets you'd place right now"; unseen streets add nothing.
double cityMemory(
  Iterable<CardState> cards,
  DateTime now, {
  required bool Function(String itemId) isCore,
  Fsrs fsrs = const Fsrs(),
}) => cards
    .where((c) => c.memory != null && isCore(c.itemId))
    .fold(0, (sum, c) => sum + fsrs.retrievability(c.memory!, now));
