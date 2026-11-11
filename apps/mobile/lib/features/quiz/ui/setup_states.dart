import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/quiz/ui/round_controller.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The `/round` states before question 1: loading (after 300 ms), not enough
/// streets, and an area the active pack doesn't have.
class SetupStates extends ConsumerWidget {
  const SetupStates({super.key, required this.state, required this.onRetry});

  final RoundState state;

  /// Starts the round again (after a difficulty change).
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider).value;
    final difficulty = settings?.difficulty ?? Difficulty.medium;
    return switch (state) {
      RoundNotEnough(:final count) => _Message(
        expression: PindoExpression.encouraging,
        title: l10n.setupSparseTitle,
        body:
            '${l10n.setupSparseCount(count, difficultyName(l10n, difficulty))} '
            '${l10n.setupSparseBody}',
        primary: switch (settings?.area) {
          RectArea() => l10n.setupSparseBiggerRectangle,
          CircleArea() => l10n.setupSparseBiggerCircle,
          _ => l10n.setupSparseAddNeighbour,
        },
        onPrimary: () => context.go(Routes.area),
        secondary: difficulty == Difficulty.expert
            ? null
            : l10n.setupSparseSwitchDifficulty(
                difficultyName(l10n, Difficulty.values[difficulty.index + 1]),
              ),
        onSecondary: () async {
          await ref
              .read(settingsDaoProvider)
              .chooseDifficulty(Difficulty.values[difficulty.index + 1]);
          await onRetry();
        },
      ),
      RoundAreaMissing() => _Message(
        expression: PindoExpression.thinking,
        title: l10n.areaNoneTitle,
        body: l10n.setupAreaMissingBody,
        primary: l10n.homeChooseArea,
        onPrimary: () => context.go(Routes.area),
      ),
      _ => const _Loading(),
    };
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.expression,
    required this.title,
    required this.body,
    required this.primary,
    required this.onPrimary,
    this.secondary,
    this.onSecondary,
  });

  final PindoExpression expression;
  final String title;
  final String body;
  final String primary;
  final VoidCallback onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final c = PindoroTheme.of(context).colors;
    return PageScaffold(
      title: '',
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: PindoroSpace.s3,
        children: [
          if (secondary != null)
            PindoroButton(
              label: secondary!,
              variant: PindoroButtonVariant.secondary,
              onPressed: onSecondary,
            ),
          PindoroButton(label: primary, onPressed: onPrimary),
        ],
      ),
      children: [
        const SizedBox(height: PindoroSpace.s8),
        Pindo(expression, height: 96),
        Text(
          title,
          textAlign: TextAlign.center,
          style: PindoroType.titleLg.copyWith(color: c.textPrimary),
        ),
        Text(
          body,
          textAlign: TextAlign.center,
          style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}

/// Nothing for 300 ms, then thinking Pindo and the lane loader (States rule).
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FutureBuilder<void>(
      future: Future<void>.delayed(const Duration(milliseconds: 300)),
      builder: (context, wait) {
        if (wait.connectionState != ConnectionState.done) {
          return const SizedBox.expand();
        }
        final c = PindoroTheme.of(context).colors;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: PindoroSpace.s4,
            children: [
              const Pindo(PindoExpression.thinking, height: 88),
              Text(
                context.l10n.setupLoading,
                style: PindoroType.titleMd.copyWith(color: c.textPrimary),
              ),
              const LaneLoader(),
              PindoroButton(
                label: context.l10n.commonCancel,
                variant: PindoroButtonVariant.tertiary,
                onPressed: () => context.go(Routes.home),
              ),
            ],
          ),
        );
      },
    ),
  );
}
