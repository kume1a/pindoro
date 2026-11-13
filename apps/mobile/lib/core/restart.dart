import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Closes the progress database, runs `swap` while nothing has it open, then
/// starts the app again on the database it leaves (a restored backup).
typedef Restart = Future<void> Function(Future<void> Function() swap);

/// Overridden in main().
final restartProvider = Provider<Restart>(
  (ref) => throw UnimplementedError('restartProvider must be overridden'),
);
