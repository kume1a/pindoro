import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/drive_device.dart';
import 'package:pindoro/core/hold.dart';
import 'package:pindoro/core/location.dart';
import 'package:pindoro/features/drive/ui/nav_voice.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/nav_data.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

final driveControllerProvider =
    NotifierProvider.autoDispose<DriveController, DriveState>(
      DriveController.new,
    );

/// Where a drive goes (DriveScreen `setup`).
enum DriveTo { run, surprise, own }

/// The destination: a pack junction on [street].
typedef DriveTarget = ({int junction, NamedStreet street});

/// The setup's suggestion (SPEC §16.23 items 113–114): the level, and the route's turns that
/// are the player's ([silent], [yours] of [turns]).
typedef LevelSuggestion = ({
  DriveLevel level,
  int yours,
  int turns,
  Set<String> silent,
});

sealed class DriveState {
  const DriveState();
}

/// Choosing where to go: today's run, a surprise or the player's [own]
/// street. [denied] once location was refused; [noTarget] when nothing
/// fits the choice. [target] and its [suggestion] once found from where the
/// player is; [level] once picked (else the suggestion).
final class DriveSetup extends DriveState {
  const DriveSetup({
    this.to = DriveTo.run,
    this.own,
    this.denied,
    this.noTarget = false,
    this.target,
    this.suggestion,
    this.level,
  });

  final DriveTo to;
  final NamedStreet? own;
  final LocationDenied? denied;
  final bool noTarget;
  final DriveTarget? target;
  final LevelSuggestion? suggestion;
  final DriveLevel? level;

  /// The level picked, else the suggestion; today's run is the GPS-free test (Off) unless
  /// another is picked.
  DriveLevel get chosen =>
      level ??
      (to == DriveTo.run
          ? DriveLevel.off
          : suggestion?.level ?? DriveLevel.guided);

  /// The levels the player may pick (item 114): more help or one step less; any with no
  /// suggestion, and any on today's run, a route of the player's own turns.
  List<DriveLevel> get choices => switch (suggestion) {
    final s? when to != DriveTo.run => levelChoices(s.level),
    _ => DriveLevel.values,
  };

  bool sameChoice(DriveSetup other) => to == other.to && own == other.own;
}

/// Driving to [target] since [startedAt] at [level] (the guard and Rescue change it), [drivenM]
/// so far; [view] is the navigator's latest.
final class DriveRecording extends DriveState {
  const DriveRecording({
    required this.target,
    required this.to,
    required this.startedAt,
    required this.level,
    this.drivenM = 0,
    this.view,
    this.muted = false,
    this.rescued = false,
  });

  final DriveTarget target;
  final DriveTo to;
  final DateTime startedAt;
  final DriveLevel level;
  final double drivenM;
  final NavView? view;
  final bool muted;
  final bool rescued;

  /// Controls take input only while stopped (item 116); before the first fix the car hasn't
  /// moved.
  bool get stopped => view?.stopped ?? true;

  DriveRecording copyWith({
    DriveLevel? level,
    double? drivenM,
    NavView? view,
    bool? muted,
    bool? rescued,
  }) => DriveRecording(
    target: target,
    to: to,
    startedAt: startedAt,
    level: level ?? this.level,
    drivenM: drivenM ?? this.drivenM,
    view: view ?? this.view,
    muted: muted ?? this.muted,
    rescued: rescued ?? this.rescued,
  );
}

/// The drive graded like a recital (SPEC §5.3): the matched [match] over
/// the best route, [stoppedM] from the target when it ended short of it,
/// the turns of the book [credited] and [failed], and the GPS [gaps]; a
/// [rescued] drive's tier is at most Close (§16.23 item 116).
final class DriveReview extends DriveState {
  const DriveReview({
    required this.target,
    required this.match,
    required this.graded,
    required this.stoppedM,
    required this.credited,
    required this.failed,
    required this.gaps,
    this.rescued = false,
  });

  final DriveTarget target;
  final DriveMatch match;
  final RecitalResult? graded;
  final double? stoppedM;
  final int credited;
  final int failed;
  final GpsGaps gaps;
  final bool rescued;

  Tier? get tier => switch (graded?.tier) {
    final t? when rescued && t.index < Tier.close.index => Tier.close,
    final t => t,
  };
}

/// A drive (SPEC §5.3 drives, §16.23, boards V3-50 and V32-*): pick a destination and the help
/// suggested for it, drive with the navigator speaking by level, then map-match and grade the
/// track. A drive at Off is the GPS-free drive: every decision on it is evidence for its J card
/// (§4); the other levels log their decisions and change no card until M9 step 5.
class DriveController extends Notifier<DriveState> {
  StreamSubscription<DriveFix>? _track;
  Timer? _tick;
  Future<void>? _running;
  Navigator? _nav;
  NavWords? _words;
  String _voice = 'en-US';
  DriveLevel _startLevel = DriveLevel.off;
  DriveLevel? _suggested;
  final List<DriveFix> _fixes = [];
  bool _ending = false;

  DriveDevice get _device => ref.read(driveDeviceProvider);

  @override
  DriveState build() {
    ref.onDispose(() {
      unawaited(_track?.cancel());
      _tick?.cancel();
      if (_nav != null) unawaited(_device.stop());
    });
    unawaited(Future.microtask(_prepare));
    return const DriveSetup();
  }

  /// Runs [step], or waits for the one still running: a double tap on Start or End drive, or
  /// End during arrival, opens one track and saves the drive once.
  Future<void> _once(Future<void> Function() step) => _running ??= () async {
    try {
      await step();
    } finally {
      _running = null;
    }
  }();

  void choose(DriveTo to) {
    if (state case final DriveSetup s) {
      state = DriveSetup(to: to, own: s.own);
      unawaited(_prepare());
    }
  }

  void pickOwn(NamedStreet street) {
    if (state case DriveSetup()) {
      state = DriveSetup(to: DriveTo.own, own: street);
      unawaited(_prepare());
    }
  }

  /// A level the setup offers (item 114).
  void pickLevel(DriveLevel level) {
    if (state case final DriveSetup s when s.choices.contains(level)) {
      state = DriveSetup(
        to: s.to,
        own: s.own,
        target: s.target,
        suggestion: s.suggestion,
        level: level,
      );
    }
  }

  /// Finds the setup's destination from where the player is, and the level suggested for the
  /// route there.
  Future<void> _prepare() async {
    final setup = state;
    if (setup is! DriveSetup) return;
    final here = await ref.read(locationServiceProvider).locate();
    if (!ref.mounted) return;
    bool current() =>
        state is DriveSetup && (state as DriveSetup).sameChoice(setup);
    if (!current()) return;
    if (here is LocationDenied) {
      state = DriveSetup(to: setup.to, own: setup.own, denied: here);
      return;
    }
    final at = here is Located ? here.position : null;
    final target = await _target(setup, at);
    final suggestion = target == null || at == null
        ? null
        : await _suggest(target, at);
    if (!ref.mounted || !current()) return;
    state = DriveSetup(
      to: setup.to,
      own: setup.own,
      noTarget: target == null,
      target: target,
      suggestion: suggestion,
    );
  }

  Future<LevelSuggestion?> _suggest(DriveTarget target, LatLng here) async {
    final graph = await ref.hold(drivingGraphProvider.future);
    if (graph == null) return null;
    final pack = await ref.read(packRepositoryProvider.future);
    final streets = await ref.read(cityStreetsProvider.future);
    final settings = await ref.read(settingsDaoProvider).read();
    final near = graph.edgeNear(here, 4 * LearningConfig.driveSnapM);
    if (near == null) return null;
    final from =
        distanceBetween(here, graph.at(near.from)) <
            distanceBetween(here, graph.at(near.to))
        ? near.from
        : near.to;
    final plan = planNav(
      graph,
      NavCost(streets, toleranceKmh: settings.speedToleranceKmh),
      from: from,
      to: target.junction,
      streets: streets,
      junctionNodes: pack.junctionNodes(),
    );
    if (plan == null) return null;
    final history = await ref.hold(navHistoryProvider.future);
    final byNode = await ref.hold(junctionsByNodeProvider.future);
    final cards = {
      for (final c in await ref.read(learningDaoProvider).cards())
        if (c.type == CardType.j) c.itemId: c,
    };
    final raion = raionAt(pack.districts(), graph.at(target.junction));
    final s = routeSuggestion(
      decisions: plan.decisions,
      cards: cards,
      history: history.decisions,
      past: history.past,
      areaJ: raion == null ? 0 : jCardsIn(raion, cards.values, byNode, graph),
      now: ref.read(clockProvider)(),
    );
    return (
      level: s.level,
      yours: s.silent.length,
      turns: plan.decisions.length,
      silent: s.silent,
    );
  }

  /// Start drive: the destination found at setup (or now) and the track, its notification
  /// reading [title] and [text]; the navigator speaks from the first fix.
  Future<void> start({required String title, required String text}) =>
      _once(() => _start(title, text));

  Future<void> _start(String title, String text) async {
    final setup = state;
    if (setup is! DriveSetup) return;
    final location = ref.read(locationServiceProvider);
    var target = setup.target;
    if (target == null) {
      final here = await location.locate();
      if (!ref.mounted) return;
      if (here is LocationDenied) {
        state = DriveSetup(to: setup.to, own: setup.own, denied: here);
        return;
      }
      target = await _target(setup, here is Located ? here.position : null);
      if (!ref.mounted) return;
      if (target == null) {
        state = DriveSetup(to: setup.to, own: setup.own, noTarget: true);
        return;
      }
    }
    final graph = await ref.hold(drivingGraphProvider.future);
    if (graph == null || !ref.mounted) return;
    final pack = await ref.read(packRepositoryProvider.future);
    final streets = await ref.read(cityStreetsProvider.future);
    final landmarks = await ref.hold(navLandmarksProvider.future);
    final settings = await ref.read(settingsDaoProvider).read();
    final georgian =
        (settings.appLanguage?.name ??
                PlatformDispatcher.instance.locale.languageCode) ==
            'ka' &&
        await _device.canSpeak('ka-GE');
    _voice = georgian ? 'ka-GE' : 'en-US';
    _words = NavWords(
      lookupAppLocalizations(Locale(georgian ? 'ka' : 'en')),
      georgian: georgian,
    );
    final districts = pack.districts();
    _startLevel = setup.chosen;
    _suggested = setup.suggestion?.level;
    _nav = Navigator(
      graph: graph,
      cost: NavCost(streets, toleranceKmh: settings.speedToleranceKmh),
      destination: target.junction,
      level: _startLevel,
      streets: streets,
      landmarks: landmarks,
      junctionNodes: pack.junctionNodes(),
      silent: setup.suggestion?.silent ?? const {},
      districtAt: (p) => switch (raionAt(districts, p)) {
        final d? => georgian ? d.nameKa : (d.nameEn ?? transliterate(d.nameKa)),
        null => null,
      },
    );
    _fixes.clear();
    _ending = false;
    await _device.start();
    await _device.keepScreenOn(on: _startLevel != DriveLevel.off);
    if (!ref.mounted) return;
    state = DriveRecording(
      target: target,
      to: setup.to,
      startedAt: ref.read(clockProvider)(),
      level: _startLevel,
    );
    _track = location.track(title: title, text: text).listen(_onFix);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onFix(DriveFix fix) {
    final last = _fixes.lastOrNull;
    _fixes.add(fix);
    final r = state;
    final nav = _nav;
    if (r is! DriveRecording || nav == null) return;
    _apply(
      r.copyWith(
        drivenM: last == null
            ? r.drivenM
            : r.drivenM + distanceBetween(last.at, fix.at),
      ),
      nav.onFix(fix),
    );
  }

  /// Between fixes: only the GPS-lost line and "Still finding you" change anything.
  void _onTick() {
    final r = state;
    final nav = _nav;
    if (r is! DriveRecording || nav == null) return;
    final u = nav.onTick(ref.read(clockProvider)());
    if (u.view.gpsLostS != null || u.prompt != null) _apply(r, u);
  }

  void _apply(DriveRecording r, NavUpdate u) {
    state = r.copyWith(view: u.view, level: u.view.level);
    if (!r.muted) {
      if (u.prompt case final p?) _say(_words!.words(p, u.view.level));
      if (u.chime) unawaited(_device.chime());
    }
    if (u.view.arrived && !_ending) {
      _ending = true;
      unawaited(_arrive(r));
    }
  }

  void _say(String text) => unawaited(_device.say(text, _voice));

  /// Arrival (item 116): the line said to its end, then the drive ends by itself.
  Future<void> _arrive(DriveRecording r) async {
    if (!r.muted && r.level != DriveLevel.off) {
      await _device.say(_words!.arrived(r.target.street), _voice);
    }
    await end();
  }

  /// Off's Rescue, while stopped (item 116): Guided from here, said once.
  void rescue() {
    final r = state;
    final nav = _nav;
    if (r is! DriveRecording ||
        nav == null ||
        !r.stopped ||
        r.level != DriveLevel.off) {
      return;
    }
    nav.rescue();
    state = r.copyWith(level: DriveLevel.guided, rescued: true);
    unawaited(_device.keepScreenOn(on: true));
    if (!r.muted) _say(_words!.l10n.navRescued);
  }

  /// Mute or unmute every prompt, while stopped (item 117).
  void toggleMute() {
    if (state case final DriveRecording r when r.stopped) {
      state = r.copyWith(muted: !r.muted);
    }
  }

  /// End drive: stops the track, matches it to the streets and grades it
  /// against the best legal route to the destination; at Off saves each
  /// decision as evidence and the near-due J cards it failed as Again.
  Future<void> end() => _once(_end);

  Future<void> _end() async {
    final recording = state;
    if (recording is! DriveRecording) return;
    await _track?.cancel();
    _track = null;
    _tick?.cancel();
    final nav = _nav;
    unawaited(_device.stop());
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
    final gpsFree = _startLevel == DriveLevel.off && !recording.rescued;
    final evidence = graded == null || !gpsFree
        ? const <({String itemId, bool ok})>[]
        : await _saveEvidence(graded, now);
    final credited = evidence.where((e) => e.ok).length;
    final failed = evidence.length - credited;
    final review = DriveReview(
      target: recording.target,
      match: match,
      graded: graded,
      stoppedM: stoppedM,
      credited: credited,
      failed: failed,
      gaps: gpsGaps(_fixes, recording.startedAt, now),
      rescued: recording.rescued,
    );
    await _log(
      recording,
      review,
      endedAt: now,
      graph: graph,
      decisions: gpsFree || nav == null
          ? (graded == null
                ? const []
                : offDriveDecisions(
                    graph,
                    graded,
                    _fixes,
                    junctionNodes: (await ref.read(
                      packRepositoryProvider.future,
                    )).junctionNodes(),
                  ))
          : nav.passed,
      recoveries: nav?.recoveries ?? 0,
    );
    _nav = null;
    if (!ref.mounted) return;
    state = review;
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

  /// Writes the drive, its track and its [decisions] (hesitations found on [graph]) to the
  /// drive log (SPEC §16.23 item 124).
  Future<void> _log(
    DriveRecording recording,
    DriveReview review, {
    required DateTime endedAt,
    required RoadGraph graph,
    required List<PassedDecision> decisions,
    required int recoveries,
  }) async {
    final fixes = List.of(_fixes);
    final pack = await ref.read(packRepositoryProvider.future);
    final match = review.match;
    final graded = review.graded;
    final id = newId();
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
                hesitated: hesitatedNear(graph, match, d.junction),
              ),
          ],
          DriveRow(
            id: id,
            startedAt: recording.startedAt,
            endedAt: endedAt,
            level: _startLevel,
            goal: recording.to.name,
            targetNode: pack.junctionNodes()[recording.target.junction],
            targetStreet: recording.target.street.id,
            outcome: graded == null || review.stoppedM != null
                ? DriveOutcome.stopped
                : DriveOutcome.arrived,
            drivenM: match.drivenM,
            tier: review.tier,
            stretch: graded?.stretch,
            uTurns: match.uTurns.length,
            hesitations: match.hesitations.length,
            credited: review.credited,
            failed: review.failed,
            fixes: fixes.length,
            gpsGaps: review.gaps.count,
            longestGapS: review.gaps.longest.inSeconds,
            suggested: _suggested,
            recoveries: recoveries,
            rescued: recording.rescued,
          ),
          encodeTrack(fixes),
        );
    ref.invalidate(pastDrivesProvider);
    ref.invalidate(navHistoryProvider);
  }
}
