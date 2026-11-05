import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screens.dart';
import '../features/quiz/quiz_screen.dart';
import '../features/quiz/results_screen.dart';
import '../features/settings/settings_screen.dart';
import 'database.dart';

abstract final class Routes {
  static const String welcome = '/welcome';
  static const String city = '/city';
  static const String area = '/area';
  static const String difficulty = '/difficulty';
  static const String home = '/home';
  static const String quiz = '/quiz';
  static const String results = '/results';
  static const String settings = '/settings';
}

/// First run opens onboarding; afterwards the app starts at home.
Future<String> initialLocation(AppDatabase db) async =>
    (await db.readSettings()).onboardingDone ? Routes.home : Routes.welcome;

GoRouter buildRouter(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
    GoRoute(path: Routes.city, builder: (_, _) => const CityScreen()),
    GoRoute(path: Routes.area, builder: (_, _) => const AreaScreen()),
    GoRoute(
      path: Routes.difficulty,
      builder: (_, _) => const DifficultyScreen(),
    ),
    GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
    GoRoute(
      path: Routes.quiz,
      builder: (_, state) =>
          QuizScreen(roundId: state.uri.queryParameters['round']),
    ),
    GoRoute(
      path: Routes.results,
      redirect: (_, state) =>
          state.uri.queryParameters.containsKey('round') ? null : Routes.home,
      builder: (_, state) =>
          ResultsScreen(roundId: state.uri.queryParameters['round']!),
    ),
    GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
  ],
);
