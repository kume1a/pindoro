import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/hold.dart';
import 'package:pindoro/core/location.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
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

/// Recording since [startedAt] towards the setup's choice [to], [drivenM] so
/// far.
final class DriveRecording extends DriveState {
  const DriveRecording({
    required this.target,
    required this.to,
    required this.startedAt,
    this.drivenM = 0,
  });

  final DriveTarget target;
  final DriveTo to;
  final DateTime startedAt;
  final double drivenM;
}

/// The drive graded like a recital (SPEC §5.3): the matched [match] over
/// the best route, [stoppedM] from the target when it ended short of it,
/// the turns of the book [credited] and [failed], and the GPS [gaps].
final class DriveReview extends DriveState {
  const DriveReview({
    required this.target,
    required this.match,
    required this.graded,
    required this.stoppedM,
    required this.credited,
    required this.failed,
    required this.gaps,
  });

  final DriveTarget target;
  final DriveMatch match;
  final RecitalResult? graded;
  final double? stoppedM;
  final int credited;
  final int failed;
  final GpsGaps gaps;
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
    state = DriveRecording(target: target, to: setup.to, startedAt: startedAt);
    _track = location.track(title: title, text: text).listen((fix) {
      final last = _fixes.lastOrNull;
      _fixes.add(fix);
      if (state case final DriveRecording r when last != null) {
        state = DriveRecording(
          target: r.target,
          to: r.to,
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
    final now = ref.read(clockProvider)();
    final graph = (await ref.hold(drivingGraphProvider.future))!;
    final streets = await ref.read(cityStreetsProvider.future);
    final match = matchDrive(graph, _fixes);
    final (:graded, :stoppedM) = gradeDrive(
      graph,
      match,
      recording.target.junction,
      streets: streets,
    );
    final evidence = graded == null
        ? const <({String itemId, bool ok})>[]
        : await _saveEvidence(graded, now);
    final credited = evidence.where((e) => e.ok).length;
    final failed = evidence.length - credited;
    final gaps = await _log(
      recording,
      endedAt: now,
      outcome: graded == null || stoppedM != null
          ? DriveOutcome.stopped
          : DriveOutcome.arrived,
      graph: graph,
      match: match,
      graded: graded,
      credited: credited,
      failed: failed,
    );
    if (!ref.mounted) return;
    state = DriveReview(
      target: recording.target,
      match: match,
      graded: graded,
      stoppedM: stoppedM,
      credited: credited,
      failed: failed,
      gaps: gaps,
    );
  }

  /// Saves each decision of the book's J items as evidence, and the
  /// near-due cards it failed as Again.
  Future<List<({String itemId, bool ok})>> _saveEvidence(
    RecitalResult graded,
    DateTime now,
  ) async {
    final pack = await ref.read(packRepositoryProvider.future);
    final book = await ref.read(routeBookProvider.future);
    final dao = ref.read(learningDaoProvider);
    final cards = {for (final c in await dao.cards()) c.itemId: c};
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
    return evidence;
  }

  /// Writes the drive, its track and the junctions it chose at (graded on
  /// [graph]) to the drive log (SPEC §16.23 item 124) and returns its GPS
  /// gaps.
  Future<GpsGaps> _log(
    DriveRecording recording, {
    required DateTime endedAt,
    required DriveOutcome outcome,
    RoadGraph? graph,
    DriveMatch? match,
    RecitalResult? graded,
    int credited = 0,
    int failed = 0,
  }) async {
    final fixes = List.of(_fixes);
    final gaps = gpsGaps(fixes, recording.startedAt, endedAt);
    final pack = await ref.read(packRepositoryProvider.future);
    final id = newId();
    final decisions = graph == null || match == null || graded == null
        ? const <PassedDecision>[]
        : offDriveDecisions(
            graph,
            graded,
            fixes,
            junctionNodes: pack.junctionNodes(),
          );
    await ref
        .read(driveLogDaoProvider)
        .save(
          decisions: [
            for (final (seq, d) in decisions.indexed)
              DriveDecisionRow(
                driveId: id,
                seq: seq,
                at: d.at,
                itemKey: d.key,
                planned: d.planned,
                ok: d.ok,
                level: d.level,
                help: d.help,
                recentHelp: d.recentHelp,
                hesitated: hesitatedNear(graph!, match!, d.junction),
              ),
          ],
          DriveRow(
            id: id,
            startedAt: recording.startedAt,
            endedAt: endedAt,
            level: DriveLevel.off,
            goal: recording.to.name,
            targetNode: pack.junctionNodes()[recording.target.junction],
            targetStreet: recording.target.street.id,
            outcome: outcome,
            drivenM: match?.drivenM ?? recording.drivenM,
            tier: graded?.tier,
            stretch: graded?.stretch,
            uTurns: match?.uTurns.length,
            hesitations: match?.hesitations.length,
            credited: credited,
            failed: failed,
            fixes: fixes.length,
            gpsGaps: gaps.count,
            longestGapS: gaps.longest.inSeconds,
          ),
          encodeTrack(fixes),
        );
    ref.invalidate(pastDrivesProvider);
    return gaps;
  }

  /// Lost? Show the way: the test ends ungraded, logged as abandoned.
  Future<void> abandon() => _once(_abandon);

  Future<void> _abandon() async {
    final recording = state;
    await _track?.cancel();
    _track = null;
    if (recording is DriveRecording) {
      await _log(
        recording,
        endedAt: ref.read(clockProvider)(),
        outcome: DriveOutcome.abandoned,
      );
    }
    _fixes.clear();
    if (ref.mounted) state = const DriveSetup();
  }
}
