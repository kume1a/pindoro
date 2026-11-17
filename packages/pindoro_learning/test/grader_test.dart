import 'dart:math';

import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_learning/pindoro_learning.dart';
import 'package:test/test.dart';

const _lat = 41.7;
const _lon = 44.8;
const _mPerDegLat = 111320.0;
final _mPerDegLon = _mPerDegLat * cos(_lat * pi / 180);

/// A point [east] and [north] metres from the test origin.
LatLng at(double east, double north) =>
    LatLng(_lat + north / _mPerDegLat, _lon + east / _mPerDegLon);

/// An east–west street [north] metres from the origin, 0–400 m east.
NamedStreet street(
  String id, {
  double north = 0,
  String? name,
  String roadClass = 'residential',
}) {
  final line = [at(0, north), at(400, north)];
  return NamedStreet([
    Street(
      id: id,
      nameKa: name ?? id,
      nameEn: null,
      roadClass: roadClass,
      difficulty: Difficulty.expert,
      lengthM: 400,
      midpoint: at(200, north),
      bbox: Bbox.of(line),
      geometry: [line],
    ),
  ]);
}

void main() {
  final target = street('target');

  PinGrade grade(
    LatLng pin, {
    List<NamedStreet> nearby = const [],
    Set<String> confusable = const {},
    int rtMs = 8000,
    int priorSuccesses = 0,
  }) => Grader.gradePin(
    pin: pin,
    target: target,
    nearby: nearby,
    confusable: confusable,
    rtMs: rtMs,
    priorSuccesses: priorSuccesses,
  );

  group('SPEC §5.1, in order', () {
    test('a pin on a confusable street is a mix-up: Miss, Again', () {
      final sibling = street('lane5', north: 60);
      final g = grade(at(200, 58), nearby: [sibling], confusable: {'lane5'});
      expect(g.isMixUp, isTrue);
      expect(g.snapStreetId, 'lane5');
      expect(g.tier, Tier.miss);
      expect(g.rating, Rating.again);
      expect(g.distanceM, closeTo(58, 1));
    });

    test('a mix-up wins over distance, even beyond 100 m', () {
      final sibling = street('lane5', north: 130);
      final g = grade(at(200, 128), nearby: [sibling], confusable: {'lane5'});
      expect(g.isMixUp, isTrue);
      expect(g.rating, Rating.again);
    });

    test('140 m away is Close and Again; the target is still the snap', () {
      final g = grade(at(200, 140), rtMs: 2000, priorSuccesses: 5);
      expect(g.tier, Tier.close);
      expect(g.rating, Rating.again);
      expect(g.snapStreetId, 'target');
      expect(g.isMixUp, isFalse);
    });

    test('400 m away is a Miss with no snap', () {
      final g = grade(at(200, 400));
      expect(g.tier, Tier.miss);
      expect(g.rating, Rating.again);
      expect(g.snapStreetId, isNull);
    });

    test('within 100 m but on a non-confusable neighbour: Great, Hard', () {
      final neighbour = street('other', north: -60);
      final g = grade(at(200, -45), nearby: [neighbour]);
      expect(g.snapStreetId, 'other');
      expect(g.isMixUp, isFalse);
      expect(g.tier, Tier.great);
      expect(g.rating, Rating.hard);
    });

    test('a neighbour snap shows Great even inside the Perfect zone', () {
      final neighbour = street('other', north: -30);
      final g = grade(
        at(200, -20),
        nearby: [neighbour],
        rtMs: 2000,
        priorSuccesses: 5,
      );
      expect(g.tier, Tier.great);
      expect(g.rating, Rating.hard);
    });

    test('on the street but slower than 20 s: Hard, tier by distance', () {
      expect(grade(at(200, 5), rtMs: 25000).rating, Rating.hard);
      expect(grade(at(200, 5), rtMs: 25000).tier, Tier.perfect);
      expect(grade(at(200, 60), rtMs: 25000).tier, Tier.great);
    });

    test(
      'fast, inside the Perfect zone, with 2 prior successes: Perfect, Easy',
      () {
        final g = grade(at(200, 5), rtMs: 4000, priorSuccesses: 2);
        expect(g.tier, Tier.perfect);
        expect(g.rating, Rating.easy);
        expect(g.snapStreetId, 'target');
      },
    );

    test(
      'otherwise Good: too few successes, a Great distance, or not fast enough',
      () {
        expect(
          grade(at(200, 5), rtMs: 4000, priorSuccesses: 1).rating,
          Rating.good,
        );
        expect(
          grade(at(200, 5), rtMs: 4000, priorSuccesses: 1).tier,
          Tier.perfect,
        );
        expect(
          grade(at(200, 60), rtMs: 4000, priorSuccesses: 5).rating,
          Rating.good,
        );
        expect(
          grade(at(200, 60), rtMs: 4000, priorSuccesses: 5).tier,
          Tier.great,
        );
        expect(
          grade(at(200, 5), rtMs: 9000, priorSuccesses: 5).rating,
          Rating.good,
        );
      },
    );
  });

  group('boundaries', () {
    test('exactly 20 s is not slow; exactly 6 s is fast', () {
      expect(grade(at(200, 5), rtMs: 20000).rating, Rating.good);
      expect(
        grade(at(200, 5), rtMs: 6000, priorSuccesses: 2).rating,
        Rating.easy,
      );
    });

    test('the Perfect zone grows with the road class half-width', () {
      final avenue = street('target', roadClass: 'primary');
      final g = Grader.gradePin(
        pin: at(200, 28),
        target: avenue,
        nearby: const [],
        confusable: const {},
        rtMs: 4000,
        priorSuccesses: 2,
      );
      expect(g.tier, Tier.perfect);
      expect(g.rating, Rating.easy);
      expect(
        grade(at(200, 28), rtMs: 4000, priorSuccesses: 2).tier,
        Tier.great,
      );
    });

    test(
      'a tie between the target and a crossing street snaps to the target',
      () {
        final crossing = street('lane5', north: 0);
        final g = grade(at(200, 0), nearby: [crossing], confusable: {'lane5'});
        expect(g.snapStreetId, 'target');
        expect(g.isMixUp, isFalse);
      },
    );

    test('streets farther than 150 m never snap', () {
      final far = street('far', north: 400);
      final g = grade(at(200, 390), nearby: [far, target]);
      expect(g.snapStreetId, 'far');
      final none = grade(at(200, 200), nearby: [far]);
      expect(none.snapStreetId, isNull);
    });
  });

  group('confusablesOf', () {
    final elsewhere = street(
      'rustaveli-gldani',
      north: 5000,
      name: 'რუსთაველის გამზირი',
    );
    final centre = street('rustaveli-centre', name: 'რუსთაველის  გამზირი');
    final other = street('other', north: 100, name: 'ჭავჭავაძის გამზირი');
    final all = [centre, elsewhere, other];

    test('takes same-name streets elsewhere, by the normalised name', () {
      expect(confusablesOf(centre, all, const []), {'rustaveli-gldani'});
    });

    test(
      'takes logged confusions in both directions, never the street itself',
      () {
        expect(
          confusablesOf(other, all, const [('rustaveli-centre', 'other')]),
          {'rustaveli-centre'},
        );
        expect(confusablesOf(other, all, const [('other', 'other')]), isEmpty);
      },
    );

    test('takes the street’s family', () {
      expect(confusablesOf(other, all, const [], family: {'lane-1'}), {
        'lane-1',
      });
    });
  });

  test('normaliseName matches the pipeline', () {
    expect(
      normaliseName('  «Ilia»  Chavchavadze\tAve '),
      'ilia chavchavadze ave',
    );
  });

  group('other cards (SPEC §5.2)', () {
    final long = street('long');

    test('ends count within max(150 m, 10 % of length), either way round', () {
      ExtentGrade ends(LatLng a, LatLng b) =>
          Grader.gradeExtent(pins: (a, b), street: long);
      final both = ends(at(390, 40), at(-100, 0));
      expect((both.hits, both.rating, both.tier), (2, Rating.good, Tier.great));
      final one = ends(at(0, 140), at(200, 0));
      expect((one.hits, one.rating, one.tier), (1, Rating.hard, Tier.close));
      final none = ends(at(200, 0), at(200, 300));
      expect((none.hits, none.rating), (0, Rating.again));
    });

    test('bearings: 20° Great, 45° Close, else Miss; the error wraps', () {
      expect(bearingError(350, 10), 20);
      expect(Grader.gradeBearing(bearingError(350, 10)), Tier.great);
      expect(Grader.gradeBearing(45), Tier.close);
      expect(Grader.gradeBearing(46), Tier.miss);
      expect(Grader.ratingOfTier(Tier.close), Rating.hard);
    });

    test('a name pick: the street is Good, another Again', () {
      expect(Grader.gradeName(knew: true), Rating.good);
      expect(Grader.gradeName(knew: false), Rating.again);
    });

    test('the name check offers 6 names, confusables before neighbours', () {
      final nearby = [
        for (var i = 1; i <= 8; i++) street('s$i', north: i * 100.0),
      ];
      final choices = nameChoices(
        target: long,
        streets: [
          long,
          ...nearby,
          street('twin', north: 5000, name: 'long'),
        ],
        confusable: {'s8'},
        random: Random(1),
      );
      expect(choices, hasLength(LearningConfig.nameCheckOptions));
      expect(
        choices.map((s) => s.id).toSet(),
        {'long', 's8', 's1', 's2', 's3', 's4'},
        reason: 'the far twin shares the name, so it never stands as a choice',
      );
    });
  });
}
