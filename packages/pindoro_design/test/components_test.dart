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
                chips: ['2 in a row'],
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
  });
}

final Object _goldensSkip = Platform.isLinux
    ? false
    : 'goldens are Linux-only; run `just goldens` to update them';
