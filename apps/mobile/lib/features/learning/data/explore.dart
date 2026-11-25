import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/features/learning/data/cards.dart';
import 'package:pindoro/features/learning/data/day.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Feeds an Explore pin to the learning cards (SPEC §16.16): graded like a
/// session pin, it reviews a due or nearly due card, creates one for a
/// first-sight Good or Easy, and is only logged otherwise. Then marks the
/// day when it counts. Everything it reads from [ref] is taken before the
/// first await: the round may be left while the pin saves. No [pin] is "I don't know".
Future<void> learnFromExplore(
  Ref ref, {
  required NamedStreet street,
  required LatLng? pin,
  required int rtMs,
  required String roundId,
}) async {
  final dao = ref.read(learningDaoProvider);
  final now = ref.read(clockProvider)();
  final streetsFuture = ref.read(cityStreetsProvider.future);
  final curriculumFuture = ref.read(curriculumProvider.future);
  final markDay = dayMarker(ref, roundId: roundId);
  final streets = await streetsFuture;
  final curriculum = await curriculumFuture;
  final all = streets.values.toSet();
  final card = await _cardOf(dao, street);
  final itemId = card?.itemId ?? CardType.p.item(street.id);
  final successes = priorSuccesses(await dao.log())[itemId] ?? 0;
  final grade = pin == null
      ? null
      : Grader.gradePin(
          pin: pin,
          target: street,
          nearby: all,
          confusable: confusablesOf(
            street,
            all,
            await dao.confusionPairs(),
            family: curriculum.familyOf(street.id),
          ),
          rtMs: rtMs,
          priorSuccesses: successes,
        );
  final result = exploreAnswer(
    card,
    itemId: itemId,
    grade: grade,
    now: now,
    rtMs: rtMs,
    sessionId: roundId,
  );
  await dao.saveAnswer(card: result.card, log: result.log);
  await markDay();
}

/// The street's P card, on whichever of its parts it was made.
Future<CardState?> _cardOf(LearningDao dao, NamedStreet street) async {
  for (final part in street.parts) {
    if (await dao.card(CardType.p.item(part.id)) case final card?) return card;
  }
  return null;
}
