import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro_design/pindoro_design.dart';

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildPindoroTheme(Brightness.light),
  home: Scaffold(body: Center(child: child)),
);

String _word(double b) => '${b.round()}°';

BearingDial _dial({
  required ValueChanged<double> onChanged,
  double player = 300,
  double? truth,
  bool enabled = true,
}) => BearingDial(
  playerBearing: player,
  trueBearing: truth,
  enabled: enabled,
  onChanged: onChanged,
  caption: 'Your arrow',
  semanticsLabel: 'Compass',
  describeBearing: _word,
  northLabel: 'N',
);

/// The dial's centre on screen.
Offset _centre(WidgetTester tester) =>
    tester.getCenter(find.byType(CustomPaint).last);

void main() {
  testWidgets('a touch points the arrow at the finger, and it follows', (
    tester,
  ) async {
    final seen = <double>[];
    await tester.pumpWidget(_host(_dial(onChanged: seen.add)));
    final centre = _centre(tester);
    final drag = await tester.startGesture(centre + const Offset(0, -80));
    await drag.moveTo(centre + const Offset(80, 0));
    await drag.moveTo(centre + const Offset(-80, 0));
    await drag.up();
    expect(seen.first, closeTo(0, 1e-9));
    expect(seen, contains(closeTo(90, 1e-9)));
    expect(seen.last, closeTo(270, 1e-9));
  });

  testWidgets('disabled, or after Check, a drag changes nothing', (
    tester,
  ) async {
    final seen = <double>[];
    await tester.pumpWidget(_host(_dial(onChanged: seen.add, enabled: false)));
    final centre = _centre(tester);
    await tester.dragFrom(centre + const Offset(0, -80), const Offset(80, 80));
    await tester.pumpWidget(_host(_dial(onChanged: seen.add, truth: 252)));
    await tester.dragFrom(centre + const Offset(0, -80), const Offset(80, 80));
    expect(seen, isEmpty);
  });

  testWidgets('a screen reader turns the arrow one tick at a time', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final seen = <double>[];
    await tester.pumpWidget(_host(_dial(onChanged: seen.add, player: 345)));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Compass')),
      matchesSemantics(
        label: 'Compass',
        value: '345°',
        increasedValue: '15°',
        decreasedValue: '315°',
        isSlider: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        hasFocusAction: true,
      ),
    );
    final compass = find.semantics.byLabel('Compass');
    tester.semantics
      ..performAction(compass, SemanticsAction.increase)
      ..performAction(compass, SemanticsAction.decrease);
    expect(seen, [15, 315]);
    handle.dispose();
  });

  testWidgets('arrow keys turn it 30°', (tester) async {
    final seen = <double>[];
    await tester.pumpWidget(_host(_dial(onChanged: seen.add, player: 0)));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(seen, [30, 330]);
  });
}
