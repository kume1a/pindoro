import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/lesson/ui/lesson_controller.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

void main() {
  const unit = AppConfig.fixtureDistrictId;
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        packRepositoryProvider.overrideWith((ref) async {
          final repo = SqlitePackRepository.open(AppConfig.fixturePackAsset);
          ref.onDispose(repo.close);
          return repo;
        }),
        lessonRandomProvider.overrideWithValue(Random(3)),
      ],
    );
    c.listen(lessonControllerProvider, (_, _) {}); // keep it alive
    addTearDown(c.dispose);
    return c;
  }

  LessonPlaying playing(ProviderContainer c) =>
      c.read(lessonControllerProvider) as LessonPlaying;

  /// Answers every step until the lesson saves: pins on the street (or far
  /// away when [missPin] says so), names right unless [wrongName] says so,
  /// road trips along the best route unless [showTrip] gives them up.
  Future<String> playThrough(
    ProviderContainer c, {
    bool Function(PinStep step)? missPin,
    bool Function(NameStep step)? wrongName,
    bool Function(TripStep step)? showTrip,
  }) async {
    final controller = c.read(lessonControllerProvider.notifier);
    for (var guard = 0; guard < 40; guard++) {
      final state = c.read(lessonControllerProvider);
      if (state is LessonSaved) return state.resultId;
      final p = state as LessonPlaying;
      if (p.run.startsFixes && !p.fixesOpen) controller.openFixes();
      switch (p.run.step) {
        case final PinStep step:
          controller.placePin(
            missPin?.call(step) ?? false
                ? const LatLng(41.9, 45.2)
                : step.street.geometry.first.first,
          );
          controller.confirm();
        case final NameStep step:
          final wrong = wrongName?.call(step) ?? false;
          controller
            ..choose(
              step.options.indexWhere((o) => (o.id == step.street.id) != wrong),
            )
            ..check();
        case final TripStep step when showTrip?.call(step) ?? false:
          controller.showRoute();
        case final TripStep step:
          var draft = p.route!;
          for (final e in step.trip.best.edges) {
            draft = draft.take(e);
          }
          controller
            ..drawTo(draft)
            ..checkRoute();
        case CardStep():
      }
      await controller.next();
    }
    fail('the lesson never ended');
  }

  group('an app kill', () {
    const lesson1 = (unitId: unit, kind: LessonKind.lesson, lesson: 1);

    /// Past the 4 cards and the first test's answer.
    Future<LessonPlaying> playFirstTest(ProviderContainer c) async {
      final controller = c.read(lessonControllerProvider.notifier);
      await controller.start(lesson1);
      while (playing(c).run.step is CardStep) {
        await controller.next();
      }
      final step = playing(c).run.step;
      switch (step) {
        case PinStep():
          controller
            ..placePin(step.street.geometry.first.first)
            ..confirm();
        case NameStep():
          controller
            ..choose(step.options.indexWhere((o) => o.id == step.street.id))
            ..check();
        case _:
          fail('a test comes after the cards');
      }
      return playing(c);
    }

    Future<SavedLesson?> saved() => ProgressDao(db).savedLesson(DateTime.now());

    test('resumes the lesson after its last answer', () async {
      final before = await playFirstTest(container());
      await pumpEventQueue();
      expect((await saved())?.lesson, 1);

      final c = container();
      await c.read(lessonControllerProvider.notifier).start(lesson1);
      final after = playing(c);
      expect(after.run.index, before.run.index + 1);
      expect(after.run.answers, hasLength(1));
      expect(after.run.stepXp, before.run.stepXp);
      expect(
        [for (final s in after.run.steps) s.street.id],
        [for (final s in before.run.steps) s.street.id],
      );
      // The clock pauses while the app is dead: it never runs backwards.
      expect(after.startedAt.isBefore(before.startedAt), isFalse);

      final id = await playThrough(c);
      expect((await ProgressDao(db).lessonResult(id)).lesson, 1);
      expect(await saved(), isNull);
    });

    test('leaving drops it; another lesson replaces it', () async {
      final c = container();
      await playFirstTest(c);
      await pumpEventQueue();
      await c.read(lessonControllerProvider.notifier).leave();
      expect(await saved(), isNull);

      await playFirstTest(container());
      await pumpEventQueue();
      final other = container();
      await other.read(lessonControllerProvider.notifier).start((
        unitId: unit,
        kind: LessonKind.practice,
        lesson: 1,
      ));
      expect(playing(other).run.answers, isEmpty);
      expect(await saved(), isNull);
    });

    test('a save from another pack version starts over', () async {
      await playFirstTest(container());
      await pumpEventQueue();
      await (db.update(
        db.savedLessons,
      )).write(const SavedLessonsCompanion(packVersion: Value('old')));
      final c = container();
      await c.read(lessonControllerProvider.notifier).start(lesson1);
      expect(playing(c).run.index, 0);
      expect(await saved(), isNull);
    });
  });

  test('a lesson plays its cards and tests, then saves once', () async {
    final c = container();
    await c.read(lessonControllerProvider.notifier).start((
      unitId: unit,
      kind: LessonKind.lesson,
      lesson: 1,
    ));
    final first = playing(c);
    expect(first.run.steps.whereType<CardStep>(), hasLength(4));
    expect(first.run.steps, hasLength(11));
    expect(first.run.steps.last, isA<TripStep>());

    final id = await playThrough(c);
    final result = await ProgressDao(db).lessonResult(id);
    expect(result.kind, LessonKind.lesson);
    expect(result.lesson, 1);
    expect(result.unitId, unit);
    expect(result.perfect, isTrue);
    expect(result.xp, LessonRules.maxXp);
    expect(await ProgressDao(db).lessonsDone(), 1);
    expect(await ProgressDao(db).roadTrips(), 1);
  });

  test(
    'a road trip given up comes back once and stays out of the Pit stop',
    () async {
      final c = container();
      await c.read(lessonControllerProvider.notifier).start((
        unitId: unit,
        kind: LessonKind.lesson,
        lesson: 1,
      ));
      expect(playing(c).firstTrip, isTrue);
      final id = await playThrough(c, showTrip: (step) => !step.fix);
      final answers = await ProgressDao(db).lessonAnswersOf(id);
      expect(
        [for (final a in answers.skip(6)) (a.kind, a.tier, a.fix)],
        [
          (LessonAnswerKind.trip, Tier.miss, false),
          (LessonAnswerKind.trip, Tier.perfect, true),
        ],
      );
      final result = await ProgressDao(db).lessonResult(id);
      expect((result.rightFirst, result.tests), (6, 7));
      expect(result.xp, 4 * 100 + 2 * LessonRules.nameXp + 50 + 20);
      expect(await ProgressDao(db).pitStop('tbilisi'), isEmpty);
    },
  );

  test('mistakes come back once at the end, at half XP', () async {
    final c = container();
    await c.read(lessonControllerProvider.notifier).start((
      unitId: unit,
      kind: LessonKind.lesson,
      lesson: 1,
    ));
    final firstName = playing(
      c,
    ).run.steps.whereType<NameStep>().first.street.id;
    final id = await playThrough(
      c,
      wrongName: (step) => step.street.id == firstName && !step.fix,
    );
    final answers = await ProgressDao(db).lessonAnswersOf(id);
    expect(answers, hasLength(8));
    expect(answers.last.fix, isTrue);
    expect(answers.last.streetId, firstName);
    expect(answers.last.xp, LessonRules.nameXp ~/ 2);
    final result = await ProgressDao(db).lessonResult(id);
    expect(result.perfect, isFalse);
    expect((result.rightFirst, result.tests), (6, 7));
    expect(
      result.xp,
      4 * 100 + 100 + LessonRules.nameXp + LessonRules.nameXp ~/ 2 + 20,
    );
    expect(await ProgressDao(db).pitStop('tbilisi'), isEmpty);
  });

  test('a test waits for its answer before the next step', () async {
    final c = container();
    final controller = c.read(lessonControllerProvider.notifier);
    await controller.start((unitId: unit, kind: LessonKind.lesson, lesson: 1));
    while (playing(c).run.step is CardStep) {
      await controller.next();
    }
    final firstTest = playing(c).run.index;
    await controller.next();
    await controller.next();
    expect(playing(c).run.index, firstTest);
    expect(playing(c).run.answers, isEmpty);
  });

  test('leaving before the end writes nothing', () async {
    final c = container();
    final controller = c.read(lessonControllerProvider.notifier);
    await controller.start((unitId: unit, kind: LessonKind.lesson, lesson: 1));
    for (var i = 0; i < 5; i++) {
      await controller.next();
    }
    c.dispose();
    expect(await ProgressDao(db).totalXp(), 0);
    expect(await ProgressDao(db).hasPlayed(), isFalse);
  });

  test('practice: the tests only, at half XP', () async {
    final c = container();
    await c.read(lessonControllerProvider.notifier).start((
      unitId: unit,
      kind: LessonKind.practice,
      lesson: 1,
    ));
    expect(playing(c).run.steps.whereType<CardStep>(), isEmpty);
    final id = await playThrough(c);
    final result = await ProgressDao(db).lessonResult(id);
    expect(result.xp, (4 * 100 + 2 * LessonRules.nameXp + 100) ~/ 2);
    expect(await ProgressDao(db).lessonsDone(), 0);
  });

  test("the unit's Pit stop plays lessons 1–3's mistakes", () async {
    final c = container();
    final controller = c.read(lessonControllerProvider.notifier);
    await controller.start((unitId: unit, kind: LessonKind.lesson, lesson: 1));
    final missed = playing(c).run.steps.whereType<PinStep>().first.street.id;
    await playThrough(
      c,
      missPin: (step) => step.street.id == missed && !step.fix,
    );

    await controller.start((
      unitId: unit,
      kind: LessonKind.pitStop,
      lesson: null,
    ));
    final steps = playing(c).run.steps;
    expect([for (final s in steps) s.street.id], [missed]);
    expect((steps.single as PinStep).lastDistanceM, isNotNull);
    final id = await playThrough(c);
    final result = await ProgressDao(db).lessonResult(id);
    expect(result.kind, LessonKind.pitStop);
    expect(result.xp, 100);
  });

  test('a lesson that is not in the course goes missing', () async {
    final c = container();
    await c.read(lessonControllerProvider.notifier).start((
      unitId: unit,
      kind: LessonKind.lesson,
      lesson: 99,
    ));
    expect(c.read(lessonControllerProvider), isA<LessonMissing>());
    await db
        .into(db.lessonResults)
        .insert(
          LessonResultsCompanion.insert(
            cityId: 'tbilisi',
            unitId: unit,
            kind: LessonKind.lesson,
            lesson: const Value(1),
            difficulty: Difficulty.medium,
            xp: 0,
            perfect: true,
            rightFirst: 6,
            tests: 6,
            durationMs: 1,
          ),
        );
    await c.read(lessonControllerProvider.notifier).start((
      unitId: unit,
      kind: LessonKind.pitStop,
      lesson: null,
    ));
    expect(
      c.read(lessonControllerProvider),
      isA<LessonMissing>(),
      reason: 'nothing to tune up',
    );
  });
}
