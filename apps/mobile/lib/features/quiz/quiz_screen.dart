import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../app/database.dart';
import '../../app/placeholder_screen.dart';
import '../../app/router.dart';
import '../map/pindoro_map.dart';
import 'answer_row.dart';
import 'round_controller.dart';

/// Plays a round: resumes [roundId], retries [retryOf]'s missed streets, or
/// starts one from the saved area and difficulty.
class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key, this.roundId, this.retryOf});

  final String? roundId;
  final String? retryOf;

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  @override
  void initState() {
    super.initState();
    // Providers can't change while the tree builds; begin right after.
    Future.microtask(_begin);
  }

  Future<void> _begin() async {
    final controller = ref.read(roundControllerProvider.notifier);
    final roundId = widget.roundId;
    if (roundId != null) return controller.resume(roundId);
    final retryOf = widget.retryOf;
    if (retryOf != null) return controller.startRetry(retryOf);
    final settings = await ref.read(databaseProvider).readSettings();
    await controller.start(
      settings.area,
      settings.lastDifficulty ?? Difficulty.easy,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(roundControllerProvider, (_, next) {
      if (next is RoundFinished) {
        context.go(Routes.resultsOf(next.roundId));
      }
    });
    return switch (ref.watch(roundControllerProvider)) {
      final RoundInPlay play => Scaffold(body: _Playing(play)),
      RoundNotEnough(:final count) => _Blocked(
        'This area has only $count streets at this difficulty.',
      ),
      RoundAreaMissing() => const _Blocked(
        'This area is not in the installed city pack.',
      ),
      RoundLoading() || RoundFinished() => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class _Playing extends ConsumerWidget {
  const _Playing(this.play);

  final RoundInPlay play;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(roundControllerProvider.notifier);
    final round = play.round;
    final pin = play.pin;
    final revealed = switch (play) {
      final RoundRevealed r => r,
      RoundAsking() => null,
    };
    return Stack(
      children: [
        ref.watch(pindoroMapBuilderProvider)(
          PindoroMap(
            area: round.shape,
            pin: pin,
            truth: revealed?.round.current.geometry,
            measure: revealed == null ? null : (pin!, revealed.nearest),
            onTap: revealed == null ? controller.placePin : null,
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(PindoroSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: PindoroSpace.s2,
              children: [
                StreetPlate(round.current.name),
                Text(
                  '${round.number} / ${round.total}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (revealed != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(PindoroSpace.s4),
                      child: AnswerRow(revealed.answer),
                    ),
                  ),
                if (revealed == null)
                  PindoroButton(
                    label: 'Confirm',
                    onPressed: pin == null
                        ? null
                        : () => unawaited(controller.confirm()),
                  )
                else
                  PindoroButton(
                    label: round.isLast ? 'See results' : 'Next',
                    onPressed: () => unawaited(controller.next()),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A round can't start here; send the player to change area or difficulty.
class _Blocked extends StatelessWidget {
  const _Blocked(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
    title: 'Round',
    body: message,
    actions: [
      PindoroButton(
        label: 'Pick an area',
        onPressed: () => context.push(Routes.area),
      ),
      PindoroButton(
        label: 'Pick a difficulty',
        variant: PindoroButtonVariant.secondary,
        onPressed: () => context.push(Routes.difficulty),
      ),
    ],
  );
}
