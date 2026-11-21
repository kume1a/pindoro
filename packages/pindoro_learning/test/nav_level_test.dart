import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 11, 21, 9);

/// A J card last reviewed Good [daysAgo] days ago with [stability], introduced a week before.
CardState _card({double stability = 60, int daysAgo = 3}) {
  final last = _now.subtract(Duration(days: daysAgo));
  return CardState(
    itemId: 'J:n1:n2:n3',
    phase: CardPhase.review,
    memory: Memory(stability: stability, difficulty: 5, lastReview: last),
    dueAt: last.add(Duration(days: stability.round())),
    reps: 3,
    lastRating: Rating.good,
    introAt: last.subtract(const Duration(days: 7)),
  );
}

final _edge = RoadEdge(
  id: 1,
  from: 1,
  to: 2,
  streetId: null,
  lengthM: 100,
  line: const [LatLng(41.7, 44.7), LatLng(41.701, 44.7)],
);

/// [n] decisions keyed `k0` … `k<n-1>`.
List<NavDecision> _decisions(int n) => [
  for (var i = 0; i < n; i++)
    (
      index: i,
      junction: i,
      approach: null,
      exit: _edge,
      turn: null,
      street: null,
      newStreet: false,
      atM: 100.0 * i,
      key: 'k$i',
      landmark: null,
      signals: false,
    ),
];

Set<String> _keys(int n) => {for (var i = 0; i < n; i++) 'k$i'};

PastDrive _drove(
  DriveLevel level, {
  double? stretch = 1.1,
  int recoveries = 0,
  Set<String>? decisions,
}) => (
  level: level,
  decisions: decisions ?? _keys(20),
  stretch: stretch,
  recoveries: recoveries,
);

DriveLevel _suggest({
  required int silentOf20,
  double? minRecall = 0.9,
  List<PastDrive> past = const [],
  int areaJ = 10,
}) => suggestLevel(
  decisions: _decisions(20),
  silent: _keys(silentOf20),
  minRecall: minRecall,
  past: past,
  areaJ: areaJ,
);

void main() {
  _historyTests();
  group('silent-eligible', () {
    test('a Known card at high recall with no recent failure', () {
      expect(silentEligible(_card(), null, _now), isTrue);
      expect(
        silentEligible(_card(), (lastFailure: _now, ownDrives: const []), _now),
        isFalse,
      );
      expect(
        silentEligible(_card(), (
          lastFailure: _now.subtract(
            const Duration(days: LearningConfig.silentNoFailDays),
          ),
          ownDrives: const [],
        ), _now),
        isTrue,
      );
    });

    test('not at low recall', () {
      expect(
        silentEligible(_card(stability: 4, daysAgo: 10), null, _now),
        isFalse,
      );
    });

    test('no card: right on the player\'s own the last two drives', () {
      expect(
        silentEligible(null, (
          lastFailure: null,
          ownDrives: [true, true],
        ), _now),
        isTrue,
      );
      expect(
        silentEligible(null, (
          lastFailure: null,
          ownDrives: [true, false, true],
        ), _now),
        isFalse,
      );
      expect(
        silentEligible(null, (lastFailure: null, ownDrives: [true]), _now),
        isFalse,
      );
      expect(silentEligible(null, null, _now), isFalse);
    });
  });

  group('suggested level', () {
    test('by the share of silent decisions', () {
      expect(_suggest(silentOf20: 15), DriveLevel.quiet);
      expect(_suggest(silentOf20: 14), DriveLevel.quiet);
      expect(_suggest(silentOf20: 13), DriveLevel.coached);
      expect(_suggest(silentOf20: 8), DriveLevel.coached);
      expect(_suggest(silentOf20: 7), DriveLevel.guided);
    });

    test('Off needs every recall high and a Quiet drive on the route with at '
        'most one recovery', () {
      expect(_suggest(silentOf20: 19), DriveLevel.quiet);
      final quiet = _drove(DriveLevel.quiet, recoveries: 1);
      expect(_suggest(silentOf20: 19, past: [quiet, quiet]), DriveLevel.off);
      expect(
        _suggest(silentOf20: 19, minRecall: 0.7, past: [quiet, quiet]),
        DriveLevel.quiet,
      );
      expect(
        _suggest(
          silentOf20: 19,
          past: [_drove(DriveLevel.quiet, recoveries: 2)],
        ),
        DriveLevel.quiet,
      );
    });

    test('always Guided where the destination\'s raion has few J cards', () {
      expect(_suggest(silentOf20: 20, areaJ: 4), DriveLevel.guided);
    });

    test(
      'less help only after two good drives at the last level, one step',
      () {
        final good = _drove(DriveLevel.coached);
        expect(_suggest(silentOf20: 15, past: [good]), DriveLevel.coached);
        expect(_suggest(silentOf20: 15, past: [good, good]), DriveLevel.quiet);
        expect(
          _suggest(
            silentOf20: 15,
            past: [good, _drove(DriveLevel.coached, stretch: 1.4)],
          ),
          DriveLevel.coached,
        );
      },
    );

    test(
      'more help after two poor drives, or when the share falls, one step',
      () {
        final poor = _drove(DriveLevel.quiet, recoveries: 3);
        expect(
          _suggest(silentOf20: 15, past: [poor, poor]),
          DriveLevel.coached,
        );
        expect(
          _suggest(silentOf20: 2, past: [_drove(DriveLevel.off)]),
          DriveLevel.quiet,
        );
      },
    );

    test('drives elsewhere don\'t count', () {
      final other = _drove(DriveLevel.off, decisions: {'x'});
      expect(_suggest(silentOf20: 15, past: [other, other]), DriveLevel.quiet);
    });

    test('the player may take more help, or one step less', () {
      expect(levelChoices(DriveLevel.coached), [
        DriveLevel.guided,
        DriveLevel.coached,
        DriveLevel.quiet,
      ]);
      expect(levelChoices(DriveLevel.off), DriveLevel.values);
    });
  });

  group('drive credit', () {
    // Recall about 0.91 at 16 of 20 days.
    final due = _card(daysAgo: 16, stability: 20);

    ({Rating? rating, CreditSkip? skip}) credit({
      CardState? card,
      bool ok = true,
      NavHelp help = NavHelp.none,
      bool recentHelp = false,
      bool hesitated = false,
      List<DateTime> passes = const [],
      DateTime? lastCredited,
    }) => driveCredit(
      card: card ?? due,
      ok: ok,
      help: help,
      recentHelp: recentHelp,
      hesitated: hesitated,
      now: _now,
      passes: passes,
      lastCredited: lastCredited,
    );

    test('an unaided success is Good, Hard after a hesitation, never Easy', () {
      expect(credit().rating, Rating.good);
      expect(credit(hesitated: true).rating, Rating.hard);
    });

    test('help, or help in the minute before, is exposure only', () {
      for (final help in [NavHelp.cue, NavHelp.guided, NavHelp.recovery]) {
        expect(credit(help: help).skip, CreditSkip.helped);
        expect(credit(help: help, ok: false).skip, CreditSkip.helped);
      }
      expect(credit(recentHelp: true).skip, CreditSkip.recentHelp);
    });

    test('a failure is Again, whatever the guards on success', () {
      expect(
        credit(ok: false, card: _card(), lastCredited: _now).rating,
        Rating.again,
      );
    });

    test(
      'a success counts only near due, once a day, and weekly on a habit',
      () {
        expect(credit(card: _card(daysAgo: 1)).skip, CreditSkip.notDue);
        expect(
          credit(lastCredited: _now.subtract(const Duration(hours: 1))).skip,
          CreditSkip.creditedToday,
        );
        final passes = [
          for (var d = 0; d < LearningConfig.habitPasses; d++)
            _now.subtract(Duration(days: d)),
        ];
        expect(
          credit(
            passes: passes,
            lastCredited: _now.subtract(const Duration(days: 3)),
          ).skip,
          CreditSkip.habitual,
        );
        expect(
          credit(
            passes: passes,
            lastCredited: _now.subtract(
              const Duration(days: LearningConfig.habitCreditDays),
            ),
          ).rating,
          Rating.good,
        );
        expect(
          driveCredit(
            card: null,
            ok: true,
            help: NavHelp.none,
            recentHelp: false,
            hesitated: false,
            now: _now,
          ).skip,
          CreditSkip.noCard,
        );
      },
    );
  });
}

void _historyTests() {
  group('history from the drive log', () {
    LoggedDecision decision(
      String drive,
      String key, {
      bool? ok = true,
      NavHelp help = NavHelp.none,
      int daysAgo = 1,
    }) => (
      driveId: drive,
      key: key,
      ok: ok,
      help: help,
      recentHelp: false,
      at: _now.subtract(Duration(days: daysAgo)),
    );

    test('own drives latest first, failures from the log and elsewhere', () {
      final h = navHistory(
        drives: [
          (id: 'b', level: DriveLevel.quiet, stretch: 1.1, recoveries: 1),
          (id: 'a', level: DriveLevel.guided, stretch: null, recoveries: 0),
        ],
        decisions: [
          decision('a', 'k1', help: NavHelp.guided, daysAgo: 3),
          decision('b', 'k1'),
          decision('a', 'k2', ok: false, daysAgo: 3),
          decision('b', 'k3', ok: null),
        ],
        failures: {'k4': _now},
      );
      expect(h.decisions['k1']!.ownDrives, [true, false]);
      expect(
        h.decisions['k2']!.lastFailure,
        _now.subtract(const Duration(days: 3)),
      );
      expect(h.decisions['k3'], isNull);
      expect(h.decisions['k4']!.lastFailure, _now);
      expect(h.past.map((p) => p.level), [DriveLevel.quiet, DriveLevel.guided]);
      expect(h.past.first.decisions, {'k1', 'k3'});
    });

    test('a route\'s suggestion counts its silent decisions', () {
      final s = routeSuggestion(
        decisions: _decisions(2),
        cards: {'k0': _card()},
        history: {
          'k1': (lastFailure: null, ownDrives: [true, true]),
        },
        past: const [],
        areaJ: 10,
        now: _now,
      );
      expect(s.silent, {'k0', 'k1'});
      expect(s.level, DriveLevel.quiet);
    });
  });
}
