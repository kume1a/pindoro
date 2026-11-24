import 'package:flutter/material.dart';

/// Pops [context]'s route only while it is the top one: a second pop during its exit (another
/// state change, a double tap) would close the screen under it.
void popIfCurrent(BuildContext context) {
  if (context.mounted && (ModalRoute.isCurrentOf(context) ?? false)) {
    Navigator.of(context).pop();
  }
}

/// [screen] in [context]'s theme: a route pushed from a screen with a theme of its own (the
/// drive's day or night) is otherwise built in the app's.
Widget inThemeOf(BuildContext context, Widget screen) =>
    Theme(data: Theme.of(context), child: screen);
