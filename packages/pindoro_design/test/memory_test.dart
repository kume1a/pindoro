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

  test('the chart top is the max plus 5 %, rounded up a decade below, and '
      'never under 100', () {
    expect(chartTop(1284), 1400);
    expect(chartTop(486), 520);
    expect(chartTop(86), 100);
    expect(chartTop(20), 100);
    expect(chartTop(0), 100);
  });

  testWidgets('the chart is one image, with any number of points', (
    tester,
  ) async {
    for (final (points, days) in <(List<ChartPoint>, int)>[
      (const [], 14),
      (const [(at: 1, value: 20)], 14),
      ([for (var i = 0; i <= 10; i++) (at: i / 10, value: 120.0 * i)], 0),
    ]) {
      await tester.pumpWidget(
        _host(
          MemoryChart(
            points: points,
            days: days,
            startLabel: 'Sep 8',
            endLabel: 'Today',
            semanticsLabel: 'City memory over time',
            animate: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('City memory over time'), findsOneWidget);
      expect(tester.getSize(find.byType(MemoryChart)).height, 132);
    }
  });

  testWidgets('the City memory row reads as one button and opens on a tap', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(
        MemoryRow(
          label: 'City memory',
          value: '20',
          of: 'of 3 216 streets',
          change: '+20 today',
          counts: const (
            mastered: 0,
            solid: 0,
            known: 9,
            seen: 15,
            total: 3216,
          ),
          semanticsLabel: 'City memory: 20 of 3 216 streets',
          onTap: () => opened++,
        ),
      ),
    );
    expect(find.text('+20 today'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('City memory: 20 of 3 216 streets'));
    expect(opened, 1);
  });

  testWidgets('the week strip keeps a zero day and reads as one node', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const WeekBars(
          counts: [0, 9, 8, 0, 2, 0, 0],
          labels: ['Today', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
          title: 'Next 7 days',
          meta: '19 reviews this week',
          semanticsLabel: 'Reviews due, next 7 days',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('0'), findsNWidgets(4));
    expect(find.bySemanticsLabel('Reviews due, next 7 days'), findsOneWidget);
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
