import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/app/tab_shell.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/account/ui/account_screen.dart';
import 'package:pindoro/features/drive/ui/drive_screen.dart';
import 'package:pindoro/features/home/ui/home_screen.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/me/ui/me_screen.dart';
import 'package:pindoro/features/memory/ui/district_progress_screen.dart';
import 'package:pindoro/features/memory/ui/progress_screen.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/quiz/ui/quiz_screen.dart';
import 'package:pindoro/features/results/ui/result_street_screen.dart';
import 'package:pindoro/features/results/ui/results_screen.dart';
import 'package:pindoro/features/session/ui/session_screen.dart';
import 'package:pindoro/features/settings/ui/anchor_screen.dart';
import 'package:pindoro/features/settings/ui/landmark_add_screen.dart';
import 'package:pindoro/features/settings/ui/landmarks_screen.dart';
import 'package:pindoro/features/settings/ui/learn_settings_screen.dart';
import 'package:pindoro/features/settings/ui/settings_screen.dart';
import 'package:pindoro/features/setup/ui/area_screen.dart';
import 'package:pindoro/features/setup/ui/city_screen.dart';
import 'package:pindoro/features/setup/ui/difficulty_screen.dart';
import 'package:pindoro/features/setup/ui/welcome_screen.dart';
import 'package:pindoro/features/streak/ui/streak_screen.dart';
import 'package:pindoro/features/today/ui/today_screen.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// The tabs and Results arrive with a fade rather than a slide (canvas M-40,
/// M-43).
Page<void> _fadePage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: PindoroMotion.durationFast,
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );

/// A saved Explore round reopens Explore, which offers to continue it; a
/// player who placed a city (or finished a round) opens Today; anyone else
/// starts at Welcome.
Future<String> startLocation(AppDatabase db) async {
  final progress = ProgressDao(db);
  if (await progress.resumableRound(DateTime.now()) != null) {
    return Routes.home;
  }
  return await progress.hasPlayed() ? Routes.today : Routes.welcome;
}

/// The tabs (Today, Explore, Progress, Me) share a [TabShell]; every other
/// route sits on the root navigator, over the bottom navigation.
GoRouter buildRouter(String initialLocation) {
  // ponytail: one per tab, as long as the router (the app) lives.
  final scroll = [for (var i = 0; i < TabShell.tabs; i++) ScrollController()];
  StatefulShellBranch tab(
    int index,
    String path,
    Widget Function(GoRouterState state) screen,
  ) => StatefulShellBranch(
    routes: [
      GoRoute(
        path: path,
        builder: (_, state) => PrimaryScrollController(
          controller: scroll[index],
          child: screen(state),
        ),
      ),
    ],
  );

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute(
        pageBuilder: (_, state, shell) =>
            _fadePage(state, TabShell(shell: shell, scroll: scroll)),
        navigatorContainerBuilder: (_, shell, children) =>
            FadeIndexedStack(index: shell.currentIndex, children: children),
        branches: [
          tab(TabShell.today, Routes.today, (_) => const TodayScreen()),
          tab(
            TabShell.explore,
            Routes.home,
            (state) => HomeScreen(summary: state.extra as RoundSummary?),
          ),
          tab(
            TabShell.progress,
            Routes.progress,
            (_) => const ProgressScreen(),
          ),
          tab(TabShell.me, Routes.me, (_) => const MeScreen()),
        ],
      ),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(
        path: Routes.city,
        builder: (_, state) =>
            CityScreen(learn: state.uri.queryParameters.containsKey('learn')),
      ),
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
        redirect: _requires('round', otherwise: Routes.home),
        pageBuilder: (_, state) =>
            _fadePage(state, ResultsScreen(roundId: _param(state, 'round'))),
        routes: [
          GoRoute(
            path: 'street/:index',
            builder: (_, state) => ResultStreetScreen(
              roundId: _param(state, 'round'),
              index: int.parse(state.pathParameters['index']!),
            ),
          ),
        ],
      ),
      GoRoute(path: Routes.streak, builder: (_, _) => const StreakScreen()),
      GoRoute(path: Routes.account, builder: (_, _) => const AccountScreen()),
      GoRoute(
        path: Routes.accountPassword,
        builder: (_, _) => const ChangePasswordScreen(),
      ),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
      GoRoute(path: Routes.credits, builder: (_, _) => const CreditsScreen()),
      GoRoute(
        path: Routes.session,
        builder: (_, state) => SessionScreen(
          placement: state.uri.queryParameters.containsKey('placement'),
          more: state.uri.queryParameters.containsKey('more'),
        ),
      ),
      GoRoute(
        path: Routes.progressDistrict,
        builder: (_, state) =>
            DistrictProgressScreen(id: state.uri.queryParameters['id'] ?? ''),
      ),
      GoRoute(
        path: Routes.learnSettings,
        builder: (_, _) => const LearnSettingsScreen(),
      ),
      GoRoute(
        path: Routes.anchor,
        builder: (_, state) => AnchorScreen(
          anchor: state.uri.queryParameters['which'] == 'work'
              ? Anchor.work
              : Anchor.home,
        ),
      ),
      GoRoute(
        path: Routes.landmarks,
        builder: (_, _) => const LandmarksScreen(),
      ),
      GoRoute(
        path: Routes.landmarkAdd,
        builder: (_, _) => const LandmarkAddScreen(),
      ),
      GoRoute(path: Routes.drive, builder: (_, _) => const DriveScreen()),
    ],
  );
}

/// Sends a route opened without its [key] query parameter to [otherwise].
GoRouterRedirect _requires(String key, {String otherwise = Routes.today}) =>
    (_, state) => state.uri.queryParameters.containsKey(key) ? null : otherwise;

/// A query parameter its route's [_requires] made sure of.
String _param(GoRouterState state, String key) =>
    state.uri.queryParameters[key]!;
