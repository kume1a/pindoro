import 'dart:math';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/features/lesson/ui/lesson_controller.dart';
import 'package:pindoro/features/lesson/ui/lesson_screen.dart';
import 'package:pindoro/features/map/ui/pindoro_map.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro/features/progress/data/reminders.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  const unit = AppConfig.fixtureDistrictId;
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

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester, String location) async {
    // The Path's current stop floats for good; settle without motion.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          remindersProvider.overrideWithValue(_NoReminders()),
          pindoroMapBuilderProvider.overrideWithValue(
            (map) => const SizedBox.expand(),
          ),
          lessonRandomProvider.overrideWithValue(Random(5)),
          packRepositoryProvider.overrideWith((ref) async {
            final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
            ref.onDispose(repo.close);
            return repo;
          }),
        ],
        child: PindoroApp(initialLocation: location),
      ),
    );
    await settle(tester);
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
  }

  testWidgets('a lesson from the first card to Lesson complete and back', (
    tester,
  ) async {
    await pumpApp(tester, Routes.lessonOf(unit, 1));
    expect(find.text('New street · 1 of 4'), findsOneWidget);
    expect(find.text('Where it is'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tap(tester, find.text('Got it'));
    }
    expect(find.text('New street · 4 of 4'), findsOneWidget);
    await tap(tester, find.text('Start the test'));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LessonScreen)),
    );
    for (var i = 0; i < 6; i++) {
      final p = container.read(lessonControllerProvider) as LessonPlaying;
      switch (p.run.step) {
        case final PinStep step:
          container
              .read(lessonControllerProvider.notifier)
              .placePin(step.street.geometry.first.first);
          await settle(tester);
          await tap(tester, find.text('Confirm'));
          await tap(tester, find.text('Next'));
        case final NameStep step:
          expect(find.text('Which street is this?'), findsOneWidget);
          await tap(tester, find.text(streetName(step.street, null)));
          await tap(tester, find.text('Check'));
          expect(find.text('Correct!'), findsOneWidget);
          await tap(tester, find.text('Continue'));
        case CardStep():
          fail('no cards after the test starts');
        case TripStep():
          fail('no road trip in this lesson');
      }
    }
    await settle(tester);
    expect(find.text('Perfect lesson!'), findsOneWidget);
    expect(find.bySemanticsLabel('Accuracy, 100 %'), findsOneWidget);
    expect(find.bySemanticsLabel('New streets, 4'), findsOneWidget);

    await tap(tester, find.text('Continue'));
    await settle(tester);
    expect(find.text('1 of 6 lessons'), findsOneWidget);
  });

  testWidgets('leaving asks first and writes nothing', (tester) async {
    await pumpApp(tester, Routes.lessonOf(unit, 1));
    await tap(tester, find.bySemanticsLabel('Leave the lesson'));
    expect(find.text('Leave this lesson?'), findsOneWidget);
    await tap(tester, find.text('Keep learning'));
    expect(find.text('New street · 1 of 4'), findsOneWidget);

    await tap(tester, find.bySemanticsLabel('Leave the lesson'));
    await tap(tester, find.text('Leave'));
    expect(find.text('0 of 6 lessons'), findsOneWidget);
    expect(await tester.runAsync(ProgressDao(db).hasPlayed), isFalse);
  });
}

class _NoReminders implements Reminders {
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(ReminderNotice notice) async {}

  @override
  Future<void> cancel() async {}
}
