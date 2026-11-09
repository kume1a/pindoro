import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

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

  testWidgets('the review gauge reads its step', (tester) async {
    await tester.pumpWidget(
      _host(const ReviewGauge(2, semanticLabel: 'Review step 2 of 4')),
    );
    expect(find.bySemanticsLabel('Review step 2 of 4'), findsOneWidget);
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

  testWidgets('the nav bar reports taps and reads the current tab and badge', (
    tester,
  ) async {
    int? tapped;
    await tester.pumpWidget(
      _host(
        PindoroNavBar(
          items: const [
            (
              glyph: PindoroGlyph.map,
              label: 'Free play',
              badge: null,
              semanticLabel: null,
            ),
            (
              glyph: PindoroGlyph.wrench,
              label: 'Pit stop',
              badge: 7,
              semanticLabel: 'Pit stop, 7 streets due',
            ),
          ],
          current: 0,
          onSelect: (i) => tapped = i,
        ),
      ),
    );
    expect(find.text('7'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Free play')),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Pit stop, 7 streets due')),
      isSemantics(isButton: true, isSelected: false),
    );
    await tester.tap(find.bySemanticsLabel('Pit stop, 7 streets due'));
    expect(tapped, 1);
  });

  testWidgets('the nav bar keeps its height under a Scaffold', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPindoroTheme(Brightness.light),
        home: Scaffold(
          bottomNavigationBar: PindoroNavBar(
            items: const [
              (
                glyph: PindoroGlyph.user,
                label: 'Me',
                badge: null,
                semanticLabel: null,
              ),
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

  testWidgets('a path stop reads its label and takes taps, locked too', (
    tester,
  ) async {
    final taps = <String>[];
    await tester.pumpWidget(
      _host(
        Column(
          spacing: 64,
          children: [
            const SizedBox(height: 40),
            PathStop(
              look: PathStopLook.current,
              glyph: PindoroGlyph.play,
              big: true,
              ring: 0.3,
              tip: 'Start',
              semanticLabel: 'Lesson 1. Current.',
              onTap: () => taps.add('current'),
            ),
            PathStop(
              look: PathStopLook.locked,
              glyph: PindoroGlyph.lock,
              semanticLabel: 'Lesson 2. Locked.',
              onTap: () => taps.add('locked'),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Lesson 1. Current.'));
    await tester.tap(find.bySemanticsLabel('Lesson 2. Locked.'));
    expect(taps, ['current', 'locked']);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('a signpost is one heading', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const Signpost(
          number: 2,
          line: '2 of 6 lessons',
          title: 'Vake',
          semanticLabel: 'Unit 2, Vake. 2 of 6 lessons done.',
        ),
      ),
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel('Unit 2, Vake. 2 of 6 lessons done.'),
      ),
      matchesSemantics(
        label: 'Unit 2, Vake. 2 of 6 lessons done.',
        isHeader: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('plate choices are a radio group that reports taps', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    String? tapped;
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            for (final (name, state) in [
              ('Pekini Avenue', PlateChoiceState.selected),
              ('Kostava Street', PlateChoiceState.idle),
            ])
              PlateChoice(
                name: name,
                sub: 'sub',
                state: state,
                onTap: () => tapped = name,
              ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Kostava Street'));
    expect(tapped, 'Kostava Street');
    expect(
      tester.getSemantics(find.bySemanticsLabel('Pekini Avenue, sub')),
      matchesSemantics(
        label: 'Pekini Avenue, sub',
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('the feedback bar runs its action', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      _host(
        FeedbackBar(
          right: false,
          title: 'Not quite',
          body: 'The marked plate is right.',
          action: 'Got it',
          onAction: () => pressed = true,
        ),
      ),
    );
    await tester.tap(find.text('Got it'));
    expect(pressed, isTrue);
  });

  testWidgets('endpoint pins read their letter; the car renders', (
    tester,
  ) async {
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
    final colors = PindoroTheme.of(tester.element(find.byType(PinMark))).colors;
    final png = await tester.runAsync(() => CarMark(colors).toPng(2));
    // PNG signature.
    expect(png!.take(4), [0x89, 0x50, 0x4E, 0x47]);
  });

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
                  const Pill(label: '338', icon: PindoroGlyph.xp),
                ],
              ),
              const StreetPlate(
                'Davit Aghmashenebeli Avenue',
                prompt: 'Try again: drop a pin on',
                promptGlyph: PindoroGlyph.reroute,
                subline: 'Vake · you were 1.2 km away',
              ),
              const Row(
                spacing: 12,
                children: [
                  LevelBadge(3, size: 44),
                  Expanded(child: XpBar(value: 0.87, semanticLabel: 'Level 3')),
                ],
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
                xpLabel: '+74 XP',
                chips: [Pill(label: '2 in a row')],
                action: SizedBox(height: 56),
              ),
              ListGroup(
                children: [
                  ResultRow(
                    tier: Tier.close,
                    street: 'Davit Aghmashenebeli Avenue',
                    detail: (tierWord: 'Close', rest: ' · 240 m · to retry'),
                    xp: 39,
                    semanticLabel: 'Question 2',
                    onTap: () {},
                  ),
                ],
              ),
              const Center(
                child: RewardTotal(value: '+695 XP', semanticLabel: '695 XP'),
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
        PindoroNavBar bar(int current, int due) => PindoroNavBar(
          items: [
            (
              glyph: PindoroGlyph.map,
              label: 'Free play',
              badge: null,
              semanticLabel: null,
            ),
            (
              glyph: PindoroGlyph.wrench,
              label: 'Pit stop',
              badge: due,
              semanticLabel: null,
            ),
            (
              glyph: PindoroGlyph.user,
              label: 'Me',
              badge: null,
              semanticLabel: null,
            ),
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
                    bar(0, 7),
                    bar(1, 12),
                    pair(
                      const StatTile(
                        glyph: PindoroGlyph.pin,
                        label: 'Streets known',
                        value: '180',
                      ),
                      const StatTile(
                        glyph: PindoroGlyph.road,
                        label: 'Lessons',
                        value: '14',
                      ),
                    ),
                    pair(
                      const StatTile(
                        glyph: PindoroGlyph.car,
                        label: 'Road trips',
                        value: '9',
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
      testWidgets('pit stop ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
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
                    Row(
                      spacing: 12,
                      children: [
                        RowTile(
                          PindoroGlyph.wrench,
                          face: c.pathNodeReviewFill,
                          ink: c.pathNodeReviewIcon,
                          lip: c.pathNodeReviewLip,
                        ),
                        for (var step = 1; step <= 4; step++)
                          ReviewGauge(step, semanticLabel: '$step'),
                      ],
                    ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: PitStopChip('Added to your Pit stop'),
                    ),
                    ListGroup(
                      children: [
                        for (final (tier, step) in [
                          (Tier.miss, 1),
                          (Tier.close, 3),
                        ])
                          ListRow(
                            title: 'Davit Aghmashenebeli Avenue',
                            subtitle: 'Missed · 1 day ago',
                            leading: TierBadge(tier),
                            trailing: ReviewGauge(step, semanticLabel: ''),
                          ),
                      ],
                    ),
                    const Row(
                      spacing: 8,
                      children: [
                        Swatch(progress: DistrictProgress.notStarted, size: 22),
                        Swatch(progress: DistrictProgress.inProgress, size: 22),
                        Swatch(progress: DistrictProgress.complete, size: 22),
                      ],
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
          matchesGoldenFile('goldens/pit_stop_${brightness.name}.png'),
        );
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('streak ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 640));
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
                const Row(
                  spacing: 12,
                  children: [
                    DailyGoalRing(progress: 0.64, semanticLabel: '320 of 500'),
                    DailyGoalRing(progress: 1, semanticLabel: 'met'),
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
      testWidgets('path ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const xs = [195.0, 128.0, 195.0, 262.0, 195.0, 128.0, 195.0];
        final points = [
          const Offset(195, 0),
          for (final (i, x) in xs.indexed) Offset(x - 16, 150 + 104.0 * i),
        ];
        Widget stop(int i, PathStopLook look, PindoroGlyph glyph) {
          final big = look == PathStopLook.current;
          final size = PathStop.sizeOf(big: big);
          return Positioned(
            left: points[i + 1].dx - size / 2,
            top: points[i + 1].dy - size / 2,
            child: PathStop(
              look: look,
              glyph: glyph,
              big: big,
              ring: big ? 0.25 : null,
              tip: big ? 'Start' : null,
              semanticLabel: '$i',
              onTap: () {},
            ),
          );
        }

        await tester.pumpWidget(
          _host(
            brightness: brightness,
            SizedBox(
              height: 860,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: LessonRoad(points: points, driven: 3.5),
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    child: Column(
                      spacing: 8,
                      children: [
                        Signpost(
                          number: 2,
                          line: '2 of 6 lessons',
                          title: 'Vake District',
                          semanticLabel: 'open',
                        ),
                        Signpost(
                          number: 3,
                          line: 'Locked',
                          title: 'Saburtalo District',
                          locked: true,
                          semanticLabel: 'locked',
                        ),
                      ],
                    ),
                  ),
                  stop(0, PathStopLook.done, PindoroGlyph.check),
                  stop(1, PathStopLook.perfect, PindoroGlyph.star),
                  stop(2, PathStopLook.review, PindoroGlyph.wrench),
                  stop(3, PathStopLook.current, PindoroGlyph.play),
                  stop(4, PathStopLook.locked, PindoroGlyph.lock),
                  stop(5, PathStopLook.locked, PindoroGlyph.wrench),
                  stop(6, PathStopLook.locked, PindoroGlyph.trophy),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/path_${brightness.name}.png'),
        );
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('lesson ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                for (final (name, state) in [
                  ('Kostava Street', PlateChoiceState.idle),
                  ('Pekini Avenue', PlateChoiceState.selected),
                  ('Ilia Chavchavadze Avenue', PlateChoiceState.right),
                  ('Vazha-Pshavela Avenue', PlateChoiceState.wrong),
                  ('Abashidze Street', PlateChoiceState.dim),
                ])
                  PlateChoice(
                    name: name,
                    sub: 'sub-line',
                    state: state,
                    onTap: () {},
                  ),
                FeedbackBar(
                  right: true,
                  title: 'Correct!',
                  body: 'Pekini Avenue',
                  xpLabel: '+50 XP',
                  action: 'Continue',
                  onAction: () {},
                ),
                FeedbackBar(
                  right: false,
                  title: 'Not quite',
                  body: 'The marked plate is right. It comes back at the end.',
                  action: 'Got it',
                  onAction: () {},
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/lesson_${brightness.name}.png'),
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
                    const LevelBadge.glyph(PindoroGlyph.trophy, size: 110),
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
  });
}

final Object _goldensSkip = Platform.isLinux
    ? false
    : 'goldens are Linux-only; run `just goldens` to update them';
