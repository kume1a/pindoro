import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  home: Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);

const _names = [
  (label: 'Machabeli Street', sublabel: null),
  (label: 'Chavchavadze Avenue', sublabel: null),
  (label: 'Paliashvili Street', sublabel: null),
  (label: 'Abashidze Street', sublabel: null),
  (label: 'Kazbegi Avenue', sublabel: null),
  (label: 'Tamarashvili Street', sublabel: null),
];

AnswerTray _tray({
  List<AnswerChoiceData> choices = _names,
  AnswerResult? result,
  ValueChanged<int>? onConfirm,
}) => AnswerTray(
  key: const ValueKey('q1'),
  question: 'Which street is painted yellow?',
  meta: '6 names',
  choices: choices,
  confirmLabel: 'Confirm',
  confirmHint: 'Pick a name first.',
  result: result,
  onConfirm: onConfirm ?? (_) {},
);

/// Whether the tray laid its choices out in one column.
bool _oneColumn(WidgetTester tester) =>
    tester.getTopLeft(find.text(_names[0].label)).dx ==
    tester.getTopLeft(find.text(_names[1].label)).dx;

/// A 360 × 800 dp phone, as MediaQuery sees it.
void _phone(WidgetTester tester) {
  tester.view
    ..devicePixelRatio = 3
    ..physicalSize = const Size(1080, 2400);
  addTearDown(tester.view.reset);
}

PindoroButton _confirm(WidgetTester tester) =>
    tester.widget<PindoroButton>(find.widgetWithText(PindoroButton, 'Confirm'));

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('the tray builds in ${brightness.name}, in two columns', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(_host(_tray(), brightness: brightness));
      expect(tester.takeException(), isNull);
      expect(find.text('6 names'), findsOneWidget);
      expect(_oneColumn(tester), isFalse);
    });
  }

  testWidgets('a pick enables Confirm, which grades the pick', (tester) async {
    _phone(tester);
    final confirmed = <int>[];
    await tester.pumpWidget(_host(_tray(onConfirm: confirmed.add)));
    expect(_confirm(tester).onPressed, isNull);
    await tester.tap(find.text('Paliashvili Street'));
    await tester.pump();
    await tester.tap(find.text('Kazbegi Avenue'));
    await tester.pump();
    expect(confirmed, isEmpty);
    await tester.tap(find.text('Confirm'));
    expect(confirmed, [4]);
  });

  testWidgets('the result locks the choices and Confirm', (tester) async {
    _phone(tester);
    final confirmed = <int>[];
    await tester.pumpWidget(
      _host(_tray(result: (picked: 4, right: 0), onConfirm: confirmed.add)),
    );
    await tester.tap(find.text('Paliashvili Street'));
    await tester.pump();
    expect(_confirm(tester).onPressed, isNull);
    expect(find.byType(PindoroIcon), findsWidgets);
    expect(confirmed, isEmpty);
  });

  testWidgets('a word too wide for half the tray, or 200 % text, takes one '
      'numbered column', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _host(
        _tray(
          choices: [
            ..._names.take(5),
            (label: 'Grandunioncanalembankmentnorth Street', sublabel: null),
          ],
        ),
      ),
    );
    expect(_oneColumn(tester), isTrue);
    expect(find.text('1'), findsOneWidget);

    await tester.pumpWidget(_host(_tray(), textScale: 2));
    expect(tester.takeException(), isNull);
    expect(_oneColumn(tester), isTrue);
  });

  testWidgets('dragging the handle down peeks; a tap opens it again', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_host(_tray()));
    await tester.drag(find.text('6 names'), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.text('Confirm'), findsNothing);
    await tester.tap(find.text('6 names'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm'), findsOneWidget);
  });

  testWidgets('the sweep picks a label up on a tap, and a socket takes a '
      'dropped one', (tester) async {
    _phone(tester);
    int? held;
    int? dropped;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SweepSocket(
                semanticsLabel: 'Lane 1, empty',
                waking: held != null,
                onAccept: (i) => setState(() => dropped = i),
              ),
              SweepTray(
                question: 'Which lane is which?',
                meta: '0 of 3 placed',
                labels: const [
                  (label: '1st Lane', sublabel: null),
                  (label: '2nd Lane', sublabel: null),
                  (label: '3rd Lane', sublabel: null),
                ],
                placed: const {},
                held: held,
                onHold: (i) => setState(() => held = i),
                confirmLabel: 'Confirm',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('2nd Lane'));
    await tester.pump();
    expect(held, 1);
    await tester.tap(find.text('2nd Lane'));
    await tester.pump();
    expect(held, isNull);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('3rd Lane')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(held, 2);
    await gesture.moveTo(tester.getCenter(find.byType(SweepSocket)));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(dropped, 2);
  });

  testWidgets('a checked socket shows the truth under a wrong label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SweepSocket(
              semanticsLabel: 'Lane 1',
              label: '2nd Lane',
              right: false,
              truth: '1st Lane',
            ),
            SweepSocket(
              semanticsLabel: 'Lane 2',
              label: '2nd Lane',
              right: true,
            ),
          ],
        ),
        brightness: Brightness.dark,
      ),
    );
    expect(find.text('1st Lane'), findsOneWidget);
  });

  group('goldens', skip: _goldensSkip, () {
    for (final brightness in Brightness.values) {
      testWidgets('answer tray ${brightness.name}', (tester) async {
        _phone(tester);
        await tester.pumpWidget(
          _host(
            brightness: brightness,
            Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 16,
              children: [
                _tray(result: (picked: 4, right: 0)),
                const Wrap(
                  children: [
                    SweepSocket(semanticsLabel: 'Lane 1'),
                    SweepSocket(semanticsLabel: 'Lane 2', waking: true),
                    SweepSocket(semanticsLabel: 'Lane 3', label: '3rd Lane'),
                    SweepSocket(
                      semanticsLabel: 'Lane 4',
                      label: '2nd Lane',
                      right: false,
                      truth: '4th Lane',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/answer_tray_${brightness.name}.png'),
        );
      });
    }
  });
}

final Object _goldensSkip = Platform.isLinux
    ? false
    : 'goldens are Linux-only; run `just goldens` to update them';
