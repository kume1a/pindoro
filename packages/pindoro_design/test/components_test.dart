import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

import 'junction_sample.dart';

/// Animations off, so pops and count-ups show their final frame.
Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildPindoroTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );

void main() {
  testWidgets('every icon asset loads', (tester) async {
    await tester.pumpWidget(
      _host(
        Wrap(children: [for (final g in PindoroGlyph.values) PindoroIcon(g)]),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(PindoroIcon), findsNWidgets(PindoroGlyph.values.length));
  });

  testWidgets('segmented control reports the tapped segment', (tester) async {
    String? picked;
    await tester.pumpWidget(
      _host(
        SegmentedControl(
          segments: const {'a': 'Light', 'b': 'Dark'},
          selected: 'a',
          onChanged: (v) => picked = v,
        ),
      ),
    );
    await tester.tap(find.text('Dark'));
    expect(picked, 'b');
  });

  testWidgets('a check row is a checkbox: partial reads as mixed', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        ListGroup(
          children: [
            for (final (title, check) in [
              ('Partial', CheckState.partial),
              ('Included', CheckState.included),
            ])
              ListRow(title: title, check: check, onTap: () {}),
          ],
        ),
      ),
    );
    expect(
      tester.getSemantics(find.text('Partial')),
      isSemantics(
        label: 'Partial',
        hasCheckedState: true,
        isCheckStateMixed: true,
        isButton: false,
      ),
    );
    expect(
      tester.getSemantics(find.text('Included')),
      isSemantics(
        label: 'Included',
        hasCheckedState: true,
        isChecked: true,
        isButton: false,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a toggle row flips on a tap anywhere in the row', (
    tester,
  ) async {
    var value = false;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => ListGroup(
            children: [
              ListRow(
                title: 'Sound',
                toggled: value,
                trailing: PindoroToggle(value: value),
                onTap: () => setState(() => value = !value),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sound'));
    expect(value, isTrue);
  });

  testWidgets('question bar labels its progress for screen readers', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const QuestionBar(
          tiers: [Tier.great, Tier.miss],
          total: 10,
          semanticLabel: 'Question 3 of 10',
        ),
      ),
    );
    expect(find.bySemanticsLabel('Question 3 of 10'), findsOneWidget);
  });

  testWidgets('the streak pill is one labelled button', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        StreakPill(
          label: '13',
          state: StreakPillState.atRisk,
          semanticLabel: '13-day streak',
          onPressed: () => taps++,
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('13-day streak'));
    expect(taps, 1);
    expect(
      tester.getSize(find.byType(StreakPill)).height,
      greaterThanOrEqualTo(PindoroSize.tapMin),
    );
  });

  testWidgets('the nav bar reports taps and reads the current tab', (
    tester,
  ) async {
    int? tapped;
    await tester.pumpWidget(
      _host(
        PindoroNavBar(
          items: const [
            (glyph: PindoroGlyph.road, label: 'Today', semanticLabel: null),
            (
              glyph: PindoroGlyph.chart,
              label: 'Progress',
              semanticLabel: 'Progress, tab',
            ),
          ],
          current: 0,
          onSelect: (i) => tapped = i,
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Today')),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Progress, tab')),
      isSemantics(isButton: true, isSelected: false),
    );
    await tester.tap(find.bySemanticsLabel('Progress, tab'));
    expect(tapped, 1);
  });

  testWidgets('the nav bar keeps its height under a Scaffold', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPindoroTheme(Brightness.light),
        home: Scaffold(
          bottomNavigationBar: PindoroNavBar(
            items: const [
              (glyph: PindoroGlyph.user, label: 'Me', semanticLabel: null),
            ],
            current: 0,
            onSelect: (_) {},
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(PindoroNavBar)).height, lessThan(84));
  });

  testWidgets('a stat tile reads as one label', (tester) async {
    await tester.pumpWidget(
      _host(
        const StatTile(
          glyph: PindoroGlyph.flame,
          label: 'Best streak',
          value: '21 days',
        ),
      ),
    );
    expect(find.bySemanticsLabel('Best streak, 21 days'), findsOneWidget);
  });

  testWidgets('a badge tile reads as one label', (tester) async {
    await tester.pumpWidget(
      _host(
        const BadgeTile(
          glyph: PindoroGlyph.car,
          field: Colors.indigo,
          name: 'Road trip',
          condition: 'Finish 5 road trips',
          semanticLabel: 'Road trip, locked, 2 of 5.',
          locked: true,
          progress: 0.4,
        ),
      ),
    );
    expect(find.bySemanticsLabel('Road trip, locked, 2 of 5.'), findsOneWidget);
    expect(find.byType(Minibar), findsOneWidget);
  });

  testWidgets('a one-word badge name too long for its tile shrinks onto '
      'one line instead of breaking mid-word', (tester) async {
    const word = 'ადგილობრივი';
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 110,
          child: BadgeTile(
            glyph: PindoroGlyph.pin,
            field: Colors.indigo,
            name: word,
            condition: 'Learn one area',
            semanticLabel: word,
          ),
        ),
      ),
    );
    final style = tester.widget<Text>(find.text(word)).style!;
    final name = tester.getRect(find.text(word));
    expect(name.height, lessThan(style.fontSize! * 2), reason: 'one line');
    expect(name.width, lessThanOrEqualTo(110), reason: 'shrunk to fit');
  });

  testWidgets('the fade stack shows the old child only while fading', (
    tester,
  ) async {
    Widget stack(int index) => MaterialApp(
      home: FadeIndexedStack(
        index: index,
        children: const [Text('a'), Text('b')],
      ),
    );
    await tester.pumpWidget(stack(0));
    expect(find.text('b'), findsNothing);
    await tester.pumpWidget(stack(1));
    await tester.pump(PindoroMotion.durationFast ~/ 2);
    expect(find.text('a'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('the calendar reads as one image and starts on firstWeekday', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        StreakCalendar(
          month: DateTime(2026, 11),
          dayState: (_) => StreakDay.plain,
          weekdays: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
          firstWeekday: DateTime.sunday,
          semanticLabel: 'November',
        ),
      ),
    );
    expect(find.bySemanticsLabel('November'), findsOneWidget);
    final first = find.byType(Text).first;
    expect(tester.widget<Text>(first).data, 'S');
    // November 2026 starts on a Sunday: day 1 sits under the first header.
    expect(tester.getCenter(find.text('1')).dx, tester.getCenter(first).dx);
  });

  testWidgets('a skeleton shimmers, and holds still under reduce motion', (
    tester,
  ) async {
    // _host turns animations off; this one needs them on.
    await tester.pumpWidget(
      _host(
        const MediaQuery(
          data: MediaQueryData(),
          child: Skeleton(width: 56, height: 56, radius: 28),
        ),
      ),
    );
    expect(tester.getSize(find.byType(Skeleton)), const Size(56, 56));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(
      _host(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Skeleton(width: 56, height: 56),
        ),
      ),
    );
    // Settles (the theme's own lerp ends); a shimmer would never settle.
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a tappable pill is its own button next to other pills', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        Wrap(
          children: [
            const Pill(label: '3 to your Pit stop'),
            Pill(label: 'Up to 4th in Avenue league', onTap: () => taps++),
          ],
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Up to 4th in Avenue league')),
      matchesSemantics(
        label: 'Up to 4th in Avenue league',
        isButton: true,
        hasTapAction: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    await tester.tap(find.text('Up to 4th in Avenue league'));
    expect(taps, 1);
  });

  testWidgets(
    'endpoint pins read their letter; the car and a landmark render',
    (tester) async {
      await tester.pumpWidget(
        _host(
          brightness: Brightness.light,
          Builder(
            builder: (context) =>
                PinMark.endpoint('B', PindoroTheme.of(context).colors),
          ),
        ),
      );
      expect(find.bySemanticsLabel('B'), findsOneWidget);
      final colors = PindoroTheme.of(
        tester.element(find.byType(PinMark)),
      ).colors;
      for (final mark in [
        CarMark(colors).toPng,
        PoiMark(icon: 'cafe', color: colors.mapPoiFood, colors: colors).toPng,
      ]) {
        final png = await tester.runAsync(() => mark(2));
        // PNG signature.
        expect(png!.take(4), [0x89, 0x50, 0x4E, 0x47]);
      }
    },
  );

  group('goldens', skip: _goldensSkip, () {
    Future<void> pumpGallery(WidgetTester tester, Brightness brightness) async {
      await tester.binding.setSurfaceSize(const Size(400, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _host(
          brightness: brightness,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                children: [
                  PindoroIconButton(
                    glyph: PindoroGlyph.close,
                    semanticLabel: 'Leave round',
                    onPressed: () {},
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: QuestionBar(
                      tiers: [Tier.perfect, Tier.miss, Tier.close],
                      total: 10,
                      semanticLabel: 'Question 4 of 10',
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Pill(label: '14 min', icon: PindoroGlyph.timer),
                ],
              ),
              const StreetPlate(
                'Davit Aghmashenebeli Avenue',
                prompt: 'Try again: drop a pin on',
                promptGlyph: PindoroGlyph.reroute,
                subline: 'Vake · you were 1.2 km away',
              ),
              PindoroButton(label: 'Got it', tier: Tier.miss, onPressed: () {}),
              SegmentedControl(
                segments: const {'l': 'Light', 'd': 'Dark', 's': 'System'},
                selected: 'd',
                onChanged: (_) {},
              ),
              const SectionTitle('Display and feedback'),
              ListGroup(
                children: [
                  ListRow(
                    title: 'Sound',
                    subtitle: 'Chimes, taps and celebrations',
                    leading: const RowTile(PindoroGlyph.soundOn),
                    trailing: PindoroToggle(value: true, onChanged: (_) {}),
                    toggled: true,
                    onTap: () {},
                  ),
                  ListRow(
                    title: 'Haptics',
                    leading: const RowTile(PindoroGlyph.haptics),
                    trailing: PindoroToggle(value: false, onChanged: (_) {}),
                    toggled: false,
                    onTap: () {},
                  ),
                ],
              ),
              ListGroup(
                children: [
                  for (final (title, check) in [
                    ('Vake', CheckState.partial),
                    ('Vazha-Pshavela Blocks', CheckState.on),
                    ('Lisi', CheckState.off),
                    ('Sololaki', CheckState.included),
                  ])
                    ListRow(
                      title: title,
                      subtitle: '312 streets',
                      check: check,
                      onTap: () {},
                    ),
                ],
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Pindo(PindoExpression.happy, height: 80),
                  Pindo(PindoExpression.thinking, height: 80),
                  PinMark(
                    face: Color(0xFF2F54EB),
                    lip: Color(0xFF233AAA),
                    dot: Color(0xFFFFFFFF),
                    halo: Color(0xFFFFFFFF),
                  ),
                ],
              ),
              const Center(child: Wordmark(height: 40)),
              const RevealSheet(
                tier: Tier.great,
                label: 'Great!',
                sentence: '84 m away. So close to perfect.',
                headerChip: NextReviewChip(
                  label: 'Next review in 12 days',
                  backThisSession: false,
                  animate: false,
                ),
                chips: [Pill(label: '2 in a row')],
                action: SizedBox(height: 56),
              ),
              ListGroup(
                children: [
                  ResultRow(
                    tier: Tier.close,
                    street: 'Davit Aghmashenebeli Avenue',
                    detail: (tierWord: 'Close', rest: ' · 240 m · to retry'),
                    semanticLabel: 'Question 2',
                    onTap: () {},
                  ),
                ],
              ),
              const TierTally(
                counts: {Tier.perfect: 3, Tier.great: 4, Tier.close: 2},
                labels: {
                  Tier.perfect: 'Perfect',
                  Tier.great: 'Great',
                  Tier.close: 'Close',
                  Tier.miss: 'Miss',
                },
                semanticLabel: 'tally',
              ),
              const CoachBubble(
                title: 'Drop a pin where you think this street is',
                body: 'You can drag it before you confirm.',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final brightness in Brightness.values) {
      testWidgets(brightness.name, (tester) async {
        await pumpGallery(tester, brightness);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/components_${brightness.name}.png'),
        );
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('navigation ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 420));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        PindoroNavBar bar(int current) => PindoroNavBar(
          items: const [
            (glyph: PindoroGlyph.road, label: 'Today', semanticLabel: null),
            (glyph: PindoroGlyph.map, label: 'Explore', semanticLabel: null),
            (glyph: PindoroGlyph.chart, label: 'Progress', semanticLabel: null),
            (glyph: PindoroGlyph.user, label: 'Me', semanticLabel: null),
          ],
          current: current,
          onSelect: (_) {},
        );
        Widget pair(Widget a, Widget b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              Expanded(child: a),
              Expanded(child: b),
            ],
          ),
        );
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            Builder(
              builder: (context) {
                final c = PindoroTheme.of(context).colors;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    bar(0),
                    bar(2),
                    pair(
                      const StatTile(
                        glyph: PindoroGlyph.pin,
                        label: 'Streets known',
                        value: '180',
                      ),
                      const StatTile(
                        glyph: PindoroGlyph.retry,
                        label: 'Reviews',
                        value: '24',
                      ),
                    ),
                    pair(
                      const StatTile(
                        glyph: PindoroGlyph.plus,
                        label: 'New',
                        value: '10',
                      ),
                      StatTile(
                        glyph: PindoroGlyph.flame,
                        glyphColor: c.streakFlame,
                        label: 'Best streak',
                        value: '21 days',
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/navigation_${brightness.name}.png'),
        );
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('badges ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            Builder(
              builder: (context) {
                final c = PindoroTheme.of(context).colors;
                final shields = [
                  (PindoroGlyph.pinDrop, c.badgeFirstPin),
                  (PindoroGlyph.star, c.badgeBullseye),
                  (PindoroGlyph.flame, c.badgeOnFire),
                  (PindoroGlyph.district, c.badgeNavigator),
                  (PindoroGlyph.car, c.badgeRoadTrip),
                  (PindoroGlyph.moon, c.badgeNightOwl),
                  (PindoroGlyph.globe, c.badgeExplorer),
                  (PindoroGlyph.wrench, c.badgePitCrew),
                ];
                BadgeTile tile(
                  int i,
                  String name, {
                  bool locked = false,
                  double? progress,
                  String? newLabel,
                }) => BadgeTile(
                  glyph: shields[i].$1,
                  field: shields[i].$2,
                  name: name,
                  condition: 'Condition of $name',
                  semanticLabel: '',
                  locked: locked,
                  progress: progress,
                  newLabel: newLabel,
                );
                Widget row(List<Widget> tiles) => IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [for (final t in tiles) Expanded(child: t)],
                  ),
                );
                return Column(
                  spacing: 12,
                  children: [
                    Wrap(
                      spacing: 4,
                      children: [
                        for (final (glyph, field) in shields)
                          BadgeShield(glyph: glyph, field: field, size: 40),
                      ],
                    ),
                    row([
                      tile(0, 'First pin', newLabel: 'New'),
                      tile(1, 'Bullseye'),
                      // Short text: the card still fills its column.
                      BadgeTile(
                        glyph: shields[3].$1,
                        field: shields[3].$2,
                        name: 'Navigator',
                        condition: 'Short',
                        semanticLabel: '',
                      ),
                    ]),
                    row([
                      tile(4, 'Road trip', locked: true, progress: 0.4),
                      tile(5, 'Night owl', locked: true),
                      tile(7, 'Pit crew', locked: true, progress: 0.1),
                    ]),
                    BadgeShield(
                      glyph: shields[1].$1,
                      field: shields[1].$2,
                      size: 110,
                    ),
                  ],
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/badges_${brightness.name}.png'),
        );
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('streak ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 760));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const met = {1, 2, 4, 5};
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    for (final state in StreakPillState.values)
                      StreakPill(
                        label: '13',
                        state: state,
                        semanticLabel: state.name,
                      ),
                  ],
                ),
                StreakCalendar(
                  month: DateTime(2026, 11),
                  today: 5,
                  dayState: (d) => met.contains(d)
                      ? StreakDay.met
                      : d == 3
                      ? StreakDay.frozen
                      : d < 5
                      ? StreakDay.missed
                      : StreakDay.plain,
                  weekdays: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
                  semanticLabel: 'November',
                ),
                const StreakFreezeCard(
                  title: 'Streak freeze equipped · 1 of 2',
                  body:
                      'Miss a day and your streak stays put. You earn one '
                      'for every 7 days in a row.',
                ),
                const StreakWeek(
                  days: [
                    StreakDay.met,
                    StreakDay.met,
                    StreakDay.frozen,
                    StreakDay.missed,
                    StreakDay.met,
                    StreakDay.met,
                    StreakDay.met,
                  ],
                  labels: ['Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Today'],
                  title: 'Last 7 days',
                  meta: '5 of 7 counted',
                  semanticsLabel: '',
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/streak_${brightness.name}.png'),
        );
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('route ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 240));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            Builder(
              builder: (context) {
                final c = PindoroTheme.of(context).colors;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    PinMark.endpoint('A', c),
                    PinMark.endpoint('B', c),
                  ],
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/route_${brightness.name}.png'),
        );
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('tabs ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        Polyline square(double lat, double lon, double size) => [
          LatLng(lat, lon),
          LatLng(lat, lon + size),
          LatLng(lat + size, lon + size),
          LatLng(lat + size, lon),
          LatLng(lat, lon),
        ];
        MapDistrict district(int i, DistrictProgress progress, String name) => (
          boundary: [
            [square(41.70, 44.70 + 0.05 * i, 0.05)],
          ],
          progress: progress,
          name: name,
          labelAt: LatLng(41.725, 44.725 + 0.05 * i),
        );
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                const SectionTitle('Where it grows', meta: '9 of 10 started'),
                TileGrid(columns: 2, const [
                  StatTile(
                    glyph: PindoroGlyph.turnRight,
                    label: 'Turns',
                    value: '10',
                  ),
                  StatTile(
                    glyph: PindoroGlyph.bolt,
                    label: 'Drills',
                    value: '2',
                    caption: 'sweep, crossings',
                  ),
                ]),
                DistrictMap(
                  height: 160,
                  semanticsLabel: '',
                  districts: [
                    district(0, DistrictProgress.notStarted, 'Isani'),
                    district(1, DistrictProgress.started, 'Vake'),
                    district(2, DistrictProgress.inProgress, 'Didube'),
                    district(3, DistrictProgress.complete, 'Sololaki'),
                  ],
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    for (final p in DistrictProgress.values)
                      Swatch(progress: p, label: p.name, size: 16),
                  ],
                ),
                Row(
                  spacing: 12,
                  children: [
                    AreaMiniMap(
                      area: [
                        [square(41.70, 44.70, 0.01)],
                      ],
                      streets: const [
                        [LatLng(41.702, 44.701), LatLng(41.708, 44.709)],
                        [LatLng(41.705, 44.700), LatLng(41.705, 44.710)],
                      ],
                    ),
                    const Expanded(child: SheetHandle()),
                  ],
                ),
                const TitledCard(
                  title: 'Last round',
                  meta: 'Pikris Gora · Medium',
                  child: MiniTally(
                    counts: {
                      Tier.perfect: 1,
                      Tier.great: 4,
                      Tier.close: 2,
                      Tier.miss: 3,
                    },
                    semanticLabel: '',
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/tabs_${brightness.name}.png'),
        );
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('memory ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1080));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const counts = (
          mastered: 412,
          solid: 630,
          known: 220,
          seen: 90,
          total: 3282,
        );
        const weekly = [
          120.0,
          180.0,
          260.0,
          400.0,
          520.0,
          610.0,
          700.0,
          860.0,
          990.0,
          1180.0,
          1284.0,
        ];
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                MemoryChart(
                  points: [
                    for (final (i, v) in weekly.indexed)
                      (at: i / (weekly.length - 1), value: v),
                  ],
                  startLabel: 'Sep 8',
                  endLabel: 'Today',
                  semanticsLabel: '',
                ),
                const MemoryChart(
                  points: [
                    (at: 10 / 13, value: 12),
                    (at: 11 / 13, value: 14),
                    (at: 12 / 13, value: 17),
                    (at: 1, value: 20),
                  ],
                  days: 14,
                  startLabel: 'Nov 3',
                  endLabel: 'Today',
                  semanticsLabel: '',
                ),
                MemoryRow(
                  label: 'City memory',
                  value: '1 284',
                  of: 'of 3 216 streets',
                  change: '+8 since yesterday',
                  counts: counts,
                  semanticsLabel: '',
                  onTap: () {},
                ),
                const WeekBars(
                  counts: [24, 31, 27, 22, 35, 0, 26],
                  labels: ['Today', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
                  title: 'Next 7 days',
                  meta: 'about 26 reviews a day',
                  semanticsLabel: '',
                ),
                const MemoryBar(counts: counts, semanticsLabel: ''),
                const MemoryLegend(
                  counts: counts,
                  names: (
                    mastered: 'Mastered',
                    solid: 'Solid',
                    known: 'Known',
                    seen: 'Seen',
                  ),
                ),
                const MemoryBar(
                  counts: (
                    mastered: 0,
                    solid: 4,
                    known: 7,
                    seen: 12,
                    total: 61,
                  ),
                  semanticsLabel: '',
                  compact: true,
                ),
                ForecastBars(
                  counts: const [
                    34,
                    22,
                    18,
                    30,
                    25,
                    12,
                    9,
                    28,
                    31,
                    20,
                    15,
                    26,
                    40,
                    19,
                  ],
                  title: 'Reviews, next 14 days',
                  average: 'about 27 a day',
                  startLabel: 'Today',
                  endLabel: 'Nov 29',
                  semanticsLabel: '',
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/memory_${brightness.name}.png'),
        );
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('bearing dial ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(920, 380));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        Widget dial(double player, double? truth, String caption) => SizedBox(
          width: 280,
          child: BearingDial(
            playerBearing: player,
            trueBearing: truth,
            onChanged: (_) {},
            caption: caption,
            semanticsLabel: 'Compass',
            describeBearing: (b) => '$b',
          ),
        );
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            Row(
              spacing: 16,
              children: [
                dial(300, null, 'Your arrow: west-north-west'),
                dial(270, 252, 'Your arrow: west · Vake Park: west-south-west'),
                dial(
                  40,
                  252,
                  'Your arrow: north-east · Vake Park: west-south-west',
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/bearing_${brightness.name}.png'),
        );
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('route marks ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(560, 160));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            Row(
              spacing: 16,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in [
                  ExitDirection.left,
                  ExitDirection.straight,
                  ExitDirection.right,
                ])
                  ExitButton(
                    direction: d,
                    selected: d == ExitDirection.right,
                    onTap: () {},
                    semanticsLabel: exitLabel(d),
                  ),
                sampleLandmark,
                const CarMarker(),
                const MapTip('2'),
                const MapTip('3', selected: true),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/route_marks_${brightness.name}.png'),
        );
      });
    }
  });
}

final Object _goldensSkip = Platform.isLinux
    ? false
    : 'goldens are Linux-only; run `just goldens` to update them';
