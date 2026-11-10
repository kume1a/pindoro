import 'dart:async';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_design/pindoro_design.dart';

void main() {
  testWidgets(
    'a slow course: nothing, then skeletons, then what is happening',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      addTearDown(db.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            packRepositoryProvider.overrideWith((ref) async {
              final repo = SqlitePackRepository.open(
                AppConfig.fixturePackAsset,
              );
              ref.onDispose(repo.close);
              return repo;
            }),
            courseProvider.overrideWith(
              (ref) => Completer<CourseData?>().future,
            ),
          ],
          child: PindoroApp(initialLocation: Routes.path),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Skeleton), findsNothing);

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(Skeleton), findsNWidgets(5));
      expect(find.text('Laying out your course'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Laying out your course'), findsOneWidget);
      expect(
        find.textContaining('districts and their streets'),
        findsOneWidget,
      );
      expect(find.byType(LaneLoader), findsOneWidget);
    },
  );
}
