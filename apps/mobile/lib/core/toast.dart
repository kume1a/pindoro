import 'package:flutter/material.dart';

typedef ToastAction = ({String label, VoidCallback onPressed});

/// A short, non-blocking message (the design's Toast); a new one replaces the
/// current one. [above] lifts it over a pinned bottom action. It stays 3 s,
/// or 5 s with an [action].
void showToast(
  BuildContext context,
  String message, {
  double above = 0,
  ToastAction? action,
}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        margin: EdgeInsets.fromLTRB(16, 0, 16, 16 + above),
        duration: Duration(seconds: action == null ? 3 : 5),
        persist: false,
        action: action == null
            ? null
            : SnackBarAction(label: action.label, onPressed: action.onPressed),
      ),
    );
}
