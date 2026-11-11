import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/map/ui/widgets/map_taps.dart';

void main() {
  testWidgets('a tap lands on lift; drags, long presses and pinches do not', (
    tester,
  ) async {
    final taps = <Offset>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        // Stands in for the map's platform view, which takes hits.
        child: MapTaps(
          onTap: taps.add,
          child: const ColoredBox(color: Color(0xFF000000)),
        ),
      ),
    );

    await tester.tapAt(const Offset(100, 200));
    expect(taps, [const Offset(100, 200)]);

    await tester.dragFrom(const Offset(100, 200), const Offset(60, 0));
    final hold = await tester.createGesture();
    await hold.down(const Offset(100, 200));
    await hold.up(timeStamp: kLongPressTimeout);
    final first = await tester.startGesture(const Offset(100, 200));
    final second = await tester.startGesture(const Offset(200, 300));
    await first.up();
    await second.up();
    expect(taps, hasLength(1));
  });
}
