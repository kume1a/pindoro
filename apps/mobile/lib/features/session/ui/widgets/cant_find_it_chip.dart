import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pindoro/core/dialogs.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro_design/pindoro_design.dart';

/// "Can't find it?" on a pack place (SPEC §16.18 item 94): once confirmed,
/// [onHide] hides the place on this phone.
class CantFindItChip extends StatelessWidget {
  const CantFindItChip({super.key, required this.name, required this.onHide});

  final String name;
  final VoidCallback onHide;

  Future<void> _ask(BuildContext context) async {
    final l10n = context.l10n;
    final hide = await askChoice(
      context,
      title: l10n.placeHideTitle(name),
      body: l10n.placeHideBody,
      primary: l10n.landmarksKeep,
      secondary: l10n.placeHideConfirm,
    );
    if (hide) onHide();
  }

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.placeCantFind;
    return Tappable(
      onTap: () => unawaited(_ask(context)),
      label: label,
      child: StatChip(label: label, glyph: PindoroGlyph.flag),
    );
  }
}
