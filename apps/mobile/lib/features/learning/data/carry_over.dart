import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

/// Streets the old game knew (a Great or Perfect) in the open pack's city
/// become cards (PLAN M2 step 7): each known street without a card gets one,
/// once per pack opened.
final carryOverProvider = FutureProvider<void>((ref) async {
  final pack = await ref.watch(packRepositoryProvider.future);
  final streets = await ref.watch(cityStreetsProvider.future);
  final learning = ref.read(learningDaoProvider);
  final now = ref.read(clockProvider)();
  final carded = {
    for (final card in await learning.cards())
      if (streets[itemKey(card.itemId)] case final street?) street.id,
  };
  final known = knownStreetIds(
    await ref.read(progressDaoProvider).bestTierByPart(pack.city().id),
    streets,
  );
  final random = Random(startOfDay(now).millisecondsSinceEpoch);
  await learning.putCards([
    for (final id in known.toList()..sort())
      if (!carded.contains(id)) carriedOver(CardType.p.item(id), now, random),
  ]);
});
