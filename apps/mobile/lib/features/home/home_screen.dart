import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/database.dart';
import '../../app/placeholder_screen.dart';
import '../../app/router.dart';

final _progressProvider = FutureProvider.autoDispose<LevelProgress>(
  (ref) async =>
      progressWithinLevel(await ref.watch(databaseProvider).totalXp()),
);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(_progressProvider).value;
    return PlaceholderScreen(
      title: 'Home',
      body: progress == null
          ? ''
          : 'Level ${progress.level} · '
                '${progress.xpIntoLevel} / ${progress.xpForLevel} xp',
      actions: [
        PindoroButton(
          label: 'Play',
          onPressed: () => context.push(Routes.quiz),
        ),
        PindoroButton(
          label: 'Settings',
          variant: PindoroButtonVariant.secondary,
          onPressed: () => context.push(Routes.settings),
        ),
      ],
    );
  }
}
