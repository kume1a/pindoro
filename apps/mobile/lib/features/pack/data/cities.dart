import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';

/// City ids the player has played, most recent first.
final recentCityIdsProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(progressDaoProvider).recentCityIds(),
);
