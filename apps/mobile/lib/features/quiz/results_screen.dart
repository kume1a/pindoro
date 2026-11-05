import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/database.dart';
import '../../app/placeholder_screen.dart';
import '../../app/router.dart';
import '../home/level_bar.dart';
import '../pack/sqlite_pack_repository.dart';
import 'answer_row.dart';

typedef _Results = ({
  List<Answer> answers,
  Map<String, String> names,
  int totalXp,
});

final _resultsProvider = FutureProvider.autoDispose.family<_Results, String>((
  ref,
  roundId,
) async {
  final db = ref.watch(databaseProvider);
  final pack = await ref.watch(packRepositoryProvider.future);
  final answers = await db.answersForRound(roundId);
  return (
    answers: answers,
    names: pack.streetNames(answers.map((a) => a.streetId)),
    totalXp: await db.totalXp(),
  );
});

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(_resultsProvider(roundId)).value;
    if (results == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final roundXp = results.answers.fold(0, (sum, a) => sum + a.xp);
    final levelUp =
        levelForXp(results.totalXp) > levelForXp(results.totalXp - roundXp);
    return PlaceholderScreen(
      title: 'Results',
      body: '+$roundXp xp this round${levelUp ? ' · level up!' : ''}',
      actions: [
        PindoroButton(label: 'Done', onPressed: () => context.go(Routes.home)),
      ],
      child: Column(
        spacing: PindoroTokens.spaceMd,
        children: [
          LevelBar(results.totalXp),
          Expanded(
            child: ListView(
              children: [
                for (final a in results.answers)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: PindoroTokens.spaceXs,
                    ),
                    child: AnswerRow(
                      a,
                      name: results.names[a.streetId] ?? a.streetId,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
