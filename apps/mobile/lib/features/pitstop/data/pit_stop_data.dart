import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

typedef PitStopEntry = ({ReviewItem item, NamedStreet street});

typedef PitStopData = ({
  DateTime today,

  /// Due streets still in the pack, most overdue first.
  List<PitStopEntry> due,

  /// The first day after today with streets due, and how many; null when
  /// nothing waits.
  ({DateTime day, int count})? next,

  /// The last Pit stop round's answers by tier; empty before the first.
  Map<Tier, int> lastTally,
});

/// The open city's Pit stop, for its screen.
final pitStopProvider = FutureProvider.autoDispose<PitStopData>((ref) async {
  ref.watch(progressChangesProvider);
  final dao = ref.watch(progressDaoProvider);
  final pack = await ref.watch(packRepositoryProvider.future);
  final streets = await ref.watch(cityStreetsProvider.future);
  final cityId = pack.city().id;
  final today = calendarDay(DateTime.now());
  final items = await dao.pitStop(cityId);
  final later = items.laterIn(streets, today);
  final tally = <Tier, int>{};
  for (final a in await dao.lastPitStopAnswers(cityId)) {
    tally.update(a.tier, (n) => n + 1, ifAbsent: () => 1);
  }
  return (
    today: today,
    due: [
      for (final i in items.dueIn(streets, today))
        (item: i, street: streets[i.streetId]!),
    ],
    next: later.isEmpty
        ? null
        : (
            day: parseDayKey(later.first.dueOn),
            count: later.where((i) => i.dueOn == later.first.dueOn).length,
          ),
    lastTally: tally,
  );
});
