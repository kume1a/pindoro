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
import 'package:pindoro/features/learning/data/drive_history.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/nav_data.dart';
import 'package:pindoro/features/learning/data/route_book.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

export 'package:pindoro/features/learning/data/drive_places.dart'
    show DriveDest, DriveTarget;

final driveControllerProvider =
    NotifierProvider.autoDispose<DriveController, DriveState>(
      DriveController.new,
    );

/// Where a drive goes (DriveScreen `setup`, board V32-10): today's run, a surprise, Home, Work or
/// a street or place of the player's own.
enum DriveTo { run, surprise, home, work, own }

/// The setup's suggestion (SPEC §16.23 items 113–114, 121): the level, and the route's turns
/// that are the player's ([silent], [yours] of [turns]); the route planned from here and its key
/// decisions by key.
typedef DriveSuggestion = ({
  DriveLevel level,
  int yours,
  int turns,
  Set<String> silent,

  /// Each turn on the route, in order: whether it is yours (the setup's pips).
  List<bool> pips,
  NavPlan plan,
  Set<String> keys,
});

sealed class DriveState {
  const DriveState();
}

/// Choosing where to go and how much help: no [to] while searching; today's run, a surprise,
/// Home, Work or the player's [own] street or place. [here] once found, [denied] once location
/// was refused; [noTarget] when nothing fits the choice. [target] and its [suggestion] once found
/// from where the player is; [level] once picked (else the suggestion).
final class DriveSetup extends DriveState {
  const DriveSetup({
    this.to,
    this.own,
    this.here,
    this.denied,
    this.noTarget = false,
    this.target,
    this.suggestion,
    this.level,
  });

  final DriveTo? to;
  final DriveDest? own;
  final LatLng? here;
  final LocationDenied? denied;
  final bool noTarget;
  final DriveTarget? target;
  final DriveSuggestion? suggestion;
  final DriveLevel? level;

  /// The level picked, else the suggestion; today's run is the GPS-free test (Off) unless
  /// another is picked.
  DriveLevel get chosen =>
      level ??
      (to == DriveTo.run
          ? DriveLevel.off
          : suggestion?.level ?? DriveLevel.guided);

  /// The levels the player may pick (item 114): more help or one step less; any with no
  /// suggestion, and any on today's run.
  List<DriveLevel> get choices => switch (suggestion) {
    final s? when to != DriveTo.run => levelChoices(s.level),
    _ => DriveLevel.values,
  };

  bool sameChoice(DriveSetup other) => to == other.to && own == other.own;
}

/// Driving to [target] (at [destination]) since [startedAt] at [level] (the guard, Rescue and a
/// pick while stopped change it, among the setup's [choices]); [view] is the
/// navigator's latest. [speaking] while a prompt is said, [guardedAt] when the guard last
/// stepped in, [beat] counts the speed chimes (each pulses the sign).
final class DriveRecording extends DriveState {
  const DriveRecording({
    required this.target,
    required this.destination,
    required this.to,
    required this.startedAt,
    required this.level,
    required this.choices,
    this.suggestion,
    this.view,
    this.muted = false,
    this.rescued = false,
    this.speaking = false,
    this.guardedAt,
    this.beat = 0,
  });

  final DriveTarget target;
  final LatLng destination;
  final DriveTo to;
  final DateTime startedAt;
  final DriveLevel level;
  final List<DriveLevel> choices;
  final DriveSuggestion? suggestion;
  final NavView? view;
  final bool muted;
  final bool rescued;
  final bool speaking;
  final DateTime? guardedAt;
  final int beat;

  /// Controls take input only while stopped (item 116); before the first fix the car hasn't
  /// moved.
  bool get stopped => view?.stopped ?? true;

  DriveRecording copyWith({
    DriveTarget? target,
    LatLng? destination,
    DriveLevel? level,
    NavView? view,
    bool? muted,
    bool? rescued,
    bool? speaking,
    DateTime? guardedAt,
    int? beat,
  }) => DriveRecording(
    target: target ?? this.target,
    destination: destination ?? this.destination,
    to: to,
    startedAt: startedAt,
    level: level ?? this.level,
    choices: choices,
    suggestion: suggestion,
    view: view ?? this.view,
    muted: muted ?? this.muted,
    rescued: rescued ?? this.rescued,
    speaking: speaking ?? this.speaking,
    guardedAt: guardedAt ?? this.guardedAt,
    beat: beat ?? this.beat,
  );
}

/// The drive graded like a recital (SPEC §5.3): the matched [match] over
/// the best route, [stoppedM] from the target when it ended short of it,
/// the J cards it reviewed as a success ([credited]) and as Again ([failed]), and the GPS
/// [gaps]; a [rescued] drive's tier is at most Close (§16.23 item 116). [id] is the drive's in
/// the log.
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
    this.id,
  });

  final DriveTarget target;
  final DriveMatch match;
  final RecitalResult? graded;
  final double? stoppedM;
  final int credited;
  final int failed;
  final GpsGaps gaps;
  final bool rescued;
  final String? id;

  Tier? get tier => switch (graded?.tier) {
    final t? when rescued && t.index < Tier.close.index => Tier.close,
    final t => t,
  };
}

/// A drive (SPEC §5.3 drives, §16.23, boards V3-50 and V32-*): pick a destination and the help
/// suggested for it, drive with the navigator speaking by level, then map-match and grade the
/// track. Every decision taken without help reviews its J card (item 119): Good, Hard after a
/// hesitation, Again when missed; Guided turns, Coached cues and recoveries are exposure only.
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

  /// The drive's id in the log, known from setup so the preview's results name it.
  String _id = newId();

  /// The level with the most help the drive reached (items 122–123).
  DriveLevel _mostHelp = DriveLevel.off;
  int _speaking = 0;

  DriveDevice get _device => ref.read(driveDeviceProvider);

  /// The id the drive about to start will have in the log.
  String get driveId => _id;

  @override
  DriveState build() {
    final device = _device;
    ref.onDispose(() {
      unawaited(_track?.cancel());
      _tick?.cancel();
      if (_nav != null) unawaited(device.stop());
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

  /// Today's run, Surprise me, Home or Work.
  void choose(DriveTo to) {
    if (state case final DriveSetup s) {
      state = DriveSetup(to: to, here: s.here);
      unawaited(_prepare());
    }
  }

  /// A street or place the player searched for, or a recent destination.
  void pickOwn(DriveDest dest) {
    if (state case final DriveSetup s) {
      state = DriveSetup(to: DriveTo.own, own: dest, here: s.here);
      unawaited(_prepare());
    }
  }

  /// Back to the search.
  void clear() {
    if (state case final DriveSetup s) state = DriveSetup(here: s.here);
  }

  /// A level the setup offers (item 114).
  void pickLevel(DriveLevel level) {
    if (state case final DriveSetup s when s.choices.contains(level)) {
      state = DriveSetup(
        to: s.to,
        own: s.own,
        here: s.here,
        target: s.target,
        suggestion: s.suggestion,
        level: level,
      );
    }
  }

  /// Finds where the player is and, once a destination is chosen, the target and the level
  /// suggested for the route there.
  Future<void> _prepare() async {
    final setup = state;
    if (setup is! DriveSetup) return;
    final located = await ref.read(locationServiceProvider).locate();
    if (!ref.mounted) return;
    bool current() =>
        state is DriveSetup && (state as DriveSetup).sameChoice(setup);
    if (!current()) return;
    if (located is LocationDenied) {
      state = DriveSetup(to: setup.to, own: setup.own, denied: located);
      return;
    }
    final here = located is Located ? located.position : null;
    if (setup.to == null) {
      state = DriveSetup(here: here);
      return;
    }
    final found = await _find(setup, here);
    if (!ref.mounted || !current()) return;
    final picked = (state as DriveSetup).level;
    state = DriveSetup(
      to: setup.to,
      own: setup.own,
      here: here,
      noTarget: found == null,
      target: found?.target,
      suggestion: found?.suggestion,
      level: switch (found?.suggestion) {
        final s? when setup.to != DriveTo.run =>
          levelChoices(s.level).contains(picked) ? picked : null,
        _ => picked,
      },
    );
  }

  /// The setup's destination from [here] and its suggestion; for Surprise me the first new
  /// destination whose route is [LearningConfig.surpriseMinShare] the player's (item 122).
  Future<({DriveTarget target, DriveSuggestion? suggestion})?> _find(
    DriveSetup setup,
    LatLng? here,
  ) async {
    if (setup.to != DriveTo.surprise) {
      final target = await _target(setup, here);
      if (target == null) return null;
      return (
        target: target,
        suggestion: here == null ? null : await _suggest(target, here),
      );
    }
    if (here == null) return null;
    final graph = await ref.hold(drivingGraphProvider.future);
    final suggest = await _suggester(here);
    if (graph == null || suggest == null) return null;
    final streets = await ref.read(cityStreetsProvider.future);
    final pack = await ref.read(packRepositoryProvider.future);
    final now = ref.read(clockProvider)();
    final cards = await ref.read(learningDaoProvider).cards();
    final driven = {
      for (final d in await ref.read(driveLogDaoProvider).all()) d.targetNode,
    };
    final nodes = pack.junctionNodes();
    for (final j in surpriseEnds(
      graph: graph,
      junctionNodes: nodes,
      knownParts: {
        for (final c in cards)
          if (c.type == CardType.p && isKnown(c, now))
            ...?streets[itemKey(c.itemId)]?.parts.map((p) => p.id),
      },
      from: here,
      seed: now.microsecondsSinceEpoch,
    ).take(_surpriseTries)) {
      if (driven.contains(nodes[j])) continue;
      final street = streetAt(graph, streets, j);
      if (street == null) continue;
      final target = (junction: j, street: street, place: null);
      final s = suggest(target);
      if (s != null &&
          s.turns > 0 &&
          s.yours / s.turns >= LearningConfig.surpriseMinShare) {
        return (target: target, suggestion: s);
      }
    }
    return null;
  }

  /// How many surprise destinations are planned before giving up.
  static const int _surpriseTries = 12;

  Future<DriveSuggestion?> _suggest(DriveTarget target, LatLng here) async =>
      (await _suggester(here))?.call(target);

  /// The suggestion for a target from [here], with the graph, cards and history read once
  /// (Surprise me tries up to [_surpriseTries] targets); null without a road graph.
  Future<DriveSuggestion? Function(DriveTarget target)?> _suggester(
    LatLng here,
  ) async {
    final graph = await ref.hold(drivingGraphProvider.future);
    if (graph == null) return null;
    final pack = await ref.read(packRepositoryProvider.future);
    final streets = await ref.read(cityStreetsProvider.future);
    final settings = await ref.read(settingsDaoProvider).read();
    final landmarks = await ref.hold(navLandmarksProvider.future);
    final history = await ref.hold(navHistoryProvider.future);
    final byNode = await ref.hold(junctionsByNodeProvider.future);
    final cards = {
      for (final c in await ref.read(learningDaoProvider).cards())
        if (c.type == CardType.j) c.itemId: c,
    };
    final nodes = pack.junctionNodes();
    final districts = pack.districts();
    final now = ref.read(clockProvider)();
    const fsrs = Fsrs();
    return (DriveTarget target) {
      final plan = planFrom(
        graph,
        here,
        target.junction,
        streets: streets,
        landmarks: landmarks,
        junctionNodes: nodes,
        toleranceKmh: settings.speedToleranceKmh,
      );
      if (plan == null) return null;
      final raion = raionAt(districts, graph.at(target.junction));
      final keys = [for (final d in plan.decisions) d.key];
      final s = routeSuggestion(
        keys: keys,
        cards: cards,
        history: history.decisions,
        past: history.past,
        areaJ: raion == null ? 0 : jCardsIn(raion, cards.values, byNode, graph),
        now: now,
      );
      final pips = [for (final key in keys) s.silent.contains(key)];
      return (
        level: s.level,
        yours: pips.where((mine) => mine).length,
        turns: plan.decisions.length,
        silent: s.silent,
        pips: pips,
        plan: plan,
        keys: {
          for (final d in keyDecisions(
            graph,
            plan.decisions,
            silent: s.silent,
            recall: {
              for (final key in keys.nonNulls)
                if (cards[key]?.memory case final m?)
                  key: fsrs.retrievability(m, now),
            },
          ))
            ?d.key,
        },
      );
    };
  }

  /// Start drive: the destination found at setup (or now) and the track, its notification
  /// reading [title] and [text]; the navigator speaks from the first fix.
  Future<void> start({required String title, required String text}) =>
      _once(() => _start(title, text));

  Future<void> _start(String title, String text) async {
    final setup = state;
    if (setup is! DriveSetup || setup.to == null) return;
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
    _mostHelp = _startLevel;
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
    _speaking = 0;
    await _device.start();
    await _device.keepScreenOn(on: _startLevel != DriveLevel.off);
    if (!ref.mounted) return;
    state = DriveRecording(
      target: target,
      destination: graph.at(target.junction),
      to: setup.to!,
      startedAt: ref.read(clockProvider)(),
      level: _startLevel,
      choices: setup.choices,
      suggestion: setup.suggestion,
    );
    _track = location.track(title: title, text: text).listen(_onFix);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onFix(DriveFix fix) {
    _fixes.add(fix);
    final r = state;
    final nav = _nav;
    if (r is! DriveRecording || nav == null) return;
    _apply(r, nav.onFix(fix));
  }

  /// Between fixes: only the GPS-lost line and "Still finding you" change anything.
  void _onTick() {
    final r = state;
    final nav = _nav;
    if (r is! DriveRecording || nav == null) return;
    final u = nav.onTick(ref.read(clockProvider)());
    if (u.view.gpsLostS != null || u.prompt != null) _apply(r, u);
  }

  /// The drive reached [level]: the most help so far is kept (items 122–123).
  void _reached(DriveLevel level) {
    if (level.index < _mostHelp.index) _mostHelp = level;
  }

  void _apply(DriveRecording r, NavUpdate u) {
    state = r.copyWith(
      view: u.view,
      level: u.view.level,
      guardedAt: u.prompt?.kind == PromptKind.guard
          ? ref.read(clockProvider)()
          : null,
      beat: u.chime ? r.beat + 1 : null,
    );
    _reached(u.view.level);
    if (!r.muted) {
      if (u.prompt case final p?) _say(_words!.words(p, u.view.level));
      if (u.chime) unawaited(_device.chime());
    }
    if (u.view.arrived && !_ending) {
      _ending = true;
      unawaited(_arrive(r));
    }
  }

  /// Says [text]; [DriveRecording.speaking] while it does (Coached's bars).
  void _say(String text) => unawaited(_speak(text));

  Future<void> _speak(String text) async {
    void speaking(bool on) {
      if (state case final DriveRecording r when r.speaking != on) {
        state = r.copyWith(speaking: on);
      }
    }

    _speaking++;
    speaking(true);
    try {
      await _device.say(text, _voice);
    } finally {
      if (--_speaking == 0 && ref.mounted) speaking(false);
    }
  }

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
    _reached(DriveLevel.guided);
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

  /// A level picked while stopped applies at once (item 116), among the setup's choices.
  void pickDriveLevel(DriveLevel level) {
    final r = state;
    final nav = _nav;
    if (r is! DriveRecording ||
        nav == null ||
        !r.stopped ||
        level == r.level ||
        !r.choices.contains(level)) {
      return;
    }
    nav.setLevel(level);
    _reached(level);
    state = r.copyWith(level: level);
    unawaited(_device.keepScreenOn(on: level != DriveLevel.off));
  }

  /// A destination changed while stopped (item 116): the way there from the next fix.
  Future<void> changeDestination(DriveDest dest) async {
    final r = state;
    final nav = _nav;
    if (r is! DriveRecording || nav == null || !r.stopped) return;
    final at = r.view?.at;
    final target = await _target(DriveSetup(to: DriveTo.own, own: dest), at);
    final graph = await ref.hold(drivingGraphProvider.future);
    if (target == null || graph == null || !ref.mounted) return;
    final s = at == null ? null : await _suggest(target, at);
    if (!ref.mounted || state is! DriveRecording) return;
    nav.setDestination(target.junction, silent: s?.silent ?? const {});
    state = (state as DriveRecording).copyWith(
      target: target,
      destination: graph.at(target.junction),
    );
  }

  /// End drive: stops the track, matches it to the streets, grades it against the best legal
  /// route to the destination, and reviews each decision's J card by item 119.
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
    final pack = await ref.read(packRepositoryProvider.future);
    final match = matchDrive(graph, _fixes);
    final (:graded, :stoppedM) = gradeDrive(
      graph,
      match,
      recording.target.junction,
      streets: streets,
    );
    final gpsFree =
        _startLevel == DriveLevel.off && _mostHelp == DriveLevel.off;
    final decisions = gpsFree || nav == null
        ? (graded == null
              ? const <PassedDecision>[]
              : offDriveDecisions(
                  graph,
                  graded,
                  _fixes,
                  junctionNodes: pack.junctionNodes(),
                ))
        : nav.passed;
    final hesitated = [
      for (final d in decisions) hesitatedNear(graph, match, d.junction),
    ];
    final (:credited, :failed, :effects) = await _credit(
      decisions,
      hesitated,
      now,
    );
    final id = _id;
    final review = DriveReview(
      id: id,
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
      decisions: decisions,
      hesitated: hesitated,
      effects: effects,
      recoveries: nav?.recoveries ?? 0,
    );
    _nav = null;
    _id = newId();
    if (!ref.mounted) return;
    state = review;
  }

  Future<DriveTarget?> _target(DriveSetup setup, LatLng? here) async {
    final graph = await ref.hold(drivingGraphProvider.future);
    final streets = await ref.read(cityStreetsProvider.future);
    if (graph == null) return null;
    switch (setup.to) {
      case null || DriveTo.surprise:
        return null;
      case DriveTo.run:
        final run = await ref.hold(todayRunProvider.future);
        return run == null
            ? null
            : (junction: run.ends.to, street: run.ends.toStreet, place: null);
      case DriveTo.home || DriveTo.work:
        final places = await ref.hold(drivePlacesProvider.future);
        return setup.to == DriveTo.home ? places.home : places.work;
      case DriveTo.own:
        final own = setup.own;
        return own == null
            ? null
            : resolveDest(graph, streets, own, here: here);
    }
  }

  /// Reviews each of [decisions]' J cards by item 119 ([hesitated] alike in order): passes of the
  /// last [LearningConfig.habitWindowDays] make a habitual corridor, and a card credited today
  /// (or this week on a corridor) waits. Each decision of the route book taken without help is
  /// evidence, carded or not (a miss keeps it from going silent, item 113). [effects] holds what
  /// each did to its card, in order (item 124).
  Future<({int credited, int failed, List<String?> effects})> _credit(
    List<PassedDecision> decisions,
    List<bool> hesitated,
    DateTime now,
  ) async {
    final dao = ref.read(learningDaoProvider);
    final cards = {for (final c in await dao.cards()) c.itemId: c};
    final book = (await ref.read(routeBookProvider.future)).questions;
    final since = now.subtract(
      const Duration(days: LearningConfig.habitWindowDays),
    );
    final lastCredited = <String, DateTime>{
      for (final e in await dao.log(since: since))
        if (e.source == ReviewSource.drive && e.rating.isSuccess)
          e.itemId: e.ts,
    };
    final passes = <String, List<DateTime>>{};
    for (final r in await ref.read(driveLogDaoProvider).decisions()) {
      if (r.itemKey case final key? when r.at.isAfter(since)) {
        passes.putIfAbsent(key, () => []).add(r.at);
      }
    }
    final evidence = <({String itemId, bool ok})>[];
    final reviews = <({CardState card, LogEntry log})>[];
    final effects = List<String?>.filled(decisions.length, null);
    for (final (i, d) in decisions.indexed) {
      final key = d.key;
      final ok = d.ok;
      if (key == null || ok == null) continue;
      if (book[key] is TurnQuestion &&
          d.help == NavHelp.none &&
          !d.recentHelp) {
        evidence.add((itemId: key, ok: ok));
      }
      final (:review, :skip) = driveReview(
        cards[key],
        ok: ok,
        help: d.help,
        recentHelp: d.recentHelp,
        hesitated: hesitated[i],
        now: now,
        passes: [...?passes[key], d.at],
        lastCredited: lastCredited[key],
      );
      effects[i] = review?.log.rating.name ?? skip?.name;
      if (review == null) continue;
      reviews.add(review);
      cards[key] = review.card;
      if (review.log.rating.isSuccess) lastCredited[key] = now;
    }
    if (evidence.isNotEmpty || reviews.isNotEmpty) {
      await dao.saveTest(
        source: ReviewSource.drive,
        at: now,
        evidence: evidence,
        reviews: reviews,
      );
    }
    final credited = reviews.where((r) => r.log.rating.isSuccess).length;
    return (
      credited: credited,
      failed: reviews.length - credited,
      effects: effects,
    );
  }

  /// Writes the drive, its track and its [decisions] ([hesitated] alike in order) to the drive
  /// log (SPEC §16.23 item 124).
  Future<void> _log(
    DriveRecording recording,
    DriveReview review, {
    required DateTime endedAt,
    required List<PassedDecision> decisions,
    required List<bool> hesitated,
    required List<String?> effects,
    required int recoveries,
  }) async {
    final fixes = List.of(_fixes);
    final pack = await ref.read(packRepositoryProvider.future);
    final nodes = pack.junctionNodes();
    final match = review.match;
    final graded = review.graded;
    final keys = recording.suggestion?.keys ?? const <String>{};
    final id = review.id!;
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
                hesitated: hesitated[seq],
                keyTurn: keys.contains(d.key),
                effect: effects[seq],
              ),
          ],
          DriveRow(
            id: id,
            startedAt: recording.startedAt,
            endedAt: endedAt,
            level: _startLevel,
            goal: recording.to.name,
            targetNode: nodes[recording.target.junction],
            targetStreet: recording.target.street.id,
            targetPlace: recording.target.place?.id,
            startNode: nodes[match.path.junctions.firstOrNull],
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
            mostHelp: _mostHelp,
          ),
          encodeTrack(fixes),
        );
    ref
      ..invalidate(pastDrivesProvider)
      ..invalidate(navHistoryProvider)
      ..invalidate(driveHistoryProvider)
      ..invalidate(pendingDebriefProvider);
  }
}
