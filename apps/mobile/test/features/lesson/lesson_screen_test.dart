import 'dart:math';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/app/app.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/speech.dart';
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

  Future<void> pumpApp(
    WidgetTester tester,
    String location, {
    bool screenReader = false,
    Speech? speech,
  }) async {
    // The Path's current stop floats for good; settle without motion.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(
          disableAnimations: true,
          accessibleNavigation: screenReader,
        );
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
          speechProvider.overrideWithValue(speech ?? _FakeSpeech()),
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
          fail('the road trip comes last');
      }
    }

    // Step 11: the first road trip ever, drawn along the best route.
    expect(find.text('Road trip: draw the shortest drive to'), findsOneWidget);
    expect(find.text('Drag from A along the streets to B'), findsOneWidget);
    final trip = container.read(lessonControllerProvider) as LessonPlaying;
    var route = trip.route!;
    for (final e in (trip.run.step as TripStep).trip.best.edges) {
      route = route.take(e);
    }
    container.read(lessonControllerProvider.notifier).drawTo(route);
    await settle(tester);
    await tap(tester, find.text('Check route'));
    expect(find.text('Best route!'), findsOneWidget);
    await tap(tester, find.text('Next'));
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

  testWidgets('Hear the name reads the plate in its language', (tester) async {
    await pumpApp(tester, Routes.lessonOf(unit, 1));
    expect(find.bySemanticsLabel('Hear the name'), findsNothing);

    final speech = _FakeSpeech({'ka-GE'});
    await pumpApp(tester, Routes.lessonOf(unit, 1), speech: speech);
    final step =
        (ProviderScope.containerOf(
                  tester.element(find.byType(LessonScreen)),
                ).read(lessonControllerProvider)
                as LessonPlaying)
            .run
            .step;
    await tap(tester, find.bySemanticsLabel('Hear the name'));
    expect(speech.said, [(step.street.name, 'ka-GE')]);
  });

  /// Plays every step right up to the road trip.
  Future<void> toTrip(WidgetTester tester, ProviderContainer container) async {
    final controller = container.read(lessonControllerProvider.notifier);
    LessonPlaying play() =>
        container.read(lessonControllerProvider) as LessonPlaying;
    while (play().run.step is! TripStep) {
      switch (play().run.step) {
        case final PinStep step:
          controller
            ..placePin(step.street.geometry.first.first)
            ..confirm();
        case final NameStep step:
          controller
            ..choose(step.options.indexOf(step.street))
            ..check();
        case CardStep() || TripStep():
      }
      await controller.next();
    }
    await settle(tester);
  }

  testWidgets('Choose turns from a list gives the list without a reader', (
    tester,
  ) async {
    await tester.runAsync(() => SettingsDao(db).setTurnList(on: true));
    await pumpApp(tester, Routes.lessonOf(unit, 1));
    await toTrip(
      tester,
      ProviderScope.containerOf(tester.element(find.byType(LessonScreen))),
    );
    expect(find.text('At the junction, go'), findsOneWidget);
  });

  testWidgets('the first-trip ghost goes once the trip is answered', (
    tester,
  ) async {
    await pumpApp(tester, Routes.lessonOf(unit, 1));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LessonScreen)),
    );
    LessonPlaying play() =>
        container.read(lessonControllerProvider) as LessonPlaying;
    await toTrip(tester, container);
    expect(play().firstTrip, isTrue);
    // Given up, the trip comes back in Fix them without the ghost.
    container.read(lessonControllerProvider.notifier).showRoute();
    expect(play().firstTrip, isFalse);
    await settle(tester);
  });

  testWidgets('with a screen reader the road trip is a list of turns', (
    tester,
  ) async {
    await pumpApp(tester, Routes.lessonOf(unit, 1), screenReader: true);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LessonScreen)),
    );
    LessonPlaying play() =>
        container.read(lessonControllerProvider) as LessonPlaying;
    await toTrip(tester, container);
    expect(find.text('At the junction, go'), findsOneWidget);

    final streets = await container.read(cityStreetsProvider.future);
    String label(TurnOption t) {
      final name = streetName(streets[t.edge.streetId]!, null);
      return switch (t.turn) {
        Turn.start => 'Onto $name',
        Turn.left => 'Left onto $name',
        Turn.straight => 'Straight on $name',
        Turn.right => 'Right onto $name',
        Turn.back => 'Back along $name',
      };
    }

    final trip = (play().run.step as TripStep).trip;
    for (final edge in trip.best.edges) {
      final turns = turnsAt(play().route!);
      final pick = turns.firstWhere((t) => t.edge.id == edge.id);
      final same = turns.where((t) => label(t) == label(pick)).toList();
      await tap(tester, find.text(label(pick)).at(same.indexOf(pick)));
    }
    expect(play().route!.reached, isTrue);
    expect(find.text('At the junction, go'), findsNothing);
    await tap(tester, find.text('Check route'));
    expect(find.text('Best route!'), findsOneWidget);
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

class _FakeSpeech implements Speech {
  _FakeSpeech([this.languages = const {}]);

  final Set<String> languages;
  final List<(String, String)> said = [];

  @override
  Future<bool> canSpeak(String languageTag) async =>
      languages.contains(languageTag);

  @override
  Future<void> speak(String text, String languageTag) async =>
      said.add((text, languageTag));
}
