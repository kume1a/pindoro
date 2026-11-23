import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pindoro/features/map/ui/widgets/map_sprite.dart';

void main() {
  testWidgets('a sprite pictures its child with its foot at the centre', (
    tester,
  ) async {
    final pngs = <Uint8List>[];
    await tester.pumpWidget(
      Center(
        child: MapSprite(
          foot: Alignment.bottomCenter,
          pixelRatio: 2,
          onPng: pngs.add,
          child: const SizedBox(width: 40, height: 20),
        ),
      ),
    );
    // The foot 20 dp below the box's top: 20 dp each way from it, plus 24 dp of bleed.
    expect(tester.getSize(find.byType(MapSprite)), const Size(88, 88));
    final image = await tester.runAsync(() async {
      while (pngs.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final codec = await ui.instantiateImageCodec(pngs.single);
      return (await codec.getNextFrame()).image;
    });
    expect((image!.width, image.height), (176, 176));
  });
}
