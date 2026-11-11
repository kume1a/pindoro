import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/map/ui/widgets/route_draw_layer.dart';

void main() {
  test('a street is cut where the finger is nearest it', () {
    const street = [Offset(0, 0), Offset(100, 0), Offset(100, 100)];
    // Beside the first segment: cut on it, the corner not reached yet.
    expect(lineUpTo(street, const Offset(40, 10)), const [
      Offset(0, 0),
      Offset(40, 0),
    ]);
    // Past the corner: the whole first segment, then part of the second.
    expect(lineUpTo(street, const Offset(90, 60)), const [
      Offset(0, 0),
      Offset(100, 0),
      Offset(100, 60),
    ]);
    // Behind the start or beyond the end: clamped to the street.
    expect(lineUpTo(street, const Offset(-30, 5)), const [
      Offset(0, 0),
      Offset(0, 0),
    ]);
    expect(
      lineUpTo(street, const Offset(120, 150)).last,
      const Offset(100, 100),
    );
  });
}
