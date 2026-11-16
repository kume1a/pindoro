import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The current time for learning code; tests override it to move the clock.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
