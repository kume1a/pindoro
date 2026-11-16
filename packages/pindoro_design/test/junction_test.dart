import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro_design/pindoro_design.dart';

import 'junction_sample.dart';

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildPindoroTheme(Brightness.light),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('an exit button is a labelled toggle that takes taps', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _host(
        ExitButton(
          direction: ExitDirection.right,
          selected: true,
          onTap: () => taps++,
          semanticsLabel: 'Turn right',
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byType(ExitButton)),
      matchesSemantics(
        label: 'Turn right',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.byType(ExitButton));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('the junction map shows its exits only while choosing', (
    tester,
  ) async {
    final chosen = <ExitDirection>[];
    Widget map(JunctionState state) => _host(
      SizedBox(
        width: 360,
        height: 560,
        child: JunctionMap(
          geometry: sampleJunction,
          state: state,
          onChoose: chosen.add,
          exitLabel: exitLabel,
          semanticsLabel: 'Unlabelled map of the junction ahead',
          correct: state == JunctionState.choosing ? null : ExitDirection.right,
          landmark: sampleLandmark,
          carLabel: 'You, driving north',
        ),
      ),
    );
    await tester.pumpWidget(map(JunctionState.choosing));
    expect(find.byType(ExitButton), findsNWidgets(3));
    await tester.tap(find.bySemanticsLabel('Turn right'));
    expect(chosen, [ExitDirection.right]);
    final right = tester.getCenter(find.bySemanticsLabel('Turn right'));
    final left = tester.getCenter(find.bySemanticsLabel('Turn left'));
    final straight = tester.getCenter(find.bySemanticsLabel('Go straight on'));
    expect(right.dx, greaterThan(left.dx), reason: 'heading up: east is right');
    expect(straight.dy, lessThan(right.dy));

    await tester.pumpWidget(map(JunctionState.right));
    expect(find.byType(ExitButton), findsNothing);
    expect(find.byType(LandmarkBadge), findsOneWidget);
  });

  testWidgets('a southbound approach still comes up from the bottom', (
    tester,
  ) async {
    const southbound = JunctionGeometry(
      roads: [],
      approach: [Offset(0, 300), Offset.zero],
      exits: {
        ExitDirection.left: [Offset.zero, Offset(300, 0)],
        ExitDirection.right: [Offset.zero, Offset(-300, 0)],
      },
    );
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 360,
          height: 560,
          child: JunctionMap(
            geometry: southbound,
            state: JunctionState.choosing,
            onChoose: (_) {},
            exitLabel: exitLabel,
            semanticsLabel: 'Map',
          ),
        ),
      ),
    );
    final right = tester.getCenter(find.bySemanticsLabel('Turn right'));
    final left = tester.getCenter(find.bySemanticsLabel('Turn left'));
    expect(right.dx, greaterThan(left.dx), reason: 'west is right going south');
  });
}
