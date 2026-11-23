import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pindoro/core/clock.dart';
import 'package:pindoro/core/compass.dart';
import 'package:pindoro/core/database/database.dart' show Settings;
import 'package:pindoro/core/format.dart';
import 'package:pindoro/core/labels.dart';
import 'package:pindoro/core/page_scaffold.dart';
import 'package:pindoro/core/routes.dart';
import 'package:pindoro/core/settings.dart';
import 'package:pindoro/features/drive/ui/debrief_data.dart';
import 'package:pindoro/features/drive/ui/drive_levels.dart';
import 'package:pindoro/features/drive/ui/plan_map.dart';
import 'package:pindoro/features/learning/data/drive_history.dart';
import 'package:pindoro/features/learning/data/drive_log.dart';
import 'package:pindoro/features/learning/data/drive_places.dart';
import 'package:pindoro/features/learning/data/runs.dart';
import 'package:pindoro/features/learning/ui/drive_labels.dart';
import 'package:pindoro/features/learning/ui/junction_name.dart';
import 'package:pindoro/features/map/ui/widgets/tier_reveal.dart';
import 'package:pindoro/features/pack/data/sqlite_pack_repository.dart';
import 'package:pindoro/l10n/app_localizations.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';
import 'package:pindoro_learning/pindoro_learning.dart';

enum _Step { offer, recall, reveal, review, summary, streets, point }

/// A drive's debrief (board V32-50, SPEC §16.23 item 121), also a past drive (V32-60). Fresh
/// (within [LearningConfig.debriefOfferHours] of its end and not gone through) it offers the
/// walk: each turn recalled before it's shown, the whole drive with its review marks, the tier
/// and numbers, the streets driven with a drill of the missed turns, and once per new
/// destination Point to home. Otherwise it opens on the tier and numbers, with the turns a tap
/// away.
class DebriefScreen extends ConsumerStatefulWidget {
  const DebriefScreen({required this.id, required this.onDone, super.key});

  final String id;
  final VoidCallback onDone;

  @override
  ConsumerState<DebriefScreen> createState() => _DebriefScreenState();
}

class _DebriefScreenState extends ConsumerState<DebriefScreen> {
  _Step? _step;

  /// Going through the whole debrief (from the offer), not looking back at a past drive.
  bool _walk = false;
  int _turn = 0;

  /// What the driver said they did at the turn; null for "I don't remember".
  Turn? _said;

  void _go(_Step step) => setState(() => _step = step);

  Future<void> _log(DriveEventKind kind, {String? itemKey, double? value}) =>
      ref
          .read(driveLogDaoProvider)
          .addEvent(
            driveId: widget.id,
            at: ref.read(clockProvider)(),
            kind: kind,
            itemKey: itemKey,
            value: value,
          );

  void _recall(DebriefTurn t, Turn? said) {
    final done = _turnOf(t.exits, t.done);
    unawaited(
      _log(
        DriveEventKind.recall,
        itemKey: t.key,
        value: said == null ? null : (said == done ? 1 : 0),
      ),
    );
    setState(() {
      _said = said;
      _step = _Step.reveal;
    });
  }

  Future<void> _nextTurn(DriveDebrief d) async {
    if (_turn + 1 < d.turns.length) {
      setState(() {
        _turn++;
        _step = _Step.recall;
      });
      return;
    }
    await _log(DriveEventKind.debrief, value: d.turns.length.toDouble());
    if (!mounted) return;
    ref.invalidate(pendingDebriefProvider);
    _go(_Step.review);
  }

  @override
  Widget build(BuildContext context) {
    final debrief = ref.watch(driveDebriefProvider(widget.id));
    final d = debrief.value;
    if (d == null) {
      return debrief.isLoading
          ? const Scaffold(body: Center(child: LaneLoader()))
          : PageScaffold(
              title: context.l10n.pastDrivesTitle,
              children: [
                Text(context.l10n.pastDriveGone, style: PindoroType.bodyMd),
              ],
            );
    }
    if (_step == null) {
      final ago = ref.read(clockProvider)().difference(d.drive.endedAt);
      _walk = ago.inHours < LearningConfig.debriefOfferHours && !d.recalled;
      _step = _walk && d.turns.isNotEmpty ? _Step.offer : _Step.summary;
    }
    final afterStreets = d.point ? _Step.point : null;
    return switch (_step!) {
      _Step.offer => _Offer(
        debrief: d,
        onGo: () => _go(_Step.recall),
        onLater: widget.onDone,
      ),
      _Step.recall => _Recall(
        debrief: d,
        index: _turn,
        onSaid: (said) => _recall(d.turns[_turn], said),
      ),
      _Step.reveal => _Reveal(
        debrief: d,
        index: _turn,
        said: _said,
        onNext: () => _nextTurn(d),
      ),
      _Step.review => _Review(
        debrief: d,
        action: _walk ? context.l10n.commonNext : context.l10n.commonDone,
        onNext: _walk ? () => _go(_Step.summary) : widget.onDone,
      ),
      _Step.summary => _Summary(
        debrief: d,
        walk: _walk,
        onNext: _walk
            ? () => _go(_Step.streets)
            : d.marks.isEmpty
            ? widget.onDone
            : () => _go(_Step.review),
      ),
      _Step.streets => _Streets(
        debrief: d,
        onNext: afterStreets == null ? widget.onDone : () => _go(afterStreets),
      ),
      _Step.point => _Point(
        debrief: d,
        onPointed: (error) =>
            unawaited(_log(DriveEventKind.point, value: error)),
        onDone: widget.onDone,
      ),
    };
  }
}

/// The way on [exits] that [edge] leaves by; null when the ways can't be told apart by
/// direction.
Turn? _turnOf(Map<Turn, RoadEdge>? exits, RoadEdge edge) =>
    exits?.entries.where((e) => e.value.id == edge.id).firstOrNull?.key;

/// A turn as a word for the sentences: left, right, straight on, back.
String _turnName(Turn? t) => t?.name ?? 'other';

MarkKind _kind(TurnMark mark) => MarkKind.values.byName(mark.name);

String _markName(AppLocalizations l10n, TurnMark mark) => switch (mark) {
  TurnMark.good => l10n.markGood,
  TurnMark.hard => l10n.markHard,
  TurnMark.again => l10n.markAgain,
  TurnMark.helped => l10n.markHelped,
  TurnMark.watched => l10n.markWatched,
};

String _markNote(AppLocalizations l10n, TurnMark mark) => switch (mark) {
  TurnMark.good => l10n.markGoodNote,
  TurnMark.hard => l10n.markHardNote,
  TurnMark.again => l10n.markAgainNote,
  TurnMark.helped => l10n.markHelpedNote,
  TurnMark.watched => l10n.markWatchedNote,
};

/// The drive's route and track, and where it started and ended.
typedef _Lines = ({
  MultiPolyline route,
  MultiPolyline track,
  LatLng? start,
  LatLng? end,
});

_Lines _lines(DriveDebrief d, RoadGraph? graph) {
  final track = d.review.match.path.lines;
  return (
    route: d.review.graded?.best?.lines ?? const [],
    track: track,
    start: track.firstOrNull?.firstOrNull,
    end: graph == null ? null : targetPoint(graph, d.review.target),
  );
}

/// What names turn [t]: its landmark, else its streets, else "this junction".
String _placeOf(
  AppLocalizations l10n,
  DebriefTurn t,
  RoadGraph graph,
  Map<String, NamedStreet> streets,
  Settings? settings,
) => switch (t.landmark) {
  final l? => landmarkName(l, settings),
  null =>
    junctionName(graph, t.junction, streets, settings) ??
        l10n.debriefThisJunction,
};

/// [edge]'s street by its shown name; a link road has none.
String _streetOf(
  AppLocalizations l10n,
  RoadEdge edge,
  Map<String, NamedStreet> streets,
  Settings? settings,
) => switch (streets[edge.streetId]) {
  final s? => streetName(s, settings),
  null => l10n.debriefLinkRoad,
};

/// The turn being gone through on the map: the way in (and, revealed, the way taken) in
/// cobalt, a good way on in yellow.
Widget _turnMap(
  BuildContext context,
  RoadGraph graph,
  DebriefTurn t, {
  required int number,
  required bool revealed,
  required Widget bottom,
}) {
  final approach = t.approach.lineFrom(t.approach.other(t.junction));
  final done = t.done.lineFrom(t.junction);
  final way = t.way.lineFrom(t.junction);
  return PlanMapLayout(
    semanticsLabel: context.l10n.a11yDebriefTurnMap,
    track: [approach, if (revealed) done],
    route: [if (revealed) way],
    frame: [...approach, ...done, ...way],
    pins: [
      (
        graph.at(t.junction),
        revealed && t.mark != null
            ? ReviewMark(_kind(t.mark!), onMap: true)
            : TurnNumber(number, onMap: true, current: true),
      ),
    ],
    bottom: bottom,
  );
}

/// The turns' progress over a panel: "Turn 2 of 5 · first say, then see".
Widget _turnDots(AppLocalizations l10n, int index, int count) => StepDots(
  count: count,
  current: index,
  line: l10n.debriefTurnOf(index + 1, count),
  semanticsLabel: l10n.a11yDebriefTurns,
  semanticsValue: l10n.a11yStepOf(index + 1, count),
);

/// On arrival (V32-50 `offer`): where the drive ended, its turns, time and level; go through
/// it now or later (it stays offered for a day).
class _Offer extends ConsumerWidget {
  const _Offer({
    required this.debrief,
    required this.onGo,
    required this.onLater,
  });

  final DriveDebrief debrief;
  final VoidCallback onGo;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final graph = ref.watch(drivingGraphProvider).value;
    final d = debrief;
    final lines = _lines(d, graph);
    final minutes = d.drive.endedAt
        .difference(d.drive.startedAt)
        .inMinutes
        .clamp(1, 1 << 20);
    return Scaffold(
      body: PlanMapLayout(
        semanticsLabel: l10n.a11yDriveMap,
        frame: [for (final line in lines.track) ...line, ?lines.end],
        start: lines.start,
        end: lines.end,
        bottom: BottomPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s3,
            children: [
              Semantics(
                header: true,
                child: Text(
                  d.drive.outcome == DriveOutcome.arrived
                      ? l10n.debriefArrived(
                          streetName(d.review.target.street, settings),
                        )
                      : l10n.debriefEnded,
                  style: PindoroType.titleLg.copyWith(color: c.textPrimary),
                ),
              ),
              Text(
                [
                  l10n.debriefTurnCount(d.marks.length),
                  l10n.debriefMinutes(minutes),
                  levelLabel(l10n, d.drive.level),
                ].join(' · '),
                style: PindoroType.labelMd.copyWith(color: c.textSecondary),
              ),
              Text(
                l10n.debriefOfferNote,
                style: PindoroType.bodyMd.copyWith(color: c.textPrimary),
              ),
              PindoroButton(label: l10n.debriefGo, onPressed: onGo),
              PindoroButton(
                label: l10n.debriefLater,
                variant: PindoroButtonVariant.tertiary,
                onPressed: onLater,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One turn, before it's shown (V32-50 `recall`): the way in and the junction, "what did you
/// do?" with its ways on, or "I don't remember".
class _Recall extends ConsumerWidget {
  const _Recall({
    required this.debrief,
    required this.index,
    required this.onSaid,
  });

  final DriveDebrief debrief;
  final int index;
  final ValueChanged<Turn?> onSaid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final graph = ref.watch(drivingGraphProvider).value;
    final streets = ref.watch(cityStreetsProvider).value;
    if (graph == null || streets == null) return const Scaffold();
    final t = debrief.turns[index];
    final heading = l10n.compassWord(
      compassPointOf(arrivingBearing(t.approach, t.junction)).name,
    );
    final came = switch (streets[t.approach.streetId]) {
      final s? => l10n.debriefCame(streetName(s, settings), heading),
      null => l10n.debriefCameHeading(heading),
    };
    final exits = t.exits;
    return Scaffold(
      body: _turnMap(
        context,
        graph,
        t,
        number: index + 1,
        revealed: false,
        bottom: BottomPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s3,
            children: [
              _turnDots(l10n, index, debrief.turns.length),
              Semantics(
                header: true,
                child: Text(
                  l10n.debriefRecallAsk(
                    _placeOf(l10n, t, graph, streets, settings),
                  ),
                  style: PindoroType.titleMd.copyWith(color: c.textPrimary),
                ),
              ),
              Text(
                exits == null ? came : '$came ${l10n.debriefTapWhat}',
                style: PindoroType.bodySm.copyWith(color: c.textSecondary),
              ),
              if (exits != null) ExitChoices(turns: exits.keys, onTap: onSaid),
              PindoroButton(
                label: exits == null ? l10n.debriefShow : l10n.debriefForgot,
                variant: exits == null
                    ? PindoroButtonVariant.primary
                    : PindoroButtonVariant.tertiary,
                onPressed: () => onSaid(null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The turn shown (V32-50 `reveal`): what was said against what was done, its mark, and the
/// way when it was missed (drilled now).
class _Reveal extends ConsumerWidget {
  const _Reveal({
    required this.debrief,
    required this.index,
    required this.said,
    required this.onNext,
  });

  final DriveDebrief debrief;
  final int index;
  final Turn? said;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final graph = ref.watch(drivingGraphProvider).value;
    final streets = ref.watch(cityStreetsProvider).value;
    if (graph == null || streets == null) return const Scaffold();
    final t = debrief.turns[index];
    final mark = t.mark;
    final done = _turnOf(t.exits, t.done);
    final missed = mark == TurnMark.again;
    final sentence = [
      if (said != null)
        said == done ? l10n.debriefRemembered : l10n.debriefNotRemembered,
      l10n.debriefWent(
        _turnName(done),
        _streetOf(l10n, t.done, streets, settings),
      ),
      if (missed)
        l10n.debriefWayWas(
          _turnName(_turnOf(t.exits, t.way)),
          _streetOf(l10n, t.way, streets, settings),
        ),
    ].join(' ');
    final last = index + 1 == debrief.turns.length;
    return Scaffold(
      body: _turnMap(
        context,
        graph,
        t,
        number: index + 1,
        revealed: true,
        bottom: BottomPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s3,
            children: [
              _turnDots(l10n, index, debrief.turns.length),
              if (mark != null)
                Row(
                  spacing: PindoroSpace.s3,
                  children: [
                    ReviewMark(_kind(mark)),
                    Expanded(
                      child: Text(
                        _markName(l10n, mark),
                        style: PindoroType.titleMd.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              Semantics(
                liveRegion: true,
                child: Text(
                  sentence,
                  style: PindoroType.bodyMd.copyWith(color: c.textPrimary),
                ),
              ),
              if (missed && debrief.drill.contains(t.key))
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: StatChip(
                    label: l10n.debriefInDrill,
                    glyph: PindoroGlyph.reroute,
                  ),
                ),
              PindoroButton(
                label: last ? l10n.debriefSeeDrive : l10n.debriefNextTurn,
                onPressed: onNext,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The whole drive north-up (V32-50 `review`, V32-60's "See the turns"): the track over the
/// best route, each turn's review mark, and the marks counted with what they mean.
class _Review extends ConsumerWidget {
  const _Review({
    required this.debrief,
    required this.action,
    required this.onNext,
  });

  final DriveDebrief debrief;
  final String action;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final graph = ref.watch(drivingGraphProvider).value;
    final d = debrief;
    final lines = _lines(d, graph);
    final counts = {
      for (final kind in TurnMark.values)
        kind: d.marks.where((m) => m.mark == kind).length,
    };
    return Scaffold(
      body: PlanMapLayout(
        semanticsLabel: l10n.a11yDriveMap,
        route: lines.route,
        track: lines.track,
        start: lines.start,
        end: lines.end,
        pins: [
          for (final m in d.marks)
            (m.at, ReviewMark(_kind(m.mark), onMap: true)),
        ],
        bottom: BottomPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: PindoroSpace.s2,
            children: [
              SectionTitle(
                l10n.debriefYourTurns(d.marks.length),
                meta: l10n.debriefLegend,
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                ),
                child: SingleChildScrollView(
                  child: ListGroup(
                    children: [
                      for (final MapEntry(key: kind, value: n)
                          in counts.entries)
                        if (n > 0)
                          ListRow(
                            leading: ReviewMark(_kind(kind)),
                            title: _markName(l10n, kind),
                            subtitle: _markNote(l10n, kind),
                            semanticsLabel:
                                '${_markName(l10n, kind)}, ${formatNumber(n)}. '
                                '${_markNote(l10n, kind)}',
                            trailing: Text(
                              formatNumber(n),
                              style: PindoroType.numericMd.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              PindoroButton(label: action, onPressed: onNext),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tier and the numbers (V32-50 `summary`, V32-60 one drive): how much longer than the
/// best route, U-turns, times lost, GPS gaps and the turns; "Next time: try Quiet" when the
/// route's suggestion stepped down.
class _Summary extends ConsumerWidget {
  const _Summary({
    required this.debrief,
    required this.walk,
    required this.onNext,
  });

  final DriveDebrief debrief;
  final bool walk;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final graph = ref.watch(drivingGraphProvider).value;
    final d = debrief;
    final review = d.review;
    final match = review.match;
    final graded = review.graded;
    final tier = d.drive.tier ?? Tier.miss;
    final uTurns = match.uTurns.length;
    final stretch = graded?.stretch;
    final target = streetName(review.target.street, settings);
    final lines = _lines(d, graph);
    final sentence = [
      if (graded == null)
        l10n.driveNoTrack
      else if (review.stoppedM case final m?)
        l10n.driveStoppedShort(formatDistance(m, l10n), target)
      else if (tier == Tier.miss)
        l10n.driveLongWay
      else
        l10n.driveFound,
      if (uTurns > 0) l10n.driveUTurns(uTurns),
      if (d.drive.rescued) l10n.debriefRescued,
      if (review.gaps.count > 0)
        l10n.driveGpsLost(review.gaps.count, formatClock(review.gaps.longest)),
    ].join(' ');
    final counts = d.counts;
    final turnsLine = [
      if (counts.own > 0) l10n.debriefOwn(counts.own),
      if (counts.missed > 0) l10n.debriefMissed(counts.missed),
      if (counts.helped > 0) l10n.debriefHelped(counts.helped),
      if (counts.watched > 0) l10n.debriefWatched(counts.watched),
    ].join(' · ');
    final next = d.next;
    final celebration = celebrationFor(tier);
    return Scaffold(
      body: PlanMapLayout(
        semanticsLabel: l10n.a11yDriveMap,
        route: lines.route,
        track: lines.track,
        start: lines.start,
        end: lines.end,
        pins: [
          for (final m in d.marks)
            (m.at, ReviewMark(_kind(m.mark), onMap: true)),
        ],
        front: [
          if (celebration != null && walk)
            RevealCelebration(revealKey: d.drive.id, size: celebration),
        ],
        bottom: RevealDock(
          revealKey: d.drive.id,
          sheet: TierRevealSheet(
            tier: tier,
            label: tierLabel(l10n, tier),
            sentence: sentence,
            chips: [
              SizedBox(
                width: double.infinity,
                child: Row(
                  spacing: PindoroSpace.s2,
                  children: [
                    Expanded(
                      child: StatTile(
                        label: l10n.driveLonger,
                        value: stretch == null
                            ? l10n.progressNoValue
                            : l10n.driveLongerBy(
                                formatNumber(((stretch - 1) * 100).round()),
                              ),
                        glyph: PindoroGlyph.route,
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        label: l10n.driveUTurnsTile,
                        value: formatNumber(uTurns),
                        glyph: PindoroGlyph.uTurn,
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        label: l10n.debriefLost,
                        value: formatNumber(d.drive.recoveries),
                        glyph: PindoroGlyph.reroute,
                      ),
                    ),
                  ],
                ),
              ),
              if (turnsLine.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    l10n.debriefTurnsLine(turnsLine),
                    style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                  ),
                ),
              if (next != null && walk)
                SuggestionCard(
                  glyph: levelIcon(next.level),
                  title: l10n.debriefTryNext(levelLabel(l10n, next.level)),
                  line: l10n.driveYours(next.yours, next.turns),
                ),
            ],
            action: walk
                ? l10n.debriefNextStreets
                : d.marks.isEmpty
                ? l10n.commonDone
                : l10n.debriefSeeTurns,
            onNext: () async => onNext(),
          ),
        ),
      ),
    );
  }
}

/// The streets driven, learned or not yet, and the missed turns to drill now as relearns
/// (V32-50 `streets`).
class _Streets extends ConsumerWidget {
  const _Streets({required this.debrief, required this.onNext});

  final DriveDebrief debrief;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final settings = ref.watch(settingsProvider).value;
    final graph = ref.watch(drivingGraphProvider).value;
    final streets = ref.watch(cityStreetsProvider).value;
    final now = ref.watch(clockProvider)();
    final d = debrief;
    String state(CardState card) => switch (memoryState(card, now)) {
      MemoryState.mastered => l10n.memoryMastered,
      MemoryState.solid => l10n.memorySolid,
      MemoryState.known => l10n.memoryKnown,
      MemoryState.seen => l10n.memorySeen,
    };
    final learned = d.streets.where((s) => s.card != null).length;
    final missed = [
      for (final t in d.turns)
        if (d.drill.contains(t.key) && graph != null && streets != null)
          _placeOf(l10n, t, graph, streets, settings),
    ];
    return PageScaffold(
      title: l10n.debriefStreetsTitle,
      showBack: false,
      footer: PindoroButton(
        label: d.point ? l10n.debriefNextPoint : l10n.commonDone,
        onPressed: onNext,
      ),
      children: [
        SectionTitle(
          l10n.debriefStreetsLine(learned, d.streets.length - learned),
          meta: l10n.debriefStreetCount(d.streets.length),
        ),
        ListGroup(
          children: [
            for (final s in d.streets)
              ListRow(
                leading: RowTile(
                  s.card == null ? PindoroGlyph.plus : PindoroGlyph.checkCircle,
                ),
                title: streetName(s.street, settings),
                subtitle: switch (s.card) {
                  final card? => l10n.debriefLearned(state(card)),
                  null => l10n.debriefNotYet,
                },
              ),
          ],
        ),
        if (missed.isNotEmpty)
          TitledCard(
            title: l10n.debriefMissedTurns(missed.length),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: PindoroSpace.s3,
              children: [
                Text(
                  [
                    l10n.debriefAt(missed.join(', ')),
                    l10n.driveAboutMin((missed.length / 3).ceil()),
                  ].join(' · '),
                  style: PindoroType.bodySm.copyWith(color: c.textSecondary),
                ),
                PindoroButton(
                  label: l10n.debriefDrill,
                  variant: PindoroButtonVariant.secondary,
                  onPressed: () =>
                      unawaited(context.push(Routes.drillOf(d.drill))),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Point to home (V32-50 `point`, once per new destination): the phone's top as the dial's
/// arrow (dragged instead without a compass), then home revealed with the error in degrees and
/// its tier (10°, 25°, 45°), logged as the pointing error.
class _Point extends ConsumerStatefulWidget {
  const _Point({
    required this.debrief,
    required this.onPointed,
    required this.onDone,
  });

  final DriveDebrief debrief;
  final ValueChanged<double> onPointed;
  final VoidCallback onDone;

  @override
  ConsumerState<_Point> createState() => _PointState();
}

class _PointState extends ConsumerState<_Point> {
  StreamSubscription<double>? _compass;

  /// The arrow: the phone's heading, smoothed, or where it was dragged.
  double _arrow = 0;
  bool _hasCompass = false;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _compass = ref.read(compassProvider).listen((heading) {
      if (_locked) return;
      // Low-pass along the shorter way round, redrawn from 1° of change.
      final delta = (heading - _arrow + 540) % 360 - 180;
      final next = _hasCompass ? (_arrow + 0.2 * delta) % 360 : heading;
      if (_hasCompass && (next - _arrow).abs() < 1) return;
      setState(() {
        _hasCompass = true;
        _arrow = next;
      });
    });
  }

  @override
  void dispose() {
    unawaited(_compass?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = PindoroTheme.of(context).colors;
    final graph = ref.watch(drivingGraphProvider).value;
    final home = ref.watch(drivePlacesProvider).value?.home;
    String word(double b) => l10n.compassWord(compassPointOf(b).name);
    final here = graph == null
        ? null
        : targetPoint(graph, widget.debrief.review.target);
    final homeAt = home == null || graph == null
        ? null
        : targetPoint(graph, home);
    final truth = here == null || homeAt == null
        ? null
        : bearingDegrees(here, homeAt);
    final error = truth == null ? null : bearingError(_arrow, truth);
    final tier = error == null ? null : pointingTier(error);
    return PageScaffold(
      title: l10n.debriefPointTitle,
      showBack: false,
      footer: PindoroButton(
        label: _locked ? l10n.commonDone : l10n.debriefPointHere,
        onPressed: _locked
            ? widget.onDone
            : truth == null
            ? null
            : () {
                setState(() => _locked = true);
                widget.onPointed(error!);
              },
      ),
      children: [
        Text(
          _locked && truth != null
              ? l10n.debriefHomeIs(
                  word(truth),
                  formatDistance(distanceBetween(here!, homeAt!), l10n),
                )
              : l10n.debriefPointNote,
          style: PindoroType.bodyMd.copyWith(color: c.textPrimary),
        ),
        BearingDial(
          playerBearing: _arrow,
          trueBearing: _locked ? truth : null,
          enabled: !_hasCompass && !_locked,
          onChanged: (b) => setState(() => _arrow = b),
          semanticsLabel: l10n.a11yCompass,
          describeBearing: word,
          animate: !MediaQuery.disableAnimationsOf(context),
          degrees: _locked && error != null
              ? l10n.debriefDegrees(formatNumber(error.round()))
              : null,
          caption: _locked && truth != null
              ? l10n.debriefPointCaptionHome(word(_arrow), word(truth))
              : _hasCompass
              ? l10n.debriefPointCaption(word(_arrow))
              : l10n.debriefPointDrag,
        ),
        if (_locked && tier != null && error != null)
          Center(
            child: Semantics(
              liveRegion: true,
              child: DialResultChip(
                tier: tier,
                label: l10n.sessionBearingTitle(
                  tierLabel(l10n, tier),
                  formatNumber(error.round()),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
