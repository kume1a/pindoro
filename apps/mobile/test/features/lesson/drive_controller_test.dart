import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/core/config.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/features/lesson/ui/drive_controller.dart';
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
        lessonRandomProvider.overrideWithValue(Random(4)),
      ],
    );
    c.listen(driveControllerProvider, (_, _) {}); // keep it alive
    addTearDown(c.dispose);
    return c;
  }

  DrivePlaying playing(ProviderContainer c) =>
      c.read(driveControllerProvider) as DrivePlaying;

  /// Draws the current trip's best route and checks it.
  void driveBest(ProviderContainer c) {
    final p = playing(c);
    var draft = p.draft;
    for (final e in p.trip.best.edges) {
      draft = draft.take(e);
    }
    c.read(driveControllerProvider.notifier)
      ..drawTo(draft)
      ..checkRoute();
  }

  test(
    '3 passed trips pass the Final drive; the third adds the bonus',
    () async {
      final c = container();
      final controller = c.read(driveControllerProvider.notifier);
      await controller.start(unit);
      expect(playing(c).firstTrip, isTrue);
      final destinations = <String>{};
      for (var i = 0; i < 3; i++) {
        final p = playing(c);
        expect(p.passed, i);
        final straight = distanceBetween(
          p.graph.at(p.trip.from),
          p.graph.at(p.trip.to),
        );
        expect(
          straight,
          inInclusiveRange(TripRules.driveMinM, TripRules.driveMaxM),
        );
        destinations.add(p.trip.destination.id);
        driveBest(c);
        expect(playing(c).score!.tier, Tier.perfect);
        await controller.next();
      }
      expect(destinations, hasLength(3));
      expect(c.read(driveControllerProvider), isA<DrivePassed>());
      final results = await ProgressDao(db).lessonResultsIn('tbilisi');
      expect(
        [for (final r in results) (r.kind, r.xp)],
        [
          (LessonKind.finalDrive, 100),
          (LessonKind.finalDrive, 100),
          (LessonKind.finalDrive, 100 + CourseRules.unitBonusXp),
        ],
      );
      expect(await ProgressDao(db).roadTrips(), 3);
    },
  );

  test('a Miss offers a new trip; leaving keeps the trips passed', () async {
    final c = container();
    final controller = c.read(driveControllerProvider.notifier);
    await controller.start(unit);
    driveBest(c);
    await controller.next();
    final second = playing(c);
    controller.showRoute();
    expect(playing(c).passes, isFalse);
    expect(playing(c).completes, isFalse);
    await controller.next();
    final third = playing(c);
    expect(third.passed, 1);
    expect(third.number, 2);
    expect((
      third.trip.from,
      third.trip.to,
    ), isNot((second.trip.from, second.trip.to)));
    c.dispose();

    final again = container();
    await again.read(driveControllerProvider.notifier).start(unit);
    expect(playing(again).passed, 1);
    expect(playing(again).firstTrip, isFalse);
    final results = await ProgressDao(db).lessonResultsIn('tbilisi');
    expect([for (final r in results) r.rightFirst], [1, 0]);
  });

  test('a unit that is not in the course goes missing', () async {
    final c = container();
    await c.read(driveControllerProvider.notifier).start('osm:r1');
    expect(c.read(driveControllerProvider), isA<DriveMissing>());
  });
}
