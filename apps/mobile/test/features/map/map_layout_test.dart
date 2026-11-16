import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/map/ui/map_layout.dart';
import 'package:pindoro_design/pindoro_design.dart';

void main() {
  testWidgets('the map is built with the heights its overlays cover', (
    tester,
  ) async {
    MapInsets? insets;
    Widget layout(double plate) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
        child: MapLayout(
          map: (i) {
            insets = i;
            return const SizedBox.expand();
          },
          top: SizedBox(height: plate),
          bottom: const SizedBox(height: 200),
        ),
      ),
    );

    await tester.pumpWidget(layout(100));
    await tester.pump();
    expect(insets, (top: 24 + PindoroSpace.s4 * 2 + 100, bottom: 200));

    // A plate that wraps to two lines moves the top inset with it.
    await tester.pumpWidget(layout(140));
    await tester.pump();
    expect(insets?.top, 24 + PindoroSpace.s4 * 2 + 140);
  });

  testWidgets('without a top overlay the map clears the status bar', (
    tester,
  ) async {
    MapInsets? insets;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
          child: MapLayout(
            map: (i) {
              insets = i;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    expect(insets, (top: 24.0, bottom: 0.0));
  });
}
