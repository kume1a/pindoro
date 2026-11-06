// Renders the design system's branding SVGs to the PNGs the native icon and
// splash generators need: `flutter test tool/rasterize_branding_test.dart`
// from packages/pindoro_design, then `just branding`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const _branding = '../../apps/mobile/assets/branding';

/// Draws [svg] scaled to [content] px, centred on a [canvas] px square.
Future<void> _render(String svg, String out, int canvas, double content) async {
  final info = await vg.loadPicture(SvgFileLoader(File(svg)), null);
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  final scale = content / info.size.longestSide;
  c
    ..translate(
      (canvas - info.size.width * scale) / 2,
      (canvas - info.size.height * scale) / 2,
    )
    ..scale(scale)
    ..drawPicture(info.picture);
  final image = await recorder.endRecording().toImage(canvas, canvas);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File(out)
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
  image.dispose();
  info.picture.dispose();
}

void main() {
  testWidgets('rasterize branding', (tester) async {
    await tester.runAsync(() async {
      // Adaptive icon layers keep their 1080 grid.
      for (final layer in ['android-foreground', 'android-monochrome']) {
        await _render(
          '$_branding/$layer.svg',
          '$_branding/png/$layer.png',
          1080,
          1080,
        );
      }
      // iOS launch image (LaunchScreen.storyboard centres it) at 1x/2x/3x.
      for (final (scale, suffix) in [(1, ''), (2, '@2x'), (3, '@3x')]) {
        await _render(
          'assets/logos/pindoro-mark-reversed.svg',
          '../../apps/mobile/ios/Runner/Assets.xcassets/LaunchImage.imageset/'
              'LaunchImage$suffix.png',
          384 * scale,
          160.0 * scale,
        );
      }
      // Android 12 splash icons: 1152 canvas, artwork inside the 768 circle.
      for (final (mark, out) in [
        ('pindoro-mark-reversed', 'splash-mark'),
        ('pindoro-mark-dark', 'splash-mark-dark'),
      ]) {
        await _render(
          'assets/logos/$mark.svg',
          '$_branding/png/$out.png',
          1152,
          480,
        );
      }
    });
  });
}
