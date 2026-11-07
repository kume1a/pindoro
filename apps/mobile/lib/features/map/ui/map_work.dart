import 'dart:async';

import 'package:flutter/widgets.dart';

extension MapWork on State {
  /// Runs platform map work (style setup, source updates) that can outlive
  /// the widget, e.g. a back tap while the style still loads. Once the map is
  /// gone its controller and context fail; those errors are expected and
  /// dropped, any other still surfaces.
  void runMapWork(Future<void> Function() work) => unawaited(
    work().catchError((Object error, StackTrace stack) {
      if (mounted) Error.throwWithStackTrace(error, stack);
    }),
  );
}
