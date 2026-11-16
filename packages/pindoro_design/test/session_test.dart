import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro_core/pindoro_core.dart';
import 'package:pindoro_design/pindoro_design.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildPindoroTheme(Brightness.light),
  home: Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);

Iterable<PindoroGlyph> _glyphs(WidgetTester tester) => tester
    .widgetList<PindoroIcon>(find.byType(PindoroIcon))
    .map((i) => i.glyph);

void main() {
  group('NextReviewChip', () {
    testWidgets('a scheduled review shows the calendar', (tester) async {
      await tester.pumpWidget(
        _host(
          const NextReviewChip(
            label: 'Next review in 12 days',
            backThisSession: false,
            animate: false,
          ),
        ),
      );
      expect(find.text('Next review in 12 days'), findsOneWidget);
      expect(_glyphs(tester), [PindoroGlyph.calendar]);
    });

    testWidgets('back in this session shows retry, after its pop', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const NextReviewChip(
            label: 'Back in this session',
            backThisSession: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Back in this session'), findsOneWidget);
      expect(_glyphs(tester), [PindoroGlyph.retry]);
    });
  });

  group('IntroSheet', () {
    IntroSheet sheet({
      VoidCallback? onHear,
      String? etymology,
      String? family,
    }) => IntroSheet(
      title: 'Where it is',
      where: 'Runs north-west from the river.',
      facts: '2.1 km · avenue · crosses 9 streets',
      gotItLabel: 'Got it',
      onGotIt: () {},
      regionLabel: 'About this street',
      hearLabel: 'Hear the name',
      onHear: onHear,
      etymology: etymology,
      family: family,
    );

    testWidgets('Hear the name shows only with a voice', (tester) async {
      await tester.pumpWidget(_host(sheet()));
      expect(find.bySemanticsLabel('Hear the name'), findsNothing);
      await tester.pumpWidget(_host(sheet(onHear: () {})));
      expect(find.bySemanticsLabel('Hear the name'), findsOneWidget);
    });

    testWidgets('etymology and the family chip only when given', (
      tester,
    ) async {
      await tester.pumpWidget(_host(sheet()));
      expect(find.byType(StatChip), findsNothing);
      await tester.pumpWidget(
        _host(
          sheet(
            etymology: 'Named after the poet Vazha-Pshavela.',
            family: '26 May Street · 9 lanes, 6 dead ends',
          ),
        ),
      );
      expect(find.text('Named after the poet Vazha-Pshavela.'), findsOneWidget);
      expect(find.text('26 May Street · 9 lanes, 6 dead ends'), findsOneWidget);
      expect(_glyphs(tester), contains(PindoroGlyph.road));
    });

    testWidgets('Got it goes on', (tester) async {
      var gotIt = 0;
      await tester.pumpWidget(
        _host(
          IntroSheet(
            title: 'Where it is',
            where: 'x',
            facts: 'y',
            gotItLabel: 'Got it',
            onGotIt: () => gotIt++,
            regionLabel: 'About this street',
          ),
        ),
      );
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(gotIt, 1);
    });
  });

  testWidgets('RevealSheet ends its header with the given chip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        RevealSheet(
          tier: Tier.great,
          label: 'Great!',
          sentence: '84 m away.',
          headerChip: const NextReviewChip(
            label: 'Next review in 12 days',
            backThisSession: false,
            animate: false,
          ),
          action: PindoroButton(label: 'Next', onPressed: () {}),
        ),
      ),
    );
    expect(find.text('Next review in 12 days'), findsOneWidget);
    expect(find.byType(XpChip), findsNothing);
  });
}
