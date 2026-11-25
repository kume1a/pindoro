import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro_design/pindoro_design.dart';

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
}
