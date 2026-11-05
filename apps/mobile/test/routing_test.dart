import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/app/database.dart';
import 'package:pindoro/app/router.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester, String location) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: PindoroApp(initialLocation: location),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, String label) async {
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
      // Drift work happens on real async; give it a moment to finish.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'onboarding walks welcome -> city -> area -> difficulty -> home',
    (tester) async {
      await pumpApp(tester, Routes.welcome);
      expect(find.text('პინდორო'), findsOneWidget);

      await tapAndSettle(tester, 'Start');
      expect(find.text('City'), findsOneWidget);
      await tapAndSettle(tester, 'Tbilisi');
      expect(find.text('Area'), findsOneWidget);
      await tapAndSettle(tester, 'Vake');
      expect(find.text('Difficulty'), findsOneWidget);
      await tapAndSettle(tester, 'expert');
      expect(find.text('Home'), findsOneWidget);

      final settings = await tester.runAsync(db.readSettings);
      expect(settings!.onboardingDone, isTrue);
      expect(settings.lastCity, 'tbilisi');
      expect(settings.lastDifficulty, Difficulty.expert);
    },
  );

  testWidgets('home opens settings with the OSM attribution', (tester) async {
    await pumpApp(tester, Routes.home);
    expect(find.text('Play'), findsOneWidget);

    await tapAndSettle(tester, 'Settings');
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
  });

  testWidgets('results shows one badge per tier', (tester) async {
    await pumpApp(tester, Routes.results);
    expect(find.byType(FeedbackBadge), findsNWidgets(Tier.values.length));
  });
}
