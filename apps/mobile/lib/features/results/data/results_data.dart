import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

/// One answered question with its street (null when retired from the pack).
typedef ResultEntry = ({Answer answer, NamedStreet? street});

typedef ResultsData = ({
  Round round,
  PackRepository pack,

  /// The round's area; [shape] is null when the pack lacks its districts.
  Area? area,
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
  final dao = ref.watch(progressDaoProvider);
  final pack = await ref.watch(packRepositoryProvider.future);
  final streets = await ref.watch(cityStreetsProvider.future);
  final progress = await dao.roundProgress(roundId);
  final round = progress.round;
  final answers = progress.answers;
  final bestBefore = await dao.bestTierByPart(
    round.cityId,
    before: round.startedAt,
  );
  final knownBefore = knownStreetIds(bestBefore, streets);
  final area = parseArea(round.areaJson);
  return (
    round: round,
    pack: pack,
    area: area,
    shape: area?.shapeIn(pack),
    entries: [
      for (final a in answers) (answer: a, street: streets[a.streetId]),
    ],
    totalXp: await dao.totalXp(),
    roundXp: answers.xp,
    retryCount: progress.retryIds.length,
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
