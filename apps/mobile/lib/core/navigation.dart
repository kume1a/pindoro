import 'package:flutter/widgets.dart';

/// Pops [context]'s route only while it is the top one: a second pop during its exit (another
/// state change, a double tap) would close the screen under it.
void popIfCurrent(BuildContext context) {
  if (context.mounted && (ModalRoute.isCurrentOf(context) ?? false)) {
    Navigator.of(context).pop();
  }
}
