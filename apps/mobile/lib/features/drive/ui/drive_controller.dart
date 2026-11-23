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

bool _sameVia(List<DriveTarget> a, List<DriveTarget> b) =>
    a.length == b.length && a.indexed.every((e) => e.$2 == b[e.$1]);

/// Choosing where to go and how much help: no [to] while searching; today's run, a surprise,
/// Home, Work or the player's [own] street or place. [here] once found, [denied] once location
/// was refused; [noTarget] when nothing fits the choice. [target] and the route [options] (the
/// quickest first, item 129) once found from where the player is, [suggestion] the one picked;
/// [level] once picked (else the suggestion). [via]: the stops on the way, in order (item 134).
final class DriveSetup extends DriveState {
  const DriveSetup({
    this.to,
    this.own,
    this.via = const [],
    this.here,
    this.denied,
    this.noTarget = false,
    this.target,
    this.options = const [],
    this.suggestion,
    this.level,
  });

  final DriveTo? to;
  final DriveDest? own;
  final List<DriveTarget> via;
  final LatLng? here;
  final LocationDenied? denied;
  final bool noTarget;
  final DriveTarget? target;
  final List<DriveSuggestion> options;
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

  bool sameChoice(DriveSetup other) =>
      to == other.to && own == other.own && _sameVia(via, other.via);

  /// This setup with [suggestion] and [level] picked.
  DriveSetup picking(DriveSuggestion? suggestion, DriveLevel? level) =>
      DriveSetup(
        to: to,
        own: own,
        via: via,
        here: here,
        denied: denied,
        noTarget: noTarget,
        target: target,
        options: options,
        suggestion: suggestion,
        level: level,
      );
}

/// Driving to [target] (at [destination]) since [startedAt] at [level] (the guard, Rescue and a
/// pick while stopped change it, among the setup's [choices]); [view] is the
/// navigator's latest. [speaking] while a prompt is said, [guardedAt] when the guard last
/// stepped in, [beat] counts the speed chimes (each pulses the sign). [start] is where the
/// setup found the phone: the map opens there until the first fix. [districts] by id name the
/// view's district.
final class DriveRecording extends DriveState {
  const DriveRecording({
    required this.target,
    required this.destination,
    required this.to,
    this.via = const [],
    required this.startedAt,
    required this.level,
    required this.choices,
    this.start,
    this.suggestion,
    this.view,
    this.muted = false,
    this.rescued = false,
    this.speaking = false,
    this.guardedAt,
    this.beat = 0,
    this.districts = const {},
  });

  final DriveTarget target;
  final LatLng destination;
  final DriveTo to;

  /// The stops on the way not reached yet, in order (item 134).
  final List<DriveTarget> via;
  final DateTime startedAt;
  final DriveLevel level;
  final List<DriveLevel> choices;
  final LatLng? start;
  final DriveSuggestion? suggestion;
  final NavView? view;
  final bool muted;
  final bool rescued;
  final bool speaking;
  final DateTime? guardedAt;
  final int beat;
  final Map<String, District> districts;

  /// The district the car is in.
  District? get district => districts[view?.district];

  /// Controls take input only while stopped (item 116); before the first fix the car hasn't
  /// moved.
  bool get stopped => view?.stopped ?? true;

  DriveRecording copyWith({
    DriveTarget? target,
    LatLng? destination,
    List<DriveTarget>? via,
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
    via: via ?? this.via,
    startedAt: startedAt,
    level: level ?? this.level,
    choices: choices,
    start: start,
    suggestion: suggestion,
    view: view ?? this.view,
    muted: muted ?? this.muted,
    rescued: rescued ?? this.rescued,
    speaking: speaking ?? this.speaking,
    guardedAt: guardedAt ?? this.guardedAt,
    beat: beat ?? this.beat,
    districts: districts,
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

/// A fix timed this long before the drive started is a cached location, not the car's.
const Duration _staleFix = Duration(seconds: 30);

/// A fresh fix this far from the one the setup planned from plans again (item 135).
const double _refineM = 50;

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
  Future<LocationResult>? _locating;
  Future<LatLng?>? _refining;

  /// What the drive said, showed and was touched for (item 124), saved with it; the names
  /// heard or shown so far and the screen shown last.
  final List<DriveNote> _notes = [];
  final Set<(String, String)> _named = {};
  String? _screen;

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
    final s = state;
    final via = switch (s) {
      DriveSetup(:final via) || DriveRecording(:final via) => via,
      _ => null,
    };
    if (via == null || via.length >= LearningConfig.navViaMax || _ending) {
      return;
    }
    final here = switch (s) {
      final DriveSetup s => s.here,
      final DriveRecording r => r.view?.at,
      _ => null,
    };
    final stop = await _target(DriveSetup(to: DriveTo.own, own: dest), here);
    if (stop == null || !ref.mounted) return;
    _setVia([...via, stop]);
  }

  /// Drops the [i]th stop on the way.
  void removeStop(int i) {
    final via = switch (state) {
      DriveSetup(:final via) || DriveRecording(:final via) => via,
      _ => const <DriveTarget>[],
    };
    if (i < 0 || i >= via.length || _ending) return;
    _setVia([...via]..removeAt(i));
  }

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
  /// once [fresh] comes, it plans again from there when that lies more than [_refineM] away
  /// (item 135).
  Future<void> _refine(Future<LatLng?> fresh, LatLng here) async {
    final at = await fresh;
    if (!ref.mounted || at == null) return;
    final s = state;
    if (s is! DriveSetup || s.here != here) return;
    if (distanceBetween(here, at) > _refineM) await _prepare(at: at);
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

  /// How many surprise destinations are planned before giving up.
  static const int _surpriseTries = 12;

  /// Up to [count] route options to [target] from [here] with their suggestions, the quickest
  /// first.
  Future<List<DriveSuggestion>> _suggest(
    DriveTarget target,
    LatLng here, {
    int count = LearningConfig.navOptions,
    List<DriveTarget> via = const [],
  }) async =>
      (await _suggester(here))?.call(target, count: count, via: via) ??
      const [];

  /// The route options for a target from [here] through the stops `via` (up to `count`, the
  /// quickest first), each with its suggestion; the graph, cards and history read once
  /// (Surprise me tries up to [_surpriseTries] targets). Null without a road graph.
  Future<
    List<DriveSuggestion> Function(
      DriveTarget target, {
      int count,
      List<DriveTarget> via,
    })?
  >
  _suggester(LatLng here) async {
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
    DriveSuggestion suggestion(NavPlan plan, int areaJ) {
      final keys = [for (final d in plan.decisions) d.key];
      final s = routeSuggestion(
        keys: keys,
        cards: cards,
        history: history.decisions,
        past: history.past,
        areaJ: areaJ,
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
    }

    return (
      DriveTarget target, {
      int count = LearningConfig.navOptions,
      List<DriveTarget> via = const [],
    }) {
      final raion = raionAt(districts, graph.at(target.junction));
      final areaJ = raion == null
          ? 0
          : jCardsIn(raion, cards.values, byNode, graph);
      return [
        for (final plan in plansFrom(
          graph,
          here,
          stopsOf(graph, target),
          via: [for (final v in via) viaStopOf(graph, v)],
          streets: streets,
          landmarks: landmarks,
          junctionNodes: nodes,
          toleranceKmh: settings.speedToleranceKmh,
          count: count,
        ))
          suggestion(plan, areaJ),
      ];
    };
  }

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
        state = DriveSetup(to: setup.to, own: setup.own, denied: here);
        return;
      }
      start ??= here is Located ? here.position : null;
      target = await _target(setup, start);
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
    final districts = pack.districts();
    final districtsById = {for (final d in districts) d.id: d};
    await _pickVoice(settings, districtsById);
    // A level picked while the phone was being found counts; another destination stops here.
    final current = state;
    if (!ref.mounted || current is! DriveSetup || !current.sameChoice(setup)) {
      return;
    }
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
    _notes.clear();
    _named.clear();
    _screen = null;
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
        fix.t.isBefore(r.startedAt.subtract(_staleFix))) {
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
      _note(
        DriveEventKind.prompt,
        itemKey: p.decision?.key,
        detail: p.kind.name,
        value: r.muted ? 0 : 1,
      );
      if (r.muted) continue;
      unawaited(_speech.add(_words!.words(p, u.view.level), kind: p.kind));
      if (NavWords.streetSaid(p) case final s?) _noteName(s, heard: true);
    }
    if (u.chime && !r.muted) unawaited(_device.chime());
    // The side as the car came along the stop's road: the new view already looks on.
    if (u.view.reached != null) _reachStop(next, side: r.view?.side);
    _noteScreen(state as DriveRecording);
    if (u.view.arrived && !_ending) {
      _ending = true;
      unawaited(_arrive(next));
    }
  }

  void _note(
    DriveEventKind kind, {
    String? itemKey,
    String? detail,
    double? value,
  }) => _notes.add((
    at: ref.read(clockProvider)(),
    kind: kind,
    itemKey: itemKey,
    detail: detail,
    value: value,
  ));

  /// The first time [street] is heard or shown on this drive.
  void _noteName(NamedStreet street, {required bool heard}) {
    final how = heard ? 'heard' : 'shown';
    if (_named.add((street.id, how))) {
      _note(DriveEventKind.name, itemKey: street.id, detail: how);
    }
  }

  /// The screen [r] shows, when it changed, and the street names on it: Guided's street and
  /// turn card, a recovery's next street.
  void _noteScreen(DriveRecording r) {
    final v = r.view;
    final screen = [
      r.level.name,
      if (v?.recovering ?? false) 'recovery',
      if (v?.gpsLostS != null) 'lost',
      if (r.stopped) 'stopped',
    ].join(' ');
    if (screen != _screen) {
      _screen = screen;
      _note(DriveEventKind.screen, detail: screen);
    }
    if (v == null || v.gpsLostS != null) return;
    final next = v.next;
    final card = next != null && (v.prepareM != null || v.turned == null)
        ? next.street
        : v.turned?.street;
    for (final s in switch (r.level) {
      DriveLevel.guided => [v.street, card],
      _ when v.recovering => [next?.street],
      _ => const <NamedStreet?>[],
    }.nonNulls) {
      _noteName(s, heard: false);
    }
  }

  /// A touch on the screen while moving (item 124 expects none; Guided's map allows them).
  void noteTouch() {
    if (state case final DriveRecording r when !r.stopped && !_ending) {
      _note(
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
    if (stop.place == null) _noteName(stop.street, heard: true);
    unawaited(_speech.add(_words!.reachedStop(stop, side: side)));
  }

  /// Arrival (item 116): the line said to its end, then the drive ends by itself.
  Future<void> _arrive(DriveRecording r) async {
    try {
      if (!r.muted && r.level != DriveLevel.off) {
        _noteName(r.target.street, heard: true);
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
    _noteScreen(state = r.copyWith(level: DriveLevel.guided, rescued: true));
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
    _noteScreen(state = r.copyWith(level: level));
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
    state = (state as DriveRecording).copyWith(
      target: target,
      destination: targetPoint(graph, target),
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
      nodes: nodes,
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
    final match = matchDrive(graph, _fixes);
    // A destination changed or a stop reached on the way is graded from there: the way to it
    // isn't a detour. Each turn was judged as it came.
    final last = _changedAt == 0
        ? match
        : matchDrive(graph, _fixes.sublist(_changedAt));
    _gradedStart = last.path.junctions.firstOrNull;
    final (:graded, :stoppedM) = gradeDrive(
      graph,
      last,
      recording.target.junction,
      streets: streets,
    );
    final gpsFree =
        _startLevel == DriveLevel.off && _mostHelp == DriveLevel.off;
    final decisions = gpsFree || nav == null
        ? (graded == null
              ? const <PassedDecision>[]
              : offDriveDecisions(graph, graded, _fixes, junctionNodes: nodes))
        : nav.passed;
    return (
      match: match,
      graded: graded,
      stoppedM: stoppedM,
      decisions: decisions,
      hesitated: [
        for (final d in decisions) hesitatedNear(graph, match, d.junction),
      ],
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
          notes: List.of(_notes),
        );
    ref
      ..invalidate(pastDrivesProvider)
      ..invalidate(navHistoryProvider)
      ..invalidate(driveHistoryProvider)
      ..invalidate(pendingDebriefProvider);
  }
}
