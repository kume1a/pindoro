import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/features/course/data/course_data.dart';
import 'package:pindoro/features/league/data/league_data.dart';
import 'package:pindoro/features/lesson/ui/lesson_controller.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/features/progress/data/progress_dao.dart';
import 'package:pindoro_core/pindoro_core.dart';

final driveControllerProvider =
    NotifierProvider.autoDispose<DriveController, DriveState>(
      DriveController.new,
    );

sealed class DriveState {
  const DriveState();
}

final class DriveLoading extends DriveState {
  const DriveLoading();
}

/// No unit, no road graph or no trip to drive: back to the Path.
final class DriveMissing extends DriveState {
  const DriveMissing();
}

/// The unit's Final drive passed: Unit complete is next, with the [xp] this
/// visit earned (for its level-up).
final class DrivePassed extends DriveState {
  const DrivePassed(this.unitId, this.xp);

  final String unitId;
  final int xp;
}

/// A trip of the Final drive: [passed] trips passed before it (earlier
/// visits count), [score] once it is answered, [xp] earned in this visit.
final class DrivePlaying extends DriveState {
  const DrivePlaying({
    required this.cityId,
    required this.unit,
    required this.shape,
    required this.difficulty,
    required this.graph,
    required this.passed,
    required this.number,
    required this.trip,
    required this.draft,
    required this.used,
    required this.xp,
    required this.startedAt,
    required this.firstTrip,
    this.score,
  });

  final String cityId;
  final CourseUnit unit;
  final AreaShape shape;
  final Difficulty difficulty;
  final RoadGraph graph;
  final int passed;

  /// Trips offered in this visit, from 0: tells one trip from the next.
  final int number;
  final Trip trip;
  final RouteDraft draft;

  /// Destination streets already driven to, so each trip goes elsewhere.
  final Set<String> used;
  final int xp;
  final DateTime startedAt;
  final bool firstTrip;
  final Score? score;

  bool get answered => score != null;

  bool get passes => score != null && score!.tier != Tier.miss;

  /// This trip passes the Final drive.
  bool get completes => passes && passed + 1 >= CourseRules.finalDriveTrips;

  DrivePlaying copyWith({RouteDraft? draft, Score? score, int? xp}) =>
      DrivePlaying(
        cityId: cityId,
        unit: unit,
        shape: shape,
        difficulty: difficulty,
        graph: graph,
        passed: passed,
        number: number,
        trip: trip,
        draft: draft ?? this.draft,
        used: used,
        xp: xp ?? this.xp,
        startedAt: startedAt,
        firstTrip: firstTrip,
        score: score ?? this.score,
      );
}

/// Plays a unit's Final drive (or Jump ahead on a locked unit): road trips
/// across the raion until [CourseRules.finalDriveTrips] passed. Each trip is
/// saved as soon as it is answered, so leaving keeps the ones passed.
class DriveController extends Notifier<DriveState> {
  Future<void>? _saving;

  @override
  DriveState build() => const DriveLoading();

  // Leaving disposes this controller: methods take the DAO before their
  // first await and check ref.mounted before touching state again.
  ProgressDao get _dao => ref.read(progressDaoProvider);

  Future<void> start(String unitId) async {
    final dao = _dao;
    final plan = await ref.read(coursePlanProvider.future);
    final graph = await ref.read(roadGraphProvider.future);
    final settings = await ref.read(settingsDaoProvider).read();
    final unit = plan?.units.where((u) => u.id == unitId).firstOrNull;
    if (plan == null || unit == null || graph == null) {
      if (ref.mounted) state = const DriveMissing();
      return;
    }
    final city = plan.pack.city();
    final results = await dao.lessonResultsIn(city.id);
    final firstTrip = await dao.roadTrips() == 0;
    if (!ref.mounted) return;
    final passed = [
      for (final r in results)
        if (r.unitId == unit.id && outcomeOf(r).passed) r,
    ].length;
    final shape = DistrictsArea({unit.id}).shapeIn(plan.pack);
    final trip = shape == null ? null : _pick(graph, unit, const {});
    if (shape == null ||
        trip == null ||
        passed >= CourseRules.finalDriveTrips) {
      state = const DriveMissing();
      return;
    }
    state = DrivePlaying(
      cityId: city.id,
      unit: unit,
      shape: shape,
      difficulty: settings.difficulty,
      graph: graph,
      passed: passed,
      number: 0,
      trip: trip,
      draft: RouteDraft(graph, trip.from, trip.to),
      used: {trip.destination.id},
      xp: 0,
      startedAt: DateTime.now(),
      firstTrip: firstTrip,
    );
  }

  /// A trip across [unit]'s raion to a street not yet in [used] (any street
  /// once every one was); a lesson-length one when no drive-length trip
  /// fits, so a small raion's unit can still be passed.
  Trip? _pick(RoadGraph graph, CourseUnit unit, Set<String> used) {
    Trip? pick(Set<String> avoid) => pickTrip(
      graph,
      destinations: [
        for (final s in unit.streets)
          if (!avoid.contains(s.id)) s,
      ],
      starts: unit.streets,
      minM: TripRules.driveMinM,
      maxM: TripRules.driveMaxM,
      within: unit.district.boundary,
      random: ref.read(lessonRandomProvider),
    );
    return pick(used) ??
        pick(const {}) ??
        pickTrip(
          graph,
          destinations: unit.streets,
          starts: unit.streets,
          minM: TripRules.lessonMinM,
          maxM: TripRules.lessonMaxM,
          within: unit.district.boundary,
          random: ref.read(lessonRandomProvider),
        );
  }

  void drawTo(RouteDraft draft) {
    if (state case final DrivePlaying p when !p.answered) {
      state = p.copyWith(draft: draft);
    }
  }

  void checkRoute() {
    if (state case final DrivePlaying p when !p.answered && p.draft.reached) {
      _answer(
        p,
        scoreRoute(p.draft.lengthM, p.trip.best.lengthM, p.difficulty),
      );
    }
  }

  /// Gives the trip up: a Miss.
  void showRoute() {
    if (state case final DrivePlaying p when !p.answered) {
      _answer(p, (tier: Tier.miss, xp: 0));
    }
  }

  void _answer(DrivePlaying p, Score score) {
    final answered = p.copyWith(score: score);
    final bonus = answered.completes ? CourseRules.unitBonusXp : 0;
    state = answered.copyWith(xp: p.xp + score.xp + bonus);
    _saving = _dao
        .finishTrip(
          cityId: p.cityId,
          unitId: p.unit.id,
          difficulty: p.difficulty,
          trip: p.trip,
          score: score,
          completesUnit: answered.completes,
          startedAt: p.startedAt,
        )
        .then((_) {
          if (ref.mounted) ref.invalidate(standingProvider);
        });
  }

  /// On to Unit complete once the drive passes, else to a new trip (after a
  /// Miss too: a new A and B).
  Future<void> next() async {
    final p = state;
    if (p is! DrivePlaying || !p.answered) return;
    await _saving;
    // A second Next tapped during the save already moved on.
    if (!ref.mounted || !identical(state, p)) return;
    if (p.completes) {
      state = DrivePassed(p.unit.id, p.xp);
      return;
    }
    final trip = _pick(p.graph, p.unit, p.used);
    if (trip == null) {
      state = const DriveMissing();
      return;
    }
    state = DrivePlaying(
      cityId: p.cityId,
      unit: p.unit,
      shape: p.shape,
      difficulty: p.difficulty,
      graph: p.graph,
      passed: p.passed + (p.passes ? 1 : 0),
      number: p.number + 1,
      trip: trip,
      draft: RouteDraft(p.graph, trip.from, trip.to),
      used: {...p.used, trip.destination.id},
      xp: p.xp,
      startedAt: DateTime.now(),
      firstTrip: false,
    );
  }
}

/// The bar's trip ("Road trip 2 of 3").
int driveStep(DrivePlaying p) =>
    math.min(p.passed + 1, CourseRules.finalDriveTrips);
