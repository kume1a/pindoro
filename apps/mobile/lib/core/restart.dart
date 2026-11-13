import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Closes the progress database, moves `restored` in as the database file
/// and starts the app again on it. A restored file that won't boot is put
/// aside: the app starts on the old database and the error goes on.
typedef Restart = Future<void> Function(File restored);

/// Overridden in main().
final restartProvider = Provider<Restart>(
  (ref) => throw UnimplementedError('restartProvider must be overridden'),
);
