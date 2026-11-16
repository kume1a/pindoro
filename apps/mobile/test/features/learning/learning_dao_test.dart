import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/personal_landmarks.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

void main() {
  late AppDatabase db;
  late LearningDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = LearningDao(db);
  });
  tearDown(() => db.close());

  final t0 = DateTime(2026, 3, 2, 9, 30);
  final itemId = CardType.p.item('street-1');

  ({CardState card, LogEntry log}) answer(
    CardState? card,
    Rating rating,
    DateTime at,
  ) => applyReview(
    card,
    itemId: itemId,
    rating: rating,
    now: at,
    format: ReviewFormat.retrieval1,
    source: ReviewSource.session,
    sessionId: 's1',
    distanceM: 12.5,
    snapId: 'street-1',
    rtMs: 5400,
  );

  test('an intro is saved as a learning card with no memory', () async {
    await dao.putCard(introduce(itemId, t0));
    final card = (await dao.card(itemId))!;
    expect(card.phase, CardPhase.learning);
    expect(card.memory, isNull);
    expect(card.introAt!.isAtSameMomentAs(t0), isTrue);
  });

  test('an answer saves the card and its log row round trip', () async {
    final intro = introduce(itemId, t0);
    await dao.putCard(intro);
    final first = answer(
      intro,
      Rating.good,
      t0.add(const Duration(minutes: 2)),
    );
    await dao.saveAnswer(card: first.card, log: first.log);
    final later = answer(
      first.card,
      Rating.hard,
      t0.add(const Duration(days: 2)),
    );
    await dao.saveAnswer(card: later.card, log: later.log);

    final card = (await dao.card(itemId))!;
    expect(card.phase, CardPhase.review);
    expect(card.reps, 2);
    expect(card.lastRating, Rating.hard);
    expect(card.memory!.stability, later.card.memory!.stability);
    expect(card.memory!.difficulty, later.card.memory!.difficulty);
    expect(card.dueAt!.isAtSameMomentAs(later.card.dueAt!), isTrue);
    expect(card.introAt!.isAtSameMomentAs(t0), isTrue);
    expect(card.lastDistanceM, 12.5);
    expect(card.lastSnapId, 'street-1');

    final log = await dao.log();
    expect(log, hasLength(2));
    final row = log.last;
    expect(row.itemId, itemId);
    expect(row.type, CardType.p);
    expect(row.format, ReviewFormat.retrieval1);
    expect(row.rating, Rating.hard);
    expect(row.source, ReviewSource.session);
    expect(row.sessionId, 's1');
    expect(row.rtMs, 5400);
    expect(row.elapsedDays, later.log.elapsedDays);
    expect(row.sBefore, later.log.sBefore);
    expect(row.ts.isAtSameMomentAs(later.log.ts), isTrue);
    expect(await dao.log(since: t0.add(const Duration(days: 1))), hasLength(1));
  });

  test('an answer without a card is logged only (a pretest)', () async {
    final pretest = answer(null, Rating.again, t0).log;
    await dao.saveAnswer(log: pretest);
    expect(await dao.cards(), isEmpty);
    expect(await dao.log(), hasLength(1));
  });

  test('a mix-up saves the pair and counts repeats', () async {
    for (var i = 0; i < 2; i++) {
      final r = answer(null, Rating.again, t0.add(Duration(minutes: i)));
      await dao.saveAnswer(
        card: r.card,
        log: r.log,
        mixUp: (target: 'street-1', hit: 'street-2'),
      );
    }
    expect(await dao.confusionPairs(), [('street-1', 'street-2')]);
    final row = await db.select(db.confusions).getSingle();
    expect(row.count, 2);
    expect(
      row.lastAt.isAtSameMomentAs(t0.add(const Duration(minutes: 1))),
      isTrue,
    );
  });

  test('the review log refuses updates and deletes', () async {
    final r = answer(null, Rating.good, t0);
    await dao.saveAnswer(card: r.card, log: r.log);
    await expectLater(
      db.customStatement('UPDATE review_log SET rating = 1'),
      throwsA(isA<SqliteException>()),
    );
    await expectLater(
      db.customStatement('DELETE FROM review_log'),
      throwsA(isA<SqliteException>()),
    );
    expect(await dao.log(), hasLength(1));
  });

  test('minutes a day default to 20', () async {
    final row = await (db.select(db.userSettings)).getSingleOrNull();
    expect(row, isNull);
    await db.into(db.userSettings).insert(const UserSettingsCompanion());
    expect((await db.select(db.userSettings).getSingle()).minutesPerDay, 20);
  });

  test('personal landmarks: saved newest first, deleted by id', () async {
    PersonalLandmarkRow at(String name, DateTime now) => newPersonalLandmark(
      name: ' $name ',
      kind: 'fuel',
      lat: 41.7,
      lon: 44.8,
      junctionNode: 123,
      approachNode: 456,
      onLeft: true,
      now: now,
    );
    final older = at('Connect', t0);
    await dao.savePersonalLandmark(older);
    await dao.savePersonalLandmark(
      at('Church', t0.add(const Duration(hours: 1))),
    );
    final saved = await dao.personalLandmarks();
    expect(saved.map((l) => l.name), ['Church', 'Connect']);
    expect(saved.last.id, startsWith('me:'));
    expect(
      (saved.last.junctionId, saved.last.approachEdgeId, saved.last.side),
      ('n123', 'n456', 'left'),
    );
    await dao.deletePersonalLandmark(older.id);
    expect((await dao.personalLandmarks()).map((l) => l.name), ['Church']);
  });

  test('a recital saves its answer, every decision as evidence and the J '
      'cards it failed', () async {
    final r = applyReview(
      null,
      itemId: 'R:n1:n2',
      rating: Rating.hard,
      now: t0,
      format: ReviewFormat.recital,
      source: ReviewSource.session,
    );
    final j = applyReview(
      null,
      itemId: 'J:n5:n4:n6',
      rating: Rating.again,
      now: t0,
      format: ReviewFormat.recital,
      source: ReviewSource.recital,
    );
    await dao.saveTest(
      log: r.log,
      card: r.card,
      source: ReviewSource.recital,
      at: t0,
      evidence: const [
        (itemId: 'J:n5:n4:n6', ok: false),
        (itemId: 'J:n7:n5:n8', ok: true),
      ],
      reviews: [j],
    );
    expect((await dao.log()).map((e) => (e.itemId, e.source)), [
      ('R:n1:n2', ReviewSource.session),
      ('J:n5:n4:n6', ReviewSource.recital),
    ]);
    expect((await dao.card('J:n5:n4:n6'))!.lastRating, Rating.again);
    final evidence = await db.select(db.implicitEvidence).get();
    expect(evidence.map((e) => (e.itemId, e.outcome, e.source)), [
      ('J:n5:n4:n6', 0, ReviewSource.recital),
      ('J:n7:n5:n8', 1, ReviewSource.recital),
    ]);
  });

  test('runs round trip oldest first; reported moves are kept once', () async {
    Run run(String id, DateTime at, List<String> items) => (
      id: id,
      fromNode: 1,
      toNode: 2,
      random: items.isEmpty,
      items: items,
      createdAt: at,
    );
    await dao.saveRun(run('n3:n4', t0.add(const Duration(days: 1)), const []));
    await dao.saveRun(run('n1:n2', t0, const ['J:n1:n2:n3', 'J:n2:n3:n4']));
    final runs = await dao.recitalRuns();
    expect(runs.map((r) => (r.id, r.items.join(' '), r.random)), [
      ('n1:n2', 'J:n1:n2:n3 J:n2:n3:n4', false),
      ('n3:n4', '', true),
    ]);
    await dao.reportMove('oneway:n1:n2', t0);
    await dao.reportMove('oneway:n1:n2', t0);
    await dao.reportMove('turn:n1:n2:n3', t0);
    expect(await dao.reportedMoves(), {'oneway:n1:n2', 'turn:n1:n2:n3'});
  });
}
