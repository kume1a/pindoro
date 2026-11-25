import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

Future<Uint8List> renderPng(
  Size size,
  double pixelRatio,
  void Function(Canvas canvas) paint,
) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder)..scale(pixelRatio));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      (size.width * pixelRatio).ceil(),
      (size.height * pixelRatio).ceil(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  } finally {
    picture.dispose();
  }
}
