import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro_design/pindoro_design.dart';

Widget _host(Widget child, {bool calm = false}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildPindoroTheme(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: calm),
    child: child!,
  ),
  home: Scaffold(
    body: Center(child: SizedBox(width: 302, child: child)),
  ),
);

const MemoryCounts _counts = (
  mastered: 0,
  solid: 10,
  known: 10,
  seen: 0,
  total: 40,
);

Finder _segment(WidgetTester tester, Color Function(PindoroColors) colour) {
  final c = PindoroTheme.of(tester.element(find.byType(Scaffold))).colors;
  return find.byWidgetPredicate((w) => w is ColoredBox && w.color == colour(c));
}

void main() {
  test('segments share the width by count, empty ones and their gaps out', () {
    expect(memorySegmentWidths([0, 4, 7, 0], 22, 302), [
      closeTo(300 * 4 / 22, 1e-9),
      closeTo(300 * 7 / 22, 1e-9),
    ]);
    expect(memorySegmentWidths([0, 0, 0, 0], 61, 300), isEmpty);
    expect(memorySegmentWidths([5], 0, 300), isEmpty);
  });

  testWidgets('the bar draws each state as its share, the rest is track', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const MemoryBar(
          counts: _counts,
          semanticsLabel:
              'Bagebi: 0 mastered, 10 solid, 10 known, 0 seen of 40',
        ),
      ),
    );
    expect(tester.getSize(_segment(tester, (c) => c.memorySolid)).width, 75);
    expect(tester.getSize(_segment(tester, (c) => c.memoryKnown)).width, 75);
    expect(tester.getSize(_segment(tester, (c) => c.memoryKnown)).height, 14);
    expect(_segment(tester, (c) => c.memoryMastered), findsNothing);
    expect(_segment(tester, (c) => c.memorySeen), findsNothing);
    expect(
      find.bySemanticsLabel(
        'Bagebi: 0 mastered, 10 solid, 10 known, 0 seen of 40',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the compact bar is 6 dp', (tester) async {
    await tester.pumpWidget(
      _host(
        const MemoryBar(counts: _counts, semanticsLabel: '', compact: true),
      ),
    );
    expect(tester.getSize(_segment(tester, (c) => c.memorySolid)).height, 6);
  });

  testWidgets('a growing bar starts empty, unless motion is reduced', (
    tester,
  ) async {
    const bar = MemoryBar(counts: _counts, semanticsLabel: '', animate: true);
    await tester.pumpWidget(_host(bar));
    expect(tester.getSize(_segment(tester, (c) => c.memorySolid)).width, 0);
    await tester.pumpAndSettle();
    expect(tester.getSize(_segment(tester, (c) => c.memorySolid)).width, 75);

    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pumpWidget(_host(bar, calm: true));
    expect(tester.getSize(_segment(tester, (c) => c.memorySolid)).width, 75);
  });

  testWidgets('the legend names every state with its formatted count', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        MemoryLegend(
          counts: (mastered: 1412, solid: 630, known: 0, seen: 90, total: 3282),
          names: (
            mastered: 'Mastered',
            solid: 'Solid',
            known: 'Known',
            seen: 'Seen',
          ),
          format: (n) => n.toString().replaceAll('1412', '1 412'),
        ),
      ),
    );
    for (final text in ['Mastered 1 412', 'Solid 630', 'Known 0', 'Seen 90']) {
      expect(find.text(text, findRichText: true), findsOneWidget);
    }
  });

  test('the chart top is the max plus 5 %, rounded up a decade below', () {
    expect(chartTop(1284), 1400);
    expect(chartTop(86), 91);
    expect(chartTop(5), 10);
    expect(chartTop(0), 10);
  });

  testWidgets('the chart is one image, with any number of values', (
    tester,
  ) async {
    for (final values in <List<double>>[
      [],
      [12.0],
      [120, 180, 240, 400, 520, 610, 700, 860, 990, 1180, 1284],
    ]) {
      await tester.pumpWidget(
        _host(
          MemoryChart(
            values: values,
            startLabel: 'Sep 8',
            endLabel: 'Today',
            semanticsLabel: 'City memory over the last 10 weeks',
            animate: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsLabel('City memory over the last 10 weeks'),
        findsOneWidget,
      );
      expect(tester.getSize(find.byType(MemoryChart)).height, 132);
    }
  });

  test('the busiest day fills the bars; an empty day draws nothing', () {
    expect(forecastBarHeights([34, 17, 0, 68]), [28, 14, 0, 56]);
    expect(forecastBarHeights([0, 0]), [0, 0]);
  });

  testWidgets('the forecast card reads as one node', (tester) async {
    await tester.pumpWidget(
      _host(
        ForecastBars(
          counts: [34, for (var i = 0; i < 13; i++) 20 + i],
          title: 'Reviews, next 14 days',
          average: 'about 27 a day',
          startLabel: 'Today',
          endLabel: 'Nov 29',
          semanticsLabel: 'Reviews, next 14 days, about 27 a day. Today 34.',
          animate: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Reviews, next 14 days, about 27 a day. Today 34.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Nov 29'), findsNothing);
  });
}
