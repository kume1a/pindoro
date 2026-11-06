import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screens.dart';
import '../features/quiz/quiz_screen.dart';
import '../features/quiz/results_screen.dart';
import '../features/settings/settings_screen.dart';
import 'database.dart';

/// Paths from docs/design/v1-screens.md § Navigation.
abstract final class Routes {
  static const String home = '/';
  static const String welcome = '/welcome';
  static const String city = '/city';
  static const String area = '/area';
  static const String difficulty = '/difficulty';

  /// `?round=<id>` resumes, `?retry=<id>` plays that round's missed streets.
  static const String round = '/round';

  /// `?round=<id>`; `/results/street/<index>?round=<id>` opens one answer.
  static const String results = '/results';
  static const String settings = '/settings';
  static const String credits = '/settings/credits';

  static String resume(String roundId) => '$round?round=$roundId';
  static String retry(String roundId) => '$round?retry=$roundId';
  static String resultsOf(String roundId) => '$results?round=$roundId';
  static String resultStreet(String roundId, int index) =>
      '$results/street/$index?round=$roundId';
}

/// Welcome shows until the player finishes a first round; then Home.
Future<String> initialLocation(AppDatabase db) async =>
    await db.hasFinishedRound() ? Routes.home : Routes.welcome;

GoRouter buildRouter(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
    GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
    GoRoute(path: Routes.city, builder: (_, _) => const CityScreen()),
    GoRoute(path: Routes.area, builder: (_, _) => const AreaScreen()),
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
      builder: (_, state) =>
          ResultsScreen(roundId: state.uri.queryParameters['round']!),
    ),
    GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
    GoRoute(path: Routes.credits, builder: (_, _) => const CreditsScreen()),
  ],
);
