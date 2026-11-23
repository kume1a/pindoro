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

/// Runs [work] one call at a time: calls made while it runs fold into one more run right after,
/// so a fast run of changes never queues up stale frames on the platform channel.
class SerialWork {
  SerialWork(this.work);

  final Future<void> Function() work;
  bool _running = false;
  bool _again = false;

  Future<void> call() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await work();
      } while (_again);
    } finally {
      _running = false;
    }
  }
}
