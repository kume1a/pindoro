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
  /// away when [missPin] says so), names right unless [wrongName] says so.
  Future<String> playThrough(
    ProviderContainer c, {
    bool Function(PinStep step)? missPin,
    bool Function(NameStep step)? wrongName,
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
        case TripStep():
          fail('no road trip in this lesson');
        case CardStep():
      }
      await controller.next();
    }
    fail('the lesson never ended');
  }

  test('a lesson plays its cards and tests, then saves once', () async {
    final c = container();
    await c.read(lessonControllerProvider.notifier).start((
      unitId: unit,
      kind: LessonKind.lesson,
      lesson: 1,
    ));
    final first = playing(c);
    expect(first.run.steps.whereType<CardStep>(), hasLength(4));
    expect(first.run.steps, hasLength(10));

    final id = await playThrough(c);
    final result = await ProgressDao(db).lessonResult(id);
    expect(result.kind, LessonKind.lesson);
    expect(result.lesson, 1);
    expect(result.unitId, unit);
    expect(result.perfect, isTrue);
    expect(result.xp, LessonRules.maxXp - LessonRules.tripXp);
    expect(await ProgressDao(db).lessonsDone(), 1);
  });

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
    expect(answers, hasLength(7));
    expect(answers.last.fix, isTrue);
    expect(answers.last.streetId, firstName);
    expect(answers.last.xp, LessonRules.nameXp ~/ 2);
    final result = await ProgressDao(db).lessonResult(id);
    expect(result.perfect, isFalse);
    expect((result.rightFirst, result.tests), (5, 6));
    expect(
      result.xp,
      4 * 100 + LessonRules.nameXp + LessonRules.nameXp ~/ 2 + 20,
    );
    expect(await ProgressDao(db).pitStop('tbilisi'), isEmpty);
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
    expect(result.xp, (4 * 100 + 2 * LessonRules.nameXp) ~/ 2);
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
