import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/settings/ui/landmark_add_screen.dart';
import 'package:pindoro/features/settings/ui/landmarks_screen.dart';
import 'package:pindoro/features/settings/ui/learn_settings_screen.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import '../../support/settle.dart';

void main() {
  late AppDatabase db;
  late List<PindoroMap> maps;
  late ({int junction, LatLng at, int node}) spot;

  setUpAll(() {
    final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
    final graph = repo.roadGraph()!;
    final nodes = repo.junctionNodes();
    // A junction where two named streets meet and a car can drive in.
    final junction = graph.junctions.keys.firstWhere(
      (j) =>
          graph.edgesAt(j).where((e) => e.streetId != null).length >= 3 &&
          graph.edgesAt(j).any((e) => graph.canDrive(e, e.other(j))),
    );
    spot = (junction: junction, at: graph.at(junction), node: nodes[junction]!);
    repo.close();
  });

  setUp(() {
    maps = [];
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1080, 4400)
      ..devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          pindoroMapBuilderProvider.overrideWithValue((map) {
            maps.add(map);
            return const SizedBox.expand();
          }),
          packRepositoryProvider.overrideWith((ref) async {
            final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
            ref.onDispose(repo.close);
            return repo;
          }),
        ],
        // Learning settings and the landmark screens alone, outside the
        // app shell.
        child: MaterialApp.router(
          theme: buildPindoroTheme(Brightness.light),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          routerConfig: GoRouter(
            initialLocation: Routes.learnSettings,
            routes: [
              GoRoute(
                path: Routes.learnSettings,
                builder: (_, _) => const LearnSettingsScreen(),
              ),
              GoRoute(
                path: Routes.landmarks,
                builder: (_, _) => const LandmarksScreen(),
              ),
              GoRoute(
                path: Routes.landmarkAdd,
                builder: (_, _) => const LandmarkAddScreen(),
              ),
            ],
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'a landmark is marked on the map, snapped, named, listed and deleted',
    timeout: const Timeout(Duration(minutes: 1)),
    (tester) async {
      await pump(tester);
      expect(find.text('Add the places you steer by'), findsOneWidget);
      await tapThrough(tester, find.text('Your landmarks'));
      expect(find.textContaining('Turn cards then name them'), findsOneWidget);
      await tapThrough(tester, find.text('Add a landmark'));

      expect(find.textContaining('Tap the map where it is'), findsOneWidget);
      maps.last.onTap!(
        LatLng(spot.at.lat + 0.0002, spot.at.lon),
      ); // about 22 m off
      await settle(tester);
      expect(maps.last.pin, spot.at, reason: 'snapped to the junction');
      expect(maps.last.frame, isNotNull, reason: 'the junction is framed');
      expect(maps.last.bottomInset, greaterThan(0), reason: 'above the panel');
      // The form waits for Next, so the map keeps its room to re-pick.
      expect(find.byType(TextField), findsNothing);
      final picking = maps.last.bottomInset;
      await tapThrough(tester, find.text('Next'));
      expect(find.textContaining('Seen driving'), findsWidgets);
      expect(maps.last.bottomInset, greaterThan(picking));
      await tapThrough(tester, find.text('Change spot'));
      expect(find.byType(TextField), findsNothing);
      await tapThrough(tester, find.text('Next'));

      // The keyboard lifts the panel, Save and all, instead of hiding it.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 2.75);
      await tester.pump();
      final screen =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(
        tester.getBottomLeft(find.text('Save landmark')).dy,
        lessThan(screen - 300),
      );
      tester.view.resetViewInsets();
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Connect fuel station');
      await settle(tester);
      await tapThrough(tester, find.text('Church'));
      await tapThrough(tester, find.text('On your left'));
      await tapThrough(tester, find.text('Save landmark'));

      final saved = (await tester.runAsync(LearningDao(db).personalLandmarks))!;
      expect(saved.single.name, 'Connect fuel station');
      expect(
        (saved.single.kind, saved.single.junctionId, saved.single.side),
        ('worship', 'n${spot.node}', 'left'),
      );
      expect(find.text('Connect fuel station'), findsOneWidget);
      expect(find.textContaining('Church · '), findsOneWidget);

      await tapThrough(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w is PindoroIconButton &&
              w.semanticLabel == 'Delete Connect fuel station',
        ),
      );
      await tapThrough(tester, find.text('Delete'));
      expect(await tester.runAsync(LearningDao(db).personalLandmarks), isEmpty);
      expect(find.text('Connect fuel station'), findsNothing);
    },
  );
}
