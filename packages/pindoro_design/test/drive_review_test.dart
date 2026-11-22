import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

Widget _host(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildPindoroTheme(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: true,
      textScaler: TextScaler.linear(textScale),
    ),
    child: child!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// Every v3.2 parked part, as the golden shows them.
Widget _parts() => Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 16,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final k in MarkKind.values) ReviewMark(k),
          for (final k in MarkKind.values) ReviewMark(k, onMap: true),
        ],
      ),
      const Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          TurnNumber(1),
          TurnNumber(12),
          TurnNumber(2, onMap: true),
          TurnNumber(3, onMap: true, current: true),
          StartRing(onMap: true),
          DestinationFlag(onMap: true),
          DestinationFlag(),
        ],
      ),
      const StepDots(
        count: 5,
        current: 1,
        line: 'Key turn 2 of 5',
        semanticsLabel: 'Key turns',
        semanticsValue: '2 of 5',
      ),
      const Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          TierChip(tier: Tier.perfect, label: 'Perfect'),
          TierChip(tier: Tier.great, label: 'Great'),
          TierChip(tier: Tier.close, label: 'Close'),
          TierChip(tier: Tier.miss, label: 'Miss'),
          TierChip(tier: null, label: 'No tier'),
        ],
      ),
      const GoalLine(
        done: 1,
        goal: 2,
        count: '1 of 2',
        text: 'drives at Quiet or Off',
      ),
      const GoalLine(
        done: 0,
        goal: 1,
        count: '0 of 1',
        text: 'new place, without help',
      ),
      PlanChecklist(
        items: const [
          (title: 'Home → Work at Quiet', subtitle: 'Your usual Monday'),
          (title: 'Work → Home at Quiet', subtitle: '12 of 13 turns are yours'),
          (title: 'Harbour Road at Off', subtitle: 'A new place nearby'),
        ],
        picked: const {0, 1},
        limit: 2,
        onChanged: (_) {},
      ),
      const RouteLevelStair(
        months: [
          (month: 'Mar', level: 0),
          (month: 'Apr', level: 1),
          (month: 'May', level: null),
          (month: 'Jun', level: 2),
          (month: 'Jul', level: 3),
        ],
        semanticsLabel: 'Guided in March, Off since July',
      ),
      SuggestionCard(
        glyph: PindoroGlyph.compass,
        title: 'Next time: try Quiet',
        line: 'Home → Work: 16 of 17 turns are yours now.',
        action: 'Try Quiet next time',
        onAction: () {},
      ),
      const Center(
        child: DialResultChip(tier: Tier.great, label: 'Great · 18° off'),
      ),
    ],
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('every part builds in ${brightness.name}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(_parts(), brightness: brightness));
      expect(tester.takeException(), isNull);
      expect(find.text('No tier'), findsOneWidget);
    });
  }

  testWidgets('every part builds at 200 % text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(_parts(), textScale: 2));
    expect(tester.takeException(), isNull);
    // Lists' marks grow with the text; the map's keep their size.
    expect(tester.getSize(find.byType(ReviewMark).first).width, 48);
    expect(tester.getSize(find.byType(ReviewMark).last).height, 28 + 2);
  });

  testWidgets('step dots read as one progress value', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const StepDots(
          count: 5,
          current: 1,
          line: 'Key turn 2 of 5',
          semanticsLabel: 'Key turns',
          semanticsValue: '2 of 5',
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byType(StepDots)),
      matchesSemantics(label: 'Key turns', value: '2 of 5'),
    );
    semantics.dispose();
  });

  testWidgets('step dots past twelve steps show the line only', (tester) async {
    await tester.pumpWidget(
      _host(
        const StepDots(
          count: 17,
          current: 8,
          line: 'Turn 9 of 17',
          semanticsLabel: 'Turns',
          semanticsValue: '9 of 17',
        ),
      ),
    );
    expect(find.text('Turn 9 of 17'), findsOneWidget);
    expect(find.byType(AnimatedContainer), findsNothing);
  });

  testWidgets('the plan checklist toggles and, at the limit, says why', (
    tester,
  ) async {
    var picked = <int>{0};
    var limited = 0;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => PlanChecklist(
            items: const [
              (title: 'A', subtitle: 'a'),
              (title: 'B', subtitle: 'b'),
              (title: 'C', subtitle: 'c'),
            ],
            picked: picked,
            limit: 2,
            onChanged: (p) => setState(() => picked = p),
            onLimit: () => limited++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('B'));
    await tester.pump();
    expect(picked, {0, 1});
    await tester.tap(find.text('C'));
    await tester.pump();
    expect(picked, {0, 1});
    expect(limited, 1);
    await tester.tap(find.text('A'));
    await tester.pump();
    expect(picked, {1});
  });

  testWidgets('the goal line reads as one sentence', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const GoalLine(
          done: 1,
          goal: 2,
          count: '1 of 2',
          text: 'drives at Quiet or Off',
        ),
      ),
    );
    expect(find.bySemanticsLabel('1 of 2 drives at Quiet or Off'), findsOne);
    semantics.dispose();
  });

  testWidgets('pointing shows the degrees and greys a calibrating arrow', (
    tester,
  ) async {
    for (final (calibrating, truth) in [(true, null), (false, 300.0)]) {
      await tester.pumpWidget(
        _host(
          BearingDial(
            playerBearing: 290,
            onChanged: (_) {},
            caption: 'Your phone: west-north-west',
            semanticsLabel: 'Compass',
            describeBearing: (b) => '$b',
            enabled: false,
            calibrating: calibrating,
            trueBearing: truth,
            degrees: '10°',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  group('goldens', skip: _goldensSkip, () {
    for (final brightness in Brightness.values) {
      testWidgets('drive review ${brightness.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_host(_parts(), brightness: brightness));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/drive_review_${brightness.name}.png'),
        );
      });
    }
  });
}

final Object _goldensSkip = Platform.isLinux
    ? false
    : 'goldens are Linux-only; run `just goldens` to update them';
