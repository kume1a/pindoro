import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

import 'road_net.dart';

final _now = DateTime.utc(2026, 11, 21, 9); // a Saturday

/// Row junctions 0–9 west to east, each 1–8 with a side street north; junction 5 also has ways
/// south, north-east and south-east (complex).
RoadGraph _row() {
  final net = RoadNet()..street('row', 'რიგი', 'Row');
  for (var i = 0; i <= 9; i++) {
    net.junction(i, 100.0 * i, 0);
  }
  for (var i = 1; i <= 8; i++) {
    net.junction(100 + i, 100.0 * i, 100);
  }
  net
    ..junction(200, 500, -100)
    ..junction(201, 570, 70)
    ..junction(202, 570, -70);
  for (var i = 0; i < 9; i++) {
    net.edge(i, i, i + 1, 'row');
  }
  for (var i = 1; i <= 8; i++) {
    net.edge(100 + i, i, 100 + i, 'row');
  }
  net
    ..edge(300, 5, 200, 'row')
    ..edge(301, 5, 201, 'row')
    ..edge(302, 5, 202, 'row');
  return net.graph();
}

NavDecision _at(RoadGraph g, int junction) {
  RoadEdge between(int a, int b) =>
      g.edgesAt(a).firstWhere((e) => e.other(a) == b);
  return (
    index: junction,
    junction: junction,
    approach: between(junction, junction - 1),
    exit: between(junction, junction + 1),
    turn: Turn.straight,
    street: null,
    newStreet: false,
    atM: 100.0 * junction,
    key: 'k$junction',
    landmark: null,
    signals: false,
  );
}

CardState _card({double stability = 30, int daysAgo = 29, int lapses = 0}) {
  final last = _now.subtract(Duration(days: daysAgo));
  return CardState(
    itemId: RouteIds.junction(1, 2, 3),
    phase: CardPhase.review,
    memory: Memory(stability: stability, difficulty: 5, lastReview: last),
    dueAt: last.add(Duration(days: stability.round())),
    reps: 3,
    lapses: lapses,
    lastRating: Rating.good,
    introAt: last.subtract(const Duration(days: 7)),
  );
}

DriveSummary _drive(
  int daysAgo, {
  DriveLevel level = DriveLevel.quiet,
  DriveLevel? mostHelp,
  bool arrived = true,
  String? route = 'home→work',
  String? destination = 'work',
}) => (
  startedAt: _now.subtract(Duration(days: daysAgo)),
  level: level,
  mostHelp: mostHelp ?? level,
  arrived: arrived,
  route: route,
  destination: destination,
  stretch: 1.1,
  recoveries: 0,
);

void main() {
  group('key decisions', () {
    final g = _row();
    final decisions = [for (var j = 1; j <= 8; j++) _at(g, j)];
    final silent = {for (final d in decisions) d.key!}..remove('k2');

    test('the ones not silent and the complex, then the hardest to three', () {
      expect(isComplex(g, _at(g, 5)), isTrue);
      expect(isComplex(g, _at(g, 4)), isFalse);
      final keys = keyDecisions(
        g,
        decisions,
        silent: silent,
        recall: {for (final d in decisions) d.key!: 0.95, 'k7': 0.5},
      ).map((d) => d.key);
      expect(keys, ['k2', 'k5', 'k7']);
    });

    test('at most seven: the hardest, in route order', () {
      final keys = keyDecisions(
        g,
        decisions,
        recall: {'k1': 0.9, 'k8': 0.8},
      ).map((d) => d.key);
      expect(keys, ['k2', 'k3', 'k4', 'k5', 'k6', 'k7', 'k8']);
    });

    test('a short route shows all it has', () {
      expect(keyDecisions(g, [_at(g, 3)], silent: {'k3'}), hasLength(1));
    });
  });

  test('turn marks', () {
    TurnMark? mark(
      bool? ok,
      NavHelp help, {
      bool recent = false,
      bool slow = false,
    }) => turnMark(ok: ok, help: help, recentHelp: recent, hesitated: slow);
    expect(mark(null, NavHelp.none), isNull);
    expect(mark(false, NavHelp.guided), TurnMark.watched);
    expect(mark(true, NavHelp.cue), TurnMark.helped);
    expect(mark(true, NavHelp.recovery), TurnMark.helped);
    expect(mark(false, NavHelp.none, recent: true), TurnMark.helped);
    expect(mark(false, NavHelp.none), TurnMark.again);
    expect(mark(true, NavHelp.none, slow: true), TurnMark.hard);
    expect(mark(true, NavHelp.none), TurnMark.good);
    expect(
      ownShare([
        TurnMark.good,
        TurnMark.hard,
        TurnMark.helped,
        null,
        TurnMark.again,
      ]),
      0.5,
    );
    expect(ownShare([null]), isNull);
  });

  group('debrief turns', () {
    LoggedTurn t(int seq, TurnMark? mark, {bool key = false, String? id}) =>
        (seq: seq, key: id ?? 'k$seq', mark: mark, keyTurn: key);

    test('missed, helped and key turns, in drive order, each once', () {
      final turns = debriefTurns([
        t(0, TurnMark.good),
        t(1, TurnMark.good, key: true),
        t(2, TurnMark.again),
        t(3, TurnMark.watched),
        t(4, TurnMark.helped),
        t(5, TurnMark.again, id: 'k2'),
      ]);
      expect(turns.map((x) => x.seq), [1, 2, 4]);
    });

    test('at most seven, missed first', () {
      final turns = debriefTurns([
        for (var i = 0; i < 6; i++) t(i, TurnMark.good, key: true),
        t(6, TurnMark.helped),
        t(7, TurnMark.again),
      ]);
      expect(turns, hasLength(7));
      expect(turns.map((x) => x.seq), containsAll([6, 7]));
      expect(turns.map((x) => x.seq), isNot(contains(5)));
    });
  });

  test('pointing tiers at 10, 25 and 45 degrees', () {
    expect(pointingTier(10), Tier.perfect);
    expect(pointingTier(10.5), Tier.great);
    expect(pointingTier(25), Tier.great);
    expect(pointingTier(45), Tier.close);
    expect(pointingTier(46), Tier.miss);
    expect(bearingError(350, 10), 20);
  });

  group('drive review', () {
    ({CardState card, LogEntry log})? review(
      CardState? card, {
      bool ok = true,
      NavHelp help = NavHelp.none,
      bool hesitated = false,
    }) => driveReview(
      card,
      ok: ok,
      help: help,
      recentHelp: false,
      hesitated: hesitated,
      now: _now,
    ).review;

    test('on the player\'s own near due: Good, or Hard after a hesitation', () {
      final good = review(_card())!;
      expect(good.log.rating, Rating.good);
      expect(good.log.format, ReviewFormat.drive);
      expect(good.log.source, ReviewSource.drive);
      expect(good.card.phase, CardPhase.review);
      expect(review(_card(), hesitated: true)!.log.rating, Rating.hard);
    });

    test('a miss near due is Again; help, an early card or no memory none', () {
      expect(review(_card(), ok: false)!.log.rating, Rating.again);
      expect(review(_card(), help: NavHelp.cue), isNull);
      CreditSkip? skip(CardState card, {required bool ok, NavHelp? help}) =>
          driveReview(
            card,
            ok: ok,
            help: help ?? NavHelp.none,
            recentHelp: false,
            hesitated: false,
            now: _now,
          ).skip;
      expect(skip(_card(), ok: true, help: NavHelp.cue), CreditSkip.helped);
      expect(skip(_card(daysAgo: 1), ok: false), CreditSkip.sessionOnly);
      expect(review(_card(daysAgo: 1)), isNull);
      expect(review(null), isNull);
      expect(
        review(
          CardState(
            itemId: RouteIds.junction(1, 2, 3),
            phase: CardPhase.learning,
            introAt: _now,
          ),
        ),
        isNull,
      );
    });
  });

  group('the weekly goal', () {
    test('two drives without help and a new place make a week', () {
      final w = driveWeek([
        _drive(0, destination: 'lisi'),
        _drive(1),
        _drive(2, level: DriveLevel.quiet, mostHelp: DriveLevel.coached),
      ], _now);
      expect(w.week, (quietDrives: 2, newPlaces: 1));
      expect(weekDone(w.week), isTrue);
      expect(w.weeksDone, 1);
      expect(w.backOnTrack, isFalse);
    });

    test('a place is new only on its first arrival, with or without help', () {
      final w = driveWeek([
        _drive(20, level: DriveLevel.guided, destination: 'lisi'),
        _drive(0, destination: 'lisi'),
        _drive(1, arrived: false),
      ], _now);
      expect(w.week, (quietDrives: 1, newPlaces: 0));
    });

    test('a missed week after earlier drives: back on track, weeks kept', () {
      final w = driveWeek([
        _drive(19, destination: 'a'),
        _drive(18, destination: 'b'),
        _drive(8),
        _drive(1, destination: 'c'),
      ], _now);
      expect(w.weeksDone, 1);
      expect(w.lastWeek, (quietDrives: 1, newPlaces: 1));
      expect(w.backOnTrack, isTrue);
      expect(driveWeek([_drive(1)], _now).backOnTrack, isFalse);
    });
  });

  test('frequent routes and their level by month', () {
    final drives = [
      for (var i = 0; i < 3; i++) _drive(120 + i, level: DriveLevel.guided),
      _drive(60, level: DriveLevel.coached),
      _drive(2, level: DriveLevel.off),
      _drive(1, level: DriveLevel.off),
      _drive(1, route: 'home→lisi'),
    ];
    final routes = frequentRoutes(drives);
    expect(routes.single.route, 'home→work');
    expect(routes.single.drives, 6);
    final runs = levelRuns(routes.single.months);
    expect(runs.map((r) => r.level), [
      DriveLevel.guided,
      DriveLevel.coached,
      DriveLevel.off,
    ]);
    expect(runs.last.from, DateTime(2026, 11));
  });

  group('your routes first', () {
    test('routes driven twice in 14 days', () {
      expect(
        yourRoutes([
          _drive(1),
          _drive(13),
          _drive(1, route: 'x'),
          _drive(20, route: 'x'),
        ], _now),
        {'home→work'},
      );
    });

    test('habitual corridors and the reverse turn', () {
      final key = RouteIds.junction(5, 4, 6);
      expect(
        habitualKeys([
          for (final d in [1, 5, 13])
            (key: key, at: _now.subtract(Duration(days: d))),
          (key: 'other', at: _now),
        ], _now),
        {key},
      );
      expect(reverseTurn(key), RouteIds.junction(5, 6, 4));
      expect(turnNodes(key), (node: 5, from: 4, to: 6));
      expect(reverseTurn(CardType.p.item('s1')), isNull);
    });

    test('a quarter of the new cards, less while memory grows slower', () {
      expect(yourRoutesShare(gainNow: 10, gainBefore: 10), 0.25);
      expect(yourRoutesShare(gainNow: 7, gainBefore: 10), 0.15);
      expect(yourRoutesShare(gainNow: 0, gainBefore: 0), 0.25);
    });

    test('route items first, then their streets, together up to the cap', () {
      final r = yourRoutesFirst(
        newCandidates: const ['P:a', 'P:b', 'P:c'],
        openRoutes: const ['J:1', 'J:2', 'J:3'],
        mineRoutes: const {'J:3'},
        mineStreets: const ['P:main', 'P:c', 'P:side'],
        cap: 3,
      );
      expect(r.openRoutes, ['J:3', 'J:1', 'J:2']);
      expect(r.newCandidates, ['P:main', 'P:c', 'P:a', 'P:b']);
      expect(r.early, ['J:3']);
    });
  });
}
