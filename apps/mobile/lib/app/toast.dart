import 'package:flutter/material.dart';

/// A short, non-blocking message (the design's Toast); a new one replaces the
/// current one.
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
