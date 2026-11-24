import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/database/database.dart';
import 'package:pindoro/core/database/settings_dao.dart';
import 'package:pindoro/core/drive_device.dart';
import 'package:pindoro/core/hold.dart';
import 'package:pindoro/core/location.dart';
import 'package:pindoro/features/drive/ui/drive_notes.dart';
import 'package:pindoro/features/drive/ui/drive_state.dart';
import 'package:pindoro/features/drive/ui/nav_voice.dart';
import 'package:pindoro/features/learning/data/drive_history.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/drive_save.dart';
import 'package:pindoro/features/learning/data/drive_suggest.dart';
import 'package:pindoro/features/learning/data/learning_dao.dart';
import 'package:pindoro/features/learning/data/nav_data.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

export 'package:pindoro/features/drive/ui/drive_state.dart';
export 'package:pindoro/features/learning/data/drive_places.dart'
    show DriveDest, DriveTarget;

final driveControllerProvider =
    NotifierProvider.autoDispose<DriveController, DriveState>(
      DriveController.new,
    );

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

  /// What the drive says, one line at a time; [DriveRecording.speaking] meanwhile.
  late final SpeechQueue _speech = SpeechQueue(
    (text) => _device.say(text, _voice),
    onSpeaking: (on) {
      if (ref.mounted) _speaking(on: on);
    },
  );

  /// The fixes before the destination changed or the last stop on the way was reached (items
  /// 116, 134): the drive is graded from there, its route starting at [_gradedStart].
  int _changedAt = 0;
  int? _gradedStart;

  /// The key turns of every route driven (the setup's, then each destination change's), logged
  /// as such (item 121).
  final Set<String> _keyTurns = {};

  Future<LocationResult>? _locating;
  Future<LatLng?>? _refining;

  /// What the drive said, showed and was touched for (item 124), saved with it.
  late final DriveNotes _notes = DriveNotes(() => ref.read(clockProvider)());

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
      state = DriveSetup(to: to, via: s.via, here: s.here);
      unawaited(_prepare());
    }
  }

  /// A street or place the player searched for, or a recent destination.
  void pickOwn(DriveDest dest) {
    if (state case final DriveSetup s) {
      state = DriveSetup(to: DriveTo.own, own: dest, via: s.via, here: s.here);
      unawaited(_prepare());
    }
  }

  /// A destination picked where the route runs: the setup's own, or a change on a drive.
  Future<void> goTo(DriveDest dest) async {
    switch (state) {
      case DriveSetup():
        pickOwn(dest);
      case DriveRecording():
        await changeDestination(dest);
      case DriveReview():
    }
  }

  /// The same choice again once location was refused (back from the settings).
  void retry() {
    if (state case final DriveSetup s when s.denied != null) {
      state = DriveSetup(to: s.to, own: s.own, via: s.via);
      unawaited(_prepare());
    }
  }

  /// A stop on the way (item 134), last before the destination: at setup the routes are found
  /// again through it; on a drive, at any speed, the way on goes through it from the next fix.
  Future<void> addStop(DriveDest dest) async {
    if (!_canAddStop) return;
    final here = switch (state) {
      final DriveSetup s => s.here,
      final DriveRecording r => r.view?.at,
      DriveReview() => null,
    };
    final stop = await _target(DriveSetup(to: DriveTo.own, own: dest), here);
    // The stops as they are now: one may have been reached meanwhile.
    if (stop == null || !ref.mounted || !_canAddStop) return;
    _setVia([..._via, stop]);
  }

  /// Drops the [i]th stop on the way.
  void removeStop(int i) {
    final via = _via;
    if (i < 0 || i >= via.length || _ending) return;
    _setVia([...via]..removeAt(i));
  }

  /// The stops on the way now.
  List<DriveTarget> get _via => switch (state) {
    DriveSetup(:final via) || DriveRecording(:final via) => via,
    DriveReview() => const [],
  };

  bool get _canAddStop =>
      state is! DriveReview &&
      _via.length < LearningConfig.navViaMax &&
      !_ending;

  void _setVia(List<DriveTarget> via) {
    switch (state) {
      case final DriveSetup s:
        // The level picked holds while the routes are found again.
        state = DriveSetup(
          to: s.to,
          own: s.own,
          via: via,
          here: s.here,
          level: s.level,
        );
        unawaited(_prepare());
      case final DriveRecording r:
        final graph = ref.read(drivingGraphProvider).value;
        final nav = _nav;
        if (graph == null || nav == null) return;
        nav.setVia([for (final t in via) viaStopOf(graph, t)]);
        state = r.copyWith(via: via);
      case DriveReview():
    }
  }

  /// Where the phone is, one ask at a time: the setup's first `_prepare` and a destination
  /// chosen at once would ask twice, and the second ask fails while the dialog is up.
  Future<LocationResult> _locate() => _locating ??= ref
      .read(locationServiceProvider)
      .locate()
      .whenComplete(() => _locating = null);

  /// A fresh fix, one ask at a time.
  Future<LatLng?> _freshFix() => _refining ??= ref
      .read(locationServiceProvider)
      .freshFix()
      .whenComplete(() => _refining = null);

  /// The setup planned from [here], where the phone last knew it was (up to two minutes old):
  /// once [fresh] comes, it plans again from there when that lies more than [LearningConfig.navRefineM] away
  /// (item 135).
  Future<void> _refine(Future<LatLng?> fresh, LatLng here) async {
    final at = await fresh;
    if (!ref.mounted || at == null) return;
    final s = state;
    if (s is! DriveSetup || s.here != here) return;
    if (distanceBetween(here, at) > LearningConfig.navRefineM) {
      await _prepare(at: at);
    }
  }

  /// A level the setup offers (item 114).
  void pickLevel(DriveLevel level) {
    if (state case final DriveSetup s when s.choices.contains(level)) {
      state = s.picking(s.suggestion, level);
    }
  }

  /// One of the setup's route [DriveSetup.options] (item 129); the level suggested follows it.
  void pickRoute(DriveSuggestion route) {
    if (state case final DriveSetup s when s.options.contains(route)) {
      state = s.picking(route, _keptLevel(s.to, route, s.level));
    }
  }

  /// The level picked so far, when [suggestion]'s choices still offer it (any on today's run).
  static DriveLevel? _keptLevel(
    DriveTo? to,
    DriveSuggestion? suggestion,
    DriveLevel? picked,
  ) => switch (suggestion) {
    final s? when to != DriveTo.run =>
      levelChoices(s.level).contains(picked) ? picked : null,
    _ => picked,
  };

  /// Finds where the player is (or takes [at], a fresh fix) and, once a destination is chosen,
  /// the target and the level suggested for the route there.
  Future<void> _prepare({LatLng? at}) async {
    final setup = state;
    if (setup is! DriveSetup) return;
    final located = at == null ? await _locate() : Located(at);
    if (!ref.mounted) return;
    bool current() =>
        state is DriveSetup && (state as DriveSetup).sameChoice(setup);
    if (!current()) return;
    if (located is LocationDenied) {
      state = DriveSetup(
        to: setup.to,
        own: setup.own,
        via: setup.via,
        denied: located,
      );
      return;
    }
    final here = located is Located ? located.position : null;
    // Asked now, while the routes are found; weighed once they show.
    final fresh = here == null || at != null ? null : _freshFix();
    void refine() {
      if (fresh != null) unawaited(_refine(fresh, here!));
    }

    if (setup.to == null) {
      state = DriveSetup(via: setup.via, here: here);
      refine();
      return;
    }
    final found = await _find(setup, here);
    if (!ref.mounted || !current()) return;
    final quickest = found?.options.firstOrNull;
    state = DriveSetup(
      to: setup.to,
      own: setup.own,
      via: setup.via,
      here: here,
      noTarget: found == null,
      target: found?.target,
      options: found?.options ?? const [],
      suggestion: quickest,
      level: _keptLevel(setup.to, quickest, (state as DriveSetup).level),
    );
    refine();
  }

  /// The setup's destination from [here] and its route options; for Surprise me the first new
  /// destination whose quickest route is [LearningConfig.surpriseMinShare] the player's
  /// (item 122).
  Future<({DriveTarget target, List<DriveSuggestion> options})?> _find(
    DriveSetup setup,
    LatLng? here,
  ) async {
    if (setup.to != DriveTo.surprise) {
      final target = await _target(setup, here);
      if (target == null) return null;
      return (
        target: target,
        options: here == null
            ? const <DriveSuggestion>[]
            : await _suggest(target, here, via: setup.via),
      );
    }
    if (here == null) return null;
    final graph = await ref.hold(drivingGraphProvider.future);
    final suggest = await routeSuggester(ref, here);
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
    ).take(LearningConfig.surpriseTries)) {
      if (driven.contains(nodes[j])) continue;
      final street = streetAt(graph, streets, j);
      if (street == null) continue;
      final target = (junction: j, street: street, place: null, at: null);
      final s = suggest(target, count: 1).firstOrNull;
      if (s != null &&
          s.turns > 0 &&
          s.yours / s.turns >= LearningConfig.surpriseMinShare) {
        return (target: target, options: suggest(target, via: setup.via));
      }
    }
    return null;
  }

  /// Up to [count] route options to [target] from [here] with their suggestions, the quickest
  /// first.
  Future<List<DriveSuggestion>> _suggest(
    DriveTarget target,
    LatLng here, {
    int count = LearningConfig.navOptions,
    List<DriveTarget> via = const [],
  }) async =>
      (await routeSuggester(ref, here))?.call(target, count: count, via: via) ??
      const [];

  /// Start drive: the destination found at setup (or now) and the track, its notification
  /// reading [title] and [text]; the navigator speaks from the first fix.
  Future<void> start({required String title, required String text}) =>
      _once(() => _start(title, text));

  Future<void> _start(String title, String text) async {
    final setup = state;
    if (setup is! DriveSetup || setup.to == null) return;
    var target = setup.target;
    var start = setup.here;
    if (target == null) {
      final here = await _locate();
      if (!ref.mounted) return;
      if (here is LocationDenied) {
        state = DriveSetup(
          to: setup.to,
          own: setup.own,
          via: setup.via,
          denied: here,
        );
        return;
      }
      start ??= here is Located ? here.position : null;
      target = await _target(setup, start);
      if (!ref.mounted) return;
      if (target == null) {
        state = DriveSetup(
          to: setup.to,
          own: setup.own,
          via: setup.via,
          here: start,
          noTarget: true,
        );
        return;
      }
    }
    final graph = await ref.hold(drivingGraphProvider.future);
    if (graph == null || !ref.mounted) return;
    final pack = await ref.read(packRepositoryProvider.future);
    final streets = await ref.read(cityStreetsProvider.future);
    final landmarks = await ref.hold(navLandmarksProvider.future);
    final settings = await ref.read(settingsDaoProvider).read();
    final districts = pack.districts();
    final districtsById = {for (final d in districts) d.id: d};
    await _pickVoice(settings, districtsById);
    // A level picked while the phone was being found counts; another destination stops here.
    final current = state;
    if (!ref.mounted || current is! DriveSetup || !current.sameChoice(setup)) {
      return;
    }
    // The target the suggestion was planned to: a fresh fix may have found the setup's again.
    target = current.target ?? target;
    final suggestion = current.suggestion;
    _startLevel = current.chosen;
    _mostHelp = _startLevel;
    _suggested = suggestion?.level;
    _nav = Navigator(
      graph: graph,
      cost: NavCost(streets, toleranceKmh: settings.speedToleranceKmh),
      destination: suggestion?.plan.stop ?? stopsOf(graph, target).first,
      via: [for (final v in current.via) viaStopOf(graph, v)],
      level: _startLevel,
      streets: streets,
      landmarks: landmarks,
      junctionNodes: pack.junctionNodes(),
      silent: suggestion?.silent ?? const {},
      prefer: suggestion?.plan.route,
      districtAt: (p) => raionAt(districts, p)?.id,
    );
    _fixes.clear();
    _ending = false;
    _speech.clear();
    _changedAt = 0;
    _keyTurns
      ..clear()
      ..addAll(suggestion?.keys ?? const {});
    _notes.clear();
    await _device.start();
    await _device.keepScreenOn(on: _startLevel != DriveLevel.off);
    if (!ref.mounted) return;
    state = DriveRecording(
      target: target,
      destination: targetPoint(graph, target),
      to: setup.to!,
      via: current.via,
      startedAt: ref.read(clockProvider)(),
      level: _startLevel,
      choices: current.choices,
      start: start,
      suggestion: suggestion,
      districts: districtsById,
    );
    _track = ref
        .read(locationServiceProvider)
        .track(title: title, text: text)
        // ponytail: a failing stream shows as GPS lost (the ticks), nothing more to do here.
        .listen(_onFix, onError: (Object _) {});
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  /// Georgian (names in Georgian letters) when the app speaks Georgian and the phone has a
  /// Georgian voice, else English (names in Latin letters).
  Future<void> _pickVoice(
    Settings settings,
    Map<String, District> districts,
  ) async {
    final georgian =
        (settings.appLanguage?.name ??
                PlatformDispatcher.instance.locale.languageCode) ==
            'ka' &&
        await _device.canSpeak('ka-GE');
    _voice = georgian ? 'ka-GE' : 'en-US';
    _words = NavWords(
      lookupAppLocalizations(Locale(georgian ? 'ka' : 'en')),
      georgian: georgian,
      districts: districts,
    );
  }

  void _onFix(DriveFix fix) {
    final r = state;
    // A location cached from before the drive (iOS can hand one over first) isn't the car's.
    if (r is DriveRecording &&
        fix.t.isBefore(
          r.startedAt.subtract(
            const Duration(seconds: LearningConfig.driveStaleFixS),
          ),
        )) {
      return;
    }
    _fixes.add(fix);
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
    if (u.view.gpsLostS != null || u.prompts.isNotEmpty) _apply(r, u);
  }

  /// The drive went to [level]: the most help so far is kept (items 122–123).
  void _noteHelp(DriveLevel level) {
    if (level.index < _mostHelp.index) _mostHelp = level;
  }

  void _apply(DriveRecording r, NavUpdate u) {
    final next = r.copyWith(
      view: u.view,
      level: u.view.level,
      guardedAt: u.prompts.any((p) => p.kind == PromptKind.guard)
          ? ref.read(clockProvider)()
          : null,
      beat: u.chime ? r.beat + 1 : null,
    );
    state = next;
    _noteHelp(u.view.level);
    for (final p in u.prompts) {
      _notes.add(
        DriveEventKind.prompt,
        itemKey: p.decision?.key,
        detail: p.kind.name,
        value: r.muted ? 0 : 1,
      );
      if (r.muted) continue;
      unawaited(_speech.add(_words!.words(p, u.view.level), kind: p.kind));
      if (NavWords.streetSaid(p) case final s?) _notes.name(s, heard: true);
    }
    if (u.chime && !r.muted) unawaited(_device.chime());
    // The side as the car came along the stop's road: the new view already looks on.
    if (u.view.reached != null) _reachStop(next, side: r.view?.side);
    _notes.screen(state as DriveRecording);
    if (u.view.arrived && !_ending) {
      _ending = true;
      unawaited(_arrive(next));
    }
  }

  /// A touch on the screen while moving (item 124 expects none; Guided's map allows them).
  void noteTouch() {
    if (state case final DriveRecording r when !r.stopped && !_ending) {
      _notes.add(
        DriveEventKind.touch,
        detail: r.level.name,
        value: r.view?.speedKmh,
      );
    }
  }

  /// Coached's speaking bars.
  void _speaking({required bool on}) {
    if (state case final DriveRecording r when r.speaking != on) {
      state = r.copyWith(speaking: on);
    }
  }

  /// A stop on the way reached (item 134): said, dropped, and the drive graded from here on, as
  /// after a destination change.
  void _reachStop(DriveRecording r, {NavSide? side}) {
    final stop = r.via.firstOrNull;
    if (stop == null) return;
    _changedAt = _fixes.length;
    state = r.copyWith(via: r.via.sublist(1));
    if (r.muted || r.level == DriveLevel.off) return;
    if (stop.place == null) _notes.name(stop.street, heard: true);
    unawaited(_speech.add(_words!.reachedStop(stop, side: side)));
  }

  /// Arrival (item 116): the line said to its end, then the drive ends by itself.
  Future<void> _arrive(DriveRecording r) async {
    try {
      if (!r.muted && r.level != DriveLevel.off) {
        _notes.name(r.target.street, heard: true);
        await _speech.add(_words!.arrived(r.target.street, side: r.view?.side));
      }
    } finally {
      await end();
    }
  }

  /// Off's Rescue, while stopped (item 116): Guided from here, said once.
  void rescue() {
    final r = state;
    final nav = _nav;
    if (r is! DriveRecording ||
        nav == null ||
        _ending ||
        !r.stopped ||
        r.level != DriveLevel.off) {
      return;
    }
    nav.rescue();
    _noteHelp(DriveLevel.guided);
    _notes.screen(state = r.copyWith(level: DriveLevel.guided, rescued: true));
    unawaited(_device.keepScreenOn(on: true));
    if (!r.muted) unawaited(_speech.add(_words!.rescued));
  }

  /// Mute or unmute every prompt (item 117; Guided's at any speed, item 130); muting drops the
  /// lines waiting.
  void toggleMute() {
    if (state case final DriveRecording r when !_ending) {
      if (!r.muted) _speech.clear();
      state = r.copyWith(muted: !r.muted);
    }
  }

  /// A level picked applies at once (items 116, 130), among the setup's choices.
  void pickDriveLevel(DriveLevel level) {
    final r = state;
    final nav = _nav;
    if (r is! DriveRecording ||
        nav == null ||
        _ending ||
        level == r.level ||
        !r.choices.contains(level)) {
      return;
    }
    nav.setLevel(level);
    _noteHelp(level);
    _notes.screen(state = r.copyWith(level: level));
    unawaited(_device.keepScreenOn(on: level != DriveLevel.off));
  }

  /// The other ways on from the car (item 130's routes); none off the plan.
  List<NavPlan> routeOptions() =>
      _ending ? const [] : _nav?.routeOptions() ?? const [];

  /// Drives [option] (one of [routeOptions]) from here, at once.
  void takeRoute(NavPlan option) {
    if (!_ending) _nav?.takeRoute(option);
  }

  /// A destination changed, at any speed (items 116, 134): the way there, through the stops
  /// still on the way, from the next fix.
  Future<void> changeDestination(DriveDest dest) async {
    final r = state;
    final nav = _nav;
    if (r is! DriveRecording || nav == null || _ending) return;
    final at = r.view?.at;
    final target = await _target(DriveSetup(to: DriveTo.own, own: dest), at);
    final graph = await ref.hold(drivingGraphProvider.future);
    if (target == null || graph == null || !ref.mounted) return;
    final s = at == null
        ? null
        : (await _suggest(target, at, count: 1, via: r.via)).firstOrNull;
    if (!ref.mounted || state is! DriveRecording || _ending) return;
    nav.setDestination(
      s?.plan.stop ?? stopsOf(graph, target).first,
      silent: s?.silent ?? const {},
    );
    _changedAt = _fixes.length;
    _keyTurns.addAll(s?.keys ?? const {});
    state = (state as DriveRecording).copyWith(
      target: target,
      destination: targetPoint(graph, target),
      suggestion: s,
    );
  }

  /// End drive: stops the track, matches it to the streets, grades it against the best legal
  /// route to the destination, and reviews each decision's J card by item 119.
  Future<void> end() => _once(_end);

  Future<void> _end() async {
    final recording = state;
    if (recording is! DriveRecording) return;
    // The stopped controls go quiet at once: grading and saving take a while.
    _ending = true;
    _tick?.cancel();
    _speech.clear();
    await _track?.cancel();
    _track = null;
    final nav = _nav;
    unawaited(_device.stop());
    final now = ref.read(clockProvider)();
    final nodes = (await ref.read(
      packRepositoryProvider.future,
    )).junctionNodes();
    final (:match, :graded, :stoppedM, :decisions, :hesitated) = await _grade(
      recording,
      nav,
      nodes,
    );
    // The cards' reviews and the log land together: a failed save leaves End to try again
    // without crediting twice.
    final review = await ref.read(driveLogDaoProvider).transaction(() async {
      final (:credited, :failed, :effects) = await saveDriveCredit(
        ref,
        decisions,
        hesitated,
        now,
      );
      final review = DriveReview(
        id: _id,
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
        nodes: nodes,
        endedAt: now,
        decisions: decisions,
        hesitated: hesitated,
        effects: effects,
        recoveries: nav?.recoveries ?? 0,
      );
      return review;
    });
    _nav = null;
    _id = newId();
    if (!ref.mounted) return;
    state = review;
  }

  /// The drive's track matched to the streets and graded against the best legal route to the
  /// destination, and its decisions: the navigator's, or on a GPS-free drive (Off throughout)
  /// the graded path's; each with whether the car hesitated before it.
  Future<
    ({
      DriveMatch match,
      RecitalResult? graded,
      double? stoppedM,
      List<PassedDecision> decisions,
      List<bool> hesitated,
    })
  >
  _grade(DriveRecording recording, Navigator? nav, Map<int, int> nodes) async {
    final graph = (await ref.hold(drivingGraphProvider.future))!;
    final streets = await ref.read(cityStreetsProvider.future);
    // A destination changed or a stop reached on the way is graded from there. Each turn was
    // judged as it came.
    final (:match, :graded, :stoppedM, :start) = gradeDriveTrack(
      graph,
      _fixes,
      recording.target.junction,
      from: _changedAt,
      streets: streets,
    );
    _gradedStart = start;
    final decisions = reviewedDecisions(
      graph,
      startLevel: _startLevel,
      mostHelp: _mostHelp,
      passed: nav?.passed,
      graded: graded,
      fixes: _fixes,
      junctionNodes: nodes,
    );
    return (
      match: match,
      graded: graded,
      stoppedM: stoppedM,
      decisions: decisions,
      hesitated: [for (final d in decisions) hesitatedNear(graph, match, d)],
    );
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
            : (
                junction: run.ends.to,
                street: run.ends.toStreet,
                place: null,
                at: null,
              );
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

  /// Writes the drive, its track, its [decisions] ([hesitated] alike in order) and what it said,
  /// showed and was touched for to the drive log (SPEC §16.23 item 124).
  Future<void> _log(
    DriveRecording recording,
    DriveReview review, {
    required Map<int, int> nodes,
    required DateTime endedAt,
    required List<PassedDecision> decisions,
    required List<bool> hesitated,
    required List<String?> effects,
    required int recoveries,
  }) async {
    final fixes = List.of(_fixes);
    final match = review.match;
    final graded = review.graded;
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
                keyTurn: _keyTurns.contains(d.key),
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
            targetLat: recording.target.at?.lat,
            targetLon: recording.target.at?.lon,
            gradedFrom: _changedAt == 0 ? null : _changedAt,
            startNode: nodes[_gradedStart],
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
          notes: _notes.all,
        );
    ref
      ..invalidate(pastDrivesProvider)
      ..invalidate(navHistoryProvider)
      ..invalidate(driveHistoryProvider)
      ..invalidate(pendingDebriefProvider);
  }
}
