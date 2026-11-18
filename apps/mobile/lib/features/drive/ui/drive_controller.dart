import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/hold.dart';
import 'package:pindoro/core/location.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

final driveControllerProvider =
    NotifierProvider.autoDispose<DriveController, DriveState>(
      DriveController.new,
    );

/// Where a GPS-free drive goes (DriveScreen `setup`).
enum DriveTo { run, surprise, own }

/// The destination: a pack junction on [street].
typedef DriveTarget = ({int junction, NamedStreet street});

sealed class DriveState {
  const DriveState();
}

/// Choosing where to go: today's run, a surprise or the player's [own]
/// street. [denied] once location was refused; [noTarget] when nothing
/// fits the choice.
final class DriveSetup extends DriveState {
  const DriveSetup({
    this.to = DriveTo.run,
    this.own,
    this.denied,
    this.noTarget = false,
  });

  final DriveTo to;
  final NamedStreet? own;
  final LocationDenied? denied;
  final bool noTarget;

  DriveSetup copyWith({DriveTo? to, NamedStreet? own}) =>
      DriveSetup(to: to ?? this.to, own: own ?? this.own);
}

/// Recording since [startedAt], [drivenM] so far.
final class DriveRecording extends DriveState {
  const DriveRecording({
    required this.target,
    required this.startedAt,
    this.drivenM = 0,
  });

  final DriveTarget target;
  final DateTime startedAt;
  final double drivenM;
}

/// The drive graded like a recital (SPEC §5.3): the matched [match] over
/// the best route, [stoppedM] from the target when it ended short of it,
/// and the turns of the book [credited] and [failed].
final class DriveReview extends DriveState {
  const DriveReview({
    required this.target,
    required this.match,
    required this.graded,
    required this.stoppedM,
    required this.credited,
    required this.failed,
  });

  final DriveTarget target;
  final DriveMatch match;
  final RecitalResult? graded;
  final double? stoppedM;
  final int credited;
  final int failed;
}

/// A GPS-free drive (SPEC §5.3 drives, board V3-50): pick a destination,
/// record the track in the background, then map-match and grade it; every
/// decision on it is evidence for its J card (§4).
class DriveController extends Notifier<DriveState> {
  StreamSubscription<DriveFix>? _track;
  final List<DriveFix> _fixes = [];
  bool _busy = false;

  @override
  DriveState build() {
    ref.onDispose(() => unawaited(_track?.cancel()));
    return const DriveSetup();
  }

  /// Runs [step] unless another is still running: a double tap on Start or
  /// I'm there opens one track and saves the drive once.
  Future<void> _once(Future<void> Function() step) async {
    if (_busy) return;
    _busy = true;
    try {
      await step();
    } finally {
      _busy = false;
    }
  }

  void choose(DriveTo to) {
    if (state case final DriveSetup s) state = s.copyWith(to: to);
  }

  void pickOwn(NamedStreet street) {
    if (state case final DriveSetup s) {
      state = s.copyWith(to: DriveTo.own, own: street);
    }
  }

  /// Start drive: finds the destination (a surprise or the player's own
  /// street from where they are) and starts the track, its notification
  /// reading [title] and [text].
  Future<void> start({required String title, required String text}) =>
      _once(() => _start(title, text));

  Future<void> _start(String title, String text) async {
    final setup = state;
    if (setup is! DriveSetup) return;
    final location = ref.read(locationServiceProvider);
    final here = await location.locate();
    if (!ref.mounted) return;
    if (here is LocationDenied) {
      state = DriveSetup(to: setup.to, own: setup.own, denied: here);
      return;
    }
    final target = await _target(setup, here is Located ? here.position : null);
    if (!ref.mounted) return;
    if (target == null) {
      state = DriveSetup(to: setup.to, own: setup.own, noTarget: true);
      return;
    }
    _fixes.clear();
    final startedAt = ref.read(clockProvider)();
    state = DriveRecording(target: target, startedAt: startedAt);
    _track = location.track(title: title, text: text).listen((fix) {
      final last = _fixes.lastOrNull;
      _fixes.add(fix);
      if (state case final DriveRecording r when last != null) {
        state = DriveRecording(
          target: r.target,
          startedAt: r.startedAt,
          drivenM: r.drivenM + distanceBetween(last.at, fix.at),
        );
      }
    });
  }

  Future<DriveTarget?> _target(DriveSetup setup, LatLng? here) async {
    final graph = await ref.hold(drivingGraphProvider.future);
    final streets = await ref.read(cityStreetsProvider.future);
    final pack = await ref.read(packRepositoryProvider.future);
    if (graph == null) return null;
    DriveTarget? at(int? junction) {
      final street = graph
          .edgesAt(junction ?? -1)
          .map((e) => streets[e.streetId])
          .nonNulls
          .firstOrNull;
      return street == null ? null : (junction: junction!, street: street);
    }

    switch (setup.to) {
      case DriveTo.run:
        final run = await ref.hold(todayRunProvider.future);
        return run == null
            ? null
            : (junction: run.ends.to, street: run.ends.toStreet);
      case DriveTo.surprise:
        if (here == null) return null;
        final now = ref.read(clockProvider)();
        final cards = await ref.read(learningDaoProvider).cards();
        return at(
          surpriseEnd(
            graph: graph,
            junctionNodes: pack.junctionNodes(),
            knownParts: {
              for (final c in cards)
                if (c.type == CardType.p && isKnown(c, now))
                  ...?streets[itemKey(c.itemId)]?.parts.map((p) => p.id),
            },
            from: here,
            seed: now.microsecondsSinceEpoch,
          ),
        );
      case DriveTo.own:
        final own = setup.own;
        if (own == null) return null;
        final ends = {
          for (final p in own.parts) ...graph.junctionsOfPart(p.id),
        };
        final from = here ?? own.parts.first.midpoint;
        final nearest = ends.fold<int?>(
          null,
          (best, j) =>
              best == null ||
                  distanceBetween(from, graph.at(j)) <
                      distanceBetween(from, graph.at(best))
              ? j
              : best,
        );
        return nearest == null ? null : (junction: nearest, street: own);
    }
  }

  /// I'm there: stops the track, matches it to the streets and grades it
  /// against the best legal route to the destination, then saves each
  /// decision as evidence and the near-due J cards it failed as Again.
  Future<void> end() => _once(_end);

  Future<void> _end() async {
    final recording = state;
    if (recording is! DriveRecording) return;
    await _track?.cancel();
    _track = null;
    final graph = (await ref.hold(drivingGraphProvider.future))!;
    final pack = await ref.read(packRepositoryProvider.future);
    final streets = await ref.read(cityStreetsProvider.future);
    final book = await ref.read(routeBookProvider.future);
    final dao = ref.read(learningDaoProvider);
    final cards = {for (final c in await dao.cards()) c.itemId: c};
    final match = matchDrive(graph, _fixes);
    final target = recording.target.junction;
    final path = match.path;
    if (path.edges.isEmpty) {
      if (!ref.mounted) return;
      state = DriveReview(
        target: recording.target,
        match: match,
        graded: null,
        stoppedM: null,
        credited: 0,
        failed: 0,
      );
      return;
    }
    final stoppedM = distanceBetween(
      graph.at(path.junctions.last),
      graph.at(target),
    );
    final arrived = stoppedM <= LearningConfig.driveArriveM;
    final graded = RecitalGrader.score(
      graph,
      path,
      from: path.junctions.first,
      to: arrived ? path.junctions.last : target,
      streets: streets,
    );
    final now = ref.read(clockProvider)();
    final evidence = recitalEvidence(graded, pack.junctionNodes(), {
      for (final id in book.questions.keys)
        if (CardType.ofItem(id) == CardType.j) id,
    });
    await dao.saveTest(
      source: ReviewSource.drive,
      at: now,
      evidence: evidence,
      reviews: [
        for (final e in evidence)
          ?implicitReview(
            cards[e.itemId],
            ok: e.ok,
            now: now,
            source: ReviewSource.drive,
          ),
      ],
    );
    if (!ref.mounted) return;
    state = DriveReview(
      target: recording.target,
      match: match,
      graded: graded,
      stoppedM: arrived ? null : stoppedM,
      credited: evidence.where((e) => e.ok).length,
      failed: evidence.where((e) => !e.ok).length,
    );
  }

  /// Lost? Show the way: the test ends unrecorded.
  Future<void> abandon() => _once(_abandon);

  Future<void> _abandon() async {
    await _track?.cancel();
    _track = null;
    _fixes.clear();
    if (ref.mounted) state = const DriveSetup();
  }
}
