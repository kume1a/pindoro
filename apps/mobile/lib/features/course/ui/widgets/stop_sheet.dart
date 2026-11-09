import 'package:flutter/material.dart';
import 'package:pindoro/core/format.dart';
import 'package:pindoro_design/pindoro_design.dart';

typedef SheetChip = ({PindoroGlyph glyph, String label});

/// A stop's sheet (canvas R4-11, R4-12): a [kicker] ("Lesson 3 of 6 · Unit
/// 2 · Vake"), the [title], a [body], optional [chips] and the [action].
/// The action closes the sheet before it runs.
Future<void> showStopSheet(
  BuildContext context, {
  required String kicker,
  required String title,
  required String body,
  required String action,
  required VoidCallback onAction,
  List<SheetChip> chips = const [],
}) => showModalBottomSheet<void>(
  context: context,
  // Over the tab bar too, so the scrim covers the whole screen.
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (sheet) {
    final c = PindoroTheme.of(sheet).colors;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PindoroSpace.s5,
          0,
          PindoroSpace.s5,
          PindoroSpace.s6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: PindoroSpace.s3,
          children: [
            Text(
              kicker,
              style: PindoroType.labelMd.copyWith(color: c.textSecondary),
            ),
            Semantics(
              header: true,
              child: Text(
                title,
                style: PindoroType.headlineSm.copyWith(color: c.textPrimary),
              ),
            ),
            Text(
              body,
              style: PindoroType.bodyMd.copyWith(color: c.textSecondary),
            ),
            if (chips.isNotEmpty)
              Wrap(
                spacing: PindoroSpace.s2,
                runSpacing: PindoroSpace.s2,
                children: [
                  for (final chip in chips)
                    Pill(
                      label: chip.label,
                      icon: chip.glyph,
                      iconColor: chip.glyph == PindoroGlyph.xp
                          ? c.xpFill
                          : c.primaryText,
                    ),
                ],
              ),
            const SizedBox(height: PindoroSpace.s2),
            PindoroButton(
              label: action,
              onPressed: () {
                Navigator.of(sheet).pop();
                onAction();
              },
            ),
          ],
        ),
      ),
    );
  },
);

/// "3 min 12 s".
String formatMinSec(BuildContext context, Duration d) =>
    context.l10n.durationMinSec(d.inMinutes, d.inSeconds.remainder(60));
