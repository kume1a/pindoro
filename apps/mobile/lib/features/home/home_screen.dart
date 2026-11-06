import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/database.dart';
import '../../app/placeholder_screen.dart';
import '../../app/router.dart';
import '../pack/sqlite_pack_repository.dart';
import 'level_bar.dart';

typedef _Home = ({
  Settings settings,
  String? areaName,
  int totalXp,
  Round? resumable,
  int answered,
  int planned,
});

final _homeProvider = FutureProvider.autoDispose<_Home>((ref) async {
  final db = ref.watch(databaseProvider);
  final pack = await ref.watch(packRepositoryProvider.future);
  final settings = await db.readSettings();
  final resumable = await db.savedRound(DateTime.now());
  final progress = resumable == null
      ? null
      : await db.roundProgress(resumable.id);
  return (
    settings: settings,
    areaName: settings.area?.shapeIn(pack)?.name,
    totalXp: await db.totalXp(),
    resumable: resumable,
    answered: progress?.answers.length ?? 0,
    planned: progress?.planned.length ?? 0,
  );
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(_homeProvider).value;
    if (home == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // Back from a pushed screen: the round or progress may have changed.
    Future<void> open(String location) async {
      await context.push(location);
      if (context.mounted) ref.invalidate(_homeProvider);
    }

    final difficulty = home.settings.lastDifficulty ?? Difficulty.easy;
    final resumable = home.resumable;
    return PlaceholderScreen(
      title: 'Home',
      body: '${home.areaName ?? 'Pick an area'} · ${difficulty.name}',
      actions: [
        if (resumable != null) ...[
          PindoroButton(
            label: 'Continue (${home.answered}/${home.planned})',
            onPressed: () => open('${Routes.quiz}?round=${resumable.id}'),
          ),
          PindoroButton(
            label: 'New round',
            variant: PindoroButtonVariant.secondary,
            onPressed: () => open(Routes.quiz),
          ),
        ] else
          PindoroButton(label: 'Play', onPressed: () => open(Routes.quiz)),
        PindoroButton(
          label: 'Change area',
          variant: PindoroButtonVariant.tertiary,
          onPressed: () => open(Routes.area),
        ),
        PindoroButton(
          label: 'Settings',
          variant: PindoroButtonVariant.tertiary,
          onPressed: () => open(Routes.settings),
        ),
      ],
      child: Align(
        alignment: Alignment.topCenter,
        child: LevelBar(home.totalXp),
      ),
    );
  }
}
