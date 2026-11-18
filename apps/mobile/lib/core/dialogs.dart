import 'package:flutter/material.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// Asks with a [PindoroDialog]: true for [secondary] (the action asked
/// about), false for [primary] or when dismissed. A [fixed] one closes only
/// by its buttons.
Future<bool> askChoice(
  BuildContext context, {
  required String title,
  required String body,
  required String primary,
  required String secondary,
  bool fixed = false,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: !fixed,
      builder: (_) => PopScope(
        canPop: !fixed,
        child: PindoroDialog(
          title: title,
          body: body,
          primary: primary,
          secondary: secondary,
        ),
      ),
    ) ??
    false;
