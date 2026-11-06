import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../../app/database.dart';
import '../pack/sqlite_pack_repository.dart';
import 'round_controller.dart';

/// One answered question with its street (null when retired from the pack).
typedef ResultEntry = ({Answer answer, NamedStreet? street});

typedef ResultsData = ({
  Round round,
  AreaShape? shape,
  List<ResultEntry> entries,
  int totalXp,
  int roundXp,
  int retryCount,
  int newlyKnown,
});

/// Everything Results and its street view show for one round.
final resultsProvider = FutureProvider.autoDispose.family<ResultsData, String>((
  ref,
  roundId,
) async {
  final db = ref.watch(databaseProvider);
  final pack = await ref.watch(packRepositoryProvider.future);
  final progress = await db.roundProgress(roundId);
  final round = progress.round;
  final answers = progress.answers;
  final streets = {
    for (final q in resolveQuestions(pack, [
      for (final a in answers) a.streetId,
    ]))
      q.id: q.street,
  };
  final bestBefore = await db.bestTierByStreet(
    round.cityId,
    before: round.startedAt,
  );
  final names = pack.streetNames({
    ...bestBefore.keys,
    for (final a in answers) a.streetId,
  });
  final knownBefore = {
    for (final MapEntry(key: name, value: tier) in bestTierByName(
      bestBefore,
      names,
    ).entries)
      if (isKnownTier(tier)) name,
  };
  return (
    round: round,
    shape: parseArea(round.areaJson)?.shapeIn(pack),
    entries: [
      for (final a in answers) (answer: a, street: streets[a.streetId]),
    ],
    totalXp: await db.totalXp(),
    roundXp: answers.fold(0, (sum, a) => sum + a.xp),
    retryCount: (await db.retrySet(roundId)).length,
    newlyKnown: newlyKnown(
      knownBefore: knownBefore,
      roundAnswers: [
        for (final a in answers)
          if (names[a.streetId] case final name?) (name: name, tier: a.tier),
      ],
    ).length,
  );
});
