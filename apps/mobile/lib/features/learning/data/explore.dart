import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/features/learning/data/day.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/today_plan.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Feeds an Explore pin to the learning cards (SPEC §16.16): graded like a
/// session pin, it reviews a due or nearly due card, creates one for a
/// first-sight Good or Easy, and is only logged otherwise. Then marks the
/// day when it counts.
Future<void> learnFromExplore(
  Ref ref, {
  required NamedStreet street,
  required LatLng pin,
  required int rtMs,
  required String roundId,
}) async {
  final dao = ref.read(learningDaoProvider);
  final now = ref.read(clockProvider)();
  final streets = await ref.read(cityStreetsProvider.future);
  final curriculum = await ref.read(curriculumProvider.future);
  final all = streets.values.toSet();
  final itemId = CardType.p.item(street.id);
  final successes = (await dao.log())
      .where((e) => e.itemId == itemId && e.rating.isSuccess)
      .length;
  final grade = Grader.gradePin(
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
    await dao.card(itemId),
    itemId: itemId,
    grade: grade,
    now: now,
    rtMs: rtMs,
    sessionId: roundId,
  );
  await dao.saveAnswer(card: result.card, log: result.log);
  await markDayIfCounts(ref, roundId: roundId);
}
