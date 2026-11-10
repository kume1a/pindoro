import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/app/tab_shell.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/course/ui/path_screen.dart';
import 'package:pindoro/features/home/ui/home_screen.dart';
import 'package:pindoro/features/lesson/ui/drive_screen.dart';
import 'package:pindoro/features/lesson/ui/lesson_controller.dart';
import 'package:pindoro/features/lesson/ui/lesson_done_screen.dart';
import 'package:pindoro/features/lesson/ui/lesson_screen.dart';
import 'package:pindoro/features/lesson/ui/unit_done_screen.dart';
import 'package:pindoro/features/me/ui/me_screen.dart';
import 'package:pindoro/features/pitstop/ui/pit_stop_screen.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/quiz/ui/quiz_screen.dart';
import 'package:pindoro/features/results/ui/result_street_screen.dart';
import 'package:pindoro/features/results/ui/results_screen.dart';
import 'package:pindoro/features/settings/ui/settings_screen.dart';
import 'package:pindoro/features/setup/ui/area_screen.dart';
import 'package:pindoro/features/setup/ui/city_screen.dart';
import 'package:pindoro/features/setup/ui/difficulty_screen.dart';
import 'package:pindoro/features/setup/ui/start_district_screen.dart';
import 'package:pindoro/features/setup/ui/welcome_screen.dart';
import 'package:pindoro/features/setup/ui/whats_new_screen.dart';
import 'package:pindoro/features/streak/ui/streak_screen.dart';
import 'package:pindoro_core/pindoro_core.dart';
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

/// A started course opens on the Path, or in the lesson the app was killed
/// in. A player who finished a round before
/// any course started (Free play only, before the course existed) sees
/// What's new; a first round saved but unfinished opens Free play, which
/// offers to continue it; anyone else starts at Welcome.
Future<String> startLocation(AppDatabase db) async {
  final progress = ProgressDao(db);
  if (await progress.hasCourse()) {
    final saved = await progress.savedLesson(DateTime.now());
    return saved == null ? Routes.path : _lessonRoute(saved);
  }
  if (await progress.hasPlayed()) return Routes.whatsNew;
  return await progress.resumableRound(DateTime.now()) != null
      ? Routes.home
      : Routes.welcome;
}

/// A saved lesson reopens where the app was killed (canvas R4-02).
String _lessonRoute(SavedLesson saved) => saved.kind == LessonKind.pitStop
    ? Routes.unitPitStop(saved.unitId)
    : Routes.lessonOf(
        saved.unitId,
        saved.lesson!,
        practice: saved.kind == LessonKind.practice,
      );

/// `/lesson?unit=…&lesson=n` (`&practice=1`) or `?unit=…&pit-stop=1`; null
/// when it names neither.
LessonArgs? _lessonArgs(GoRouterState state) {
  final q = state.uri.queryParameters;
  final unitId = q['unit'];
  final lesson = int.tryParse(q['lesson'] ?? '');
  if (unitId == null) return null;
  if (q.containsKey('pit-stop')) {
    return (unitId: unitId, kind: LessonKind.pitStop, lesson: null);
  }
  if (lesson == null) return null;
  return (
    unitId: unitId,
    kind: q.containsKey('practice') ? LessonKind.practice : LessonKind.lesson,
    lesson: lesson,
  );
}

/// The tabs (Path, Free play, Pit stop, Me) share a [TabShell]; every other
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
          tab(TabShell.path, Routes.path, (_) => const PathScreen()),
          tab(
            TabShell.freePlay,
            Routes.home,
            (state) => HomeScreen(summary: state.extra as RoundSummary?),
          ),
          tab(TabShell.pitStop, Routes.pitStop, (_) => const PitStopScreen()),
          tab(TabShell.me, Routes.me, (_) => const MeScreen()),
        ],
      ),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.whatsNew, builder: (_, _) => const WhatsNewScreen()),
      GoRoute(
        path: Routes.city,
        builder: (_, state) =>
            CityScreen(course: state.uri.queryParameters.containsKey('course')),
      ),
      GoRoute(
        path: Routes.startDistrict,
        builder: (_, _) => const StartDistrictScreen(),
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
          pitStop: state.uri.queryParameters.containsKey('pit-stop'),
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
      GoRoute(
        path: Routes.lesson,
        redirect: (_, state) => _lessonArgs(state) == null ? Routes.path : null,
        builder: (_, state) => LessonScreen(args: _lessonArgs(state)!),
      ),
      GoRoute(
        path: Routes.lessonDone,
        redirect: (_, state) => state.uri.queryParameters.containsKey('result')
            ? null
            : Routes.path,
        pageBuilder: (_, state) => _fadePage(
          state,
          LessonDoneScreen(resultId: state.uri.queryParameters['result']!),
        ),
      ),
      GoRoute(
        path: Routes.drive,
        redirect: (_, state) =>
            state.uri.queryParameters.containsKey('unit') ? null : Routes.path,
        builder: (_, state) =>
            DriveScreen(unitId: state.uri.queryParameters['unit']!),
      ),
      GoRoute(
        path: Routes.unitDone,
        redirect: (_, state) =>
            state.uri.queryParameters.containsKey('unit') ? null : Routes.path,
        pageBuilder: (_, state) => _fadePage(
          state,
          UnitDoneScreen(unitId: state.uri.queryParameters['unit']!),
        ),
      ),
      GoRoute(path: Routes.streak, builder: (_, _) => const StreakScreen()),
      GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
      GoRoute(path: Routes.credits, builder: (_, _) => const CreditsScreen()),
    ],
  );
}
