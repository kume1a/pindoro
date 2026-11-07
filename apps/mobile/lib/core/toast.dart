import 'package:flutter/material.dart';

/// A short, non-blocking message (the design's Toast); a new one replaces the
/// current one. [above] lifts it over a pinned bottom action.
void showToast(BuildContext context, String message, {double above = 0}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        margin: EdgeInsets.fromLTRB(16, 0, 16, 16 + above),
      ),
    );
}
