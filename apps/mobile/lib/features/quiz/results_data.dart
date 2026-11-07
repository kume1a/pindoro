import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro_core/pindoro_core.dart';

import '../../app/database.dart';
import '../pack/sqlite_pack_repository.dart';

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
  bool firstPerfect,
});

/// Everything Results and its street view show for one round.
final resultsProvider = FutureProvider.autoDispose.family<ResultsData, String>((
  ref,
  roundId,
) async {
  final db = ref.watch(databaseProvider);
  final pack = await ref.watch(packRepositoryProvider.future);
  final streets = await ref.watch(cityStreetsProvider.future);
  final progress = await db.roundProgress(roundId);
  final round = progress.round;
  final answers = progress.answers;
  final bestBefore = await db.bestTierByPart(
    round.cityId,
    before: round.startedAt,
  );
  final knownBefore = {
    for (final MapEntry(key: id, value: tier) in bestTierPerStreet(
      bestBefore,
      streets,
    ).entries)
      if (isKnownTier(tier)) id,
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
          if (streets[a.streetId] case final s?) (street: s.id, tier: a.tier),
      ],
    ).length,
    // ponytail: first Perfect in this city, not across cities.
    firstPerfect:
        !bestBefore.values.contains(Tier.perfect) &&
        answers.any((a) => a.tier == Tier.perfect),
  );
});
