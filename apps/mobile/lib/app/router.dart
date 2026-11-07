import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/home/ui/home_screen.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/quiz/ui/quiz_screen.dart';
import 'package:pindoro/features/results/ui/result_street_screen.dart';
import 'package:pindoro/features/results/ui/results_screen.dart';
import 'package:pindoro/features/settings/ui/settings_screen.dart';
import 'package:pindoro/features/setup/ui/area_screen.dart';
import 'package:pindoro/features/setup/ui/city_screen.dart';
import 'package:pindoro/features/setup/ui/difficulty_screen.dart';
import 'package:pindoro/features/setup/ui/welcome_screen.dart';
import 'package:pindoro/features/streak/ui/streak_screen.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Home and Results arrive with a fade rather than a slide (canvas M-40, M-43).
Page<void> _fadePage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: PindoroMotion.durationFast,
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );

/// Welcome shows until the player finishes a first round or has one saved
/// (Home offers to continue it); then Home.
Future<String> startLocation(AppDatabase db) async {
  final progress = ProgressDao(db);
  return await progress.hasFinishedRound() ||
          await progress.resumableRound(DateTime.now()) != null
      ? Routes.home
      : Routes.welcome;
}

GoRouter buildRouter(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: Routes.home,
      pageBuilder: (_, state) =>
          _fadePage(state, HomeScreen(summary: state.extra as RoundSummary?)),
    ),
    GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
    GoRoute(path: Routes.city, builder: (_, _) => const CityScreen()),
    GoRoute(
      path: Routes.area,
      builder: (_, state) =>
          AreaScreen(district: state.uri.queryParameters['district']),
    ),
    GoRoute(
      path: Routes.difficulty,
      builder: (_, _) => const DifficultyScreen(),
    ),
    GoRoute(
      path: Routes.round,
      builder: (_, state) => QuizScreen(
        roundId: state.uri.queryParameters['round'],
        retryOf: state.uri.queryParameters['retry'],
      ),
    ),
    GoRoute(
      path: Routes.results,
      redirect: (_, state) =>
          state.uri.queryParameters.containsKey('round') ? null : Routes.home,
      pageBuilder: (_, state) => _fadePage(
        state,
        ResultsScreen(roundId: state.uri.queryParameters['round']!),
      ),
      routes: [
        GoRoute(
          path: 'street/:index',
          builder: (_, state) => ResultStreetScreen(
            roundId: state.uri.queryParameters['round']!,
            index: int.parse(state.pathParameters['index']!),
          ),
        ),
      ],
    ),
    GoRoute(path: Routes.streak, builder: (_, _) => const StreakScreen()),
    GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
    GoRoute(path: Routes.credits, builder: (_, _) => const CreditsScreen()),
  ],
);
